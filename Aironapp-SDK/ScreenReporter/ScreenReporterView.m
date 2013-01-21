//
//  ScreenReporterView.m
//  AironApp
//
//  Created by  Victor Ajsner on 17.10.12.
//  Copyright (c) 2012 Arello Mobile.
//

#import "ScreenReporterView.h"
#import <QuartzCore/QuartzCore.h>
#import "AironAppManager.h"

#import <UIKit/UIKit.h>
@interface UIView (findEAGLView)
- (UIView *)findEAGLView;
@end

@implementation UIView (findEAGLView)
- (UIView *)findEAGLView
{
    NSLog(@"%@", self);
	if([[[self class] layerClass] isSubclassOfClass:[CAEAGLLayer class]])
	{
		return self;
	}
	
    for (UIView *subview in self.subviews)
    {
		UIView * view = [subview findEAGLView];
        if(view != nil)
			return view;
    }
	
	return nil;
}
@end

@implementation ScreenReporterView
@synthesize image, menuToolbar, delegate, textField;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        imageView = [[UIImageView alloc] initWithFrame:frame];
        [self addSubview:imageView];
        [self createMenu];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWasShown:)
                                                     name:UIKeyboardDidShowNotification
                                                   object:nil];
        //For Later Use
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillHide:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark - Draw Image

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if(!isEditImage){
        return;
    }
    mouseSwiped = NO;
    UITouch *touch = [touches anyObject];
    
    if ([[event allTouches] count] == 2) {
        menuToolbar.hidden = NO;
        isEditImage = NO;
        return;
    }
    
    lastPoint = [touch locationInView:self];
    lastPoint.y -= 20;
    
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if(!isEditImage){
        return;
    }
    mouseSwiped = YES;
    
    UITouch *touch = [touches anyObject];
    CGPoint currentPoint = [touch locationInView:self];
    currentPoint.y -= 20;
    
    UIGraphicsBeginImageContext(self.frame.size);
    [imageView.image drawInRect:CGRectMake(0, 0, self.frame.size.width, self.frame.size.height)];
    CGContextSetLineCap(UIGraphicsGetCurrentContext(), kCGLineCapRound);
    CGContextSetLineWidth(UIGraphicsGetCurrentContext(), 2.0);
    CGContextSetRGBStrokeColor(UIGraphicsGetCurrentContext(), 1.0, 0.0, 0.0, 1.0);
    CGContextBeginPath(UIGraphicsGetCurrentContext());
    CGContextMoveToPoint(UIGraphicsGetCurrentContext(), lastPoint.x, lastPoint.y);
    CGContextAddLineToPoint(UIGraphicsGetCurrentContext(), currentPoint.x, currentPoint.y);
    CGContextStrokePath(UIGraphicsGetCurrentContext());
    imageView.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    lastPoint = currentPoint;
    
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if(!isEditImage){
        return;
    }
    
    UITouch *touch = [touches anyObject];

    if ([touch tapCount] == 2) {
        menuToolbar.hidden = NO;
        isEditImage = NO;
        return;
    }
    
    if(!mouseSwiped) {
        UIGraphicsBeginImageContext(self.frame.size);
        [imageView.image drawInRect:CGRectMake(0, 0, self.frame.size.width, self.frame.size.height)];
        CGContextSetLineCap(UIGraphicsGetCurrentContext(), kCGLineCapRound);
        CGContextSetLineWidth(UIGraphicsGetCurrentContext(), 2.0);
        CGContextSetRGBStrokeColor(UIGraphicsGetCurrentContext(), 1.0, 0.0, 0.0, 1.0);
        CGContextMoveToPoint(UIGraphicsGetCurrentContext(), lastPoint.x, lastPoint.y);
        CGContextAddLineToPoint(UIGraphicsGetCurrentContext(), lastPoint.x, lastPoint.y);
        CGContextStrokePath(UIGraphicsGetCurrentContext());
        CGContextFlush(UIGraphicsGetCurrentContext());
        imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
}



#import <OpenGLES/ES1/glext.h>
// IMPORTANT: Call this method after you draw and before -presentRenderbuffer:.
// Or set
//CAEAGLLayer *eaglLayer = (CAEAGLLayer *) self.layer;
//	eaglLayer.drawableProperties = @{
//	kEAGLDrawablePropertyRetainedBacking: [NSNumber numberWithBool:YES],
//	kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
//};
//kEAGLDrawablePropertyRetainedBacking = YES
+ (UIImage *) openGlScreenshot:(UIView *) eaglview
{
    GLint backingWidth, backingHeight;
	
    // Bind the color renderbuffer used to render the OpenGL ES view
    // If your application only creates a single color renderbuffer which is already bound at this point,
    // this call is redundant, but it is needed if you're dealing with multiple renderbuffers.
    // Note, replace "_colorRenderbuffer" with the actual name of the renderbuffer object defined in your class.
//    glBindRenderbufferOES(GL_RENDERBUFFER_OES, _colorRenderbuffer);	//I don't know colorbuffer pointer
	
    // Get the size of the backing CAEAGLLayer
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
	
    NSInteger x = 0, y = 0, width = backingWidth, height = backingHeight;
    NSInteger dataLength = width * height * 4;
    GLubyte *data = (GLubyte*)malloc(dataLength * sizeof(GLubyte));
	
    // Read pixel data from the framebuffer
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(x, y, width, height, GL_RGBA, GL_UNSIGNED_BYTE, data);
	
    // Create a CGImage with the pixel data
    // If your OpenGL ES content is opaque, use kCGImageAlphaNoneSkipLast to ignore the alpha channel
    // otherwise, use kCGImageAlphaPremultipliedLast
    CGDataProviderRef ref = CGDataProviderCreateWithData(NULL, data, dataLength, NULL);
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGImageRef iref = CGImageCreate(width, height, 8, 32, width * 4, colorspace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast,
                                    ref, NULL, true, kCGRenderingIntentDefault);
	
    // OpenGL ES measures data in PIXELS
    // Create a graphics context with the target size measured in POINTS
    NSInteger widthInPoints, heightInPoints;
    if (NULL != UIGraphicsBeginImageContextWithOptions) {
        // On iOS 4 and later, use UIGraphicsBeginImageContextWithOptions to take the scale into consideration
        // Set the scale parameter to your OpenGL ES view's contentScaleFactor
        // so that you get a high-resolution snapshot when its value is greater than 1.0
        CGFloat scale = eaglview.contentScaleFactor;	//TODO: what to do with this scale factor if I don't have view!????
        widthInPoints = width / scale;
        heightInPoints = height / scale;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(widthInPoints, heightInPoints), NO, scale);
    }
    else {
        // On iOS prior to 4, fall back to use UIGraphicsBeginImageContext
        widthInPoints = width;
        heightInPoints = height;
        UIGraphicsBeginImageContext(CGSizeMake(widthInPoints, heightInPoints));
    }
	
    CGContextRef cgcontext = UIGraphicsGetCurrentContext();
	
    // UIKit coordinate system is upside down to GL/Quartz coordinate system
    // Flip the CGImage by rendering it to the flipped bitmap context
    // The size of the destination area is measured in POINTS
    CGContextSetBlendMode(cgcontext, kCGBlendModeCopy);
    CGContextDrawImage(cgcontext, CGRectMake(0.0, 0.0, widthInPoints, heightInPoints), iref);
	
    // Retrieve the UIImage from the current context
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	
    UIGraphicsEndImageContext();
	
    // Clean up
    free(data);
    CFRelease(ref);
    CFRelease(colorspace);
    CGImageRelease(iref);
	
    return image;
}

+ (void) renderLayer:(UIView *) view context:(CGContextRef)context
{
	// -renderInContext: renders in the coordinate space of the layer,
	// so we must first apply the layer's geometry to the graphics context
	CGContextSaveGState(context);
	// Center the context around the window's anchor point
	CGContextTranslateCTM(context, [view center].x, [view center].y);
	// Apply the window's transform about the anchor point
	CGContextConcatCTM(context, [view transform]);
	// Offset by the portion of the bounds left of and above the anchor point
	CGContextTranslateCTM(context,
						  -[view bounds].size.width * [[view layer] anchorPoint].x,
						  -[view bounds].size.height * [[view layer] anchorPoint].y);
	
	// Render the layer hierarchy to the current context
	[[view layer] renderInContext:context];
	
	// Restore the context
	CGContextRestoreGState(context);
}

//UIKit Screenshot as per: https://developer.apple.com/library/ios/#qa/qa2010/qa1703.html
+ (UIImage *) screenshot:(BOOL) captureOpenGL
{
	//Apple: why so complicated??? It used to be just one function. Now I'm trying to shoot myself in the leg.
	UIView * eaglview = nil;
	UIImage * openGLImage = nil;
	
	if(captureOpenGL)
	{
		eaglview = [[UIApplication sharedApplication].keyWindow findEAGLView];
		if(eaglview)
			openGLImage = [ScreenReporterView openGlScreenshot:eaglview];
	}

    // Create a graphics context with the target size
    // On iOS 4 and later, use UIGraphicsBeginImageContextWithOptions to take the scale into consideration
    // On iOS prior to 4, fall back to use UIGraphicsBeginImageContext
    CGSize imageSize = [[UIScreen mainScreen] bounds].size;
    if (NULL != UIGraphicsBeginImageContextWithOptions)
        UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0);
    else
        UIGraphicsBeginImageContext(imageSize);
	
    CGContextRef context = UIGraphicsGetCurrentContext();

    // Iterate over every window from back to front
    for (UIWindow *window in [[UIApplication sharedApplication] windows])
    {
        if (![window respondsToSelector:@selector(screen)] || [window screen] == [UIScreen mainScreen])
        {
			[ScreenReporterView renderLayer:window context:context];

			if(eaglview)
			{
				NSInteger index = [window.subviews indexOfObject:eaglview];
				if(index != NSNotFound)
				{
					//render opengl image
					if(openGLImage)
					{
						UIImageView *glImage = [[UIImageView alloc] initWithImage:openGLImage];
						glImage.transform = CGAffineTransformMakeScale(1, -1);
						[glImage.layer renderInContext:context];
					}
					
					for(UIView * view in eaglview.subviews)
						[ScreenReporterView renderLayer:view context:context];
					
					for(int i = index+1; i < [window.subviews count]; ++i)
					{
						UIView * view = [window.subviews objectAtIndex:i];
						[ScreenReporterView renderLayer:view context:context];
					}
				}
			}
        }
    }
	
    // Retrieve the screenshot image
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - Setter Methods

- (void)setImage:(UIImage *)_image{
    [_image retain];
    [image release];
    [oldImage release];
    oldImage = [_image copy];
    image = _image;
    imageView.image = image;
}

#pragma mark - Action

- (void)showMenu{
    menuToolbar.hidden = NO;
    isEditImage = NO;
}

- (void)editImage{
    textField.hidden = YES;
    menuToolbar.hidden = YES;
    isEditImage = YES;
}

- (void)closeAction{
    if(delegate){
        [delegate closeAction];
    }
}

- (void)sendAction{
    if(delegate){
        menuToolbar.hidden = YES;
        showMenu.hidden = YES;
		
		BOOL textHidden = textField.hidden;
        textField.hidden = YES;
		
		//get the screenshot with no toolbar e.t.c, don't have to capture openGl as we drawing on static image
		self.image = [ScreenReporterView screenshot:NO];
        
        [delegate sendImage:image withText:textField.text];
        textField.hidden = textHidden;
        menuToolbar.hidden = NO;
        showMenu.hidden = NO;
    }
}

- (void)editTextAction{
    if(!textField){
        textField = [[UITextView alloc] init];
        [textField setFrame:CGRectMake(0, self.frame.size.height - (200 + menuToolbar.frame.size.height), menuToolbar.frame.size.width, 200)];
        textField.layer.borderWidth = 1;
        textField.layer.borderColor = [UIColor blackColor].CGColor;
        [textField.layer setMasksToBounds:YES];
        textField.text = @"";
        textField.delegate = self;
        [self addSubview:textField];
        textField.hidden = YES;
    }
    textField.hidden = !textField.hidden;
}

- (void)sendLog{
	if(delegate){
		[delegate sendLogs];
	}
}

- (void)replaceImageAction{
    self.image = oldImage;
}

#pragma mark - Private Methods

- (void)createMenu{
    if(menuToolbar){
        [menuToolbar removeFromSuperview];
        [menuToolbar release];
    }
    
    showMenu = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [showMenu setFrame:CGRectMake(0, self.frame.size.height - 25, 44 , 25)];
    [showMenu setTitle:@"Exit" forState:UIControlStateNormal];
    [showMenu addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    
    
    menuToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, self.frame.size.height - 44, self.frame.size.width, 44)];
    
    UIBarButtonItem *itemEditImage = [[UIBarButtonItem alloc] initWithTitle:@"Edit" style:UIBarButtonItemStyleBordered target:self action:@selector(editImage)];
    UIBarButtonItem *itemEditText = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(editTextAction)];
    [itemEditText setStyle:UIBarButtonItemStyleBordered];
    UIBarButtonItem *itemSend = [[UIBarButtonItem alloc] initWithTitle:@"Send" style:UIBarButtonItemStyleBordered target:self action:@selector(sendAction)];
    UIBarButtonItem *itemReplaceImage = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemReply target:self action:@selector(replaceImageAction)];
    [itemReplaceImage setStyle:UIBarButtonItemStyleBordered];
    UIBarButtonItem *itemExit = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(closeAction)];
    [itemExit setStyle:UIBarButtonItemStyleBordered];
    UIBarButtonItem *itemSendLog = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(sendLog)];
    [itemSendLog setStyle:UIBarButtonItemStyleBordered];
	
    [menuToolbar setItems:[NSArray arrayWithObjects:itemSendLog, itemEditImage, itemSend, itemEditText, itemReplaceImage, itemExit, nil]];
    
    [itemEditImage release];
    [itemEditText release];
    [itemReplaceImage release];
    [itemSend release];
    [itemExit release];
	[itemSendLog release];
    
    [self addSubview:showMenu];
    [self addSubview:menuToolbar];
    

}

#pragma mark - UITextFieldDelegate

- (void)keyboardWasShown:(NSNotification *)notification{
    // Get the size of the keyboard.
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    [UIView animateWithDuration:0.2f animations:^{
    } completion:^(BOOL finished) {
        [textField setFrame:CGRectMake(textField.frame.origin.x, self.frame.size.height - (keyboardSize.height + textField.frame.size.height), textField.frame.size.width, textField.frame.size.height)];
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification{
    [UIView animateWithDuration:0.2f animations:^{
    } completion:^(BOOL finished) {
        [textField setFrame:CGRectMake(0, self.frame.size.height - (200 + menuToolbar.frame.size.height), menuToolbar.frame.size.width, 200)];
    }];
}

-(BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if([text isEqualToString:@"\n"])
    {
        [textView resignFirstResponder];
        return NO;
    }
    return YES;
}

#pragma mark - 

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.image = nil;
    self.textField = nil;
    imageView.image = nil;
    self.menuToolbar = nil;
    [imageView release];
    [oldImage release];
    [super dealloc];
}

@end
