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

#import "GCDWebServerPrivate.h"

#define kHeadersReadBuffer 1024
#define kBodyWriteBufferSize (32 * 1024)

typedef void (^ReadBufferCompletionBlock)(dispatch_data_t buffer);
typedef void (^ReadDataCompletionBlock)(NSData* data);
typedef void (^ReadHeadersCompletionBlock)(NSData* extraData);
typedef void (^ReadBodyCompletionBlock)(BOOL success);

typedef void (^WriteBufferCompletionBlock)(BOOL success);
typedef void (^WriteDataCompletionBlock)(BOOL success);
typedef void (^WriteHeadersCompletionBlock)(BOOL success);
typedef void (^WriteBodyCompletionBlock)(BOOL success);

static NSData* _separatorData = nil;
static NSData* _continueData = nil;
static NSDateFormatter* _dateFormatter = nil;
static dispatch_queue_t _formatterQueue = NULL;

@interface GCDWebServerConnection () {
@private
  GCDWebServer* _server;
  NSData* _address;
  CFSocketNativeHandle _socket;
  NSUInteger _bytesRead;
  NSUInteger _bytesWritten;
  
  CFHTTPMessageRef _requestMessage;
  GCDWebServerRequest* _request;
  GCDWebServerHandler* _handler;
  CFHTTPMessageRef _responseMessage;
  GCDWebServerResponse* _response;
}
@end

@implementation GCDWebServerConnection (Read)

- (void)_readBufferWithLength:(NSUInteger)length completionBlock:(ReadBufferCompletionBlock)block {
  dispatch_read(_socket, length, kGCDWebServerGCDQueue, ^(dispatch_data_t buffer, int error) {
    
    @autoreleasepool {
      if (error == 0) {
        size_t size = dispatch_data_get_size(buffer);
        if (size > 0) {
          LOG_DEBUG(@"Connection received %zu bytes on socket %i", size, _socket);
          _bytesRead += size;
          [self didUpdateBytesRead];
          block(buffer);
        } else {
          if (_bytesRead > 0) {
            LOG_ERROR(@"No more data available on socket %i", _socket);
          } else {
            LOG_WARNING(@"No data received from socket %i", _socket);
          }
          block(NULL);
        }
      } else {
        LOG_ERROR(@"Error while reading from socket %i: %s (%i)", _socket, strerror(error), error);
        block(NULL);
      }
    }
    
  });
}

- (void)_readDataWithCompletionBlock:(ReadDataCompletionBlock)block {
  [self _readBufferWithLength:SIZE_T_MAX completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      NSMutableData* data = [[NSMutableData alloc] initWithCapacity:dispatch_data_get_size(buffer)];
      dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t offset, const void* buffer, size_t size) {
        [data appendBytes:buffer length:size];
        return true;
      });
      block(data);
      ARC_RELEASE(data);
    } else {
      block(nil);
    }
    
  }];
}

- (void)_readHeadersWithCompletionBlock:(ReadHeadersCompletionBlock)block {
  DCHECK(_requestMessage);
  [self _readBufferWithLength:SIZE_T_MAX completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      NSMutableData* data = [NSMutableData dataWithCapacity:kHeadersReadBuffer];
      dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t offset, const void* buffer, size_t size) {
        [data appendBytes:buffer length:size];
        return true;
      });
      NSRange range = [data rangeOfData:_separatorData options:0 range:NSMakeRange(0, data.length)];
      if (range.location == NSNotFound) {
        if (CFHTTPMessageAppendBytes(_requestMessage, data.bytes, data.length)) {
          [self _readHeadersWithCompletionBlock:block];
        } else {
          LOG_ERROR(@"Failed appending request headers data from socket %i", _socket);
          block(nil);
        }
      } else {
        NSUInteger length = range.location + range.length;
        if (CFHTTPMessageAppendBytes(_requestMessage, data.bytes, length)) {
          if (CFHTTPMessageIsHeaderComplete(_requestMessage)) {
            block([data subdataWithRange:NSMakeRange(length, data.length - length)]);
          } else {
            LOG_ERROR(@"Failed parsing request headers from socket %i", _socket);
            block(nil);
          }
        } else {
          LOG_ERROR(@"Failed appending request headers data from socket %i", _socket);
          block(nil);
        }
      }
    } else {
      block(nil);
    }
    
  }];
}

- (void)_readBodyWithRemainingLength:(NSUInteger)length completionBlock:(ReadBodyCompletionBlock)block {
  DCHECK([_request hasBody]);
  [self _readBufferWithLength:length completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      NSInteger remainingLength = length - dispatch_data_get_size(buffer);
      if (remainingLength >= 0) {
        bool success = dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t offset, const void* buffer, size_t size) {
          NSInteger result = [_request write:buffer maxLength:size];
          if (result != (NSInteger)size) {
            LOG_ERROR(@"Failed writing request body on socket %i (error %i)", _socket, (int)result);
            return false;
          }
          return true;
        });
        if (success) {
          if (remainingLength > 0) {
            [self _readBodyWithRemainingLength:remainingLength completionBlock:block];
          } else {
            block(YES);
          }
        } else {
          block(NO);
        }
      } else {
        block(NO);
        DNOT_REACHED();
      }
    } else {
      block(NO);
    }
    
  }];
}

@end

@implementation GCDWebServerConnection (Write)

- (void)_writeBuffer:(dispatch_data_t)buffer withCompletionBlock:(WriteBufferCompletionBlock)block {
  size_t size = dispatch_data_get_size(buffer);
  dispatch_write(_socket, buffer, kGCDWebServerGCDQueue, ^(dispatch_data_t data, int error) {
    
    @autoreleasepool {
      if (error == 0) {
        DCHECK(data == NULL);
        LOG_DEBUG(@"Connection sent %zu bytes on socket %i", size, _socket);
        _bytesWritten += size;
        [self didUpdateBytesWritten];
        block(YES);
      } else {
        LOG_ERROR(@"Error while writing to socket %i: %s (%i)", _socket, strerror(error), error);
        block(NO);
      }
    }
    
  });
}

- (void)_writeData:(NSData*)data withCompletionBlock:(WriteDataCompletionBlock)block {
#if !__has_feature(objc_arc)
  [data retain];
#endif
  dispatch_data_t buffer = dispatch_data_create(data.bytes, data.length, dispatch_get_main_queue(), ^{
#if __has_feature(objc_arc)
    [data self];  // Keeps ARC from releasing data too early
#else
    [data release];
#endif
  });
  [self _writeBuffer:buffer withCompletionBlock:block];
  ARC_DISPATCH_RELEASE(buffer);
}

- (void)_writeHeadersWithCompletionBlock:(WriteHeadersCompletionBlock)block {
  DCHECK(_responseMessage);
  CFDataRef message = CFHTTPMessageCopySerializedMessage(_responseMessage);
  [self _writeData:(ARC_BRIDGE NSData*)message withCompletionBlock:block];
  CFRelease(message);
}

- (void)_writeBodyWithCompletionBlock:(WriteBodyCompletionBlock)block {
  DCHECK([_response hasBody]);
  void* buffer = malloc(kBodyWriteBufferSize);
  NSInteger result = [_response read:buffer maxLength:kBodyWriteBufferSize];
  if (result > 0) {
    dispatch_data_t wrapper = dispatch_data_create(buffer, result, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
    [self _writeBuffer:wrapper withCompletionBlock:^(BOOL success) {
      
      if (success) {
        [self _writeBodyWithCompletionBlock:block];
      } else {
        block(NO);
      }
      
    }];
    ARC_DISPATCH_RELEASE(wrapper);
  } else if (result < 0) {
    LOG_ERROR(@"Failed reading response body on socket %i (error %i)", _socket, (int)result);
    block(NO);
    free(buffer);
  } else {
    block(YES);
    free(buffer);
  }
}

@end

@implementation GCDWebServerConnection

@synthesize server=_server, address=_address, totalBytesRead=_bytesRead, totalBytesWritten=_bytesWritten;

+ (void)initialize {
  if (_separatorData == nil) {
    _separatorData = [[NSData alloc] initWithBytes:"\r\n\r\n" length:4];
    DCHECK(_separatorData);
  }
  if (_continueData == nil) {
    CFHTTPMessageRef message = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 100, NULL, kCFHTTPVersion1_1);
#if __has_feature(objc_arc)
    _continueData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(message));
#else
    _continueData = (NSData*)CFHTTPMessageCopySerializedMessage(message);
#endif
    CFRelease(message);
    DCHECK(_continueData);
  }
  if (_dateFormatter == nil) {
    DCHECK([NSThread isMainThread]);  // NSDateFormatter should be initialized on main thread
    _dateFormatter = [[NSDateFormatter alloc] init];
    _dateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
    _dateFormatter.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    _dateFormatter.locale = ARC_AUTORELEASE([[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]);
    DCHECK(_dateFormatter);
  }
  if (_formatterQueue == NULL) {
    _formatterQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    DCHECK(_formatterQueue);
  }
}

- (void)_initializeResponseHeadersWithStatusCode:(NSInteger)statusCode {
  _responseMessage = CFHTTPMessageCreateResponse(kCFAllocatorDefault, statusCode, NULL, kCFHTTPVersion1_1);
  CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Connection"), CFSTR("Close"));
  CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Server"), (ARC_BRIDGE CFStringRef)[[_server class] serverName]);
  dispatch_sync(_formatterQueue, ^{
    NSString* date = [_dateFormatter stringFromDate:[NSDate date]];
    CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Date"), (ARC_BRIDGE CFStringRef)date);
  });
}

- (void)_abortWithStatusCode:(NSUInteger)statusCode {
  DCHECK(_responseMessage == NULL);
  DCHECK((statusCode >= 400) && (statusCode < 600));
  [self _initializeResponseHeadersWithStatusCode:statusCode];
  [self _writeHeadersWithCompletionBlock:^(BOOL success) {
    ;  // Nothing more to do
  }];
  LOG_DEBUG(@"Connection aborted with status code %i on socket %i", (int)statusCode, _socket);
}

// http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
- (void)_processRequest {
  DCHECK(_responseMessage == NULL);
  
  GCDWebServerResponse* response = [self processRequest:_request withBlock:_handler.processBlock];
  if (![response hasBody] || [response open]) {
    _response = ARC_RETAIN(response);
  }
  
  if (_response) {
    [self _initializeResponseHeadersWithStatusCode:_response.statusCode];
    NSUInteger maxAge = _response.cacheControlMaxAge;
    if (maxAge > 0) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Cache-Control"), (ARC_BRIDGE CFStringRef)[NSString stringWithFormat:@"max-age=%i, public", (int)maxAge]);
    } else {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Cache-Control"), CFSTR("no-cache"));
    }
    [_response.additionalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, (ARC_BRIDGE CFStringRef)key, (ARC_BRIDGE CFStringRef)obj);
    }];
    if ([_response hasBody]) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Content-Type"), (ARC_BRIDGE CFStringRef)_response.contentType);
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Content-Length"), (ARC_BRIDGE CFStringRef)[NSString stringWithFormat:@"%i", (int)_response.contentLength]);
    }
    [self _writeHeadersWithCompletionBlock:^(BOOL success) {
      
      if (success) {
        if ([_response hasBody]) {
          [self _writeBodyWithCompletionBlock:^(BOOL success) {
            
            [_response close];  // Can't do anything with result anyway
            
          }];
        }
      } else if ([_response hasBody]) {
        [_response close];  // Can't do anything with result anyway
      }
      
    }];
  } else {
    [self _abortWithStatusCode:500];
  }
  
}

- (void)_readRequestBody:(NSData*)initialData {
  if ([_request open]) {
    NSInteger length = _request.contentLength;
    if (initialData.length) {
      NSInteger result = [_request write:initialData.bytes maxLength:initialData.length];
      if (result == (NSInteger)initialData.length) {
        length -= initialData.length;
        DCHECK(length >= 0);
      } else {
        LOG_ERROR(@"Failed writing request body on socket %i (error %i)", _socket, (int)result);
        length = -1;
      }
    }
    if (length > 0) {
      [self _readBodyWithRemainingLength:length completionBlock:^(BOOL success) {
        
        if (![_request close]) {
          success = NO;
        }
        if (success) {
          [self _processRequest];
        } else {
          [self _abortWithStatusCode:500];
        }
        
      }];
    } else if (length == 0) {
      if ([_request close]) {
        [self _processRequest];
      } else {
        [self _abortWithStatusCode:500];
      }
    } else {
      [_request close];  // Can't do anything with result anyway
      [self _abortWithStatusCode:500];
    }
  } else {
    [self _abortWithStatusCode:500];
  }
}

- (void)_readRequestHeaders {
  _requestMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
  [self _readHeadersWithCompletionBlock:^(NSData* extraData) {
    
    if (extraData) {
      NSString* requestMethod = [ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestMethod(_requestMessage)) uppercaseString];
      DCHECK(requestMethod);
      NSURL* requestURL = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestURL(_requestMessage));
      DCHECK(requestURL);
      NSString* requestPath = GCDWebServerUnescapeURLString(ARC_BRIDGE_RELEASE(CFURLCopyPath((CFURLRef)requestURL)));  // Don't use -[NSURL path] which strips the ending slash
      DCHECK(requestPath);
      NSDictionary* requestQuery = nil;
      NSString* queryString = ARC_BRIDGE_RELEASE(CFURLCopyQueryString((CFURLRef)requestURL, NULL));  // Don't use -[NSURL query] to make sure query is not unescaped;
      if (queryString.length) {
        requestQuery = GCDWebServerParseURLEncodedForm(queryString);
        DCHECK(requestQuery);
      }
      NSDictionary* requestHeaders = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyAllHeaderFields(_requestMessage));
      DCHECK(requestHeaders);
      for (_handler in _server.handlers) {
        _request = ARC_RETAIN(_handler.matchBlock(requestMethod, requestURL, requestHeaders, requestPath, requestQuery));
        if (_request) {
          break;
        }
      }
      if (_request) {
        if (_request.hasBody) {
          if (extraData.length <= _request.contentLength) {
            NSString* expectHeader = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyHeaderFieldValue(_requestMessage, CFSTR("Expect")));
            if (expectHeader) {
              if ([expectHeader caseInsensitiveCompare:@"100-continue"] == NSOrderedSame) {
                [self _writeData:_continueData withCompletionBlock:^(BOOL success) {
                  
                  if (success) {
                    [self _readRequestBody:extraData];
                  }
                  
                }];
              } else {
                LOG_ERROR(@"Unsupported 'Expect' / 'Content-Length' header combination on socket %i", _socket);
                [self _abortWithStatusCode:417];
              }
            } else {
              [self _readRequestBody:extraData];
            }
          } else {
            LOG_ERROR(@"Unexpected 'Content-Length' header value on socket %i", _socket);
            [self _abortWithStatusCode:400];
          }
        } else {
          [self _processRequest];
        }
      } else {
        [self _abortWithStatusCode:405];
      }
    } else {
      [self _abortWithStatusCode:500];
    }
    
  }];
}

- (id)initWithServer:(GCDWebServer*)server address:(NSData*)address socket:(CFSocketNativeHandle)socket {
  if ((self = [super init])) {
    _server = ARC_RETAIN(server);
    _address = ARC_RETAIN(address);
    _socket = socket;
    
    [self open];
  }
  return self;
}

- (void)dealloc {
  [self close];
  
  ARC_RELEASE(_server);
  ARC_RELEASE(_address);
  
  if (_requestMessage) {
    CFRelease(_requestMessage);
  }
  ARC_RELEASE(_request);
  
  if (_responseMessage) {
    CFRelease(_responseMessage);
  }
  ARC_RELEASE(_response);
  
  ARC_DEALLOC(super);
}

@end

@implementation GCDWebServerConnection (Subclassing)

- (void)open {
  LOG_DEBUG(@"Did open connection on socket %i", _socket);
  [self _readRequestHeaders];
}

- (void)didUpdateBytesRead {
  ;
}

- (void)didUpdateBytesWritten {
  ;
}

- (GCDWebServerResponse*)processRequest:(GCDWebServerRequest*)request withBlock:(GCDWebServerProcessBlock)block {
  LOG_DEBUG(@"Connection on socket %i processing %@ request for \"%@\" (%lu bytes body)", _socket, _request.method, _request.path, (unsigned long)_request.contentLength);
  GCDWebServerResponse* response = nil;
  @try {
    response = block(request);
  }
  @catch (NSException* exception) {
    LOG_EXCEPTION(exception);
  }
  return response;
}

- (void)close {
  int result = close(_socket);
  if (result != 0) {
    LOG_ERROR(@"Failed closing socket %i for connection (%i): %s", _socket, errno, strerror(errno));
  }
  LOG_DEBUG(@"Did close connection on socket %i", _socket);
}

@end
