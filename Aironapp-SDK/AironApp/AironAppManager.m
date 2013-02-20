//
//  AironAppManager.m
//  AironApp
//
//  Created by Konstantin Kabanov on 3/5/12.
//  Copyright (c) 2012 Arello Mobile.
//

#include <sys/socket.h> // Per msqr
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
#import <CommonCrypto/CommonDigest.h>
#import "CrashReporter.h"
#import "AironAppManager.h"

#import "ScreenReporterManager.h"

#define CONSOLE_LOG_FILENAME @"console.log"
#define PREV_CONSOLE_LOG_FILENAME @"prev_console.log"

@interface AironAppManager ()

- (void) _sendCrashLogWithData: (NSData *) data;
- (void) _sendLogs: (NSString *) filePath;
- (void) _internalCheckForUpdate;
- (void) _updateApplication;

@end

@implementation AironAppManager

- (BOOL) isConfigured {
	return _serviceURL != nil;
}

- (NSString *) stringFromMD5: (NSString *) val{
    
    if(val == nil || [val length] == 0)
        return nil;
    
    const char *value = [val UTF8String];
    
    unsigned char outputBuffer[CC_MD5_DIGEST_LENGTH];
    CC_MD5(value, strlen(value), outputBuffer);
    
    NSMutableString *outputString = [[NSMutableString alloc] initWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(NSInteger count = 0; count < CC_MD5_DIGEST_LENGTH; count++){
        [outputString appendFormat:@"%02x",outputBuffer[count]];
    }
    
    return [outputString autorelease];
}

// Return the local MAC addy
// Courtesy of FreeBSD hackers email list
// Accidentally munged during previous update. Fixed thanks to erica sadun & mlamb.
- (NSString *) macaddress{
    
    int                 mib[6];
    size_t              len;
    char                *buf;
    unsigned char       *ptr;
    struct if_msghdr    *ifm;
    struct sockaddr_dl  *sdl;
    
    mib[0] = CTL_NET;
    mib[1] = AF_ROUTE;
    mib[2] = 0;
    mib[3] = AF_LINK;
    mib[4] = NET_RT_IFLIST;
    
    if ((mib[5] = if_nametoindex("en0")) == 0) {
        printf("Error: if_nametoindex error\n");
        return NULL;
    }
    
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0) {
        printf("Error: sysctl, take 1\n");
        return NULL;
    }
    
    if ((buf = malloc(len)) == NULL) {
        printf("Could not allocate memory. error!\n");
        return NULL;
    }
    
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) {
        printf("Error: sysctl, take 2");
        free(buf);
        return NULL;
    }
    
    ifm = (struct if_msghdr *)buf;
    sdl = (struct sockaddr_dl *)(ifm + 1);
    ptr = (unsigned char *)LLADDR(sdl);
    NSString *outstring = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X", 
                           *ptr, *(ptr+1), *(ptr+2), *(ptr+3), *(ptr+4), *(ptr+5)];
    free(buf);
    
    return outstring;
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Public Methods

- (NSString *) uniqueDeviceIdentifier{
    NSString *macaddress = [self macaddress];
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    
    NSString *stringToHash = [NSString stringWithFormat:@"%@%@",macaddress,bundleIdentifier];
    NSString *uniqueIdentifier = [self stringFromMD5: stringToHash];
    
    return uniqueIdentifier;
}

- (NSString *) uniqueGlobalDeviceIdentifier{
    NSString *macaddress = [self macaddress];
    NSString *uniqueIdentifier = [self stringFromMD5: macaddress];
    
    return uniqueIdentifier;
}

- (id)init {
	self = [super init];
	if (self) {
		//silent mode on start
		[self enableSilentMode:YES];
		
		_serviceURL = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"aironAppServiceURL"] copy];
		_serviceVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"aironAppServiceVersion"] copy];
		if(!_serviceVersion)
			_serviceVersion = [@"1.0" copy];
		
		_appCode = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"aironAppApplicationCode"] copy];
		
		PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
		
		NSError *error;
		
		if (![crashReporter enableCrashReporterAndReturnError: &error])  
			NSLog(@"Warning: Could not enable crash reporter: %@", error);
	}
	return self;
}

- (void) redirectConsoleLogToDocumentFolder {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	
	NSString *logPath = [documentsDirectory stringByAppendingPathComponent:CONSOLE_LOG_FILENAME];
	NSString *prevLogPath = [documentsDirectory stringByAppendingPathComponent:PREV_CONSOLE_LOG_FILENAME];
	NSLog(@"Log path: %@",  logPath);

	NSError *error = nil;
	BOOL success = NO;
	success = [[NSFileManager defaultManager] removeItemAtPath:prevLogPath error:&error];
//	if(error)
//		NSLog(@"Failed to remove prev_prev log: %@", error);
	
	error = nil;
	success = [[NSFileManager defaultManager] moveItemAtPath:logPath toPath:prevLogPath error:&error];
//	if(error)
//		NSLog(@"Failed to move prev to prev_prev log: %@", error);
	error = nil;

	[self performSelectorInBackground:@selector(redirectConsoleLogToDocumentFolderWithLogPath:) withObject:logPath];
}

- (void) redirectConsoleLogToDocumentFolderWithLogPath:(NSString *)logPath{
	@autoreleasepool {
		int d = dup(fileno(stderr));
		FILE *fp2 = fdopen(d, "w");
		
		
		freopen([logPath cStringUsingEncoding:NSASCIIStringEncoding],"a+",stderr);
		
		if (fp2 != NULL) {
			FILE *consoleLog = fopen([logPath cStringUsingEncoding:NSASCIIStringEncoding], "r");
			
			
			int size = 80;
			char *buffer = (char *) malloc (sizeof(char ) * size);
			
			int readed = 0;
			while (readed != EOF) {
				memset(buffer, 0, size);
				readed = fread(buffer, 1, size, consoleLog);
				if (readed > 0) {
					fwrite(buffer, 1, readed, fp2);
				}
				
				
				if (readed == 0) {
					fseek(consoleLog, 0, SEEK_END);
				}
			}
		}
	}
}

- (NSString *) getUUID {
	CFUUIDRef theUUID = CFUUIDCreate(NULL);
	CFStringRef string = CFUUIDCreateString(NULL, theUUID);
	CFRelease(theUUID);
	return [(NSString *)string autorelease];
}

- (void) checkAndHandlePendingCrashReport {
	[self redirectConsoleLogToDocumentFolder];
	
	PLCrashReporter *crashReporter = [PLCrashReporter sharedReporter];
	
	if ([crashReporter hasPendingCrashReport]) {
		NSLog(@"AirOnApp has pending crash report");
		NSData *crashData;
		NSError *error;
		
		crashData = [crashReporter loadPendingCrashReportDataAndReturnError: &error];  
		if (crashData == nil) {  
			NSLog(@"Could not load crash report: %@", error);
			return;
		}
		
		PLCrashReport *crashLog = [[PLCrashReport alloc] initWithData: crashData error: &error];
		if (crashLog == nil) {
			NSLog(@"Could not decode crash log: %@", error);
			return;
		}
		
		/* Format the report */
		NSString *report = [PLCrashReportTextFormatter stringValueForCrashReport: crashLog withTextFormat: PLCrashReportTextFormatiOS];
		NSData *reportData = [report dataUsingEncoding:NSUTF8StringEncoding];

		[self performSelectorInBackground:@selector(_sendCrashLogWithData:) withObject:reportData];
		
		NSString *copyLog = [self logsToUniqueFile:PREV_CONSOLE_LOG_FILENAME];
		[self performSelectorInBackground:@selector(_sendLogs:) withObject:copyLog];
		
		NSData * screenshot = [crashReporter loadPendingImage];
		if(screenshot)
			[self performSelectorInBackground:@selector(_sendScreenshot:) withObject:screenshot];

	}
}

- (void) enableSilentMode:(BOOL)silent {
	silentMode = silent;
}

- (BOOL) isSilentMode {
	if([AironAppManager isAppStoreBuild])
		return YES;
	
	return silentMode;
}

+ (BOOL) isAppStoreBuild {
	NSString * appStoreMode = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"AironAppStoreMode"];
	if(appStoreMode)
		return YES;
	
	NSString * provisioning = [[NSBundle mainBundle] pathForResource:@"embedded.mobileprovision" ofType:nil];
	if(!provisioning)
		return YES;	//AppStore

	BOOL scInfoPresent = [[NSFileManager defaultManager] fileExistsAtPath:@"SC_Info"];
	if(scInfoPresent)
		return YES;
	
	return NO;
}

- (void) checkForUpdate {
	if([AironAppManager isAppStoreBuild])
		return;
	
	[self performSelectorInBackground:@selector(_internalCheckForUpdate) withObject:nil];
}

- (void) _sendCrashLogWithData: (NSData *) crashData {
	if(!crashData || !_serviceURL)
		return;
	
	@autoreleasepool {
		NSLog(@"Sending crash report");
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/api/%@/%@", _serviceURL, _serviceVersion, @"http/crashReport"]]];
		[request setHTTPMethod:@"POST"];
		
		NSString *boundary = @"---------------------------AIRONAPP-mUlTiPaRtFoRm";
		NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
		[request addValue:contentType forHTTPHeaderField:@"Content-Type"];
		
		NSMutableData *httpBody = [NSMutableData data];
		
		NSMutableString *formData = [NSMutableString string];
		
		[formData setString:[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[application]", _appCode]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		
		[formData setString:[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[udid]", [self uniqueGlobalDeviceIdentifier]]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		
		NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
		[formData setString:[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[version]", appVersion]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		
		[formData setString:[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n", boundary, @"data[report]", @"reportfile.dump"]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:crashData];
		[formData setString:[NSString stringWithFormat:@"\r\n"]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		
		[formData setString:[NSString stringWithFormat:@"--%@--\r\n", boundary]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		
		[request setHTTPBody:httpBody];
		
		NSHTTPURLResponse *response = nil;
		NSError *error = nil;
		[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
		
		int statusCode = [response statusCode];
		if (!error && [response statusCode] == 200) {
			NSLog(@"Crash report successfully sent.");
			[[PLCrashReporter sharedReporter] purgePendingCrashReport];
		} else {
			NSLog(@"AirOnApp failed to send crash report. Status code %d, error=%@", statusCode, error);
		}
	}
}

- (void) _sendScreenshot:(NSData*)image {
	if(!image || !_serviceURL)
		return;
	
	@autoreleasepool {
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
        NSString *text = [ScreenReporterManager sharedManager].text;
		if(!text)
			text = @"";
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/api/%@/%@", _serviceURL, _serviceVersion, @"http/uploadScreenshot"]]];
		[request setHTTPMethod:@"POST"];
		
		NSString *boundary = @"---------------------------AIRONAPP-mUlTiPaRtFoRm";
		NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
		[request addValue:contentType forHTTPHeaderField:@"Content-Type"];
		
		NSMutableData *httpBody = [NSMutableData data];
		
		NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
		
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[application]", _appCode] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[udid]", [self uniqueGlobalDeviceIdentifier]] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[version]", appVersion] dataUsingEncoding:NSUTF8StringEncoding]];
        [httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[description]", text] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n", boundary, @"data[file]", @"img.jpg"] dataUsingEncoding:NSUTF8StringEncoding]];
		
		
		NSError *error = nil;
		[httpBody appendData:image];
		
		
		[httpBody appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        
		[request setHTTPBody:httpBody];
		
		NSHTTPURLResponse *response = nil;
        
		[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
		NSLog(@"response %d",[response statusCode]);
		if (!error && [response statusCode] == 200) { //Purge file log
            dispatch_async(dispatch_get_main_queue(), ^{
				if([self isSilentMode])
					return;
				
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"successful" message:@"Upload screenshot" delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles: nil];
                [alert show];
                [alert release];
            });
		}else{
            NSString *msg = [NSString stringWithFormat:@"Upload screenshot %@",error];
            dispatch_async(dispatch_get_main_queue(), ^{
				if([self isSilentMode])
					return;

                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:msg delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles: nil];
                [alert show];
                [alert release];
            });
        }
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
	}
    
}

- (NSString *) logsToUniqueFile:(NSString *)logName {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	
	NSString *prevLogPath = [documentsDirectory stringByAppendingPathComponent:logName];
	NSString *uniqFileName = [self getUUID];
	NSString *uniqLogFilePath = [documentsDirectory stringByAppendingPathComponent:uniqFileName];
	
	NSError *error = nil;
	[[NSFileManager defaultManager] copyItemAtPath:prevLogPath toPath:uniqLogFilePath error:&error];
	if (error) {
		NSLog(@"Can't move prev logs to uniq file. Aborting with error: %@", error);
		return nil;
	}
	
	return uniqLogFilePath;
}

- (void) sendLog {
	NSString *copyLog = [self logsToUniqueFile:CONSOLE_LOG_FILENAME];
	[self performSelectorInBackground:@selector(_sendLogs:) withObject:copyLog];
}

- (void) _sendLogs: (NSString *) filePath {
	if(!filePath || !_serviceURL)
		return;
	
	@autoreleasepool {
		NSLog(@"Sending logs");
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/api/%@/%@", _serviceURL, _serviceVersion, @"http/logReport"]]];
		[request setHTTPMethod:@"POST"];
		
		NSString *boundary = @"---------------------------AIRONAPP-mUlTiPaRtFoRm";
		NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
		[request addValue:contentType forHTTPHeaderField:@"Content-Type"];
		
		NSMutableData *httpBody = [NSMutableData data];
		
		NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
		
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[application]", _appCode] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[udid]", [self uniqueGlobalDeviceIdentifier]] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[version]", appVersion] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n", boundary, @"data[report]", @"reportfile.dump"] dataUsingEncoding:NSUTF8StringEncoding]];
		
		
		NSError *error = nil;
		[httpBody appendData:[[NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&error] dataUsingEncoding:NSUTF8StringEncoding]];
		
		if (error) {
			//Purge file log
			[[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
			return;
		}
		
		[httpBody appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
		[httpBody appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
		
		[request setHTTPBody:httpBody];
		
		NSHTTPURLResponse *response = nil;

		[NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
		
		int statusCode = [response statusCode];
		if (!error && [response statusCode] == 200) { //Purge file log
			NSLog(@"Logs sent.");
			dispatch_async(dispatch_get_main_queue(), ^{
				if([self isSilentMode])
					return;

                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"successful" message:@"Upload Logs" delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles: nil];
                [alert show];
                [alert release];
            });
		} else {
			NSLog(@"AirOnApp failed to send data to server. Status code %d, error=%@", statusCode, error);
			NSString *message = [NSString stringWithFormat:@"AirOnApp failed to send data to server. Status code %d, error=%@", statusCode, error];
			dispatch_async(dispatch_get_main_queue(), ^{
				if([self isSilentMode])
					return;

                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error Log" message:message delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles: nil];
                [alert show];
                [alert release];
            });
		}
		
		//Purge file log
		[[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
	}
}

- (void) _internalCheckForUpdate {
	if(!_serviceURL)
		return;
	
	if([AironAppManager isAppStoreBuild])
		return;
	
	@autoreleasepool {
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/api/%@/%@", _serviceURL, _serviceVersion, @"http/getVersion"]]];
		[request setHTTPMethod:@"POST"];
		
		NSString *boundary = @"---------------------------AIRONAPP-mUlTiPaRtFoRm";
		NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary];
		[request addValue:contentType forHTTPHeaderField:@"Content-Type"];
		
		NSMutableData *httpBody = [NSMutableData data];
		
		NSMutableString *formData = [NSMutableString string];
		
		[formData setString:[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", boundary, @"data[application]", _appCode]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		
		[formData setString:[NSString stringWithFormat:@"--%@--\r\n", boundary]];
		[httpBody appendData:[formData dataUsingEncoding:NSUTF8StringEncoding]];
		
		[request setHTTPBody:httpBody];
		
		NSHTTPURLResponse *response = nil;
		NSError *error = nil;
		NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
		NSString *responseString = [[[[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] autorelease] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		if (!error && [response statusCode] == 200) {
			NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
			NSString *currentVersion = responseString;
			
			if (![appVersion isEqualToString:currentVersion])
				[self performSelectorOnMainThread:@selector(_updateApplication) withObject:nil waitUntilDone:YES];
		}
	}
}

- (void) _updateApplication {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:@"An update is available. Would you like to update?" delegate:self cancelButtonTitle:@"No" otherButtonTitles:@"Yes", nil];
	[alert show];
	[alert release];
}

#pragma mark - Screen Reporter methods

- (void)sendImage:(UIImage*)image withText:(NSString*)text{
    NSData *dataImage = UIImageJPEGRepresentation(image,1);
    [self performSelectorInBackground:@selector(_sendScreenshot:) withObject:dataImage];
}

#pragma mark - UIAlertView Delegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == 1) {
		NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/applications/update/%@", _serviceURL, _appCode]];
		
		// Open the connection to handle redirects to avoid opening Safari browser
		NSURLConnection *connection  = [[NSURLConnection alloc] initWithRequest:[NSMutableURLRequest requestWithURL:url] delegate:self];
		if (!connection) {
			return;
		}
		
		[connection release];
	}
}

#pragma mark NSURLConnection delegate methods

- (NSURLRequest *)connection: (NSURLConnection *)inConnection
			 willSendRequest: (NSURLRequest *)inRequest
			redirectResponse: (NSURLResponse *)inRedirectResponse;
{
	NSString * scheme = [[inRequest URL] scheme];
	if([scheme isEqualToString:@"itms-services"]) {
		//now it's ok to open itms url for application update
		[[UIApplication sharedApplication] openURL:[inRequest URL]];
		return nil;
	}
	
	return inRequest;
}

#pragma mark -

+ (AironAppManager *) sharedManager {
	static AironAppManager *instance;
	static dispatch_once_t predicate;
	dispatch_once(&predicate, ^{
		instance = [[self alloc] init];
	});
	return instance;
}

- (void)dealloc {
	[_serviceURL release];
	[_serviceVersion release];
    [_appCode release];
    [super dealloc];
}

@end



@interface UIApplication(SupressWarnings)

- (BOOL)application:(UIApplication *)application aa_didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
BOOL AAdynamicDidFinishLaunching(id self, SEL _cmd, id application, id launchOptions);

@end

#import <objc/runtime.h>

@implementation UIApplication(AirOnApp)



BOOL AAdynamicDidFinishLaunching(id self, SEL _cmd, id application, id launchOptions) {
	BOOL result = YES;
	
	if ([self respondsToSelector:@selector(application:aa_didFinishLaunchingWithOptions:)]) {
		result = (BOOL) [self application:application aa_didFinishLaunchingWithOptions:launchOptions];
	} else {
		[self applicationDidFinishLaunching:application];
		result = YES;
	}
	
	[[AironAppManager sharedManager] checkAndHandlePendingCrashReport];
	[[AironAppManager sharedManager] checkForUpdate];
    [[ScreenReporterManager sharedManager] addDectedEvent];
	return result;
}

- (void) aa_setDelegate:(id<UIApplicationDelegate>)delegate {
	Method method = nil;
	method = class_getInstanceMethod([delegate class], @selector(application:didFinishLaunchingWithOptions:));
	
	if (method) {
		class_addMethod([delegate class], @selector(application:aa_didFinishLaunchingWithOptions:), (IMP)AAdynamicDidFinishLaunching, "v@:::");
		method_exchangeImplementations(class_getInstanceMethod([delegate class], @selector(application:didFinishLaunchingWithOptions:)), class_getInstanceMethod([delegate class], @selector(application:aa_didFinishLaunchingWithOptions:)));
	} else {
		class_addMethod([delegate class], @selector(application:didFinishLaunchingWithOptions:), (IMP)AAdynamicDidFinishLaunching, "v@:::");
	}
	[self aa_setDelegate:delegate];
}

+ (void) load {
	method_exchangeImplementations(class_getInstanceMethod(self, @selector(setDelegate:)), class_getInstanceMethod(self, @selector(aa_setDelegate:)));
	NSLog(@"Aironapp loaded");
}

@end
