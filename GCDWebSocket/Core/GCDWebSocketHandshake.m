//
//  GCDWebSocketHandshake.m
//  Pods
//
//  Created by ruhong zhu on 2021/9/4.
//

#import "GCDWebSocketHandshake.h"
#import "GCDWebServerPrivate.h"
#import <CommonCrypto/CommonDigest.h>

NSData* GCDWebServerComputeSHA1Digest(NSString* format, ...) {
    va_list arguments;
    va_start(arguments, format);
    const char* string = [[[NSString alloc] initWithFormat:format arguments:arguments] UTF8String];
    va_end(arguments);
    unsigned char outputBuffer[CC_SHA1_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_SHA1(string, (CC_LONG)strlen(string), outputBuffer);
#pragma clang diagnostic pop
    return [NSData dataWithBytes:outputBuffer length:CC_SHA1_DIGEST_LENGTH];
}

@interface GCDWebSocketHandshake ()
{
    CFHTTPMessageRef _responseMessage;
}

@end

@implementation GCDWebSocketHandshake

- (instancetype)initWith:(GCDWebServerRequest *)request
{
    self = [super init];
    if (self) {
        self.statusCode = kGCDWebServerHTTPStatusCode_SwitchingProtocols;
        NSString *description = @"Switching Protocols";
        _responseMessage = CFHTTPMessageCreateResponse(kCFAllocatorDefault, self.statusCode, (__bridge CFStringRef _Nullable)(description), kCFHTTPVersion1_1);
        NSString *origin = request.headers[@"Origin"];
        NSString *location = request.headers[@"Host"];
        NSString *secWebSocketKey = request.headers[@"Sec-WebSocket-Key"];
        NSString *secWebSocketAccept = [self secWebSocketAcceptWithKey:secWebSocketKey magicString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
        NSString *secWebSocketVersion = request.headers[@"Sec-WebSocket-Version"];
        NSString *secWebSocketProtocol = request.headers[@"Sec-WebSocket-Protocol"];
        [self setValue:@"websocket" forAdditionalHeader:@"Upgrade"];
        [self setValue:@"Upgrade" forAdditionalHeader:@"Connection"];
        [self setValue:origin forAdditionalHeader:@"Sec-WebSocket-Origin"];
        [self setValue:location forAdditionalHeader:@"Sec-WebSocket-Location"];
        [self setValue:secWebSocketAccept forAdditionalHeader:@"Sec-WebSocket-Accept"];
        [self setValue:secWebSocketVersion forAdditionalHeader:@"Sec-WebSocket-Version"];
        [self setValue:secWebSocketProtocol forAdditionalHeader:@"Sec-WebSocket-Protocol"];
    }
    return self;
}

- (NSData *)readData:(NSError *__autoreleasing  _Nullable *)error
{
    NSMutableData *tempData = [NSMutableData dataWithData:[super readData:error]];
    
    [self.additionalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
      CFHTTPMessageSetHeaderFieldValue(self->_responseMessage, (__bridge CFStringRef)key, (__bridge CFStringRef)obj);
    }];
    
    CFDataRef data = CFHTTPMessageCopySerializedMessage(_responseMessage);
    [tempData appendData:(__bridge NSData * _Nonnull)(data)];
    CFRelease(data);
    
#ifdef DEBUG
    NSString *log = [[NSString alloc] initWithData:tempData encoding:NSUTF8StringEncoding];
    GWS_LOG_DEBUG(@"<<========== [WebSocket Handshake]: \n%@\n<<==========", log);
#endif
    return tempData;
}

#pragma mark - private

- (NSString *)secWebSocketAcceptWithKey:(NSString *)key magicString:(NSString *)magicString
{
    NSData *sha1Data = GCDWebServerComputeSHA1Digest(@"%@%@", key, magicString);
    NSString *base64SHA1 = [sha1Data base64EncodedStringWithOptions:0];
    return base64SHA1;
}

@end
