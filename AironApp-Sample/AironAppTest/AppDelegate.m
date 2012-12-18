//
//  AppDelegate.m
//  AironAppTest
//
//  Created by Konstantin Kabanov on 3/5/12.
//  Copyright (c) 2012 Arello Mobile.
//

#import "AppDelegate.h"

@implementation AppDelegate

@synthesize window = _window;

- (void)dealloc
{
	[_window release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{	
	self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
	self.window.backgroundColor = [UIColor whiteColor];
	[self.window makeKeyAndVisible];
	
	UIButton *crashButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	crashButton.frame = CGRectMake(120.0f, 200.0f, 80.0f, 80.0f);
	[crashButton setTitle:@"Crash" forState:UIControlStateNormal];
	[crashButton addTarget:self action:@selector(crashButtonAction:) forControlEvents:UIControlEventTouchUpInside];
	
	UIButton *logButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	logButton.frame = CGRectMake(120.0f, 300.0f, 80.0f, 80.0f);
	[logButton setTitle:@"add Logs" forState:UIControlStateNormal];
	[logButton addTarget:self action:@selector(logButtonAction:) forControlEvents:UIControlEventTouchUpInside];

	[self.window addSubview:logButton];
	[self.window addSubview:crashButton];
	
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	/*
	 Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
	 Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
	 */
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
	/*
	 Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
	 If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
	 */
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
	/*
	 Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
	 */
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	/*
	 Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
	 */
}

- (void)applicationWillTerminate:(UIApplication *)application
{
	/*
	 Called when the application is about to terminate.
	 Save data if appropriate.
	 See also applicationDidEnterBackground:.
	 */
}


#pragma mark - Actions

- (void) crashMethod4 {
	NSLog(@"crash method 4");
	[self openUrl:[NSURL URLWithString:@"http://www.google.com/"]];
}

- (void) crashMethod3 {
	NSLog(@"crash method 3");
	[self crashMethod4];
}

- (void) crashMethod2 {
	NSLog(@"crash method 2");
	[self crashMethod3];
}

- (void) crashMethod1 {
	NSLog(@"crash method 1");
	[self crashMethod2];
}

- (IBAction) logButtonAction:(id)sender{
	NSLog(@"Add log");
}

- (IBAction) crashButtonAction:(id)sender {
	NSLog(@"crashButtonAction");
	[self crashMethod1];
}

#pragma mark -

@end
