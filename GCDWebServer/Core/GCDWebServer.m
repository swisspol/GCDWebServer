/*
 Copyright (c) 2012-2014, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
#import <AppKit/AppKit.h>
#endif
#endif
#import <netinet/in.h>

#import "GCDWebServerPrivate.h"

#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
#define kDefaultPort 80
#else
#define kDefaultPort 8080
#endif

NSString* const GCDWebServerOption_Port = @"Port";
NSString* const GCDWebServerOption_BonjourName = @"BonjourName";
NSString* const GCDWebServerOption_BonjourType = @"BonjourType";
NSString* const GCDWebServerOption_MaxPendingConnections = @"MaxPendingConnections";
NSString* const GCDWebServerOption_ServerName = @"ServerName";
NSString* const GCDWebServerOption_AuthenticationMethod = @"AuthenticationMethod";
NSString* const GCDWebServerOption_AuthenticationRealm = @"AuthenticationRealm";
NSString* const GCDWebServerOption_AuthenticationAccounts = @"AuthenticationAccounts";
NSString* const GCDWebServerOption_ConnectionClass = @"ConnectionClass";
NSString* const GCDWebServerOption_AutomaticallyMapHEADToGET = @"AutomaticallyMapHEADToGET";
NSString* const GCDWebServerOption_ConnectedStateCoalescingInterval = @"ConnectedStateCoalescingInterval";
#if TARGET_OS_IPHONE
NSString* const GCDWebServerOption_AutomaticallySuspendInBackground = @"AutomaticallySuspendInBackground";
#endif

NSString* const GCDWebServerAuthenticationMethod_Basic = @"Basic";
NSString* const GCDWebServerAuthenticationMethod_DigestAccess = @"DigestAccess";

#ifndef __GCDWEBSERVER_LOGGING_HEADER__
#ifdef NDEBUG
GCDWebServerLogLevel GCDLogLevel = kGCDWebServerLogLevel_Info;
#else
GCDWebServerLogLevel GCDLogLevel = kGCDWebServerLogLevel_Debug;
#endif
#endif

#if !TARGET_OS_IPHONE
static BOOL _run;
#endif

#ifndef __GCDWEBSERVER_LOGGING_HEADER__

void GCDLogMessage(GCDWebServerLogLevel level, NSString* format, ...) {
  static const char* levelNames[] = {"DEBUG", "VERBOSE", "INFO", "WARNING", "ERROR", "EXCEPTION"};
  va_list arguments;
  va_start(arguments, format);
  NSString* message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  fprintf(stderr, "[%s] %s\n", levelNames[level], [message UTF8String]);
  ARC_RELEASE(message);
}

#endif

#if !TARGET_OS_IPHONE

static void _SignalHandler(int signal) {
  _run = NO;
  printf("\n");
}

#endif

#if !TARGET_OS_IPHONE || defined(__GCDWEBSERVER_ENABLE_TESTING__)

// This utility function is used to ensure scheduled callbacks on the main thread are called when running the server synchronously
// https://developer.apple.com/library/mac/documentation/General/Conceptual/ConcurrencyProgrammingGuide/OperationQueues/OperationQueues.html
// The main queue works with the application’s run loop to interleave the execution of queued tasks with the execution of other event sources attached to the run loop
// TODO: Ensure all scheduled blocks on the main queue are also executed
static void _ExecuteMainThreadRunLoopSources() {
  SInt32 result;
  do {
    result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.0, true);
  } while (result == kCFRunLoopRunHandledSource);
}

#endif

@interface GCDWebServerHandler () {
@private
  GCDWebServerMatchBlock _matchBlock;
  GCDWebServerProcessBlock _processBlock;
}
@end

@implementation GCDWebServerHandler

@synthesize matchBlock=_matchBlock, processBlock=_processBlock;

- (id)initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock {
  if ((self = [super init])) {
    _matchBlock = [matchBlock copy];
    _processBlock = [processBlock copy];
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_matchBlock);
  ARC_RELEASE(_processBlock);
  
  ARC_DEALLOC(super);
}

@end

@interface GCDWebServer () {
@private
  id<GCDWebServerDelegate> __unsafe_unretained _delegate;
  dispatch_queue_t _syncQueue;
  dispatch_semaphore_t _sourceSemaphore;
  NSMutableArray* _handlers;
  NSInteger _activeConnections;  // Accessed through _syncQueue only
  BOOL _connected;  // Accessed on main thread only
  BOOL _disconnecting;  // Accessed on main thread only
  CFRunLoopTimerRef _disconnectTimer;  // Accessed on main thread only
  
  NSDictionary* _options;
  NSString* _serverName;
  NSString* _authenticationRealm;
  NSMutableDictionary* _authenticationBasicAccounts;
  NSMutableDictionary* _authenticationDigestAccounts;
  Class _connectionClass;
  BOOL _mapHEADToGET;
  CFTimeInterval _disconnectDelay;
  NSUInteger _port;
  dispatch_source_t _source;
  CFNetServiceRef _registrationService;
  CFNetServiceRef _resolutionService;
#if TARGET_OS_IPHONE
  BOOL _suspendInBackground;
  UIBackgroundTaskIdentifier _backgroundTask;
#endif
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
  BOOL _recording;
#endif
}
@end

@implementation GCDWebServer

@synthesize delegate=_delegate, handlers=_handlers, port=_port, serverName=_serverName, authenticationRealm=_authenticationRealm,
            authenticationBasicAccounts=_authenticationBasicAccounts, authenticationDigestAccounts=_authenticationDigestAccounts,
            shouldAutomaticallyMapHEADToGET=_mapHEADToGET;

#ifndef __GCDWEBSERVER_LOGGING_HEADER__

+ (void)load {
  const char* logLevel = getenv("logLevel");
  if (logLevel) {
    GCDLogLevel = atoi(logLevel);
  }
}

#endif

+ (void)initialize {
  GCDWebServerInitializeFunctions();
}

static void _DisconnectTimerCallBack(CFRunLoopTimerRef timer, void* info) {
  DCHECK([NSThread isMainThread]);
  GCDWebServer* server = (ARC_BRIDGE GCDWebServer*)info;
  @autoreleasepool {
    [server _didDisconnect];
  }
  server->_disconnecting = NO;
}

- (instancetype)init {
  if ((self = [super init])) {
    _syncQueue = dispatch_queue_create([NSStringFromClass([self class]) UTF8String], DISPATCH_QUEUE_SERIAL);
    _sourceSemaphore = dispatch_semaphore_create(0);
    _handlers = [[NSMutableArray alloc] init];
    CFRunLoopTimerContext context = {0, (ARC_BRIDGE void*)self, NULL, NULL, NULL};
    _disconnectTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, HUGE_VAL, HUGE_VAL, 0, 0, _DisconnectTimerCallBack, &context);
    CFRunLoopAddTimer(CFRunLoopGetMain(), _disconnectTimer, kCFRunLoopCommonModes);
#if TARGET_OS_IPHONE
    _backgroundTask = UIBackgroundTaskInvalid;
#endif
  }
  return self;
}

- (void)dealloc {
  DCHECK(_connected == NO);
  DCHECK(_activeConnections == 0);
  DCHECK(_options == nil);  // The server can never be dealloc'ed while running because of the retain-cycle with the dispatch source
  
  CFRunLoopTimerInvalidate(_disconnectTimer);
  CFRelease(_disconnectTimer);
  ARC_RELEASE(_handlers);
  ARC_DISPATCH_RELEASE(_sourceSemaphore);
  ARC_DISPATCH_RELEASE(_syncQueue);
  
  ARC_DEALLOC(super);
}

#if TARGET_OS_IPHONE

// Always called on main thread
- (void)_startBackgroundTask {
  DCHECK([NSThread isMainThread]);
  if (_backgroundTask == UIBackgroundTaskInvalid) {
    LOG_DEBUG(@"Did start background task");
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
      
      LOG_WARNING(@"Application is being suspended while %@ is still connected", [self class]);
      [self _endBackgroundTask];
      
    }];
  } else {
    DNOT_REACHED();
  }
}

#endif

// Always called on main thread
- (void)_didConnect {
  DCHECK([NSThread isMainThread]);
  DCHECK(_connected == NO);
  _connected = YES;
  LOG_DEBUG(@"Did connect");
  
#if TARGET_OS_IPHONE
  [self _startBackgroundTask];
#endif
  
  if ([_delegate respondsToSelector:@selector(webServerDidConnect:)]) {
    [_delegate webServerDidConnect:self];
  }
}

- (void)willStartConnection:(GCDWebServerConnection*)connection {
  dispatch_sync(_syncQueue, ^{
    
    DCHECK(_activeConnections >= 0);
    if (_activeConnections == 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (_disconnecting) {
          CFRunLoopTimerSetNextFireDate(_disconnectTimer, HUGE_VAL);
          _disconnecting = NO;
        }
        if (_connected == NO) {
          [self _didConnect];
        }
      });
    }
    _activeConnections += 1;
    
  });
}

#if TARGET_OS_IPHONE

// Always called on main thread
- (void)_endBackgroundTask {
  DCHECK([NSThread isMainThread]);
  if (_backgroundTask != UIBackgroundTaskInvalid) {
    if (_suspendInBackground && ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) && _source) {
      [self _stop];
    }
    [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
    _backgroundTask = UIBackgroundTaskInvalid;
    LOG_DEBUG(@"Did end background task");
  } else {
    DNOT_REACHED();
  }
}

#endif

// Always called on main thread
- (void)_didDisconnect {
  DCHECK([NSThread isMainThread]);
  DCHECK(_connected == YES);
  _connected = NO;
  LOG_DEBUG(@"Did disconnect");
  
#if TARGET_OS_IPHONE
  [self _endBackgroundTask];
#endif
  
  if ([_delegate respondsToSelector:@selector(webServerDidDisconnect:)]) {
    [_delegate webServerDidDisconnect:self];
  }
}

- (void)didEndConnection:(GCDWebServerConnection*)connection {
  dispatch_sync(_syncQueue, ^{
    DCHECK(_activeConnections > 0);
    _activeConnections -= 1;
    if (_activeConnections == 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if ((_disconnectDelay > 0.0) && (_source != NULL)) {
          CFRunLoopTimerSetNextFireDate(_disconnectTimer, CFAbsoluteTimeGetCurrent() + _disconnectDelay);
          _disconnecting = YES;
        } else {
          [self _didDisconnect];
        }
      });
    }
  });
}

- (NSString*)bonjourName {
  CFStringRef name = _resolutionService ? CFNetServiceGetName(_resolutionService) : NULL;
  return name && CFStringGetLength(name) ? ARC_BRIDGE_RELEASE(CFStringCreateCopy(kCFAllocatorDefault, name)) : nil;
}

- (NSString*)bonjourType {
  CFStringRef type = _resolutionService ? CFNetServiceGetType(_resolutionService) : NULL;
  return type && CFStringGetLength(type) ? ARC_BRIDGE_RELEASE(CFStringCreateCopy(kCFAllocatorDefault, type)) : nil;
}

- (void)addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)handlerBlock {
  DCHECK(_options == nil);
  GCDWebServerHandler* handler = [[GCDWebServerHandler alloc] initWithMatchBlock:matchBlock processBlock:handlerBlock];
  [_handlers insertObject:handler atIndex:0];
  ARC_RELEASE(handler);
}

- (void)removeAllHandlers {
  DCHECK(_options == nil);
  [_handlers removeAllObjects];
}

static void _NetServiceRegisterCallBack(CFNetServiceRef service, CFStreamError* error, void* info) {
  DCHECK([NSThread isMainThread]);
  @autoreleasepool {
    if (error->error) {
      LOG_ERROR(@"Bonjour registration error %i (domain %i)", (int)error->error, (int)error->domain);
    } else {
      GCDWebServer* server = (ARC_BRIDGE GCDWebServer*)info;
      LOG_VERBOSE(@"Bonjour registration complete for %@", [server class]);
      CFNetServiceResolveWithTimeout(server->_resolutionService, 1.0, NULL);
    }
  }
}

static void _NetServiceResolveCallBack(CFNetServiceRef service, CFStreamError* error, void* info) {
  DCHECK([NSThread isMainThread]);
  @autoreleasepool {
    if (error->error) {
      if ((error->domain != kCFStreamErrorDomainNetServices) && (error->error != kCFNetServicesErrorTimeout)) {
        LOG_ERROR(@"Bonjour resolution error %i (domain %i)", (int)error->error, (int)error->domain);
      }
    } else {
      GCDWebServer* server = (ARC_BRIDGE GCDWebServer*)info;
      LOG_INFO(@"%@ now reachable at %@", [server class], server.bonjourServerURL);
      if ([server.delegate respondsToSelector:@selector(webServerDidCompleteBonjourRegistration:)]) {
        [server.delegate webServerDidCompleteBonjourRegistration:server];
      }
    }
  }
}

static inline id _GetOption(NSDictionary* options, NSString* key, id defaultValue) {
  id value = [options objectForKey:key];
  return value ? value : defaultValue;
}

static inline NSString* _EncodeBase64(NSString* string) {
  NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
#if (TARGET_OS_IPHONE && !(__IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_7_0)) || (!TARGET_OS_IPHONE && !(__MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_9))
  if (![data respondsToSelector:@selector(base64EncodedDataWithOptions:)]) {
    return [data base64Encoding];
  }
#endif
  return ARC_AUTORELEASE([[NSString alloc] initWithData:[data base64EncodedDataWithOptions:0] encoding:NSASCIIStringEncoding]);
}

- (BOOL)_start:(NSError**)error {
  DCHECK(_source == NULL);
  
  NSUInteger port = [_GetOption(_options, GCDWebServerOption_Port, @0) unsignedIntegerValue];
  NSString* bonjourName = _GetOption(_options, GCDWebServerOption_BonjourName, @"");
  NSString* bonjourType = _GetOption(_options, GCDWebServerOption_BonjourType, @"_http._tcp");
  NSUInteger maxPendingConnections = [_GetOption(_options, GCDWebServerOption_MaxPendingConnections, @16) unsignedIntegerValue];
  int listeningSocket = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listeningSocket > 0) {
    int yes = 1;
    setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    
    struct sockaddr_in addr4;
    bzero(&addr4, sizeof(addr4));
    addr4.sin_len = sizeof(addr4);
    addr4.sin_family = AF_INET;
    addr4.sin_port = htons(port);
    addr4.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(listeningSocket, (void*)&addr4, sizeof(addr4)) == 0) {
      if (listen(listeningSocket, (int)maxPendingConnections) == 0) {
        LOG_DEBUG(@"Did open listening socket %i", listeningSocket);
        _serverName = [_GetOption(_options, GCDWebServerOption_ServerName, NSStringFromClass([self class])) copy];
        NSString* authenticationMethod = _GetOption(_options, GCDWebServerOption_AuthenticationMethod, nil);
        if ([authenticationMethod isEqualToString:GCDWebServerAuthenticationMethod_Basic]) {
          _authenticationRealm = [_GetOption(_options, GCDWebServerOption_AuthenticationRealm, _serverName) copy];
          _authenticationBasicAccounts = [[NSMutableDictionary alloc] init];
          NSDictionary* accounts = _GetOption(_options, GCDWebServerOption_AuthenticationAccounts, @{});
          [accounts enumerateKeysAndObjectsUsingBlock:^(NSString* username, NSString* password, BOOL* stop) {
            [_authenticationBasicAccounts setObject:_EncodeBase64([NSString stringWithFormat:@"%@:%@", username, password]) forKey:username];
          }];
        } else if ([authenticationMethod isEqualToString:GCDWebServerAuthenticationMethod_DigestAccess]) {
          _authenticationRealm = [_GetOption(_options, GCDWebServerOption_AuthenticationRealm, _serverName) copy];
          _authenticationDigestAccounts = [[NSMutableDictionary alloc] init];
          NSDictionary* accounts = _GetOption(_options, GCDWebServerOption_AuthenticationAccounts, @{});
          [accounts enumerateKeysAndObjectsUsingBlock:^(NSString* username, NSString* password, BOOL* stop) {
            [_authenticationDigestAccounts setObject:GCDWebServerComputeMD5Digest(@"%@:%@:%@", username, _authenticationRealm, password) forKey:username];
          }];
        }
        _connectionClass = _GetOption(_options, GCDWebServerOption_ConnectionClass, [GCDWebServerConnection class]);
        _mapHEADToGET = [_GetOption(_options, GCDWebServerOption_AutomaticallyMapHEADToGET, @YES) boolValue];
        _disconnectDelay = [_GetOption(_options, GCDWebServerOption_ConnectedStateCoalescingInterval, @1.0) doubleValue];
        _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, listeningSocket, 0, kGCDWebServerGCDQueue);
        dispatch_source_set_cancel_handler(_source, ^{
          
          @autoreleasepool {
            int result = close(listeningSocket);
            if (result != 0) {
              LOG_ERROR(@"Failed closing listening socket: %s (%i)", strerror(errno), errno);
            } else {
              LOG_DEBUG(@"Did close listening socket %i", listeningSocket);
            }
          }
          dispatch_semaphore_signal(_sourceSemaphore);
          
        });
        dispatch_source_set_event_handler(_source, ^{
          
          @autoreleasepool {
            struct sockaddr remoteSockAddr;
            socklen_t remoteAddrLen = sizeof(remoteSockAddr);
            int socket = accept(listeningSocket, &remoteSockAddr, &remoteAddrLen);
            if (socket > 0) {
              NSData* remoteAddress = [NSData dataWithBytes:&remoteSockAddr length:remoteAddrLen];
              
              struct sockaddr localSockAddr;
              socklen_t localAddrLen = sizeof(localSockAddr);
              NSData* localAddress = nil;
              if (getsockname(socket, &localSockAddr, &localAddrLen) == 0) {
                localAddress = [NSData dataWithBytes:&localSockAddr length:localAddrLen];
              } else {
                DNOT_REACHED();
              }
              
              int noSigPipe = 1;
              setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));  // Make sure this socket cannot generate SIG_PIPE
              
              GCDWebServerConnection* connection = [[_connectionClass alloc] initWithServer:self localAddress:localAddress remoteAddress:remoteAddress socket:socket];  // Connection will automatically retain itself while opened
#if __has_feature(objc_arc)
              [connection self];  // Prevent compiler from complaining about unused variable / useless statement
#else
              [connection release];
#endif
            } else {
              LOG_ERROR(@"Failed accepting socket: %s (%i)", strerror(errno), errno);
            }
          }
          
        });
        
        if (port == 0) {
          struct sockaddr addr;
          socklen_t addrlen = sizeof(addr);
          if (getsockname(listeningSocket, &addr, &addrlen) == 0) {
            struct sockaddr_in* sockaddr = (struct sockaddr_in*)&addr;
            _port = ntohs(sockaddr->sin_port);
          } else {
            LOG_ERROR(@"Failed retrieving socket address: %s (%i)", strerror(errno), errno);
          }
        } else {
          _port = port;
        }
        
        if (bonjourName) {
          _registrationService = CFNetServiceCreate(kCFAllocatorDefault, CFSTR("local."), (ARC_BRIDGE CFStringRef)bonjourType, (ARC_BRIDGE CFStringRef)(bonjourName.length ? bonjourName : _serverName), (SInt32)_port);
          if (_registrationService) {
            CFNetServiceClientContext context = {0, (ARC_BRIDGE void*)self, NULL, NULL, NULL};
            
            CFNetServiceSetClient(_registrationService, _NetServiceRegisterCallBack, &context);
            CFNetServiceScheduleWithRunLoop(_registrationService, CFRunLoopGetMain(), kCFRunLoopCommonModes);
            CFStreamError streamError = {0};
            CFNetServiceRegisterWithOptions(_registrationService, 0, &streamError);
            
            _resolutionService = CFNetServiceCreateCopy(kCFAllocatorDefault, _registrationService);
            if (_resolutionService) {
              CFNetServiceSetClient(_resolutionService, _NetServiceResolveCallBack, &context);
              CFNetServiceScheduleWithRunLoop(_resolutionService, CFRunLoopGetMain(), kCFRunLoopCommonModes);
            }
          } else {
            LOG_ERROR(@"Failed creating CFNetService");
          }
        }
        
        dispatch_resume(_source);
        LOG_INFO(@"%@ started on port %i and reachable at %@", [self class], (int)_port, self.serverURL);
        if ([_delegate respondsToSelector:@selector(webServerDidStart:)]) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate webServerDidStart:self];
          });
        }
      } else {
        if (error) {
          *error = GCDWebServerMakePosixError(errno);
        }
        LOG_ERROR(@"Failed starting listening socket: %s (%i)", strerror(errno), errno);
        close(listeningSocket);
      }
    } else {
      if (error) {
        *error = GCDWebServerMakePosixError(errno);
      }
      LOG_ERROR(@"Failed binding listening socket: %s (%i)", strerror(errno), errno);
      close(listeningSocket);
    }
  } else {
    if (error) {
      *error = GCDWebServerMakePosixError(errno);
    }
    LOG_ERROR(@"Failed creating listening socket: %s (%i)", strerror(errno), errno);
  }
  return (_source ? YES : NO);
}

- (void)_stop {
  DCHECK(_source != NULL);
  
  if (_registrationService) {
    if (_resolutionService) {
      CFNetServiceUnscheduleFromRunLoop(_resolutionService, CFRunLoopGetMain(), kCFRunLoopCommonModes);
      CFNetServiceSetClient(_resolutionService, NULL, NULL);
      CFNetServiceCancel(_resolutionService);
      CFRelease(_resolutionService);
      _resolutionService = NULL;
    }
    CFNetServiceUnscheduleFromRunLoop(_registrationService, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    CFNetServiceSetClient(_registrationService, NULL, NULL);
    CFNetServiceCancel(_registrationService);
    CFRelease(_registrationService);
    _registrationService = NULL;
  }
  
  dispatch_source_cancel(_source);
  dispatch_semaphore_wait(_sourceSemaphore, DISPATCH_TIME_FOREVER);  // Wait until the cancellation handler has been called which guarantees the listening socket is closed
  ARC_DISPATCH_RELEASE(_source);
  _source = NULL;
  _port = 0;
  
  ARC_RELEASE(_serverName);
  _serverName = nil;
  ARC_RELEASE(_authenticationRealm);
  _authenticationRealm = nil;
  ARC_RELEASE(_authenticationBasicAccounts);
  _authenticationBasicAccounts = nil;
  ARC_RELEASE(_authenticationDigestAccounts);
  _authenticationDigestAccounts = nil;
  
  dispatch_async(dispatch_get_main_queue(), ^{
    if (_disconnecting) {
      CFRunLoopTimerSetNextFireDate(_disconnectTimer, HUGE_VAL);
      _disconnecting = NO;
      [self _didDisconnect];
    }
  });
  
  LOG_INFO(@"%@ stopped", [self class]);
  if ([_delegate respondsToSelector:@selector(webServerDidStop:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [_delegate webServerDidStop:self];
    });
  }
}

#if TARGET_OS_IPHONE

- (void)_didEnterBackground:(NSNotification*)notification {
  DCHECK([NSThread isMainThread]);
  LOG_DEBUG(@"Did enter background");
  if ((_backgroundTask == UIBackgroundTaskInvalid) && _source) {
    [self _stop];
  }
}

- (void)_willEnterForeground:(NSNotification*)notification {
  DCHECK([NSThread isMainThread]);
  LOG_DEBUG(@"Will enter foreground");
  if (!_source) {
    [self _start:NULL];  // TODO: There's probably nothing we can do on failure
  }
}

#endif

- (BOOL)startWithOptions:(NSDictionary*)options error:(NSError**)error {
  if (_options == nil) {
    _options = [options copy];
#if TARGET_OS_IPHONE
    _suspendInBackground = [_GetOption(_options, GCDWebServerOption_AutomaticallySuspendInBackground, @YES) boolValue];
    if (((_suspendInBackground == NO) || ([[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground)) && ![self _start:error])
#else
    if (![self _start:error])
#endif
    {
      ARC_RELEASE(_options);
      _options = nil;
      return NO;
    }
#if TARGET_OS_IPHONE
    if (_suspendInBackground) {
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
      [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
#endif
    return YES;
  } else {
    DNOT_REACHED();
  }
  return NO;
}

- (BOOL)isRunning {
  return (_options ? YES : NO);
}

- (void)stop {
  if (_options) {
#if TARGET_OS_IPHONE
    if (_suspendInBackground) {
      [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
      [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    }
#endif
    if (_source) {
      [self _stop];
    }
    ARC_RELEASE(_options);
    _options = nil;
  } else {
    DNOT_REACHED();
  }
}

@end

@implementation GCDWebServer (Extensions)

- (NSURL*)serverURL {
  if (_source) {
    NSString* ipAddress = GCDWebServerGetPrimaryIPv4Address();
    if (ipAddress) {
      if (_port != 80) {
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%i/", ipAddress, (int)_port]];
      } else {
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/", ipAddress]];
      }
    }
  }
  return nil;
}

- (NSURL*)bonjourServerURL {
  if (_source && _resolutionService) {
    NSString* name = (ARC_BRIDGE NSString*)CFNetServiceGetTargetHost(_resolutionService);
    if (name.length) {
      name = [name substringToIndex:(name.length - 1)];  // Strip trailing period at end of domain
      if (_port != 80) {
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%i/", name, (int)_port]];
      } else {
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@/", name]];
      }
    }
  }
  return nil;
}

- (BOOL)start {
  return [self startWithPort:kDefaultPort bonjourName:@""];
}

- (BOOL)startWithPort:(NSUInteger)port bonjourName:(NSString*)name {
  NSMutableDictionary* options = [NSMutableDictionary dictionary];
  [options setObject:[NSNumber numberWithInteger:port] forKey:GCDWebServerOption_Port];
  [options setValue:name forKey:GCDWebServerOption_BonjourName];
  return [self startWithOptions:options error:NULL];
}

#if !TARGET_OS_IPHONE

- (BOOL)runWithPort:(NSUInteger)port bonjourName:(NSString*)name {
  NSMutableDictionary* options = [NSMutableDictionary dictionary];
  [options setObject:[NSNumber numberWithInteger:port] forKey:GCDWebServerOption_Port];
  [options setValue:name forKey:GCDWebServerOption_BonjourName];
  return [self runWithOptions:options error:NULL];
}

- (BOOL)runWithOptions:(NSDictionary*)options error:(NSError**)error {
  DCHECK([NSThread isMainThread]);
  BOOL success = NO;
  _run = YES;
  void (*termHandler)(int) = signal(SIGTERM, _SignalHandler);
  void (*intHandler)(int) = signal(SIGINT, _SignalHandler);
  if ((termHandler != SIG_ERR) && (intHandler != SIG_ERR)) {
    if ([self startWithOptions:options error:error]) {
      while (_run) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
      }
      [self stop];
      success = YES;
    }
    _ExecuteMainThreadRunLoopSources();
    signal(SIGINT, intHandler);
    signal(SIGTERM, termHandler);
  }
  return success;
}

#endif

@end

@implementation GCDWebServer (Handlers)

- (void)addDefaultHandlerForMethod:(NSString*)method requestClass:(Class)aClass processBlock:(GCDWebServerProcessBlock)block {
  [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
    
    if (![requestMethod isEqualToString:method]) {
      return nil;
    }
    return ARC_AUTORELEASE([[aClass alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery]);
    
  } processBlock:block];
}

- (void)addHandlerForMethod:(NSString*)method path:(NSString*)path requestClass:(Class)aClass processBlock:(GCDWebServerProcessBlock)block {
  if ([path hasPrefix:@"/"] && [aClass isSubclassOfClass:[GCDWebServerRequest class]]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:method]) {
        return nil;
      }
      if ([urlPath caseInsensitiveCompare:path] != NSOrderedSame) {
        return nil;
      }
      return ARC_AUTORELEASE([[aClass alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery]);
      
    } processBlock:block];
  } else {
    DNOT_REACHED();
  }
}

- (void)addHandlerForMethod:(NSString*)method pathRegex:(NSString*)regex requestClass:(Class)aClass processBlock:(GCDWebServerProcessBlock)block {
  NSRegularExpression* expression = [NSRegularExpression regularExpressionWithPattern:regex options:NSRegularExpressionCaseInsensitive error:NULL];
  if (expression && [aClass isSubclassOfClass:[GCDWebServerRequest class]]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:method]) {
        return nil;
      }
      if ([expression firstMatchInString:urlPath options:0 range:NSMakeRange(0, urlPath.length)] == nil) {
        return nil;
      }
      return ARC_AUTORELEASE([[aClass alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery]);
      
    } processBlock:block];
  } else {
    DNOT_REACHED();
  }
}

@end

@implementation GCDWebServer (GETHandlers)

- (void)addGETHandlerForPath:(NSString*)path staticData:(NSData*)staticData contentType:(NSString*)contentType cacheAge:(NSUInteger)cacheAge {
  [self addHandlerForMethod:@"GET" path:path requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    GCDWebServerResponse* response = [GCDWebServerDataResponse responseWithData:staticData contentType:contentType];
    response.cacheControlMaxAge = cacheAge;
    return response;
    
  }];
}

- (void)addGETHandlerForPath:(NSString*)path filePath:(NSString*)filePath isAttachment:(BOOL)isAttachment cacheAge:(NSUInteger)cacheAge allowRangeRequests:(BOOL)allowRangeRequests {
  [self addHandlerForMethod:@"GET" path:path requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    GCDWebServerResponse* response = nil;
    if (allowRangeRequests) {
      response = [GCDWebServerFileResponse responseWithFile:filePath byteRange:request.byteRange isAttachment:isAttachment];
      [response setValue:@"bytes" forAdditionalHeader:@"Accept-Ranges"];
    } else {
      response = [GCDWebServerFileResponse responseWithFile:filePath isAttachment:isAttachment];
    }
    response.cacheControlMaxAge = cacheAge;
    return response;
    
  }];
}

- (GCDWebServerResponse*)_responseWithContentsOfDirectory:(NSString*)path {
  NSDirectoryEnumerator* enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
  if (enumerator == nil) {
    return nil;
  }
  NSMutableString* html = [NSMutableString string];
  [html appendString:@"<!DOCTYPE html>\n"];
  [html appendString:@"<html><head><meta charset=\"utf-8\"></head><body>\n"];
  [html appendString:@"<ul>\n"];
  for (NSString* file in enumerator) {
    if (![file hasPrefix:@"."]) {
      NSString* type = [[enumerator fileAttributes] objectForKey:NSFileType];
      NSString* escapedFile = [file stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
      DCHECK(escapedFile);
      if ([type isEqualToString:NSFileTypeRegular]) {
        [html appendFormat:@"<li><a href=\"%@\">%@</a></li>\n", escapedFile, file];
      } else if ([type isEqualToString:NSFileTypeDirectory]) {
        [html appendFormat:@"<li><a href=\"%@/\">%@/</a></li>\n", escapedFile, file];
      }
    }
    [enumerator skipDescendents];
  }
  [html appendString:@"</ul>\n"];
  [html appendString:@"</body></html>\n"];
  return [GCDWebServerDataResponse responseWithHTML:html];
}

- (void)addGETHandlerForBasePath:(NSString*)basePath directoryPath:(NSString*)directoryPath indexFilename:(NSString*)indexFilename cacheAge:(NSUInteger)cacheAge allowRangeRequests:(BOOL)allowRangeRequests {
  if ([basePath hasPrefix:@"/"] && [basePath hasSuffix:@"/"]) {
#if __has_feature(objc_arc)
    GCDWebServer* __unsafe_unretained server = self;
#else
    __block GCDWebServer* server = self;
#endif
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:@"GET"]) {
        return nil;
      }
      if (![urlPath hasPrefix:basePath]) {
        return nil;
      }
      return ARC_AUTORELEASE([[GCDWebServerRequest alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery]);
      
    } processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      GCDWebServerResponse* response = nil;
      NSString* filePath = [directoryPath stringByAppendingPathComponent:[request.path substringFromIndex:basePath.length]];
      BOOL isDirectory;
      if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory]) {
        if (isDirectory) {
          if (indexFilename) {
            NSString* indexPath = [filePath stringByAppendingPathComponent:indexFilename];
            if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath isDirectory:&isDirectory] && !isDirectory) {
              return [GCDWebServerFileResponse responseWithFile:indexPath];
            }
          }
          response = [server _responseWithContentsOfDirectory:filePath];
        } else  {
          if (allowRangeRequests) {
            response = [GCDWebServerFileResponse responseWithFile:filePath byteRange:request.byteRange];
            [response setValue:@"bytes" forAdditionalHeader:@"Accept-Ranges"];
          } else {
            response = [GCDWebServerFileResponse responseWithFile:filePath];
          }
        }
      }
      if (response) {
        response.cacheControlMaxAge = cacheAge;
      } else {
        response = [GCDWebServerResponse responseWithStatusCode:kGCDWebServerHTTPStatusCode_NotFound];
      }
      return response;
      
    }];
  } else {
    DNOT_REACHED();
  }
}

@end

@implementation GCDWebServer (Logging)

#ifndef __GCDWEBSERVER_LOGGING_HEADER__

+ (void)setLogLevel:(GCDWebServerLogLevel)level {
  GCDLogLevel = level;
}

#endif

- (void)logVerbose:(NSString*)format, ... {
  va_list arguments;
  va_start(arguments, format);
  LOG_VERBOSE(@"%@", ARC_AUTORELEASE([[NSString alloc] initWithFormat:format arguments:arguments]));
  va_end(arguments);
}

- (void)logInfo:(NSString*)format, ... {
  va_list arguments;
  va_start(arguments, format);
  LOG_INFO(@"%@", ARC_AUTORELEASE([[NSString alloc] initWithFormat:format arguments:arguments]));
  va_end(arguments);
}

- (void)logWarning:(NSString*)format, ... {
  va_list arguments;
  va_start(arguments, format);
  LOG_WARNING(@"%@", ARC_AUTORELEASE([[NSString alloc] initWithFormat:format arguments:arguments]));
  va_end(arguments);
}

- (void)logError:(NSString*)format, ... {
  va_list arguments;
  va_start(arguments, format);
  LOG_ERROR(@"%@", ARC_AUTORELEASE([[NSString alloc] initWithFormat:format arguments:arguments]));
  va_end(arguments);
}

- (void)logException:(NSException*)exception {
  LOG_EXCEPTION(exception);
}

@end

#ifdef __GCDWEBSERVER_ENABLE_TESTING__

@implementation GCDWebServer (Testing)

- (void)setRecordingEnabled:(BOOL)flag {
  _recording = flag;
}

- (BOOL)isRecordingEnabled {
  return _recording;
}

static CFHTTPMessageRef _CreateHTTPMessageFromData(NSData* data, BOOL isRequest) {
  CFHTTPMessageRef message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, isRequest);
  if (CFHTTPMessageAppendBytes(message, data.bytes, data.length)) {
    return message;
  }
  CFRelease(message);
  return NULL;
}

static CFHTTPMessageRef _CreateHTTPMessageFromPerformingRequest(NSData* inData, NSUInteger port) {
  CFHTTPMessageRef response = NULL;
  int httpSocket = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (httpSocket > 0) {
    struct sockaddr_in addr4;
    bzero(&addr4, sizeof(addr4));
    addr4.sin_len = sizeof(port);
    addr4.sin_family = AF_INET;
    addr4.sin_port = htons(8080);
    addr4.sin_addr.s_addr = htonl(INADDR_ANY);
    if (connect(httpSocket, (void*)&addr4, sizeof(addr4)) == 0) {
      if (write(httpSocket, inData.bytes, inData.length) == (ssize_t)inData.length) {
        NSMutableData* outData = [[NSMutableData alloc] initWithLength:(256 * 1024)];
        NSUInteger length = 0;
        while (1) {
          ssize_t result = read(httpSocket, (char*)outData.mutableBytes + length, outData.length - length);
          if (result < 0) {
            length = NSUIntegerMax;
            break;
          } else if (result == 0) {
            break;
          }
          length += result;
          if (length >= outData.length) {
            outData.length = 2 * outData.length;
          }
        }
        if (length != NSUIntegerMax) {
          outData.length = length;
          response = _CreateHTTPMessageFromData(outData, NO);
        } else {
          DNOT_REACHED();
        }
        ARC_RELEASE(outData);
      }
    }
    close(httpSocket);
  }
  return response;
}

static void _LogResult(NSString* format, ...) {
  va_list arguments;
  va_start(arguments, format);
  NSString* message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  fprintf(stdout, "%s\n", [message UTF8String]);
  ARC_RELEASE(message);
}

- (NSInteger)runTestsWithOptions:(NSDictionary*)options inDirectory:(NSString*)path {
  DCHECK([NSThread isMainThread]);
  NSArray* ignoredHeaders = @[@"Date", @"Etag"];  // Dates are always different by definition and ETags depend on file system node IDs
  NSInteger result = -1;
  if ([self startWithOptions:options error:NULL]) {
    _ExecuteMainThreadRunLoopSources();
    
    result = 0;
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL];
    for (NSString* requestFile in files) {
      if (![requestFile hasSuffix:@".request"]) {
        continue;
      }
      @autoreleasepool {
        NSString* index = [[requestFile componentsSeparatedByString:@"-"] firstObject];
        BOOL success = NO;
        NSData* requestData = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:requestFile]];
        if (requestData) {
          CFHTTPMessageRef request = _CreateHTTPMessageFromData(requestData, YES);
          if (request) {
            NSString* requestMethod = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestMethod(request));
            NSURL* requestURL = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestURL(request));
            _LogResult(@"[%i] %@ %@", (int)[index integerValue], requestMethod, requestURL.path);
            NSString* prefix = [index stringByAppendingString:@"-"];
            for (NSString* responseFile in files) {
              if ([responseFile hasPrefix:prefix] && [responseFile hasSuffix:@".response"]) {
                NSData* responseData = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:responseFile]];
                if (responseData) {
                CFHTTPMessageRef expectedResponse = _CreateHTTPMessageFromData(responseData, NO);
                  if (expectedResponse) {
                    CFHTTPMessageRef actualResponse = _CreateHTTPMessageFromPerformingRequest(requestData, self.port);
                    if (actualResponse) {
                      success = YES;
                      
                      CFIndex expectedStatusCode = CFHTTPMessageGetResponseStatusCode(expectedResponse);
                      CFIndex actualStatusCode = CFHTTPMessageGetResponseStatusCode(actualResponse);
                      if (actualStatusCode != expectedStatusCode) {
                        _LogResult(@"  Status code not matching:\n    Expected: %i\n      Actual: %i", (int)expectedStatusCode, (int)actualStatusCode);
                        success = NO;
                      }
                      
                      NSDictionary* expectedHeaders = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyAllHeaderFields(expectedResponse));
                      NSDictionary* actualHeaders = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyAllHeaderFields(actualResponse));
                      for (NSString* expectedHeader in expectedHeaders) {
                        if ([ignoredHeaders containsObject:expectedHeader]) {
                          continue;
                        }
                        NSString* expectedValue = [expectedHeaders objectForKey:expectedHeader];
                        NSString* actualValue = [actualHeaders objectForKey:expectedHeader];
                        if (![actualValue isEqualToString:expectedValue]) {
                          _LogResult(@"  Header '%@' not matching:\n    Expected: \"%@\"\n      Actual: \"%@\"", expectedHeader, expectedValue, actualValue);
                          success = NO;
                        }
                      }
                      for (NSString* actualHeader in actualHeaders) {
                        if (![expectedHeaders objectForKey:actualHeader]) {
                          _LogResult(@"  Header '%@' not matching:\n    Expected: \"%@\"\n      Actual: \"%@\"", actualHeader, nil, [actualHeaders objectForKey:actualHeader]);
                          success = NO;
                        }
                      }
                      
                      NSString* expectedContentLength = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyHeaderFieldValue(expectedResponse, CFSTR("Content-Length")));
                      NSData* expectedBody = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyBody(expectedResponse));
                      NSString* actualContentLength = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyHeaderFieldValue(actualResponse, CFSTR("Content-Length")));
                      NSData* actualBody = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyBody(actualResponse));
                      if ([actualContentLength isEqualToString:expectedContentLength] && (actualBody.length > expectedBody.length)) {  // Handle web browser closing connection before retrieving entire body (e.g. when playing a video file)
                        actualBody = [actualBody subdataWithRange:NSMakeRange(0, expectedBody.length)];
                      }
                      if (![actualBody isEqualToData:expectedBody]) {
                        _LogResult(@"  Bodies not matching:\n    Expected: %lu bytes\n      Actual: %lu bytes", (unsigned long)expectedBody.length, (unsigned long)actualBody.length);
                        success = NO;
#if !TARGET_OS_IPHONE
#ifndef NDEBUG
                        if (GCDWebServerIsTextContentType([expectedHeaders objectForKey:@"Content-Type"])) {
                          NSString* expectedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"txt"]];
                          NSString* actualPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"txt"]];
                          if ([expectedBody writeToFile:expectedPath atomically:YES] && [actualBody writeToFile:actualPath atomically:YES]) {
                            NSTask* task = [[NSTask alloc] init];
                            [task setLaunchPath:@"/usr/bin/opendiff"];
                            [task setArguments:@[expectedPath, actualPath]];
                            [task launch];
                            ARC_RELEASE(task);
                          }
                        }
#endif
#endif
                      }
                      
                      CFRelease(actualResponse);
                    }
                    CFRelease(expectedResponse);
                  }
                } else {
                  DNOT_REACHED();
                }
                break;
              }
            }
            CFRelease(request);
          }
        } else {
          DNOT_REACHED();
        }
        _LogResult(@"");
        if (!success) {
          ++result;
        }
      }
      _ExecuteMainThreadRunLoopSources();
    }
    
    [self stop];
    
    _ExecuteMainThreadRunLoopSources();
  }
  return result;
}

@end

#endif
