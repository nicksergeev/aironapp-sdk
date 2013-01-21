//
//  ScreenReporterView.h
//  AironApp
//
//  Created by  Victor Ajsner on 17.10.12.
//  Copyright (c) 2012 Arello Mobile.
//

#import <UIKit/UIKit.h>

@protocol ScreenReporterDelegate <NSObject>

- (void)closeAction;
- (void)sendImage:(UIImage*)image withText:(NSString*)text;
- (void)sendLogs;

@end

@interface ScreenReporterView : UIView<UITextViewDelegate>{
    UIImageView *imageView;
    UIImage *oldImage;
    UIButton *showMenu;
    
    BOOL mouseSwiped;
    BOOL isEditImage;
    CGPoint lastPoint;
    
}

@property (nonatomic, retain) UIImage *image;
@property (nonatomic, retain) UIToolbar *menuToolbar;
@property (nonatomic, retain) UITextView *textField;
@property (nonatomic, assign) NSObject <ScreenReporterDelegate> *delegate;

+ (UIImage *) screenshot:(BOOL) captureOpenGL;

@end
