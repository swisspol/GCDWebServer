/*
 Copyright (c) 2012-2013, Pierre-Olivier Latour
 All rights reserved.
 */

#import <UIKit/UIKit.h>

#import "GCDWebServer.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate> {
@private
  UIWindow* _window;
  GCDWebServer* _webServer;
}
@property(retain, nonatomic) UIWindow* window;
@end
