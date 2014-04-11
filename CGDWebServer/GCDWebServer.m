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
#else
#import <SystemConfiguration/SystemConfiguration.h>
#endif

#import <netinet/in.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netdb.h>

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
#if !TARGET_OS_IPHONE
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

static NSDateFormatter* _dateFormatterRFC822 = nil;
static dispatch_queue_t _dateFormatterQueue = NULL;
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

NSString* GCDWebServerNormalizeHeaderValue(NSString* value) {
  if (value) {
    NSRange range = [value rangeOfString:@";"];  // Assume part before ";" separator is case-insensitive
    if (range.location != NSNotFound) {
      value = [[[value substringToIndex:range.location] lowercaseString] stringByAppendingString:[value substringFromIndex:range.location]];
    } else {
      value = [value lowercaseString];
    }
  }
  return value;
}

NSString* GCDWebServerTruncateHeaderValue(NSString* value) {
  DCHECK([value isEqualToString:GCDWebServerNormalizeHeaderValue(value)]);
  NSRange range = [value rangeOfString:@";"];
  return range.location != NSNotFound ? [value substringToIndex:range.location] : value;
}

NSString* GCDWebServerExtractHeaderValueParameter(NSString* value, NSString* name) {
  DCHECK([value isEqualToString:GCDWebServerNormalizeHeaderValue(value)]);
  NSString* parameter = nil;
  NSScanner* scanner = [[NSScanner alloc] initWithString:value];
  [scanner setCaseSensitive:NO];  // Assume parameter names are case-insensitive
  NSString* string = [NSString stringWithFormat:@"%@=", name];
  if ([scanner scanUpToString:string intoString:NULL]) {
    [scanner scanString:string intoString:NULL];
    if ([scanner scanString:@"\"" intoString:NULL]) {
      [scanner scanUpToString:@"\"" intoString:&parameter];
    } else {
      [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&parameter];
    }
  }
  ARC_RELEASE(scanner);
  return parameter;
}

// http://www.w3schools.com/tags/ref_charactersets.asp
NSStringEncoding GCDWebServerStringEncodingFromCharset(NSString* charset) {
  NSStringEncoding encoding = kCFStringEncodingInvalidId;
  if (charset) {
    encoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding((CFStringRef)charset));
  }
  return (encoding != kCFStringEncodingInvalidId ? encoding : NSUTF8StringEncoding);
}

NSString* GCDWebServerFormatHTTPDate(NSDate* date) {
  __block NSString* string;
  dispatch_sync(_dateFormatterQueue, ^{
    string = [_dateFormatterRFC822 stringFromDate:date];  // HTTP/1.1 server must use RFC822
  });
  return string;
}

NSDate* GCDWebServerParseHTTPDate(NSString* string) {
  __block NSDate* date;
  dispatch_sync(_dateFormatterQueue, ^{
    date = [_dateFormatterRFC822 dateFromString:string];  // TODO: Handle RFC 850 and ANSI C's asctime() format (http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3)
  });
  return date;
}

static inline BOOL _IsTextContentType(NSString* type) {
  return ([type hasPrefix:@"text/"] || [type hasPrefix:@"application/json"] || [type hasPrefix:@"application/xml"]);
}

NSString* GCDWebServerDescribeData(NSData* data, NSString* type) {
  if (_IsTextContentType(type)) {
    NSString* charset = GCDWebServerExtractHeaderValueParameter(type, @"charset");
    NSString* string = [[NSString alloc] initWithData:data encoding:GCDWebServerStringEncodingFromCharset(charset)];
    if (string) {
      return ARC_AUTORELEASE(string);
    }
  }
  return [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)data.length];
}

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
  return mimeType ? mimeType : kGCDWebServerDefaultMimeType;
}

NSString* GCDWebServerEscapeURLString(NSString* string) {
  return ARC_BRIDGE_RELEASE(CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (CFStringRef)string, NULL, CFSTR(":@/?&=+"), kCFStringEncodingUTF8));
}

NSString* GCDWebServerUnescapeURLString(NSString* string) {
  return ARC_BRIDGE_RELEASE(CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)string, CFSTR(""), kCFStringEncodingUTF8));
}

// http://www.w3.org/TR/html401/interact/forms.html#h-17.13.4.1
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

NSString* GCDWebServerGetPrimaryIPv4Address() {
  NSString* address = nil;
#if TARGET_OS_IPHONE
#if !TARGET_IPHONE_SIMULATOR
  const char* primaryInterface = "en0";  // WiFi interface on iOS
#endif
#else
  const char* primaryInterface = NULL;
  SCDynamicStoreRef store = SCDynamicStoreCreate(kCFAllocatorDefault, CFSTR("GCDWebServer"), NULL, NULL);
  if (store) {
    CFPropertyListRef info = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"));
    if (info) {
      primaryInterface = [[NSString stringWithString:[(ARC_BRIDGE NSDictionary*)info objectForKey:@"PrimaryInterface"]] UTF8String];
      CFRelease(info);
    }
    CFRelease(store);
  }
  if (primaryInterface == NULL) {
    primaryInterface = "lo0";
  }
#endif
  struct ifaddrs* list;
  if (getifaddrs(&list) >= 0) {
    for (struct ifaddrs* ifap = list; ifap; ifap = ifap->ifa_next) {
#if TARGET_IPHONE_SIMULATOR
      if (strcmp(ifap->ifa_name, "en0") && strcmp(ifap->ifa_name, "en1"))  // Assume en0 is Ethernet and en1 is WiFi since there is no way to use SystemConfiguration framework in iOS Simulator
#else
      if (strcmp(ifap->ifa_name, primaryInterface))
#endif
      {
        continue;
      }
      if ((ifap->ifa_flags & IFF_UP) && (ifap->ifa_addr->sa_family == AF_INET)) {
        char buffer[NI_MAXHOST];
        if (getnameinfo(ifap->ifa_addr, ifap->ifa_addr->sa_len, buffer, sizeof(buffer), NULL, 0, NI_NUMERICHOST | NI_NOFQDN) >= 0) {
          address = [NSString stringWithUTF8String:buffer];
        }
        break;
      }
    }
    freeifaddrs(list);
  }
  return address;
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

#ifndef __GCDWEBSERVER_LOGGING_HEADER__

+ (void)load {
  const char* logLevel = getenv("logLevel");
  if (logLevel) {
    GCDLogLevel = atoi(logLevel);
  }
}

#endif

+ (void)initialize {
  if (_dateFormatterRFC822 == nil) {
    DCHECK([NSThread isMainThread]);  // NSDateFormatter should be initialized on main thread
    _dateFormatterRFC822 = [[NSDateFormatter alloc] init];
    _dateFormatterRFC822.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    _dateFormatterRFC822.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    _dateFormatterRFC822.locale = ARC_AUTORELEASE([[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]);
    DCHECK(_dateFormatterRFC822);
  }
  if (_dateFormatterQueue == NULL) {
    _dateFormatterQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    DCHECK(_dateFormatterQueue);
  }
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

#if !TARGET_OS_IPHONE

- (void)setRecordingEnabled:(BOOL)flag {
  _recording = flag;
}

- (BOOL)isRecordingEnabled {
  return _recording;
}

#endif

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

static CFHTTPMessageRef _CreateHTTPMessageFromFileDump(NSString* path, BOOL isRequest) {
  NSData* data = [NSData dataWithContentsOfFile:path];
  if (data) {
    CFHTTPMessageRef message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, isRequest);
    if (CFHTTPMessageAppendBytes(message, data.bytes, data.length)) {
      return message;
    }
    CFRelease(message);
  }
  return NULL;
}

static CFHTTPMessageRef _CreateHTTPMessageFromHTTPRequestResponse(CFHTTPMessageRef request) {
  CFHTTPMessageRef response = NULL;
  CFReadStreamRef stream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, request);
  if (CFReadStreamOpen(stream)) {
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    CFDataSetLength(data, 256 * 1024);
    CFIndex length = 0;
    while (1) {
      CFIndex result = CFReadStreamRead(stream, CFDataGetMutableBytePtr(data) + length, CFDataGetLength(data) - length);
      if (result <= 0) {
        break;
      }
      length += result;
      if (length >= CFDataGetLength(data)) {
        CFDataSetLength(data, 2 * CFDataGetLength(data));
      }
    }
    if (CFReadStreamGetStatus(stream) == kCFStreamStatusAtEnd) {
      response = (CFHTTPMessageRef)CFReadStreamCopyProperty(stream, kCFStreamPropertyHTTPResponseHeader);
      if (response) {
        CFDataSetLength(data, length);
        CFHTTPMessageSetBody(response, data);
      }
    }
    CFRelease(data);
    CFReadStreamClose(stream);
    CFRelease(stream);
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
        CFHTTPMessageRef request = _CreateHTTPMessageFromFileDump([path stringByAppendingPathComponent:requestFile], YES);
        if (request) {
          _LogResult(@"[%i] %@ %@", (int)[index integerValue], ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestMethod(request)), [ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestURL(request)) path]);
          NSString* prefix = [index stringByAppendingString:@"-"];
          for (NSString* responseFile in files) {
            if ([responseFile hasPrefix:prefix] && [responseFile hasSuffix:@".response"]) {
              CFHTTPMessageRef expectedResponse = _CreateHTTPMessageFromFileDump([path stringByAppendingPathComponent:responseFile], NO);
              if (expectedResponse) {
                CFHTTPMessageRef actualResponse = _CreateHTTPMessageFromHTTPRequestResponse(request);
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
                    if ([expectedHeader isEqualToString:@"Date"]) {
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
                    
                    if (_IsTextContentType([expectedHeaders objectForKey:@"Content-Type"])) {
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
                  }
                  
                  CFRelease(actualResponse);
                }
                CFRelease(expectedResponse);
              }
              break;
            }
          }
          CFRelease(request);
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
