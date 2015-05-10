//
//  WebServer.h
//  WebServer
//
//  Created by Florent Vilmart on 2015-05-10.
//
//

#import <UIKit/UIKit.h>

//! Project version number for WebServer.
FOUNDATION_EXPORT double WebServerVersionNumber;

//! Project version string for WebServer.
FOUNDATION_EXPORT const unsigned char WebServerVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <WebServer/PublicHeader.h>

#import <WebServer/GCDWebServer.h>
#import <WebServer/GCDWebServerFileRequest.h>
#import <WebServer/GCDWebServerDataResponse.h>
#import <WebServer/GCDWebServerFunctions.h>
#import <WebServer/GCDWebServerDataRequest.h>
#import <WebServer/GCDWebServerRequest.h>
#import <WebServer/GCDWebServerConnection.h>
#import <WebServer/GCDWebServerPrivate.h>
#import <WebServer/GCDWebServerHTTPStatusCodes.h>
#import <WebServer/GCDWebServerFileResponse.h>
#import <WebServer/GCDWebServerMultiPartFormRequest.h>
#import <WebServer/GCDWebServerStreamedResponse.h>
#import <WebServer/GCDWebServerResponse.h>
#import <WebServer/GCDWebServerURLEncodedFormRequest.h>
#import <WebServer/GCDWebServer.h>
#import <WebServer/GCDWebServerErrorResponse.h>