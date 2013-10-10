/*
 Copyright (c) 2012-2013, Pierre-Olivier Latour
 All rights reserved.
 */

#import "AppDelegate.h"

@implementation AppDelegate

- (void)dealloc {
  [_window release];
  
  [super dealloc];
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  _window.backgroundColor = [UIColor whiteColor];
  [_window makeKeyAndVisible];
  
  _webServer = [[GCDWebServer alloc] init];
  [_webServer addDefaultHandlerForMethod:@"GET"
                            requestClass:[GCDWebServerRequest class]
                            processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
    
  }];
  [_webServer start];
  
  return YES;
}

@end
