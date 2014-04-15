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
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
#if !TARGET_OS_IPHONE
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
#define kMaxPendingConnections 16

@interface GCDWebServer () {
@private
  NSMutableArray* _handlers;
  
  NSUInteger _port;
  dispatch_source_t _source;
  CFNetServiceRef _service;
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
  BOOL _recording;
#endif
}
@end

@interface GCDWebServerHandler () {
@private
  GCDWebServerMatchBlock _matchBlock;
  GCDWebServerProcessBlock _processBlock;
}
@end

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

@implementation GCDWebServer

@synthesize handlers=_handlers, port=_port;

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

- (instancetype)init {
  if ((self = [super init])) {
    _handlers = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  if (_source) {
    [self stop];
  }
  
  ARC_RELEASE(_handlers);
  
  ARC_DEALLOC(super);
}

- (NSString*)bonjourName {
  CFStringRef name = _service ? CFNetServiceGetName(_service) : NULL;
  return name && CFStringGetLength(name) ? ARC_BRIDGE_RELEASE(CFStringCreateCopy(kCFAllocatorDefault, name)) : nil;
}

- (void)addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)handlerBlock {
  DCHECK(_source == NULL);
  GCDWebServerHandler* handler = [[GCDWebServerHandler alloc] initWithMatchBlock:matchBlock processBlock:handlerBlock];
  [_handlers insertObject:handler atIndex:0];
  ARC_RELEASE(handler);
}

- (void)removeAllHandlers {
  DCHECK(_source == NULL);
  [_handlers removeAllObjects];
}

- (BOOL)start {
  return [self startWithPort:kDefaultPort bonjourName:@""];
}

static void _NetServiceClientCallBack(CFNetServiceRef service, CFStreamError* error, void* info) {
  @autoreleasepool {
    if (error->error) {
      LOG_ERROR(@"Bonjour error %i (domain %i)", (int)error->error, (int)error->domain);
    } else {
      GCDWebServer* server = (ARC_BRIDGE GCDWebServer*)info;
      LOG_INFO(@"%@ now reachable at %@", [server class], server.bonjourServerURL);
    }
  }
}

- (BOOL)startWithPort:(NSUInteger)port bonjourName:(NSString*)name {
  DCHECK(_source == NULL);
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
      if (listen(listeningSocket, kMaxPendingConnections) == 0) {
        _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, listeningSocket, 0, kGCDWebServerGCDQueue);
        dispatch_source_set_cancel_handler(_source, ^{
          
          @autoreleasepool {
            int result = close(listeningSocket);
            if (result != 0) {
              LOG_ERROR(@"Failed closing socket (%i): %s", errno, strerror(errno));
            } else {
              LOG_DEBUG(@"Closed listening socket");
            }
          }
          
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
              
              Class connectionClass = [[self class] connectionClass];
              GCDWebServerConnection* connection = [[connectionClass alloc] initWithServer:self localAddress:localAddress remoteAddress:remoteAddress socket:socket];  // Connection will automatically retain itself while opened
#if __has_feature(objc_arc)
              [connection self];  // Prevent compiler from complaining about unused variable / useless statement
#else
              [connection release];
#endif
            } else {
              LOG_ERROR(@"Failed accepting socket (%i): %s", errno, strerror(errno));
            }
          }
          
        });
        
        if (port == 0) {  // Determine the actual port we are listening on
          struct sockaddr addr;
          socklen_t addrlen = sizeof(addr);
          if (getsockname(listeningSocket, &addr, &addrlen) == 0) {
            struct sockaddr_in* sockaddr = (struct sockaddr_in*)&addr;
            _port = ntohs(sockaddr->sin_port);
          } else {
            LOG_ERROR(@"Failed retrieving socket address (%i): %s", errno, strerror(errno));
          }
        } else {
          _port = port;
        }
        
        if (name) {
          _service = CFNetServiceCreate(kCFAllocatorDefault, CFSTR("local."), CFSTR("_http._tcp"), (ARC_BRIDGE CFStringRef)name, (SInt32)_port);
          if (_service) {
            CFNetServiceClientContext context = {0, (ARC_BRIDGE void*)self, NULL, NULL, NULL};
            CFNetServiceSetClient(_service, _NetServiceClientCallBack, &context);
            CFNetServiceScheduleWithRunLoop(_service, CFRunLoopGetMain(), kCFRunLoopCommonModes);
            CFStreamError error = {0};
            CFNetServiceRegisterWithOptions(_service, 0, &error);
          } else {
            LOG_ERROR(@"Failed creating CFNetService");
          }
        }
        
        dispatch_resume(_source);
        LOG_INFO(@"%@ started on port %i and reachable at %@", [self class], (int)_port, self.serverURL);
      } else {
        LOG_ERROR(@"Failed listening on socket (%i): %s", errno, strerror(errno));
        close(listeningSocket);
      }
    } else {
      LOG_ERROR(@"Failed binding socket (%i): %s", errno, strerror(errno));
      close(listeningSocket);
    }
  } else {
    LOG_ERROR(@"Failed creating socket (%i): %s", errno, strerror(errno));
  }
  return (_source ? YES : NO);
}

- (BOOL)isRunning {
  return (_source ? YES : NO);
}

- (void)stop {
  DCHECK(_source != NULL);
  if (_source) {
    if (_service) {
      CFNetServiceUnscheduleFromRunLoop(_service, CFRunLoopGetMain(), kCFRunLoopCommonModes);
      CFNetServiceSetClient(_service, NULL, NULL);
      CFRelease(_service);
      _service = NULL;
    }
    
    dispatch_source_cancel(_source);  // This will close the socket
    ARC_DISPATCH_RELEASE(_source);
    _source = NULL;
    
    LOG_INFO(@"%@ stopped", [self class]);
  }
  _port = 0;
}

@end

@implementation GCDWebServer (Subclassing)

+ (Class)connectionClass {
  return [GCDWebServerConnection class];
}

+ (NSString*)serverName {
  return NSStringFromClass(self);
}

+ (BOOL)shouldAutomaticallyMapHEADToGET {
  return YES;
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
  if (_source && _service) {
    CFStringRef name = CFNetServiceGetName(_service);
    if (name && CFStringGetLength(name)) {
      if (_port != 80) {
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@.local:%i/", name, (int)_port]];
      } else {
        return [NSURL URLWithString:[NSString stringWithFormat:@"http://%@.local/", name]];
      }
    }
  }
  return nil;
}

#if !TARGET_OS_IPHONE

- (BOOL)runWithPort:(NSUInteger)port {
  BOOL success = NO;
  _run = YES;
  void (*handler)(int) = signal(SIGINT, _SignalHandler);
  if (handler != SIG_ERR) {
    if ([self startWithPort:port bonjourName:@""]) {
      while (_run) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
      }
      [self stop];
      success = YES;
    }
    signal(SIGINT, handler);
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
  GCDWebServerResponse* response = [GCDWebServerDataResponse responseWithData:staticData contentType:contentType];
  response.cacheControlMaxAge = cacheAge;
  [self addHandlerForMethod:@"GET" path:path requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
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
  NSString* message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  LOG_VERBOSE(@"%@", message);
  ARC_RELEASE(message);
}

- (void)logInfo:(NSString*)format, ... {
  va_list arguments;
  va_start(arguments, format);
  NSString* message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  LOG_INFO(@"%@", message);
  ARC_RELEASE(message);
}

- (void)logWarning:(NSString*)format, ... {
  va_list arguments;
  va_start(arguments, format);
  NSString* message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  LOG_WARNING(@"%@", message);
  ARC_RELEASE(message);
}

- (void)logError:(NSString*)format, ... {
  va_list arguments;
  va_start(arguments, format);
  NSString* message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  LOG_ERROR(@"%@", message);
  ARC_RELEASE(message);
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
            length = NSNotFound;
            break;
          } else if (result == 0) {
            break;
          }
          length += result;
          if (length >= outData.length) {
            outData.length = 2 * outData.length;
          }
        }
        if (length != NSNotFound) {
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

- (NSInteger)runTestsInDirectory:(NSString*)path withPort:(NSUInteger)port {
  NSArray* ignoredHeaders = @[@"Date", @"Etag"];  // Dates are always different by definition and ETags depend on file system node IDs
  NSInteger result = -1;
  if ([self startWithPort:port bonjourName:nil]) {
    
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
                    CFHTTPMessageRef actualResponse = _CreateHTTPMessageFromPerformingRequest(requestData, port);
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
                      
                      NSData* expectedBody = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyBody(expectedResponse));
                      NSData* actualBody = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyBody(actualResponse));
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
    }
    
    [self stop];
  }
  return result;
}

@end

#endif
