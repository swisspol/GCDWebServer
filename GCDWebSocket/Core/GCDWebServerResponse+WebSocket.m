//
//  GCDWebServerResponse+WebSocket.m
//  GCDWebServer
//
//  Created by ruhong zhu on 2021/9/3.
//

#import "GCDWebServerResponse+WebSocket.h"
#import "GCDWebServerRequest.h"
#import "GCDWebSocketHandshake.h"

BOOL GCDIsWebSocketRequest(GCDWebServerRequest *request)
{
    NSString *upgradeHeaderValue = request.headers[@"Upgrade"];
    NSString *connectionHeaderValue = request.headers[@"Connection"];
    BOOL isWebSocket = YES;
    if (!upgradeHeaderValue || !connectionHeaderValue) {
        isWebSocket = NO;
    } else if (![[upgradeHeaderValue lowercaseString] isEqualToString:@"websocket"]) {
        isWebSocket = NO;
    } else if ([connectionHeaderValue rangeOfString:@"Upgrade" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        isWebSocket = NO;
    }
    return isWebSocket;
}

@implementation GCDWebServerResponse (WebSocket)

+ (instancetype)responseWith:(GCDWebServerRequest *)request
{
    if (GCDIsWebSocketRequest(request)) {
        GCDWebSocketHandshake *handshake = [[GCDWebSocketHandshake alloc] initWith:request];
        return handshake;
    }
    
    //响应
    GCDWebServerResponse *response = [GCDWebServerResponse responseWithStatusCode:200];
    //响应头设置，跨域请求需要设置，只允许设置的域名或者ip才能跨域访问本接口）
    [response setValue:@"*" forAdditionalHeader:@"Access-Control-Allow-Origin"];
    [response setValue:@"Content-Type" forAdditionalHeader:@"Access-Control-Allow-Headers"];
    //设置options的实效性（我设置了12个小时=43200秒）
    [response setValue:@"43200" forAdditionalHeader:@"Access-Control-max-age"];
    return response;
}

@end
