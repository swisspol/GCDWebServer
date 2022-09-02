//
//  GCDWebServerResponse+WebSocket.h
//  GCDWebServer
//
//  Created by ruhong zhu on 2021/9/3.
//

#import "GCDWebServerResponse.h"

@class GCDWebServerRequest;

FOUNDATION_EXPORT BOOL GCDIsWebSocketRequest(GCDWebServerRequest *request);

@interface GCDWebServerResponse (WebSocket)

+ (instancetype)responseWith:(GCDWebServerRequest *)request;

@end
