//
//  GCDWebSocketHandshake.h
//  Pods
//
//  Created by ruhong zhu on 2021/9/4.
//

#import "GCDWebServerResponse.h"
#import "GCDWebServerRequest.h"

@interface GCDWebSocketHandshake : GCDWebServerResponse

- (instancetype)initWith:(GCDWebServerRequest *)request;

@end
