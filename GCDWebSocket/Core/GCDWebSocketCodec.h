//
//  GCDWebSocketCodec.h
//  Pods
//
//  Created by ruhong zhu on 2021/9/7.
//

#import <Foundation/Foundation.h>
#import "GCDWebSocketDefines.h"

typedef void(^GCDWebSocketDecodeCompletion)(GCDWebSocketMessage frame);
typedef void(^GCDWebSocketEncodeCompletion)(NSData *frame);

@protocol GCDWebSocketCodec <NSObject>

@end

@protocol GCDWebSocketDecoder <NSObject>

/// 对 data 做解码，解码成功消息从 completion 回调；
/// 解码后返回长度 result：
/// result < 0 表示数据错误，需要关闭连接；
/// result >= 0 表示已经被解码的数据长度，需要从缓存移除长度；
- (NSInteger)decode:(NSData *)data completion:(GCDWebSocketDecodeCompletion)completion;

@end

@protocol GCDWebSocketEncoder <NSObject>

/// 对 message 做编码，然后从 completion 回调；
- (void)encode:(GCDWebSocketMessage)message completion:(GCDWebSocketEncodeCompletion)completion;

@end

#pragma mark - Decoder

FOUNDATION_EXPORT BOOL GCDWebSocketIsValidFrame(uint8_t frame);
FOUNDATION_EXPORT BOOL GCDWebSocketIsFinalFragment(uint8_t frame);
FOUNDATION_EXPORT NSUInteger GCDWebSocketPayloadOpcode(uint8_t frame);
FOUNDATION_EXPORT BOOL GCDWebSocketIsPayloadMasked(uint8_t frame);
FOUNDATION_EXPORT NSUInteger GCDWebSocketPayloadLength(uint8_t frame);

/// 处理 WebSocket 消息解码
@interface GCDWebSocketDecoder : NSObject <GCDWebSocketDecoder>

@end

#pragma mark - Encoder

/// 处理 WebSocket 消息编码
@interface GCDWebSocketEncoder : NSObject <GCDWebSocketEncoder>

@end
