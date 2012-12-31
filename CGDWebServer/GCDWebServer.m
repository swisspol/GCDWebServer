/*
 Copyright (c) 2012-2013, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the <organization> nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#import <netinet/in.h>

#import "GCDWebServerPrivate.h"

static BOOL _run;

NSString* GCDWebServerGetMimeTypeForExtension(NSString* extension) {
  static NSDictionary* _overrides = nil;
  if (_overrides == nil) {
    _overrides = [[NSDictionary alloc] initWithObjectsAndKeys:
                  @"text/css", @"css",
                  nil];
  }
  NSString* mimeType = nil;
  extension = [extension lowercaseString];
  if (extension.length) {
    mimeType = [_overrides objectForKey:extension];
    if (mimeType == nil) {
      CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)extension, NULL);
      if (uti) {
        mimeType = [(id)UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType) autorelease];
        CFRelease(uti);
      }
    }
  }
  return mimeType;
}

NSString* GCDWebServerUnescapeURLString(NSString* string) {
  return [(id)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)string, CFSTR(""),
                                                                      kCFStringEncodingUTF8) autorelease];
}

NSDictionary* GCDWebServerParseURLEncodedForm(NSString* form) {
  NSMutableDictionary* parameters = [NSMutableDictionary dictionary];
  NSScanner* scanner = [[NSScanner alloc] initWithString:form];
  [scanner setCharactersToBeSkipped:nil];
  while (1) {
    NSString* key = nil;
    if (![scanner scanUpToString:@"=" intoString:&key] || [scanner isAtEnd]) {
      break;
    }
    [scanner setScanLocation:([scanner scanLocation] + 1)];
    
    NSString* value = nil;
    if (![scanner scanUpToString:@"&" intoString:&value]) {
      break;
    }
    
    key = [key stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    value = [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    [parameters setObject:GCDWebServerUnescapeURLString(value) forKey:GCDWebServerUnescapeURLString(key)];
    
    if ([scanner isAtEnd]) {
      break;
    }
    [scanner setScanLocation:([scanner scanLocation] + 1)];
  }
  [scanner release];
  return parameters;
}

static void _SignalHandler(int signal) {
  _run = NO;
  printf("\n");
}

@implementation GCDWebServerHandler

@synthesize matchBlock=_matchBlock, processBlock=_processBlock;

- (id)initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock {
  if ((self = [super init])) {
    _matchBlock = Block_copy(matchBlock);
    _processBlock = Block_copy(processBlock);
  }
  return self;
}

- (void)dealloc {
  Block_release(_matchBlock);
  Block_release(_processBlock);
  
  [super dealloc];
}

@end

@implementation GCDWebServer

@synthesize handlers=_handlers, port=_port;

+ (void)initialize {
  [GCDWebServerConnection class];  // Initialize class immediately to make sure it happens on the main thread
}

- (id)init {
  if ((self = [super init])) {
    _handlers = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  if (_runLoop) {
    [self stop];
  }
  
  [_handlers release];
  
  [super dealloc];
}

- (void)addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)handlerBlock {
  DCHECK(_runLoop == nil);
  GCDWebServerHandler* handler = [[GCDWebServerHandler alloc] initWithMatchBlock:matchBlock processBlock:handlerBlock];
  [_handlers insertObject:handler atIndex:0];
  [handler release];
}

- (void)removeAllHandlers {
  DCHECK(_runLoop == nil);
  [_handlers removeAllObjects];
}

- (BOOL)start {
  return [self startWithRunloop:[NSRunLoop mainRunLoop] port:8080 bonjourName:@""];
}

static void _NetServiceClientCallBack(CFNetServiceRef service, CFStreamError* error, void* info) {
  @autoreleasepool {
    if (error->error) {
      LOG_ERROR(@"Bonjour error %i (domain %i)", error->error, (int)error->domain);
    } else {
      LOG_VERBOSE(@"Registered Bonjour service \"%@\" with type '%@' on port %i", CFNetServiceGetName(service), CFNetServiceGetType(service), CFNetServiceGetPortNumber(service));
    }
  }
}

static void _SocketCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void* data, void* info) {
  if (type == kCFSocketAcceptCallBack) {
    CFSocketNativeHandle handle = *(CFSocketNativeHandle*)data;
    int set = 1;
    setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int));  // Make sure this socket cannot generate SIG_PIPE
    @autoreleasepool {
      Class class = [[(GCDWebServer*)info class] connectionClass];
      GCDWebServerConnection* connection = [[class alloc] initWithServer:(GCDWebServer*)info address:(NSData*)address socket:handle];
      [connection release];  // Connection will automatically retain itself while opened
    }
  } else {
    DNOT_REACHED();
  }
}

- (BOOL)startWithRunloop:(NSRunLoop*)runloop port:(NSUInteger)port bonjourName:(NSString*)name {
  DCHECK(runloop);
  DCHECK(port);
  DCHECK(_runLoop == nil);
  CFSocketContext context = {0, self, NULL, NULL, NULL};
  _socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, _SocketCallBack, &context);
  if (_socket) {
    int yes = 1;
    setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    
    struct sockaddr_in addr4;
    bzero(&addr4, sizeof(addr4));
    addr4.sin_len = sizeof(addr4);
    addr4.sin_family = AF_INET;
    addr4.sin_port = htons(port);
    addr4.sin_addr.s_addr = htonl(INADDR_ANY);
    if (CFSocketSetAddress(_socket, (CFDataRef)[NSData dataWithBytes:&addr4 length:sizeof(addr4)]) == kCFSocketSuccess) {
      CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
      CFRunLoopAddSource([runloop getCFRunLoop], source, kCFRunLoopCommonModes);
      CFRelease(source);
      
      if (name) {
        _service = CFNetServiceCreate(kCFAllocatorDefault, CFSTR("local."), CFSTR("_http._tcp"), (CFStringRef)name, port);
        if (_service) {
          CFNetServiceClientContext context = {0, self, NULL, NULL, NULL};
          CFNetServiceSetClient(_service, _NetServiceClientCallBack, &context);
          CFNetServiceScheduleWithRunLoop(_service, [runloop getCFRunLoop], kCFRunLoopCommonModes);
          CFStreamError error = {0};
          CFNetServiceRegisterWithOptions(_service, 0, &error);
        } else {
          LOG_ERROR(@"Failed creating CFNetService");
        }
      }
      
      _port = port;
      _runLoop = [runloop retain];
      LOG_VERBOSE(@"%@ started on port %i", [self class], (int)port);
    } else {
      LOG_ERROR(@"Failed binding socket");
      CFRelease(_socket);
      _socket = NULL;
    }
  } else {
    LOG_ERROR(@"Failed creating CFSocket");
  }
  return (_runLoop != nil ? YES : NO);
}

- (BOOL)isRunning {
  return (_runLoop != nil ? YES : NO);
}

- (void)stop {
  DCHECK(_runLoop != nil);
  if (_socket) {
    if (_service) {
      CFNetServiceUnscheduleFromRunLoop(_service, [_runLoop getCFRunLoop], kCFRunLoopCommonModes);
      CFNetServiceSetClient(_service, NULL, NULL);
      CFRelease(_service);
    }
    
    CFSocketInvalidate(_socket);
    CFRelease(_socket);
    _socket = NULL;
    LOG_VERBOSE(@"%@ stopped", [self class]);
  }
  [_runLoop release];
  _runLoop = nil;
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

@end

@implementation GCDWebServer (Extensions)

- (BOOL)runWithPort:(NSUInteger)port {
  BOOL success = NO;
  _run = YES;
  void* handler = signal(SIGINT, _SignalHandler);
  if (handler != SIG_ERR) {
    if ([self startWithRunloop:[NSRunLoop currentRunLoop] port:port bonjourName:@""]) {
      while (_run) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
      }
      [self stop];
      success = YES;
    }
    signal(SIGINT, handler);
  }
  return success;
}

@end

@implementation GCDWebServer (Handlers)

- (void)addDefaultHandlerForMethod:(NSString*)method requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block {
  [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
    
    return [[[class alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
    
  } processBlock:block];
}

- (GCDWebServerResponse*)_responseWithContentsOfFile:(NSString*)path {
  return [GCDWebServerFileResponse responseWithFile:path];
}

- (GCDWebServerResponse*)_responseWithContentsOfDirectory:(NSString*)path {
  NSDirectoryEnumerator* enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
  if (enumerator == nil) {
    return nil;
  }
  NSMutableString* html = [NSMutableString string];
  [html appendString:@"<html><body>\n"];
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

- (void)addHandlerForBasePath:(NSString*)basePath localPath:(NSString*)localPath indexFilename:(NSString*)indexFilename cacheAge:(NSUInteger)cacheAge {
  if ([basePath hasPrefix:@"/"] && [basePath hasSuffix:@"/"]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:@"GET"]) {
        return nil;
      }
      if (![urlPath hasPrefix:basePath]) {
        return nil;
      }
      return [[[GCDWebServerRequest alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
      
    } processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      GCDWebServerResponse* response = nil;
      NSString* filePath = [localPath stringByAppendingPathComponent:[request.path substringFromIndex:basePath.length]];
      BOOL isDirectory;
      if ([[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory]) {
        if (isDirectory) {
          if (indexFilename) {
            NSString* indexPath = [filePath stringByAppendingPathComponent:indexFilename];
            if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath isDirectory:&isDirectory] && !isDirectory) {
              return [self _responseWithContentsOfFile:indexPath];
            }
          }
          response = [self _responseWithContentsOfDirectory:filePath];
        } else {
          response = [self _responseWithContentsOfFile:filePath];
        }
      }
      if (response) {
        response.cacheControlMaxAge = cacheAge;
      } else {
        response = [GCDWebServerResponse responseWithStatusCode:404];
      }
      return response;
      
    }];
  } else {
    DNOT_REACHED();
  }
}

- (void)addHandlerForMethod:(NSString*)method path:(NSString*)path requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block {
  if ([path hasPrefix:@"/"] && [class isSubclassOfClass:[GCDWebServerRequest class]]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:method]) {
        return nil;
      }
      if ([urlPath caseInsensitiveCompare:path] != NSOrderedSame) {
        return nil;
      }
      return [[[class alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
      
    } processBlock:block];
  } else {
    DNOT_REACHED();
  }
}

- (void)addHandlerForMethod:(NSString*)method pathRegex:(NSString*)regex requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block {
  NSRegularExpression* expression = [NSRegularExpression regularExpressionWithPattern:regex options:NSRegularExpressionCaseInsensitive error:NULL];
  if (expression && [class isSubclassOfClass:[GCDWebServerRequest class]]) {
    [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
      
      if (![requestMethod isEqualToString:method]) {
        return nil;
      }
      if ([expression firstMatchInString:urlPath options:0 range:NSMakeRange(0, urlPath.length)] == nil) {
        return nil;
      }
      return [[[class alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery] autorelease];
      
    } processBlock:block];
  } else {
    DNOT_REACHED();
  }
}

@end
