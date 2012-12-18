//
//  AironAppManager.h
//  AironApp
//
//  Created by Konstantin Kabanov on 3/5/12.
//  Copyright (c) 2012 Arello Mobile.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface AironAppManager : NSObject <UIAlertViewDelegate, NSURLConnectionDelegate> {
	NSString *_serviceURL;
	NSString *_serviceVersion;
	NSString *_appCode;
}

- (void) checkAndHandlePendingCrashReport;
- (void) checkForUpdate;
- (void) sendImage:(UIImage*)image withText:(NSString*)text;
- (void) sendLog;
- (BOOL) isConfigured;

+ (AironAppManager *) sharedManager;

@end
