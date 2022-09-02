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

#pragma mark - GCDWebSocketServerTransport

- (void)transport:(id<GCDWebSocketConnection>)transport received:(GCDWebSocketMessage)msg
{
    //echo message
    GCDWebSocketMessage echoMessage;
    echoMessage.header.fin = YES;
    echoMessage.header.opcode = GCDWebSocketOpcodeBinaryFrame;
    echoMessage.body.payload = msg.body.payload;
    [transport sendMessage:echoMessage];
}

@end
