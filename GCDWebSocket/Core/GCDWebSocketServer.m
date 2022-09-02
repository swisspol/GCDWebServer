//
//  GCDWebSocketServer.m
//  Pods
//
//  Created by ruhong zhu on 2021/9/20.
//

#import "GCDWebSocketServer.h"
#import "GCDWebServerPrivate.h"
#import "GCDWebServerResponse+WebSocket.h"
#import "GCDWebSocketServerConnection.h"

NSString *GCDWebServerConnectionKey(GCDWebServerConnection *con)
{
    return GCDWebServerComputeMD5Digest(@"%p%@%@", con, con.remoteAddressString, con.localAddressString);
}

@interface GCDWebSocketServer ()

@property (nonatomic, strong) NSMutableDictionary *connectionsDic;
@property (nonatomic, strong) NSTimer *checkTimer;

@end

@implementation GCDWebSocketServer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _timeout = 60;
        _connectionsDic = @{}.mutableCopy;
        [self addHandlerForMethod:@"GET" pathRegex:@"^/" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
            return [GCDWebServerResponse responseWith:request];
        }];
    }
    return self;
}

- (BOOL)startWithPort:(NSUInteger)port bonjourName:(NSString *)name
{
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[GCDWebServerOption_Port] = @(port);
    options[GCDWebServerOption_BonjourName] = name ?: @"";
    options[GCDWebServerOption_AutomaticallySuspendInBackground] = @(NO);
    options[GCDWebServerOption_ConnectionClass] = [GCDWebSocketServerConnection class];
    
    if ([self startWithOptions:options error:NULL]) {
        // 如果启动正常，则开始长链接超时检测逻辑，每秒检测一次；
        [self startCheckTimerWith:1];
        return YES;
    }
    return NO;
}

#pragma mark - check alive

- (void)stopCheckTimer
{
    if (self.checkTimer) {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
}

- (void)startCheckTimerWith:(NSTimeInterval)interval
{
    [self stopCheckTimer];
    
    self.checkTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(doCheckAction) userInfo:nil repeats:YES];
}

- (void)doCheckAction
{
    //check connection
    NSTimeInterval currentTime = CFAbsoluteTimeGetCurrent();
    NSMutableArray *timeoutConnectionKeys = [NSMutableArray array];
    NSDictionary<NSString *, id> *tempConnectionsDic = [self.connectionsDic copy];
    [tempConnectionsDic enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        GCDWebSocketServerConnection *con = nil;
        if ([obj isKindOfClass:[GCDWebSocketServerConnection class]]) {
            con = obj;
        } else {
            !key ?: [timeoutConnectionKeys addObject:key];
        }
        // timeout
        if (currentTime - con.lastReadDataTime > self.timeout) {
            [con close];
            [timeoutConnectionKeys addObject:key];
        }
    }];
    [self.connectionsDic removeObjectsForKeys:timeoutConnectionKeys];
}

#pragma mark - connection

- (void)willStartConnection:(GCDWebServerConnection *)connection
{
    [super willStartConnection:connection];
    NSString *key = GCDWebServerConnectionKey(connection);
    [self.connectionsDic setValue:connection forKey:key];
}

- (void)didEndConnection:(GCDWebServerConnection *)connection
{
    [super didEndConnection:connection];
    NSString *key = GCDWebServerConnectionKey(connection);
    [self.connectionsDic removeObjectForKey:key];
}

@end
