//
//  ScreenReporterManager.m
//  AironApp
//
//  Created by  Victor Ajsner on 17.10.12.
//  Copyright (c) 2012 Arello Mobile.
//

#import "ScreenReporterManager.h"
#import <QuartzCore/QuartzCore.h>
#import "AironAppManager.h"

@implementation ScreenReporterManager
@synthesize text, sendBlock, sendLog;

- (id)init{
	if(self = [super init]){
		self.sendBlock = ^(UIImage *image, NSString *_text){
			[[AironAppManager sharedManager] sendImage:image withText:_text];
		};
		self.sendLog = ^(){
			[[AironAppManager sharedManager] sendLog];
		};
	}
	return self;
}

#pragma mark - ScreenReporterDelegate

- (void)closeAction{
    [view removeFromSuperview];
    view.delegate = nil;
    [view release];
    view = nil;
    self.text = nil;
}

- (void)sendImage:(UIImage*)image withText:(NSString*)_text{
    self.text = _text;
    sendBlock(image, text);
}

- (void)sendLogs{
	sendLog();
}

#pragma mark - Private Methods

- (UIImage*)screenshot{
    CGImageRef screen = UIGetScreenImage();
    UIImage* image = [UIImage imageWithCGImage:screen];
    CGImageRelease(screen);

    return image;
}

- (void)switchMode{
	if(![[AironAppManager sharedManager] isConfigured]) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Aironapp SDK is not congifured yet. Please upload this build to Aironapp." delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles: nil];
		[alert show];
		[alert release];
		return;
	}

    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if(!view){
        view = [[ScreenReporterView alloc] initWithFrame:CGRectMake(0, 0, window.frame.size.width, window.frame.size.height)];
        view.image = [self screenshot];
        view.delegate = self;
        [window addSubview:view];
    }
}

#pragma mark - Publick Methods

+ (ScreenReporterManager*)sharedManager{
	static ScreenReporterManager *instance;
	static dispatch_once_t predicate;
	dispatch_once(&predicate, ^{
		instance = [[self alloc] init];
	});
	return instance;
}

- (void)addDectedEvent{
    UISwipeGestureRecognizer *oneFingerSwipeRight = [[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(switchMode)] autorelease];
    [oneFingerSwipeRight setNumberOfTouchesRequired:3];
    [oneFingerSwipeRight setDirection:UISwipeGestureRecognizerDirectionUp | UISwipeGestureRecognizerDirectionDown];
    [[UIApplication sharedApplication].keyWindow addGestureRecognizer:oneFingerSwipeRight];
}

#pragma mark - 

- (void)dealloc{
    view.delegate = nil;
    [view release];
    view = nil;
    self.text = nil;
    [super dealloc];
}

@end
