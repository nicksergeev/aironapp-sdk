//
//  ScreenReporterManager.h
//  AironApp
//
//  Created by  Victor Ajsner on 17.10.12.
//  Copyright (c) 2012 Arello Mobile.
//

#import <Foundation/Foundation.h>
#import "ScreenReporterView.h"
#import <UIKit/UIKit.h>

typedef void (^SendBlock)(UIImage *image, NSString *text);
typedef void (^SendLog)();

@interface ScreenReporterManager : NSObject<ScreenReporterDelegate>{
    ScreenReporterView * view;
    NSObject<ScreenReporterDelegate> *delegate;
    NSString *text;
}


@property (nonatomic, retain) NSString *text;
@property (nonatomic, assign) SendBlock sendBlock;
@property (nonatomic, assign) SendLog sendLog;

+ (ScreenReporterManager*)sharedManager;
- (void)addDectedEvent;

@end
