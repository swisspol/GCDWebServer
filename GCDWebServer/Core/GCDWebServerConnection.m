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
#import <netdb.h>
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
#import <libkern/OSAtomic.h>
#endif

#import "GCDWebServerPrivate.h"

#define kHeadersReadBuffer 1024

typedef void (^ReadBufferCompletionBlock)(dispatch_data_t buffer);
typedef void (^ReadDataCompletionBlock)(NSData* data);
typedef void (^ReadHeadersCompletionBlock)(NSData* extraData);
typedef void (^ReadBodyCompletionBlock)(BOOL success);

typedef void (^WriteBufferCompletionBlock)(BOOL success);
typedef void (^WriteDataCompletionBlock)(BOOL success);
typedef void (^WriteHeadersCompletionBlock)(BOOL success);
typedef void (^WriteBodyCompletionBlock)(BOOL success);

static NSData* _CRLFData = nil;
static NSData* _CRLFCRLFData = nil;
static NSData* _continueData = nil;
static NSData* _lastChunkData = nil;
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
static int32_t _connectionCounter = 0;
#endif

@interface GCDWebServerConnection () {
@private
  GCDWebServer* _server;
  NSData* _localAddress;
  NSData* _remoteAddress;
  CFSocketNativeHandle _socket;
  NSUInteger _bytesRead;
  NSUInteger _bytesWritten;
  BOOL _virtualHEAD;
  
  CFHTTPMessageRef _requestMessage;
  GCDWebServerRequest* _request;
  GCDWebServerHandler* _handler;
  CFHTTPMessageRef _responseMessage;
  GCDWebServerResponse* _response;
  NSInteger _statusCode;
  
  BOOL _opened;
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
  NSUInteger _connectionIndex;
  NSString* _requestPath;
  int _requestFD;
  NSString* _responsePath;
  int _responseFD;
#endif
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
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
          if (_requestFD > 0) {
            bool success = dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t chunkOffset, const void* chunkBytes, size_t chunkSize) {
              return (write(_requestFD, chunkBytes, chunkSize) == (ssize_t)chunkSize);
            });
            if (!success) {
              LOG_ERROR(@"Failed recording request data: %s (%i)", strerror(errno), errno);
              close(_requestFD);
              _requestFD = 0;
            }
          }
#endif
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
      dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t chunkOffset, const void* chunkBytes, size_t chunkSize) {
        [data appendBytes:chunkBytes length:chunkSize];
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
      dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t chunkOffset, const void* chunkBytes, size_t chunkSize) {
        [data appendBytes:chunkBytes length:chunkSize];
        return true;
      });
      NSRange range = [data rangeOfData:_CRLFCRLFData options:0 range:NSMakeRange(0, data.length)];
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
  DCHECK([_request hasBody] && ![_request usesChunkedTransferEncoding]);
  [self _readBufferWithLength:length completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      if (dispatch_data_get_size(buffer) <= length) {
        bool success = dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t chunkOffset, const void* chunkBytes, size_t chunkSize) {
          NSData* data = [NSData dataWithBytesNoCopy:(void*)chunkBytes length:chunkSize freeWhenDone:NO];
          NSError* error = nil;
          if (![_request performWriteData:data error:&error]) {
            LOG_ERROR(@"Failed writing request body on socket %i: %@", _socket, error);
            return false;
          }
          return true;
        });
        if (success) {
          NSUInteger remainingLength = length - dispatch_data_get_size(buffer);
          if (remainingLength) {
            [self _readBodyWithRemainingLength:remainingLength completionBlock:block];
          } else {
            block(YES);
          }
        } else {
          block(NO);
        }
      } else {
        LOG_ERROR(@"Unexpected extra content reading request body on socket %i", _socket);
        block(NO);
        DNOT_REACHED();
      }
    } else {
      block(NO);
    }
    
  }];
}

static inline NSUInteger _ScanHexNumber(const void* bytes, NSUInteger size) {
  char buffer[size + 1];
  bcopy(bytes, buffer, size);
  buffer[size] = 0;
  char* end = NULL;
  long result = strtol(buffer, &end, 16);
  return ((end != NULL) && (*end == 0) && (result >= 0) ? result : NSNotFound);
}

- (void)_readNextBodyChunk:(NSMutableData*)chunkData completionBlock:(ReadBodyCompletionBlock)block {
  DCHECK([_request hasBody] && [_request usesChunkedTransferEncoding]);
  
  while (1) {
    NSRange range = [chunkData rangeOfData:_CRLFData options:0 range:NSMakeRange(0, chunkData.length)];
    if (range.location == NSNotFound) {
      break;
    }
    NSRange extensionRange = [chunkData rangeOfData:[NSData dataWithBytes:";" length:1] options:0 range:NSMakeRange(0, range.location)];  // Ignore chunk extensions
    NSUInteger length = _ScanHexNumber((char*)chunkData.bytes, extensionRange.location != NSNotFound ? extensionRange.location : range.location);
    if (length != NSNotFound) {
      if (length) {
        if (chunkData.length < range.location + range.length + length + 2) {
          break;
        }
        const char* ptr = (char*)chunkData.bytes + range.location + range.length + length;
        if ((*ptr == '\r') && (*(ptr + 1) == '\n')) {
          NSError* error = nil;
          if ([_request performWriteData:[chunkData subdataWithRange:NSMakeRange(range.location + range.length, length)] error:&error]) {
            [chunkData replaceBytesInRange:NSMakeRange(0, range.location + range.length + length + 2) withBytes:NULL length:0];
          } else {
            LOG_ERROR(@"Failed writing request body on socket %i: %@", _socket, error);
            block(NO);
            return;
          }
        } else {
          LOG_ERROR(@"Missing terminating CRLF sequence for chunk reading request body on socket %i", _socket);
          block(NO);
          return;
        }
      } else {
        NSRange trailerRange = [chunkData rangeOfData:_CRLFCRLFData options:0 range:NSMakeRange(range.location, chunkData.length - range.location)];  // Ignore trailers
        if (trailerRange.location != NSNotFound) {
          block(YES);
          return;
        }
      }
    } else {
      LOG_ERROR(@"Invalid chunk length reading request body on socket %i", _socket);
      block(NO);
      return;
    }
  }
  
  [self _readBufferWithLength:SIZE_T_MAX completionBlock:^(dispatch_data_t buffer) {
    
    if (buffer) {
      dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t chunkOffset, const void* chunkBytes, size_t chunkSize) {
        [chunkData appendBytes:chunkBytes length:chunkSize];
        return true;
      });
      [self _readNextBodyChunk:chunkData completionBlock:block];
    } else {
      block(NO);
    }
    
  }];
}

@end

@implementation GCDWebServerConnection (Write)

- (void)_writeBuffer:(dispatch_data_t)buffer withCompletionBlock:(WriteBufferCompletionBlock)block {
  size_t size = dispatch_data_get_size(buffer);
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
  ARC_DISPATCH_RETAIN(buffer);
#endif
  dispatch_write(_socket, buffer, kGCDWebServerGCDQueue, ^(dispatch_data_t data, int error) {
    
    @autoreleasepool {
      if (error == 0) {
        DCHECK(data == NULL);
        LOG_DEBUG(@"Connection sent %zu bytes on socket %i", size, _socket);
        _bytesWritten += size;
        [self didUpdateBytesWritten];
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
        if (_responseFD > 0) {
          bool success = dispatch_data_apply(buffer, ^bool(dispatch_data_t region, size_t chunkOffset, const void* chunkBytes, size_t chunkSize) {
            return (write(_responseFD, chunkBytes, chunkSize) == (ssize_t)chunkSize);
          });
          if (!success) {
            LOG_ERROR(@"Failed recording response data: %s (%i)", strerror(errno), errno);
            close(_responseFD);
            _responseFD = 0;
          }
        }
#endif
        block(YES);
      } else {
        LOG_ERROR(@"Error while writing to socket %i: %s (%i)", _socket, strerror(error), error);
        block(NO);
      }
    }
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
    ARC_DISPATCH_RELEASE(buffer);
#endif
    
  });
}

- (void)_writeData:(NSData*)data withCompletionBlock:(WriteDataCompletionBlock)block {
#if !__has_feature(objc_arc)
  [data retain];
#endif
  dispatch_data_t buffer = dispatch_data_create(data.bytes, data.length, kGCDWebServerGCDQueue, ^{
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
  CFDataRef data = CFHTTPMessageCopySerializedMessage(_responseMessage);
  [self _writeData:(ARC_BRIDGE NSData*)data withCompletionBlock:block];
  CFRelease(data);
}

- (void)_writeBodyWithCompletionBlock:(WriteBodyCompletionBlock)block {
  DCHECK([_response hasBody]);
  NSError* error = nil;
  NSData* data = [_response performReadData:&error];
  if (data) {
    if (data.length) {
      if (_response.usesChunkedTransferEncoding) {
        const char* hexString = [[NSString stringWithFormat:@"%lx", (unsigned long)data.length] UTF8String];
        size_t hexLength = strlen(hexString);
        NSData* chunk = [NSMutableData dataWithLength:(hexLength + 2 + data.length + 2)];
        if (chunk == nil) {
          LOG_ERROR(@"Failed allocating memory for response body chunk for socket %i: %@", _socket, error);
          block(NO);
          return;
        }
        char* ptr = (char*)[(NSMutableData*)chunk mutableBytes];
        bcopy(hexString, ptr, hexLength);
        ptr += hexLength;
        *ptr++ = '\r';
        *ptr++ = '\n';
        bcopy(data.bytes, ptr, data.length);
        ptr += data.length;
        *ptr++ = '\r';
        *ptr = '\n';
        data = chunk;
      }
      [self _writeData:data withCompletionBlock:^(BOOL success) {
        
        if (success) {
          [self _writeBodyWithCompletionBlock:block];
        } else {
          block(NO);
        }
        
      }];
    } else {
      if (_response.usesChunkedTransferEncoding) {
        [self _writeData:_lastChunkData withCompletionBlock:^(BOOL success) {
          
          block(success);
          
        }];
      } else {
        block(YES);
      }
    }
  } else {
    LOG_ERROR(@"Failed reading response body for socket %i: %@", _socket, error);
    block(NO);
  }
}

@end

@implementation GCDWebServerConnection

@synthesize server=_server, localAddressData=_localAddress, remoteAddressData=_remoteAddress, totalBytesRead=_bytesRead, totalBytesWritten=_bytesWritten;

+ (void)initialize {
  if (_CRLFData == nil) {
    _CRLFData = [[NSData alloc] initWithBytes:"\r\n" length:2];
    DCHECK(_CRLFData);
  }
  if (_CRLFCRLFData == nil) {
    _CRLFCRLFData = [[NSData alloc] initWithBytes:"\r\n\r\n" length:4];
    DCHECK(_CRLFCRLFData);
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
  if (_lastChunkData == nil) {
    _lastChunkData = [[NSData alloc] initWithBytes:"0\r\n\r\n" length:5];
  }
}

- (void)_initializeResponseHeadersWithStatusCode:(NSInteger)statusCode {
  _statusCode = statusCode;
  _responseMessage = CFHTTPMessageCreateResponse(kCFAllocatorDefault, statusCode, NULL, kCFHTTPVersion1_1);
  CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Connection"), CFSTR("Close"));
  CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Server"), (ARC_BRIDGE CFStringRef)[[_server class] serverName]);
  CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Date"), (ARC_BRIDGE CFStringRef)GCDWebServerFormatRFC822([NSDate date]));
}

// http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
- (void)_processRequest {
  DCHECK(_responseMessage == NULL);
  BOOL hasBody = NO;
  
  GCDWebServerResponse* response = [self processRequest:_request withBlock:_handler.processBlock];
  if (response) {
    response = [self replaceResponse:response forRequest:_request];
    if (response) {
      if ([response hasBody]) {
        [response prepareForReading];
        hasBody = !_virtualHEAD;
      }
      NSError* error = nil;
      if (hasBody && ![response performOpen:&error]) {
        LOG_ERROR(@"Failed opening response body for socket %i: %@", _socket, error);
      } else {
        _response = ARC_RETAIN(response);
      }
    }
  }
  
  if (_response) {
    [self _initializeResponseHeadersWithStatusCode:_response.statusCode];
    if (_response.lastModifiedDate) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Last-Modified"), (ARC_BRIDGE CFStringRef)GCDWebServerFormatRFC822(_response.lastModifiedDate));
    }
    if (_response.eTag) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("ETag"), (ARC_BRIDGE CFStringRef)_response.eTag);
    }
    if ((_response.statusCode >= 200) && (_response.statusCode < 300)) {
      if (_response.cacheControlMaxAge > 0) {
        CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Cache-Control"), (ARC_BRIDGE CFStringRef)[NSString stringWithFormat:@"max-age=%i, public", (int)_response.cacheControlMaxAge]);
      } else {
        CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Cache-Control"), CFSTR("no-cache"));
      }
    }
    if (_response.contentType != nil) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Content-Type"), (ARC_BRIDGE CFStringRef)GCDWebServerNormalizeHeaderValue(_response.contentType));
    }
    if (_response.contentLength != NSNotFound) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Content-Length"), (ARC_BRIDGE CFStringRef)[NSString stringWithFormat:@"%lu", (unsigned long)_response.contentLength]);
    }
    if (_response.usesChunkedTransferEncoding) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, CFSTR("Transfer-Encoding"), CFSTR("chunked"));
    }
    [_response.additionalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL* stop) {
      CFHTTPMessageSetHeaderFieldValue(_responseMessage, (ARC_BRIDGE CFStringRef)key, (ARC_BRIDGE CFStringRef)obj);
    }];
    [self _writeHeadersWithCompletionBlock:^(BOOL success) {
      
      if (success) {
        if (hasBody) {
          [self _writeBodyWithCompletionBlock:^(BOOL successInner) {
            
            [_response performClose];  // TODO: There's nothing we can do on failure as headers have already been sent
            
          }];
        }
      } else if (hasBody) {
        [_response performClose];
      }
      
    }];
  } else {
    [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
  }
  
}

- (void)_readBodyWithLength:(NSUInteger)length initialData:(NSData*)initialData {
  NSError* error = nil;
  if (![_request performOpen:&error]) {
    LOG_ERROR(@"Failed opening request body for socket %i: %@", _socket, error);
    [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
    return;
  }
  
  if (initialData.length) {
    if (![_request performWriteData:initialData error:&error]) {
      LOG_ERROR(@"Failed writing request body on socket %i: %@", _socket, error);
      if (![_request performClose:&error]) {
        LOG_ERROR(@"Failed closing request body for socket %i: %@", _socket, error);
      }
      [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
      return;
    }
    length -= initialData.length;
  }
  
  if (length) {
    [self _readBodyWithRemainingLength:length completionBlock:^(BOOL success) {
      
      NSError* localError = nil;
      if ([_request performClose:&localError]) {
        [self _processRequest];
      } else {
        LOG_ERROR(@"Failed closing request body for socket %i: %@", _socket, error);
        [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
      }
      
    }];
  } else {
    if ([_request performClose:&error]) {
      [self _processRequest];
    } else {
      LOG_ERROR(@"Failed closing request body for socket %i: %@", _socket, error);
      [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
    }
  }
}

- (void)_readChunkedBodyWithInitialData:(NSData*)initialData {
  NSError* error = nil;
  if (![_request performOpen:&error]) {
    LOG_ERROR(@"Failed opening request body for socket %i: %@", _socket, error);
    [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
    return;
  }
  
  NSMutableData* chunkData = [[NSMutableData alloc] initWithData:initialData];
  [self _readNextBodyChunk:chunkData completionBlock:^(BOOL success) {
  
    NSError* localError = nil;
    if ([_request performClose:&localError]) {
      [self _processRequest];
    } else {
      LOG_ERROR(@"Failed closing request body for socket %i: %@", _socket, error);
      [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
    }
    
  }];
  ARC_RELEASE(chunkData);
}

- (void)_readRequestHeaders {
  _requestMessage = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
  [self _readHeadersWithCompletionBlock:^(NSData* extraData) {
    
    if (extraData) {
      NSString* requestMethod = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestMethod(_requestMessage));  // Method verbs are case-sensitive and uppercase
      if ([[_server class] shouldAutomaticallyMapHEADToGET] && [requestMethod isEqualToString:@"HEAD"]) {
        requestMethod = @"GET";
        _virtualHEAD = YES;
      }
      NSURL* requestURL = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyRequestURL(_requestMessage));
      NSString* requestPath = requestURL ? GCDWebServerUnescapeURLString(ARC_BRIDGE_RELEASE(CFURLCopyPath((CFURLRef)requestURL))) : nil;  // Don't use -[NSURL path] which strips the ending slash
      NSString* queryString = requestURL ? ARC_BRIDGE_RELEASE(CFURLCopyQueryString((CFURLRef)requestURL, NULL)) : nil;  // Don't use -[NSURL query] to make sure query is not unescaped;
      NSDictionary* requestQuery = queryString ? GCDWebServerParseURLEncodedForm(queryString) : @{};
      NSDictionary* requestHeaders = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyAllHeaderFields(_requestMessage));  // Header names are case-insensitive but CFHTTPMessageCopyAllHeaderFields() will standardize the common ones
      if (requestMethod && requestURL && requestHeaders && requestPath && requestQuery) {
        for (_handler in _server.handlers) {
          _request = ARC_RETAIN(_handler.matchBlock(requestMethod, requestURL, requestHeaders, requestPath, requestQuery));
          if (_request) {
            break;
          }
        }
        if (_request) {
          if ([_request hasBody]) {
            [_request prepareForWriting];
            if (_request.usesChunkedTransferEncoding || (extraData.length <= _request.contentLength)) {
              NSString* expectHeader = ARC_BRIDGE_RELEASE(CFHTTPMessageCopyHeaderFieldValue(_requestMessage, CFSTR("Expect")));
              if (expectHeader) {
                if ([expectHeader caseInsensitiveCompare:@"100-continue"] == NSOrderedSame) {
                  [self _writeData:_continueData withCompletionBlock:^(BOOL success) {
                    
                    if (success) {
                      if (_request.usesChunkedTransferEncoding) {
                        [self _readChunkedBodyWithInitialData:extraData];
                      } else {
                        [self _readBodyWithLength:_request.contentLength initialData:extraData];
                      }
                    }
                    
                  }];
                } else {
                  LOG_ERROR(@"Unsupported 'Expect' / 'Content-Length' header combination on socket %i", _socket);
                  [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_ExpectationFailed];
                }
              } else {
                if (_request.usesChunkedTransferEncoding) {
                  [self _readChunkedBodyWithInitialData:extraData];
                } else {
                  [self _readBodyWithLength:_request.contentLength initialData:extraData];
                }
              }
            } else {
              LOG_ERROR(@"Unexpected 'Content-Length' header value on socket %i", _socket);
              [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_BadRequest];
            }
          } else {
            [self _processRequest];
          }
        } else {
          _request = [[GCDWebServerRequest alloc] initWithMethod:requestMethod url:requestURL headers:requestHeaders path:requestPath query:requestQuery];
          DCHECK(_request);
          [self abortRequest:_request withStatusCode:kGCDWebServerHTTPStatusCode_MethodNotAllowed];
        }
      } else {
        [self abortRequest:nil withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
        DNOT_REACHED();
      }
    } else {
      [self abortRequest:nil withStatusCode:kGCDWebServerHTTPStatusCode_InternalServerError];
    }
    
  }];
}

- (id)initWithServer:(GCDWebServer*)server localAddress:(NSData*)localAddress remoteAddress:(NSData*)remoteAddress socket:(CFSocketNativeHandle)socket {
  if ((self = [super init])) {
    _server = ARC_RETAIN(server);
    _localAddress = ARC_RETAIN(localAddress);
    _remoteAddress = ARC_RETAIN(remoteAddress);
    _socket = socket;
    
    if (![self open]) {
      close(_socket);
      ARC_RELEASE(self);
      return nil;
    }
    _opened = YES;
    
    LOG_DEBUG(@"Did open connection on socket %i", _socket);
    [self _readRequestHeaders];
  }
  return self;
}

static NSString* _StringFromAddressData(NSData* data) {
  NSString* string = nil;
  const struct sockaddr* addr = data.bytes;
  char hostBuffer[NI_MAXHOST];
  char serviceBuffer[NI_MAXSERV];
  if (getnameinfo(addr, addr->sa_len, hostBuffer, sizeof(hostBuffer), serviceBuffer, sizeof(serviceBuffer), NI_NUMERICHOST | NI_NUMERICSERV | NI_NOFQDN) >= 0) {
    string = [NSString stringWithFormat:@"%s:%s", hostBuffer, serviceBuffer];
  } else {
    DNOT_REACHED();
  }
  return string;
}

- (NSString*)localAddressString {
  return _StringFromAddressData(_localAddress);
}

- (NSString*)remoteAddressString {
  return _StringFromAddressData(_remoteAddress);
}

- (void)dealloc {
  if (_opened) {
    [self close];
  }
  
  int result = close(_socket);
  if (result != 0) {
    LOG_ERROR(@"Failed closing socket %i for connection (%i): %s", _socket, errno, strerror(errno));
  } else {
    LOG_DEBUG(@"Did close connection on socket %i", _socket);
  }
  
  ARC_RELEASE(_server);
  ARC_RELEASE(_localAddress);
  ARC_RELEASE(_remoteAddress);
  
  if (_requestMessage) {
    CFRelease(_requestMessage);
  }
  ARC_RELEASE(_request);
  
  if (_responseMessage) {
    CFRelease(_responseMessage);
  }
  ARC_RELEASE(_response);
  
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
  ARC_RELEASE(_requestPath);
  ARC_RELEASE(_responsePath);
#endif
  
  ARC_DEALLOC(super);
}

@end

@implementation GCDWebServerConnection (Subclassing)

- (BOOL)open {
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
  if (_server.recordingEnabled) {
    _connectionIndex = OSAtomicIncrement32(&_connectionCounter);
    
    _requestPath = ARC_RETAIN([NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]]);
    _requestFD = open([_requestPath fileSystemRepresentation], O_CREAT | O_TRUNC | O_WRONLY);
    DCHECK(_requestFD > 0);
    
    _responsePath = ARC_RETAIN([NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]]);
    _responseFD = open([_responsePath fileSystemRepresentation], O_CREAT | O_TRUNC | O_WRONLY);
    DCHECK(_responseFD > 0);
  }
#endif
  
  return YES;
}

- (void)didUpdateBytesRead {
  ;
}

- (void)didUpdateBytesWritten {
  ;
}

- (GCDWebServerResponse*)processRequest:(GCDWebServerRequest*)request withBlock:(GCDWebServerProcessBlock)block {
  LOG_DEBUG(@"Connection on socket %i processing request \"%@ %@\" with %lu bytes body", _socket, _virtualHEAD ? @"HEAD" : _request.method, _request.path, (unsigned long)_bytesRead);
  GCDWebServerResponse* response = nil;
  @try {
    response = block(request);
  }
  @catch (NSException* exception) {
    LOG_EXCEPTION(exception);
  }
  return response;
}

// http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.26
static inline BOOL _CompareResources(NSString* responseETag, NSString* requestETag, NSDate* responseLastModified, NSDate* requestLastModified) {
  if ([requestETag isEqualToString:@"*"] && (!responseLastModified || !requestLastModified || ([responseLastModified compare:requestLastModified] != NSOrderedDescending))) {
    return YES;
  } else {
    if ([responseETag isEqualToString:requestETag]) {
      return YES;
    }
    if (responseLastModified && requestLastModified && ([responseLastModified compare:requestLastModified] != NSOrderedDescending)) {
      return YES;
    }
  }
  return NO;
}

- (GCDWebServerResponse*)replaceResponse:(GCDWebServerResponse*)response forRequest:(GCDWebServerRequest*)request {
  if ((response.statusCode >= 200) && (response.statusCode < 300) && _CompareResources(response.eTag, request.ifNoneMatch, response.lastModifiedDate, request.ifModifiedSince)) {
    NSInteger code = [request.method isEqualToString:@"HEAD"] || [request.method isEqualToString:@"GET"] ? kGCDWebServerHTTPStatusCode_NotModified : kGCDWebServerHTTPStatusCode_PreconditionFailed;
    GCDWebServerResponse* newResponse = [GCDWebServerResponse responseWithStatusCode:code];
    newResponse.cacheControlMaxAge = response.cacheControlMaxAge;
    newResponse.lastModifiedDate = response.lastModifiedDate;
    newResponse.eTag = response.eTag;
    DCHECK(newResponse);
    return newResponse;
  }
  return response;
}

- (void)abortRequest:(GCDWebServerRequest*)request withStatusCode:(NSInteger)statusCode {
  DCHECK(_responseMessage == NULL);
  DCHECK((statusCode >= 400) && (statusCode < 600));
  [self _initializeResponseHeadersWithStatusCode:statusCode];
  [self _writeHeadersWithCompletionBlock:^(BOOL success) {
    ;  // Nothing more to do
  }];
  LOG_DEBUG(@"Connection aborted with status code %i on socket %i", (int)statusCode, _socket);
}

- (void)close {
#ifdef __GCDWEBSERVER_ENABLE_TESTING__
  if (_requestPath) {
    BOOL success = NO;
    NSError* error = nil;
    if (_requestFD > 0) {
      close(_requestFD);
      NSString* name = [NSString stringWithFormat:@"%03lu-%@.request", (unsigned long)_connectionIndex, _virtualHEAD ? @"HEAD" : _request.method];
      success = [[NSFileManager defaultManager] moveItemAtPath:_requestPath toPath:[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:name] error:&error];
    }
    if (!success) {
      LOG_ERROR(@"Failed saving recorded request: %@", error);
      DNOT_REACHED();
    }
    unlink([_requestPath fileSystemRepresentation]);
  }
  
  if (_responsePath) {
    BOOL success = NO;
    NSError* error = nil;
    if (_responseFD > 0) {
      close(_responseFD);
      NSString* name = [NSString stringWithFormat:@"%03lu-%i.response", (unsigned long)_connectionIndex, (int)_statusCode];
      success = [[NSFileManager defaultManager] moveItemAtPath:_responsePath toPath:[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:name] error:&error];
    }
    if (!success) {
      LOG_ERROR(@"Failed saving recorded response: %@", error);
      DNOT_REACHED();
    }
    unlink([_responsePath fileSystemRepresentation]);
  }
#endif
  if (_request) {
    LOG_VERBOSE(@"[%@] %@ %i \"%@ %@\" (%lu | %lu)", self.localAddressString, self.remoteAddressString, (int)_statusCode, _virtualHEAD ? @"HEAD" : _request.method, _request.path, (unsigned long)_bytesRead, (unsigned long)_bytesWritten);
  } else {
    LOG_VERBOSE(@"[%@] %@ %i \"(invalid request)\" (%lu | %lu)", self.localAddressString, self.remoteAddressString, (int)_statusCode, (unsigned long)_bytesRead, (unsigned long)_bytesWritten);
  }
}

@end
