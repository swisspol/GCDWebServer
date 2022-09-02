//
//  GCDWebSocketServer.h
//  Pods
//
//  Created by ruhong zhu on 2021/9/20.
//

#import "GCDWebServer.h"
#import "GCDWebSocketDefines.h"

@protocol GCDWebSocketConnection;

@protocol GCDWebSocketServerTransport <NSObject>

@optional

- (void)transportWillStart:(id<GCDWebSocketConnection>)transport;
- (void)transportWillEnd:(id<GCDWebSocketConnection>)transport;
- (void)transport:(id<GCDWebSocketConnection>)transport received:(GCDWebSocketMessage)msg;

@end

@interface GCDWebSocketServer : GCDWebServer

/// Sets the timeout value for connections，default is 60 second
@property (nonatomic, assign) NSTimeInterval timeout;
/// Sets the transport for the connections
@property (nonatomic, weak) id<GCDWebSocketServerTransport> transport;

@end
