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

- (UIImage*)screenshot{
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIGraphicsBeginImageContext(window.bounds.size);
    [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return screenshot;
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
        self.image = [self screenshot];
        
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
