//
//  GCDWebSocketServerConnection.m
//  Pods
//
//  Created by ruhong zhu on 2021/9/3.
//

#import "GCDWebSocketServerConnection.h"
#import "GCDWebServerPrivate.h"
#import "GCDWebSocketServer.h"
#import "GCDWebSocketHandshake.h"

@interface GCDWebSocketServerConnection ()

@property (nonatomic,   weak) GCDWebSocketServer *wsServer;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic,   copy) GCDWebServerCompletionBlock completion;
@property (nonatomic, strong) GCDWebSocketHandshake *handshake;

@end

@implementation GCDWebSocketServerConnection

- (void)dealloc
{
    GWS_LOG_DEBUG(@"[dealloc] %@-%p", self.class, self);
}

- (instancetype)initWithServer:(GCDWebServer *)server localAddress:(NSData *)localAddress remoteAddress:(NSData *)remoteAddress socket:(CFSocketNativeHandle)socket
{
    self = [super initWithServer:server localAddress:localAddress remoteAddress:remoteAddress socket:socket];
    GWS_LOG_DEBUG(@"[init] %@-%p", self.class, self);
    if (self) {
        if ([server isKindOfClass:[GCDWebSocketServer class]]) {
            _wsServer = (GCDWebSocketServer *)server;
        }
        _buffer = [NSMutableData dataWithCapacity:1024];
        _readInterval = 5;
        _decoder = [[GCDWebSocketDecoder alloc] init];
        _encoder = [[GCDWebSocketEncoder alloc] init];
    }
    return self;
}

- (void)processRequest:(GCDWebServerRequest *)request completion:(GCDWebServerCompletionBlock)completion
{
    self.completion = completion;
    
    // callback
    if ([self.wsServer.transport respondsToSelector:@selector(transportWillStart:)]) {
        [self.wsServer.transport transportWillStart:self];
    }
    
    __weak typeof(self) weakSelf = self;
    void (^interruptBlock)(GCDWebServerResponse *) = ^(GCDWebServerResponse* _Nullable response) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if ([response isKindOfClass:[GCDWebSocketHandshake class]]) {
            GCDWebSocketHandshake *handshake = (GCDWebSocketHandshake *)response;
            strongSelf.handshake = handshake;
            [strongSelf sendHandshake:handshake completion:completion];
        } else {
            !completion ?: completion(response);
        }
    };
    [super processRequest:request completion:interruptBlock];
}

- (void)close
{
    if (self.completion) {
        // finish websocket handshake to release connection
        !self.handshake ?: self.completion(self.handshake);
        self.completion = nil;
    }
    [super close];
}

#pragma mark - handshake

- (void)sendHandshake:(GCDWebSocketHandshake *)handshake completion:(GCDWebServerCompletionBlock)completion
{
    NSData *handshakeData = [handshake readData:nil];
    __weak typeof(self) weakSelf = self;
    void (^completionBlock)(BOOL success) = ^(BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (success) {
            GWS_LOG_DEBUG(@"write handshake data success");
            [strongSelf startTransmitData];
        } else {
            GWS_LOG_DEBUG(@"write handshake data failure");
            [strongSelf stopTransmitData];
        }
    };
    [self writeData:handshakeData withCompletionBlock:completionBlock];
}

#pragma mark - read & write

#ifdef DEBUG

- (void)didReadBytes:(const void *)bytes length:(NSUInteger)length
{
    [super didReadBytes:bytes length:length];
    GWS_LOG_DEBUG(@"didReadBytes: %@-%@", @(length), [NSData dataWithBytes:bytes length:length]);
}

- (void)didWriteBytes:(const void *)bytes length:(NSUInteger)length
{
    [super didWriteBytes:bytes length:length];
    GWS_LOG_DEBUG(@"didWriteBytes: %@-%@", @(length), [NSData dataWithBytes:bytes length:length]);
}

#endif

#pragma mark - transport

- (void)startTransmitData
{
    GWS_LOG_DEBUG(@"--> [Start] startTransmitData");
    //先读取 header 字节，判断 websocket 长链接是否结束
    self.lastReadDataTime = CFAbsoluteTimeGetCurrent();
    __weak typeof(self) weakSelf = self;
    [self readData:self.buffer withLength:1 completionBlock:^(BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        success ? [strongSelf readFrameContinue] : [strongSelf stopTransmitData];
    }];
}

- (void)readFrameContinue
{
    GWS_LOG_DEBUG(@"----> readFrameContinue ...");
    __weak typeof(self) weakSelf = self;
    // decode websocket frame callback
    GCDWebSocketDecodeCompletion decodeCallback = ^(GCDWebSocketMessage frame) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf receiveMessage:frame];
    };
    
    // read data callback
    void (^completionBlock)(BOOL success) = ^(BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSMutableData *readBuffer = strongSelf.buffer;
        GWS_LOG_DEBUG(@"----> readData: %@", readBuffer);
        
        if (readBuffer.length == 0) {
            [strongSelf performSelector:@selector(readFrameContinue) withObject:nil afterDelay:strongSelf.readInterval];
            return;
        }
        strongSelf.lastReadDataTime = CFAbsoluteTimeGetCurrent();
        
        // decode data
        NSInteger result = [strongSelf.decoder decode:readBuffer completion:decodeCallback];
        if (result < 0) {
            [strongSelf stopTransmitData];
            return;
        } else if (result == 0) {
            return;
        }
        
        // release decoded data
        NSRange remainRange = NSMakeRange(result, strongSelf.buffer.length - result);
        NSData *remainData = [strongSelf.buffer subdataWithRange:remainRange];
        [strongSelf.buffer setData:remainData];
        
        // next read data
        [strongSelf readFrameContinue];
    };
    [self readData:self.buffer withLength:1024 completionBlock:completionBlock];
}

- (void)stopTransmitData
{
    GWS_LOG_DEBUG(@"<<-- [Stop] stopTransmitData ...");
    // callback
    if ([self.wsServer.transport respondsToSelector:@selector(transportWillEnd:)]) {
        [self.wsServer.transport transportWillEnd:self];
    }
    
    // disconnect
    [self close];
}

#pragma mark - receive

- (void)receiveMessage:(GCDWebSocketMessage)message
{
    GWS_LOG_DEBUG(@"------> [WebSocketServer] received: %@", message.body.payload);
    
    // callback
    if ([self.wsServer.transport respondsToSelector:@selector(transport:received:)]) {
        [self.wsServer.transport transport:self received:message];
    }
    
    // opcode logic
    switch (message.header.opcode) {
        case GCDWebSocketOpcodePing:
        {
            // websocket ping/pong
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            NSString *ping = [NSString stringWithFormat:@"{\"pong_time\": \"%f\"}", now];
            NSData *pingData = [ping dataUsingEncoding:NSUTF8StringEncoding];
            
            GCDWebSocketMessage pong;
            pong.header.fin = YES;
            pong.header.opcode = GCDWebSocketOpcodePong;
            pong.body.payload = pingData;
            [self sendMessage:pong];
        }
            break;
        case GCDWebSocketOpcodeTextFrame:
        {
            NSString *content = [[NSString alloc] initWithData:message.body.payload encoding:NSUTF8StringEncoding];
            GWS_LOG_DEBUG(@"--------> text frame: %@", content);
        }
            break;
            
        default:
            break;
    }//switch
}

#pragma mark - send

- (void)sendMessage:(GCDWebSocketMessage)message
{
    __weak typeof(self) weakSelf = self;
    GCDWebSocketEncodeCompletion encodeCallback = ^(NSData *frame) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        GWS_LOG_DEBUG(@"<<---------- [Begin] send message: %@", frame);
        [strongSelf writeData:frame withCompletionBlock:^(BOOL success) {
            GWS_LOG_DEBUG(@"<<---------- [End] send message: %@", success ? @"success" : @"failure");
            success ?: [strongSelf stopTransmitData];
        }];
    };
    [self.encoder encode:message completion:encodeCallback];
}

@end
