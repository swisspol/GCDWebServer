//
//  GCDWebSocketCodec.m
//  GCDWebServer
//
//  Created by 十年之前 on 2022/9/1.
//

#import "GCDWebSocketCodec.h"
#import "GCDWebServerPrivate.h"

#pragma mark - Decoder

BOOL GCDWebSocketIsValidFrame(uint8_t frame)
{
    uint8_t rsv = frame & GCDWebSocketRsvMask;
    uint8_t opcode = frame & GCDWebSocketOpcodeMask;
    // 3-7 reerved；B-F reserved；
    if (rsv || (3 <= opcode && opcode <= 7) || (0xB <= opcode && opcode <= 0xF)) {
        return NO;
    }
    return YES;
}

/**
 * 第一个字节的最高位，看是0还是1；
 * 0-表示是消息的某个分片，表示后面还有数据；
 * 1-表示是消息的最后一个分片，即全部消息结束了(发送的数据比较少，一次发送完成)
 */
BOOL GCDWebSocketIsFinalFragment(uint8_t frame)
{
    return (frame & GCDWebSocketFinMask) ? YES : NO;
}

/**
 * 第一个字节剩下的后四位表示的是操作码，代表的是数据帧类型，比如文本类型、二进制类型等；
 */
NSUInteger GCDWebSocketPayloadOpcode(uint8_t frame)
{
    return frame & GCDWebSocketOpcodeMask;
}

/**
 * MASK：1位，用于标识PayloadData是否经过掩码处理；第二个字节的第一位，判断是否有掩码；
 * 客户端发出的数据帧需要进行掩码处理，所以此位是1，数据需要解码。
 */
BOOL GCDWebSocketIsPayloadMasked(uint8_t frame)
{
    return (frame & GCDWebSocketMaskMask) ? YES : NO;
}

/**
 * Payload length === x
 * 如果 x 值在 0-125，则是payload的真实长度。
 * 如果 x 值是 126，则后面2个字节形成的16位无符号整型数的值是payload的真实长度。
 * 如果 x 值是 127，则后面8个字节形成的64位无符号整型数的值是payload的真实长度。
 * 如果payload length占用了多个字节的话，payload length的二进制表达采用网络序（big endian，重要的位在前）。
 */
NSUInteger GCDWebSocketPayloadLength(uint8_t frame)
{
    return frame & GCDWebSocketPayloadLenMask;
}

@implementation GCDWebSocketDecoder

- (NSInteger)decode:(NSData *)data completion:(GCDWebSocketDecodeCompletion)completion
{
    NSInteger result = 0;
    
    NSMutableData *readBuffer = [NSMutableData dataWithData:data];
    const uint8_t *headerBuffer = readBuffer.bytes;
    NSUInteger headIndex = 0;
    while (readBuffer.length - headIndex > 2) {
        GCDWebSocketFrameHeader frameHeader;
        memset(&frameHeader, 0, sizeof(frameHeader));
        // 第一个字节
        uint8_t firstByte = headerBuffer[headIndex];
        if (GCDWebSocketIsValidFrame(firstByte)) {
            frameHeader.opcode = GCDWebSocketPayloadOpcode(firstByte);
        } else {
            result = -1;
            break;
        }
        
        // 第二个字节
        uint8_t secondByte = headerBuffer[headIndex + 1];
        frameHeader.masked = GCDWebSocketIsPayloadMasked(secondByte);
        NSUInteger payloadLength = GCDWebSocketPayloadLength(secondByte);
        NSInteger frameLength = 1;// 帧字节个数；
        if (payloadLength <= 125) {
            // 长度用第二个字节剩下的7位表示；
            frameHeader.payloadLength = payloadLength;
            frameLength = 1 + 1;
        } else if (payloadLength == 126) {
            // 长度用第三和第四个字节表示；
            int16_t extendedPayloadLength = 0;
            [readBuffer getBytes:&extendedPayloadLength range:NSMakeRange(headIndex + 2, 2)];
            frameHeader.payloadLength = CFSwapInt16BigToHost(extendedPayloadLength);
            frameLength = 1 + 1 + 2;
        } else if (payloadLength == 127) {
            frameLength = 1 + 1 + 8;
            // 8个字节的前4个字节值必须为0，否则数据异常，连接必须关闭；
            // 长度用第六到第十个字节表示；
            int32_t pre4Byte = 0;
            [readBuffer getBytes:&pre4Byte range:NSMakeRange(headIndex + 2, 4)];
            if (pre4Byte == 0) {
                uint32_t extendedPayloadLength = 0;
                [readBuffer getBytes:&extendedPayloadLength range:NSMakeRange(headIndex + 2 + 4, 4)];
                frameHeader.payloadLength = CFSwapInt16BigToHost(extendedPayloadLength);
            } else {
                // 64bit data size in memory?
                result = -2;
                break;
            }
        }
        
        //masking key
        if (frameHeader.masked && (readBuffer.length - headIndex < frameLength + 4)) {
            break;
        }
        NSData *maskingKeyData = nil;
        if (frameHeader.masked) {
            NSRange maskingKeyRange = NSMakeRange(headIndex + frameLength, 4);
            maskingKeyData = [readBuffer subdataWithRange:maskingKeyRange];
            frameLength += 4;
        }
        
        GCDWebSocketFrameBody frameBody;
        memcpy(frameBody.maskingKey, maskingKeyData.bytes, sizeof(frameBody.maskingKey));
        
        //payload
        if (readBuffer.length - headIndex < frameLength + frameHeader.payloadLength) {
            break;
        }
        NSRange payloadRange = NSMakeRange(headIndex + frameLength, frameHeader.payloadLength);
        NSMutableData *payload = [readBuffer subdataWithRange:payloadRange].mutableCopy;
        uint8_t *pPayload = (uint8_t *)payload.bytes;
        if (frameHeader.masked && maskingKeyData) {
            for (NSInteger i=0; i<frameHeader.payloadLength; i++) {
                pPayload[i] = pPayload[i] ^ frameBody.maskingKey[i % 4];
            }
        }
        frameBody.payload = payload;
        
        GWS_LOG_DEBUG(@"[Frame] print begin ...");
        GWS_LOG_DEBUG(@"[Frame] header: fin = %d, opcode = %d, length = %lu", frameHeader.fin, frameHeader.opcode, frameHeader.payloadLength);
        GWS_LOG_DEBUG(@"[Frame] masking key: %@", maskingKeyData);
        GWS_LOG_DEBUG(@"[Frame] payload: %@", frameBody.payload);
        GWS_LOG_DEBUG(@"[Frame] print end ...");
        
        //receive message
        GCDWebSocketMessage message;
        message.header = frameHeader;
        message.body = frameBody;
        !completion ?: completion(message);
        
        //move head index
        headIndex += frameLength + frameHeader.payloadLength;
        result = headIndex;
    }
    
    GWS_LOG_DEBUG(@"=====================> [Codec] decoded data length: %ld", result);
    return result;
}

@end


#pragma mark - Encoder

@implementation GCDWebSocketEncoder

- (void)encode:(GCDWebSocketMessage)message completion:(GCDWebSocketEncodeCompletion)completion
{
    NSMutableData *sendData = [NSMutableData data];
    
    uint8_t firstByte = 0;
    firstByte = firstByte | (message.header.fin ? 0x80 : 0x0);
    firstByte = firstByte | message.header.opcode;
    [sendData appendBytes:&firstByte length:1];
    
    //服务端发送数据不做 mask，第二个字节直接为 payload length；
    uint8_t secondByte = 0;
    if (message.body.payload.length <= 125) {
        secondByte = message.body.payload.length;
        [sendData appendBytes:&secondByte length:1];
    } else if (message.body.payload.length <= 65535) {
        secondByte = 126;
        [sendData appendBytes:&secondByte length:1];
        int16_t length = CFSwapInt16(message.body.payload.length);
        [sendData appendBytes:&length length:2];
    } else {
        secondByte = 127;
        [sendData appendBytes:&secondByte length:1];
        int32_t pre4Byte = 0;
        int32_t payloadLength = (int32_t)message.body.payload.length;
        int32_t length = CFSwapInt32(payloadLength);
        [sendData appendBytes:&pre4Byte length:4];
        [sendData appendBytes:&length length:4];
    }
    
    [sendData appendData:message.body.payload];
    !completion ?: completion(sendData);
}

@end
