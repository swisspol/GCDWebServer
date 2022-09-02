//
//  GCDWebSocketServerConnection.h
//  Pods
//
//  Created by ruhong zhu on 2021/9/3.
//

#import <Foundation/Foundation.h>
#import "GCDWebServerConnection.h"
#import "GCDWebSocketCodec.h"

@protocol GCDWebSocketConnection <NSObject>

- (void)receiveMessage:(GCDWebSocketMessage)message;
- (void)sendMessage:(GCDWebSocketMessage)message;

@end

@interface GCDWebSocketServerConnection : GCDWebServerConnection <GCDWebSocketConnection>

/// 长链接等待读取间隔时长，单位：秒/s，默认5秒；
@property (nonatomic, assign) NSTimeInterval readInterval;
/// 最近一次读取到数据时间，超时时断开链接；
@property (nonatomic, assign) NSTimeInterval lastReadDataTime;

/// websocket protocol decoder
@property (nonatomic, strong) id<GCDWebSocketDecoder> decoder;
/// websocket protocol encoder
@property (nonatomic, strong) id<GCDWebSocketEncoder> encoder;

@end
