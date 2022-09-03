//
//  GCDWebSocketEchoServer.m
//  Pods
//
//  Created by ruhong zhu on 2021/9/4.
//

#import "GCDWebSocketEchoServer.h"
#import "GCDWebSocketServerConnection.h"

@interface GCDWebSocketEchoServer () <GCDWebSocketServerTransport>

@end

@implementation GCDWebSocketEchoServer

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.transport = self;
    }
    return self;
}

#pragma mark - GCDWebSocketServerTransport

- (void)transport:(GCDWebServerConnection *)transport received:(GCDWebSocketMessage)msg
{
    GCDWebSocketServerConnection *connection = nil;
    if ([transport isKindOfClass:[GCDWebSocketServerConnection class]]) {
        connection = (GCDWebSocketServerConnection *)transport;
    }
    
    //echo message
    GCDWebSocketMessage echoMessage;
    echoMessage.header.fin = YES;
    echoMessage.header.opcode = GCDWebSocketOpcodeBinaryFrame;
    echoMessage.body.payload = msg.body.payload;
    [connection sendMessage:echoMessage];
}

@end
