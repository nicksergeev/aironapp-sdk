/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2008-2010 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import <stdlib.h>
#import <fcntl.h>
#import <errno.h>
#import <string.h>
#import <stdbool.h>
#import <dlfcn.h>

#import <sys/sysctl.h>
#import <sys/time.h>

#import <mach-o/dyld.h>

#import <libkern/OSAtomic.h>

#include <execinfo.h>

#import "PLCrashReport.h"
#import "PLCrashLogWriter.h"
//#import "PLCrashLogWriterEncoding.h"
#import "PLCrashAsync.h"
#import "PLCrashAsyncSignalInfo.h"
#import "PLCrashFrameWalker.h"

#import "crash_report.pb.h"
using namespace plcrash;

#import "PLCrashSysctl.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h> // For UIDevice
#endif

/**
 * @internal
 * Maximum number of frames that will be written to the crash report for a single thread. Used as a safety measure
 * to avoid overrunning our output limit when writing a crash report triggered by frame recursion.
 */
#define MAX_THREAD_FRAMES 512 // matches Apple's crash reporting on Snow Leopard

/**
 * Initialize a new crash log writer instance and issue a memory barrier upon completion. This fetches all necessary
 * environment information.
 *
 * @param writer Writer instance to be initialized.
 * @param app_identifier Unique per-application identifier. On Mac OS X, this is likely the CFBundleIdentifier.
 * @param app_version Application version string.
 *
 * @note If this function fails, plcrash_log_writer_free() should be called
 * to free any partially allocated data.
 *
 * @warning This function is not guaranteed to be async-safe, and must be called prior to enabling the crash handler.
 */
plcrash_error_t plcrash_log_writer_init (plcrash_log_writer_t *writer, NSString *app_identifier, NSString *app_version) {
    /* Default to 0 */
    memset(writer, 0, sizeof(*writer));
    
    /* Fetch the application information */
    {
        writer->application_info.app_identifier = strdup([app_identifier UTF8String]);
        writer->application_info.app_version = strdup([app_version UTF8String]);
    }
    
    /* Fetch the process information */
    {
        /* MIB used to fetch process info */
        struct kinfo_proc process_info;
        size_t process_info_len = sizeof(process_info);
        int process_info_mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, 0 };
        int process_info_mib_len = 4;

        /* Current process */
        {            
            /* Retrieve PID */
            writer->process_info.process_id = getpid();

            /* Retrieve name */
			//TODO: MAXK: //find another way to retrieve process name!!!
            process_info_mib[3] = writer->process_info.process_id;
            if (sysctl(process_info_mib, process_info_mib_len, &process_info, &process_info_len, NULL, 0) == 0) {
                writer->process_info.process_name = strdup(process_info.kp_proc.p_comm);
            } else {
                PLCF_DEBUG("Could not retreive process name: %s", strerror(errno));
            }

            /* Retrieve path */
            char *process_path = NULL;
            uint32_t process_path_len = 0;

            _NSGetExecutablePath(NULL, &process_path_len);
            if (process_path_len > 0) {
                process_path = (char *)malloc(process_path_len);
                _NSGetExecutablePath(process_path, &process_path_len);
                writer->process_info.process_path = process_path;
            }
        }

        /* Parent process */
        {            
            /* Retrieve PID */
            writer->process_info.parent_process_id = getppid();

            /* Retrieve name */
            process_info_mib[3] = writer->process_info.parent_process_id;
            if (sysctl(process_info_mib, process_info_mib_len, &process_info, &process_info_len, NULL, 0) == 0) {
                writer->process_info.parent_process_name = strdup(process_info.kp_proc.p_comm);
            } else {
                PLCF_DEBUG("Could not retreive parent process name: %s", strerror(errno));
            }

        }
    }

    /* Fetch the machine information */
    {
        /* Model */
#if TARGET_OS_IPHONE
        /* On iOS, we want hw.machine (e.g. hw.machine = iPad2,1; hw.model = K93AP) */
        writer->machine_info.model = plcrash_sysctl_string("hw.machine");
#else
        /* On Mac OS X, we want hw.model (e.g. hw.machine = x86_64; hw.model = Macmini5,3) */
        writer->machine_info.model = plcrash_sysctl_string("hw.model");
#endif
        if (writer->machine_info.model == NULL) {
            PLCF_DEBUG("Could not retrive hw.model: %s", strerror(errno));
        }
        
        /* CPU */
        {
            int retval;

            /* Fetch the CPU types */
            if (plcrash_sysctl_int("hw.cputype", &retval)) {
                writer->machine_info.cpu_type = retval;
            } else {
                PLCF_DEBUG("Could not retrive hw.cputype: %s", strerror(errno));
            }
            
            if (plcrash_sysctl_int("hw.cpusubtype", &retval)) {
                writer->machine_info.cpu_subtype = retval;
            } else {
                PLCF_DEBUG("Could not retrive hw.cpusubtype: %s", strerror(errno));
            }

            /* Processor count */
            if (plcrash_sysctl_int("hw.physicalcpu_max", &retval)) {
                writer->machine_info.processor_count = retval;
            } else {
                PLCF_DEBUG("Could not retrive hw.physicalcpu_max: %s", strerror(errno));
            }

            if (plcrash_sysctl_int("hw.logicalcpu_max", &retval)) {
                writer->machine_info.logical_processor_count = retval;
            } else {
                PLCF_DEBUG("Could not retrive hw.logicalcpu_max: %s", strerror(errno));
            }
        }
        
        /*
         * Check if the process is emulated. This sysctl is defined in the Universal Binary Programming Guidelines,
         * Second Edition:
         *
         * http://developer.apple.com/legacy/mac/library/documentation/MacOSX/Conceptual/universal_binary/universal_binary.pdf
         */
        {
            int retval;

            if (plcrash_sysctl_int("sysctl.proc_native", &retval)) {
                if (retval == 0) {
                    writer->process_info.native = false;
                } else {
                    writer->process_info.native = true;
                }
            } else {
                /* If the sysctl is not available, the process can be assumed to be native. */
                writer->process_info.native = true;
            }
        }
    }

    /* Fetch the OS information */    
    writer->system_info.build = plcrash_sysctl_string("kern.osversion");
    if (writer->system_info.build == NULL) {
        PLCF_DEBUG("Could not retrive kern.osversion: %s", strerror(errno));
    }

#if TARGET_OS_IPHONE
    /* iPhone OS */
    writer->system_info.version = strdup([[[UIDevice currentDevice] systemVersion] UTF8String]);
#elif TARGET_OS_MAC
    /* Mac OS X */
    {
        SInt32 major, minor, bugfix;

        /* Fetch the major, minor, and bugfix versions.
         * Fetching the OS version should not fail. */
        if (Gestalt(gestaltSystemVersionMajor, &major) != noErr) {
            PLCF_DEBUG("Could not retreive system major version with Gestalt");
            return PLCRASH_EINTERNAL;
        }
        if (Gestalt(gestaltSystemVersionMinor, &minor) != noErr) {
            PLCF_DEBUG("Could not retreive system minor version with Gestalt");
            return PLCRASH_EINTERNAL;
        }
        if (Gestalt(gestaltSystemVersionBugFix, &bugfix) != noErr) {
            PLCF_DEBUG("Could not retreive system bugfix version with Gestalt");
            return PLCRASH_EINTERNAL;
        }

        /* Compose the string */
        asprintf(&writer->system_info.version, "%" PRId32 ".%" PRId32 ".%" PRId32, (int32_t)major, (int32_t)minor, (int32_t)bugfix);
    }
#else
#error Unsupported Platform
#endif
    
    /* Initialize the image info list. */
    plcrash_async_image_list_init(&writer->image_info.image_list);

    /* Ensure that any signal handler has a consistent view of the above initialization. */
    OSMemoryBarrier();

    return PLCRASH_ESUCCESS;
}

/**
 * Register a binary image with this writer.
 *
 * @param writer The writer to which the image's information will be added.
 * @param header_addr The image's address.
 *
 * @warning This function is not async safe, and must be called outside of a signal handler.
 */
void plcrash_log_writer_add_image (plcrash_log_writer_t *writer, const void *header_addr) {
    Dl_info info;

    /* Look up the image info */
    if (dladdr(header_addr, &info) == 0) {
        PLCF_DEBUG("dladdr(%p, ...) failed", header_addr);
        return;
    }

    /* Register the image */
    plcrash_async_image_list_append(&writer->image_info.image_list, (uintptr_t)header_addr, info.dli_fname);
}

/**
 * Deregister a binary image from this writer.
 *
 * @param writer The writer from which the image's information will be removed.
 * @param header_addr The image's address.
 *
 * @warning This function is not async safe, and must be called outside of a signal handler.
 */
void plcrash_log_writer_remove_image (plcrash_log_writer_t *writer, const void *header_addr) {
    plcrash_async_image_list_remove(&writer->image_info.image_list, (uintptr_t)header_addr);
}

/**
 * Set the uncaught exception for this writer. Once set, this exception will be used to
 * provide exception data for the crash log output.
 *
 * @warning This function is not async safe, and must be called outside of a signal handler.
 */
void plcrash_log_writer_set_exception (plcrash_log_writer_t *writer, NSException *exception) {
    assert(writer->uncaught_exception.has_exception == false);

    /* Save the exception data */
    writer->uncaught_exception.has_exception = true;
    writer->uncaught_exception.name = strdup([[exception name] UTF8String]);
    writer->uncaught_exception.reason = strdup([[exception reason] UTF8String]);

    /* Save the call stack, if available */
    NSArray *callStackArray = [exception callStackReturnAddresses];
    if (callStackArray != nil && [callStackArray count] > 0) {
        size_t count = [callStackArray count];
        writer->uncaught_exception.callstack_count = count;
        writer->uncaught_exception.callstack = (void **)malloc(sizeof(void *) * count);

        size_t i = 0;
        for (NSNumber *num in callStackArray) {
            assert(i < count);
            writer->uncaught_exception.callstack[i] = (void *)(uintptr_t)[num unsignedLongLongValue];
            i++;
        }
    }

    /* Ensure that any signal handler has a consistent view of the above initialization. */
    OSMemoryBarrier();
}

/**
 * Close the plcrash_writer_t output.
 *
 * @param writer Writer instance to be closed.
 */
plcrash_error_t plcrash_log_writer_close (plcrash_log_writer_t *writer) {
    return PLCRASH_ESUCCESS;
}

/**
 * Free any crash log writer resources.
 *
 * @warning This method is not async safe.
 */
void plcrash_log_writer_free (plcrash_log_writer_t *writer) {
    /* Free the app info */
    if (writer->application_info.app_identifier != NULL)
        free(writer->application_info.app_identifier);
    if (writer->application_info.app_version != NULL)
        free(writer->application_info.app_version);

    /* Free the process info */
    if (writer->process_info.process_name != NULL) 
        free(writer->process_info.process_name);
    if (writer->process_info.process_path != NULL) 
        free(writer->process_info.process_path);
    if (writer->process_info.parent_process_name != NULL) 
        free(writer->process_info.parent_process_name);
    
    /* Free the system info */
    if (writer->system_info.version != NULL)
        free(writer->system_info.version);
    
    if (writer->system_info.build != NULL)
        free(writer->system_info.build);
    
    /* Free the machine info */
    if (writer->machine_info.model != NULL)
        free(writer->machine_info.model);

    /* Free the binary image info */
    plcrash_async_image_list_free(&writer->image_info.image_list);

    /* Free the exception data */
    if (writer->uncaught_exception.has_exception) {
        if (writer->uncaught_exception.name != NULL)
            free(writer->uncaught_exception.name);

        if (writer->uncaught_exception.reason != NULL)
            free(writer->uncaught_exception.reason);
        
        if (writer->uncaught_exception.callstack != NULL)
            free(writer->uncaught_exception.callstack);
    }
}

/**
 * @internal
 *
 * Write the system info message.
 *
 * @param file Output file
 * @param timestamp Timestamp to use (seconds since epoch). Must be same across calls, as varint encoding.
 */
static void plcrash_writer_write_system_info (CrashReport_SystemInfo & system_info, plcrash_log_writer_t *writer, int64_t timestamp) {
    /* OS */
    uint32_t enumval = PLCrashReportHostOperatingSystem;
	
	system_info.set_operating_system(CrashReport_SystemInfo_OperatingSystem(enumval));

    /* OS Version */
	system_info.set_os_version(writer->system_info.version);
    
    /* OS Build */
	system_info.set_os_build(writer->system_info.build);

    /* Machine type */
    enumval = PLCrashReportHostArchitecture;
	system_info.set_architecture(Architecture(enumval));

    /* Timestamp */
	system_info.set_timestamp(timestamp);
}

/**
 * @internal
 *
 * Write the processor info message.
 *
 * @param file Output file
 * @param cpu_type The Mach CPU type.
 * @param cpu_subtype_t The Mach CPU subtype
 */
static void plcrash_writer_write_processor_info (CrashReport_Processor & processor_info, uint64_t cpu_type, uint64_t cpu_subtype) {
    /* Encoding */
    uint32_t enumval = PLCrashReportProcessorTypeEncodingMach;
	
	processor_info.set_encoding(CrashReport_Processor_TypeEncoding(enumval));

    /* Type */
	processor_info.set_type(cpu_type);

    /* Subtype */
	processor_info.set_subtype(cpu_subtype);
}

/**
 * @internal
 *
 * Write the machine info message.
 *
 * @param file Output file
 */
static void plcrash_writer_write_machine_info (CrashReport_MachineInfo & machine_info, plcrash_log_writer_t *writer) {
    
    /* Model */
    if (writer->machine_info.model != NULL)
		machine_info.set_model(writer->machine_info.model);

    /* Processor */
    {
		plcrash_writer_write_processor_info(*machine_info.mutable_processor(), writer->machine_info.cpu_type, writer->machine_info.cpu_subtype);
    }

    /* Physical Processor Count */
	machine_info.set_processor_count(writer->machine_info.processor_count);
    
    /* Logical Processor Count */
	machine_info.set_logical_processor_count(writer->machine_info.logical_processor_count);
}

/**
 * @internal
 *
 * Write the app info message.
 *
 * @param file Output file
 * @param app_identifier Application identifier
 * @param app_version Application version
 */
static void plcrash_writer_write_app_info (CrashReport_ApplicationInfo & app_info, const char *app_identifier, const char *app_version) {
    /* App identifier */
	app_info.set_identifier(app_identifier);
    
    /* App version */
	app_info.set_version(app_version);
}

/**
 * @internal
 *
 * Write the process info message.
 *
 * @param file Output file
 * @param process_name Process name
 * @param process_id Process ID
 * @param process_path Process path
 * @param parent_process_name Parent process name
 * @param parent_process_id Parent process ID
 * @param native If false, process is running under emulation.
 */
static void plcrash_writer_write_process_info (CrashReport_ProcessInfo & process_info, const char *process_name, 
                                                 const pid_t process_id, const char *process_path, 
                                                 const char *parent_process_name, const pid_t parent_process_id,
                                                 bool native) 
{
    /* Process name */
    if (process_name != NULL)
		process_info.set_process_name(process_name);

    /* Process ID */
	process_info.set_process_id(process_id);

    /* Process path */
    if (process_path != NULL)
		process_info.set_process_path(process_path);

    /* Parent process name */
    if (parent_process_name != NULL)
		process_info.set_parent_process_name(parent_process_name);

    /* Parent process ID */
	process_info.set_parent_process_id(parent_process_id);

    /* Native process. */
	process_info.set_native(native);
}

/**
 * @internal
 *
 * Write a thread backtrace register
 *
 * @param file Output file
 * @param cursor The cursor from which to acquire frame data.
 */
static void plcrash_writer_write_thread_register (CrashReport_Thread_RegisterValue & reg_value, const char *regname, plframe_greg_t regval) {
    /* Write the name */
	reg_value.set_name(regname);

    /* Write the value */
    uint64_t uint64val = regval;
	reg_value.set_value(uint64val);
}

/**
 * @internal
 *
 * Write all thread backtrace register messages
 *
 * @param file Output file
 * @param cursor The cursor from which to acquire frame data.
 */
static void plcrash_writer_write_thread_registers (CrashReport_Thread & thread, ucontext_t *uap) {
    plframe_cursor_t cursor;
    plframe_error_t frame_err;
    uint32_t regCount;

    /* Last is an index value, so increment to get the count */
    regCount = PLFRAME_REG_LAST + 1;

    /* Create the crashed thread frame cursor */
    if ((frame_err = plframe_cursor_init(&cursor, uap)) != PLFRAME_ESUCCESS) {
        PLCF_DEBUG("Failed to initialize frame cursor for crashed thread: %s", plframe_strerror(frame_err));
        return;
    }
    
    /* Fetch the first frame */
    if ((frame_err = plframe_cursor_next(&cursor)) != PLFRAME_ESUCCESS) {
        PLCF_DEBUG("Could not fetch crashed thread frame: %s", plframe_strerror(frame_err));
        return;
    }
    
    /* Write out register messages */
    for (int i = 0; i < regCount; i++) {
        plframe_greg_t regVal;
        const char *regname;
        //uint32_t msgsize;

        /* Fetch the register value */
        if ((frame_err = plframe_get_reg(&cursor, i, &regVal)) != PLFRAME_ESUCCESS) {
            // Should never happen
            PLCF_DEBUG("Could not fetch register %i value: %s", i, plframe_strerror(frame_err));
            regVal = 0;
        }

        /* Fetch the register name */
        regname = plframe_get_regname(i);

        /* Get the register message */
        plcrash_writer_write_thread_register(*thread.add_registers(), regname, regVal);
    }
}

/**
 * @internal
 *
 * Write a thread backtrace frame
 *
 * @param file Output file
 * @param pcval The frame PC value.
 */
static void plcrash_writer_write_thread_frame (CrashReport_Thread_StackFrame & stack_frame, uint64_t pcval) {
    //size_t rv = 0;

	//get symbols for the frame
	void * frame[1];
	frame[0] = (void *)pcval;
	
	char **strs = backtrace_symbols(frame, 1);
	NSLog(@"%s", strs[0]);
	
	//TODO: MAXK scan the name of the symbol
	
	stack_frame.set_pc(pcval);

	if(strs[0])
		stack_frame.set_symbol(strs[0]);
}

/**
 * @internal
 *
 * Write a thread message
 *
 * @param file Output file
 * @param thread Thread for which we'll output data.
 * @param crashctx Context to use for currently running thread (rather than fetching the thread
 * context, which we've invalidated by running at all)
 */
static void plcrash_writer_write_thread (CrashReport_Thread & cur_thread, thread_t thread, uint32_t thread_number, ucontext_t *crashctx) {
    plframe_cursor_t cursor;
    plframe_error_t ferr;
    bool crashed_thread = false;
	
    /* Write the required elements first; fatal errors may occur below, in which case we need to have
     * written out required elements before returning. */
    {
        /* Write the thread ID */
		cur_thread.set_thread_number(thread_number);

        /* Is this the crashed thread? */
        thread_t thr_self = mach_thread_self();
        if (MACH_PORT_INDEX(thread) == MACH_PORT_INDEX(thr_self))
            crashed_thread = true;

        /* Note crashed status */
		cur_thread.set_crashed(crashed_thread);
    }


    /* Write out the stack frames. */
    {
        /* Set up the frame cursor. */
        {
            /* Use the crashctx if we're running on the crashed thread */
            if (crashed_thread) {
                ferr = plframe_cursor_init(&cursor, crashctx);
            } else {
                ferr = plframe_cursor_thread_init(&cursor, thread);
            }

            /* Did cursor initialization succeed? If not, it is impossible to proceed */
            if (ferr != PLFRAME_ESUCCESS) {
                PLCF_DEBUG("An error occured initializing the frame cursor: %s", plframe_strerror(ferr));
                return;
            }
        }

        /* Walk the stack, limiting the total number of frames that are output. */
        uint32_t frame_count = 0;
        while ((ferr = plframe_cursor_next(&cursor)) == PLFRAME_ESUCCESS && frame_count < MAX_THREAD_FRAMES) {
            //uint32_t frame_size;

            /* Fetch the PC value */
            plframe_greg_t pc = 0;
            if ((ferr = plframe_get_reg(&cursor, PLFRAME_REG_IP, &pc)) != PLFRAME_ESUCCESS) {
                PLCF_DEBUG("Could not retrieve frame PC register: %s", plframe_strerror(ferr));
                break;
            }
			
            plcrash_writer_write_thread_frame(*cur_thread.add_frames(), pc);
            frame_count++;
        }

        /* Did we reach the end successfully? */
        if (ferr != PLFRAME_ENOFRAME) {
            /* This is non-fatal, and in some circumstances -could- be caused by reaching the end of the stack if the
             * final frame pointer is not NULL. */
            PLCF_DEBUG("Terminated stack walking early: %s", plframe_strerror(ferr));
        }
    }

    /* Dump registers for the crashed thread */
    if (crashed_thread) {
        plcrash_writer_write_thread_registers(cur_thread, crashctx);
    }
}


/**
 * @internal
 *
 * Write a binary image frame
 *
 * @param file Output file
 * @param name binary image path (or name).
 * @param image_base Mach-O image base.
 */
static void plcrash_writer_write_binary_image (CrashReport_BinaryImage & binary_image, const char *name, const void *header) {
    //size_t rv = 0;
    uint64_t mach_size = 0;
    uint32_t ncmds;
    const struct mach_header *header32 = (const struct mach_header *) header;
    const struct mach_header_64 *header64 = (const struct mach_header_64 *) header;

    struct load_command *cmd;
    cpu_type_t cpu_type;
    cpu_subtype_t cpu_subtype;

    /* Check for 32-bit/64-bit header and extract required values */
    switch (header32->magic) {
        /* 32-bit */
        case MH_MAGIC:
        case MH_CIGAM:
            ncmds = header32->ncmds;
            cpu_type = header32->cputype;
            cpu_subtype = header32->cpusubtype;
            cmd = (struct load_command *) (header32 + 1);
            break;

        /* 64-bit */
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            ncmds = header64->ncmds;
            cpu_type = header64->cputype;
            cpu_subtype = header64->cpusubtype;
            cmd = (struct load_command *) (header64 + 1);
            break;

        default:
            PLCF_DEBUG("Invalid Mach-O header magic value: %x", header32->magic);
            return ;
    }

    /* Compute the image size and search for a UUID */
    struct uuid_command *uuid = NULL;

    for (uint32_t i = 0; cmd != NULL && i < ncmds; i++) {
        /* 32-bit text segment */
        if (cmd->cmd == LC_SEGMENT) {
            struct segment_command *segment = (struct segment_command *) cmd;
            if (strcmp(segment->segname, SEG_TEXT) == 0) {
                mach_size = segment->vmsize;
            }
        }
        /* 64-bit text segment */
        else if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *segment = (struct segment_command_64 *) cmd;

            if (strcmp(segment->segname, SEG_TEXT) == 0) {
                mach_size = segment->vmsize;
            }
        }
        /* DWARF dSYM UUID */
        else if (cmd->cmd == LC_UUID && cmd->cmdsize == sizeof(struct uuid_command)) {
            uuid = (struct uuid_command *) cmd;
        }

        cmd = (struct load_command *) ((uint8_t *) cmd + cmd->cmdsize);
    }


	binary_image.set_size(mach_size);
    
    /* Base address */
    {
        uintptr_t base_addr;
        uint64_t u64;

        base_addr = (uintptr_t) header;
        u64 = base_addr;
		binary_image.set_base_address(u64);
    }

    /* Name */
	binary_image.set_name(name);

    /* UUID */
    if (uuid != NULL) {
        /* Write the 128-bit UUID */
		binary_image.set_uuid(uuid->uuid, sizeof(uuid->uuid));
    }
    
    /* Get the processor message size */
    plcrash_writer_write_processor_info(*binary_image.mutable_code_type(), cpu_type, cpu_subtype);
}


/**
 * @internal
 *
 * Write the crash Exception message
 *
 * @param file Output file
 * @param writer Writer containing exception data
 */
static void plcrash_writer_write_exception (CrashReport_Exception & exception, plcrash_log_writer_t *writer) {

    /* Write the name and reason */
    assert(writer->uncaught_exception.has_exception);
	exception.set_name(writer->uncaught_exception.name);
	
	exception.set_reason(writer->uncaught_exception.reason);
    
    /* Write the stack frames, if any */
    uint32_t frame_count = 0;
    for (size_t i = 0; i < writer->uncaught_exception.callstack_count && frame_count < MAX_THREAD_FRAMES; i++) {
        uint64_t pc = (uint64_t)(uintptr_t) writer->uncaught_exception.callstack[i];
        
        plcrash_writer_write_thread_frame(*exception.add_frames(), pc);
        frame_count++;
    }
}

/**
 * @internal
 *
 * Write the crash signal message
 *
 * @param file Output file
 * @param siginfo The signal information
 */
static void plcrash_writer_write_signal (CrashReport_Signal & curr_signal, siginfo_t *siginfo) {
    
    /* Fetch the signal name */
    char name_buf[10];
    const char *name;
    if ((name = plcrash_async_signal_signame(siginfo->si_signo)) == NULL) {
        PLCF_DEBUG("Warning -- unhandled signal number (signo=%d). This is a bug.", siginfo->si_signo);
        snprintf(name_buf, sizeof(name_buf), "#%d", siginfo->si_signo);
        name = name_buf;
    }

    /* Fetch the signal code string */
    char code_buf[10];
    const char *code;
    if ((code = plcrash_async_signal_sigcode(siginfo->si_signo, siginfo->si_code)) == NULL) {
        PLCF_DEBUG("Warning -- unhandled signal sicode (signo=%d, code=%d). This is a bug.", siginfo->si_signo, siginfo->si_code);
        snprintf(code_buf, sizeof(code_buf), "#%d", siginfo->si_code);
        code = code_buf;
    }
    
    /* Address value */
    uint64_t addr = (uintptr_t) siginfo->si_addr;

    /* Write it out */
	curr_signal.set_name(name);
	
	curr_signal.set_code(code);
	
	curr_signal.set_address(addr);
}

/**
 * Write the crash report. All other running threads are suspended while the crash report is generated.
 *
 * @param writer The writer context
 * @param file The output file.
 * @param siginfo Signal information
 * @param crashctx Context of the crashed thread.
 *
 * @warning This method must only be called from the thread that has triggered the crash. This must correspond
 * to the provided crashctx. Failure to adhere to this requirement will result in an invalid stack trace
 * and thread dump.
 */
plcrash_error_t plcrash_log_writer_write (plcrash_log_writer_t *writer, plcrash_async_file_t *file, siginfo_t *siginfo, ucontext_t *crashctx) {
    thread_act_array_t threads;
    mach_msg_type_number_t thread_count;
	
	CrashReport crash_report;

    /* File header */
    {
        uint8_t version = PLCRASH_REPORT_FILE_VERSION;

        /* Write the magic string (with no trailing NULL) and the version number */
        plcrash_async_file_write(file, PLCRASH_REPORT_FILE_MAGIC, strlen(PLCRASH_REPORT_FILE_MAGIC));
        plcrash_async_file_write(file, &version, sizeof(version));
    }

    /* System Info */
    {
        time_t timestamp;
        //uint32_t size;

        /* Must stay the same across both calls, so get the timestamp here */
        if (time(&timestamp) == (time_t)-1) {
            PLCF_DEBUG("Failed to fetch timestamp: %s", strerror(errno));
            timestamp = 0;
        }

        plcrash_writer_write_system_info(*crash_report.mutable_system_info(), writer, timestamp);
    }
    
    /* Machine Info */
    {
        //uint32_t size;

        /* Determine size */
        plcrash_writer_write_machine_info(*crash_report.mutable_machine_info(), writer);
    }

    /* App info */
    {
        //uint32_t size;

        /* Determine size */
        plcrash_writer_write_app_info(*crash_report.mutable_application_info(), writer->application_info.app_identifier, writer->application_info.app_version);
    }
    
    /* Process info */
    {
        plcrash_writer_write_process_info(*crash_report.mutable_process_info(), writer->process_info.process_name, writer->process_info.process_id, 
                                                 writer->process_info.process_path, writer->process_info.parent_process_name,
                                                 writer->process_info.parent_process_id, writer->process_info.native);
    }
    
    /* Threads */
    {
        task_t self = mach_task_self();
        thread_t self_thr = mach_thread_self();

        /* Get a list of all threads */
        if (task_threads(self, &threads, &thread_count) != KERN_SUCCESS) {
            PLCF_DEBUG("Fetching thread list failed");
            thread_count = 0;
        }

        /* Suspend each thread and write out its state */
        for (mach_msg_type_number_t i = 0; i < thread_count; i++) {
            thread_t thread = threads[i];
            //uint32_t size;
            bool suspend_thread = true;
            
            /* Check if we're running on the to be examined thread */
            if (MACH_PORT_INDEX(self_thr) == MACH_PORT_INDEX(threads[i])) {
                suspend_thread = false;
            }
            
            /* Suspend the thread */
            if (suspend_thread && thread_suspend(threads[i]) != KERN_SUCCESS) {
                PLCF_DEBUG("Could not suspend thread %d", i);
                continue;
            }
            
            plcrash_writer_write_thread(*crash_report.add_threads(), thread, i, crashctx);
            
            /* Resume the thread */
            if (suspend_thread)
                thread_resume(threads[i]);
        }
        
        /* Clean up the thread array */
        for (mach_msg_type_number_t i = 0; i < thread_count; i++)
            mach_port_deallocate(mach_task_self(), threads[i]);
        vm_deallocate(mach_task_self(), (vm_address_t)threads, sizeof(thread_t) * thread_count);
    }

    /* Binary Images */
    plcrash_async_image_list_set_reading(&writer->image_info.image_list, true);

    plcrash_async_image_t *image = NULL;
    while ((image = plcrash_async_image_list_next(&writer->image_info.image_list, image)) != NULL) {
        //uint32_t size;

        /* Calculate the message size */
        // TODO - switch to plframe_read_addr()
        plcrash_writer_write_binary_image(*crash_report.add_binary_images(), image->name, (const void *) image->header);
    }

    plcrash_async_image_list_set_reading(&writer->image_info.image_list, false);

    /* Exception */
    if (writer->uncaught_exception.has_exception) {
        /* Calculate the message size */
        plcrash_writer_write_exception(*crash_report.mutable_exception(), writer);
    }
    
    /* Signal */
    {
        plcrash_writer_write_signal(*crash_report.mutable_signal(), siginfo);
    }
	
	std::string str = crash_report.SerializeAsString();
	plcrash_async_file_write(file, str.c_str(), str.length());
    
    return PLCRASH_ESUCCESS;
}


/**
 * @} plcrash_log_writer
 */
