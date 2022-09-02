//
//  GCDWebSocketDefines.h
//  Pods
//
//  Created by ruhong zhu on 2021/9/10.
//

/* From RFC:

0                   1                   2                   3
0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
|     Extended payload length continued, if payload len == 127  |
+ - - - - - - - - - - - - - - - +-------------------------------+
|                               |Masking-key, if MASK set to 1  |
+-------------------------------+-------------------------------+
| Masking-key (continued)       |          Payload Data         |
+-------------------------------- - - - - - - - - - - - - - - - +
:                     Payload Data continued ...                :
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
|                     Payload Data continued ...                |
+---------------------------------------------------------------+
*/

/**
 * 第一个字节(8位)，第一个字节的最高位表示的是FIN标识；
 * 如果FIN为1表示这是消息的最后一部分分片(fragment),就是消息已经发送完毕了；如果FIN为0表示这不是消息的最后一部分数据，后续还会有数据过来；
 * FIN位后的RSV1，RSV2，RSV3，各占一位，一般值都为0，主要用于WebSocket协议的扩展，所以可以认为这三位都是0；
 * 第一个字节剩下的后四位表示的是操作码，代表的是数据帧类型，比如文本类型、二进制类型等；
 *
 * 第二个字节(8位)，第二个字节的最高位表示的是Mask位；
 * 如果Mask位为1，表示这是客户端发送过来的数据，客户端发送的数据要进行掩码；如果Mask为0，表示这是服务端发送的数据；
 * 第二个字节还剩下7位，表示的是传输字节的长度，其值为0-127，根据值的不同，存储数据长度的位置可能会向后扩展；
 * 其规则为：
 * 如果这7位表示的值在[0-125]之间那么就不用向后扩展，第二个字节的后7位就足够存储，这个7位表示的值就是发送数据的长度；
 * 如果这7位表示的值为126，表示客户端发送数据的字节长度在(125,65535)之间，需要16位来存储字节长度，所以用第三和第四个字节来表示发送数据的长度；
 * 如果这7位表示的值为127，表示客户端发送的数据的字节长度大于65535，就要用64位，8个字节才存储数据长度，即第三到第10个字节来存储，
 * 但是这8个字节的前4个字节值必须为0，否则数据异常，连接必须关闭，所以其实是用第七到第十个字节来存储数据的长度。
 *
 * 根据以上规则，我们就可以知道真实数据的位置了，接下来我们就可以对真实数据进行解析了；
 * 如果第二个字节的第一位即Mask位值为1，那么表示客户端发送的数据，那么真实数据之前就会有四个字节的掩码；
 * 解码数据的时候，我们要使用到这个掩码，因为掩码有4个字节，所以解码的时候，我们要遍历真实数据，然后依次与掩码进行异或运算。
 */

#ifndef GCDWebSocketDefines_h
#define GCDWebSocketDefines_h

typedef NS_ENUM(NSInteger, GCDWebSocketOpcode) {
    GCDWebSocketOpcodeContinuationFrame = 0x0,
    GCDWebSocketOpcodeTextFrame = 0x1,
    GCDWebSocketOpcodeBinaryFrame = 0x2,
    // 3-7 reerved
    GCDWebSocketOpcodeConnectionClose = 0x8,
    GCDWebSocketOpcodePing = 0x9,
    GCDWebSocketOpcodePong = 0xA,
    // B-F reserved
};

typedef struct GCDWebSocketFrameHeader {
    BOOL fin;
    BOOL rsv1;
    BOOL rsv2;
    BOOL rsv3;
    uint8_t opcode;
    BOOL masked;
    NSUInteger payloadLength;
} GCDWebSocketFrameHeader;

typedef struct GCDWebSocketFrameBody {
    uint8_t maskingKey[4];
    NSData *payload;
} GCDWebSocketFrameBody;

typedef struct GCDWebSocketMessage {
    GCDWebSocketFrameHeader header;
    GCDWebSocketFrameBody body;
} GCDWebSocketMessage;

#define GCDWebSocketFinMask             0x80
#define GCDWebSocketOpcodeMask          0x0F
#define GCDWebSocketRsvMask             0x70
#define GCDWebSocketMaskMask            0x80
#define GCDWebSocketPayloadLenMask      0x7F

#endif /* GCDWebSocketDefines_h */
