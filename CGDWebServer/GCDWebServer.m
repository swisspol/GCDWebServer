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
#import <MobileCoreServices/MobileCoreServices.h>
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
}
@end

@interface GCDWebServerHandler () {
@private
  GCDWebServerMatchBlock _matchBlock;
  GCDWebServerProcessBlock _processBlock;
}
@end

#if !TARGET_OS_IPHONE
static BOOL _run;
#endif

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
      CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (ARC_BRIDGE CFStringRef)extension, NULL);
      if (uti) {
        mimeType = ARC_BRIDGE_RELEASE(UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType));
        CFRelease(uti);
      }
    }
  }
  return mimeType;
}

NSString* GCDWebServerUnescapeURLString(NSString* string) {
  return ARC_BRIDGE_RELEASE(CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)string, CFSTR(""),
                                                                                    kCFStringEncodingUTF8));
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
    if (key && value) {
      [parameters setObject:GCDWebServerUnescapeURLString(value) forKey:GCDWebServerUnescapeURLString(key)];
    } else {
      DNOT_REACHED();
    }
    
    if ([scanner isAtEnd]) {
      break;
    }
    [scanner setScanLocation:([scanner scanLocation] + 1)];
  }
  ARC_RELEASE(scanner);
  return parameters;
}

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
      LOG_VERBOSE(@"Registered Bonjour service \"%@\" in domain \"%@\" with type '%@' on port %i", CFNetServiceGetName(service), CFNetServiceGetDomain(service), CFNetServiceGetType(service), (int)CFNetServiceGetPortNumber(service));
    }
  }
}

- (BOOL)startWithPort:(NSUInteger)port bonjourName:(NSString*)name {
  DCHECK(_source == NULL);
  int listeningSocket = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listeningSocket > 0) {
    int yes = 1;
    setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEPORT, &yes, sizeof(yes));
    
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
            struct sockaddr addr;
            socklen_t addrlen = sizeof(addr);
            int socket = accept(listeningSocket, &addr, &addrlen);
            if (socket > 0) {
              int yes = 1;
              setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));  // Make sure this socket cannot generate SIG_PIPE
              
              NSData* data = [NSData dataWithBytes:&addr length:addrlen];
              Class connectionClass = [[self class] connectionClass];
              GCDWebServerConnection* connection = [[connectionClass alloc] initWithServer:self address:data socket:socket];  // Connection will automatically retain itself while opened
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
        LOG_VERBOSE(@"%@ started on port %i", [self class], (int)_port);
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
    
    LOG_VERBOSE(@"%@ stopped", [self class]);
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

@end

#if !TARGET_OS_IPHONE

@implementation GCDWebServer (Extensions)

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

@end

#endif

@implementation GCDWebServer (Handlers)

- (void)addDefaultHandlerForMethod:(NSString*)method requestClass:(Class)aClass processBlock:(GCDWebServerProcessBlock)block {
  [self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {
    
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
    __unsafe_unretained GCDWebServer* server = self;
#else
    GCDWebServer* server = self;
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
        response = [GCDWebServerResponse responseWithStatusCode:404];
      }
      return response;
      
    }];
  } else {
    DNOT_REACHED();
  }
}

@end
