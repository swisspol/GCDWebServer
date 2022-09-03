//
//  GCDWebSocketServer.h
//  Pods
//
//  Created by ruhong zhu on 2021/9/20.
//

#import "GCDWebServer.h"
#import "GCDWebSocketDefines.h"

@class GCDWebServerConnection;

@protocol GCDWebSocketServerTransport <NSObject>

@optional

- (void)transportWillStart:(GCDWebServerConnection *)transport;
- (void)transportWillEnd:(GCDWebServerConnection *)transport;
- (void)transport:(GCDWebServerConnection *)transport received:(GCDWebSocketMessage)msg;

@end

@interface GCDWebSocketServer : GCDWebServer

/// Sets the timeout value for connections，default is 30 second
@property (nonatomic, assign) NSTimeInterval timeout;
/// Sets the transport for the connections
@property (nonatomic, weak) id<GCDWebSocketServerTransport> transport;

@end
