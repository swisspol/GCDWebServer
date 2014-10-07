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

#import <zlib.h>

#import "GCDWebServerPrivate.h"

#define kZlibErrorDomain @"ZlibErrorDomain"
#define kGZipInitialBufferSize (256 * 1024)

@interface GCDWebServerBodyEncoder : NSObject <GCDWebServerBodyReader>
- (id)initWithResponse:(GCDWebServerResponse*)response reader:(id<GCDWebServerBodyReader>)reader;
@end

@interface GCDWebServerGZipEncoder : GCDWebServerBodyEncoder
@end

@interface GCDWebServerBodyEncoder () {
@private
  GCDWebServerResponse* __unsafe_unretained _response;
  id<GCDWebServerBodyReader> __unsafe_unretained _reader;
}
@end

@implementation GCDWebServerBodyEncoder

- (id)initWithResponse:(GCDWebServerResponse*)response reader:(id<GCDWebServerBodyReader>)reader {
  if ((self = [super init])) {
    _response = response;
    _reader = reader;
  }
  return self;
}

- (BOOL)open:(NSError**)error {
  return [_reader open:error];
}

- (NSData*)readData:(NSError**)error {
  return [_reader readData:error];
}

- (void)close {
  [_reader close];
}

@end

@interface GCDWebServerGZipEncoder () {
@private
  z_stream _stream;
  BOOL _finished;
}
@end

@implementation GCDWebServerGZipEncoder

- (id)initWithResponse:(GCDWebServerResponse*)response reader:(id<GCDWebServerBodyReader>)reader {
  if ((self = [super initWithResponse:response reader:reader])) {
    response.contentLength = NSUIntegerMax;  // Make sure "Content-Length" header is not set since we don't know it
    [response setValue:@"gzip" forAdditionalHeader:@"Content-Encoding"];
  }
  return self;
}

- (BOOL)open:(NSError**)error {
  int result = deflateInit2(&_stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
  if (result != Z_OK) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:kZlibErrorDomain code:result userInfo:nil];
    }
    return NO;
  }
  if (![super open:error]) {
    deflateEnd(&_stream);
    return NO;
  }
  return YES;
}

- (NSData*)readData:(NSError**)error {
  NSMutableData* encodedData;
  if (_finished) {
    encodedData = [[NSMutableData alloc] init];
  } else {
    encodedData = [[NSMutableData alloc] initWithLength:kGZipInitialBufferSize];
    if (encodedData == nil) {
      DNOT_REACHED();
      return nil;
    }
    NSUInteger length = 0;
    do {
      NSData* data = [super readData:error];
      if (data == nil) {
        return nil;
      }
      _stream.next_in = (Bytef*)data.bytes;
      _stream.avail_in = (uInt)data.length;
      while (1) {
        NSUInteger maxLength = encodedData.length - length;
        _stream.next_out = (Bytef*)((char*)encodedData.mutableBytes + length);
        _stream.avail_out = (uInt)maxLength;
        int result = deflate(&_stream, data.length ? Z_NO_FLUSH : Z_FINISH);
        if (result == Z_STREAM_END) {
          _finished = YES;
        } else if (result != Z_OK) {
          ARC_RELEASE(encodedData);
          if (error != NULL) {
            *error = [NSError errorWithDomain:kZlibErrorDomain code:result userInfo:nil];
          }
          return nil;
        }
        length += maxLength - _stream.avail_out;
        if (_stream.avail_out > 0) {
          break;
        }
        encodedData.length = 2 * encodedData.length;  // zlib has used all the output buffer so resize it and try again in case more data is available
      }
      DCHECK(_stream.avail_in == 0);
    } while (length == 0);  // Make sure we don't return an empty NSData if not in finished state
    encodedData.length = length;
  }
  return ARC_AUTORELEASE(encodedData);
}

- (void)close {
  deflateEnd(&_stream);
  [super close];
}

@end

@interface GCDWebServerResponse () {
@private
  NSString* _type;
  NSUInteger _length;
  NSInteger _status;
  NSUInteger _maxAge;
  NSDate* _lastModified;
  NSString* _eTag;
  NSMutableDictionary* _headers;
  BOOL _chunked;
  BOOL _gzipped;
  
  BOOL _opened;
  NSMutableArray* _encoders;
  id<GCDWebServerBodyReader> __unsafe_unretained _reader;
}
@end

@implementation GCDWebServerResponse

@synthesize contentType=_type, contentLength=_length, statusCode=_status, cacheControlMaxAge=_maxAge, lastModifiedDate=_lastModified, eTag=_eTag,
            gzipContentEncodingEnabled=_gzipped, additionalHeaders=_headers;

+ (instancetype)response {
  return ARC_AUTORELEASE([[[self class] alloc] init]);
}

- (instancetype)init {
  if ((self = [super init])) {
    _type = nil;
    _length = NSUIntegerMax;
    _status = kGCDWebServerHTTPStatusCode_OK;
    _maxAge = 0;
    _headers = [[NSMutableDictionary alloc] init];
    _encoders = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_type);
  ARC_RELEASE(_lastModified);
  ARC_RELEASE(_eTag);
  ARC_RELEASE(_headers);
  ARC_RELEASE(_encoders);
  
  ARC_DEALLOC(super);
}

- (void)setValue:(NSString*)value forAdditionalHeader:(NSString*)header {
  [_headers setValue:value forKey:header];
}

- (BOOL)hasBody {
  return _type ? YES : NO;
}

- (BOOL)usesChunkedTransferEncoding {
  return (_type != nil) && (_length == NSUIntegerMax);
}

- (BOOL)open:(NSError**)error {
  return YES;
}

- (NSData*)readData:(NSError**)error {
  return [NSData data];
}

- (void)close {
  ;
}

- (void)prepareForReading {
  _reader = self;
  if (_gzipped) {
    GCDWebServerGZipEncoder* encoder = [[GCDWebServerGZipEncoder alloc] initWithResponse:self reader:_reader];
    [_encoders addObject:encoder];
    ARC_RELEASE(encoder);
    _reader = encoder;
  }
}

- (BOOL)performOpen:(NSError**)error {
  DCHECK(_type);
  DCHECK(_reader);
  if (_opened) {
    DNOT_REACHED();
    return NO;
  }
  _opened = YES;
  return [_reader open:error];
}

- (NSData*)performReadData:(NSError**)error {
  DCHECK(_opened);
  return [_reader readData:error];
}

- (void)performClose {
  DCHECK(_opened);
  [_reader close];
}

- (NSString*)description {
  NSMutableString* description = [NSMutableString stringWithFormat:@"Status Code = %i", (int)_status];
  if (_type) {
    [description appendFormat:@"\nContent Type = %@", _type];
  }
  if (_length != NSUIntegerMax) {
    [description appendFormat:@"\nContent Length = %lu", (unsigned long)_length];
  }
  [description appendFormat:@"\nCache Control Max Age = %lu", (unsigned long)_maxAge];
  if (_lastModified) {
    [description appendFormat:@"\nLast Modified Date = %@", _lastModified];
  }
  if (_eTag) {
    [description appendFormat:@"\nETag = %@", _eTag];
  }
  if (_headers.count) {
    [description appendString:@"\n"];
    for (NSString* header in [[_headers allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      [description appendFormat:@"\n%@: %@", header, [_headers objectForKey:header]];
    }
  }
  return description;
}

@end

@implementation GCDWebServerResponse (Extensions)

+ (instancetype)responseWithStatusCode:(NSInteger)statusCode {
  return ARC_AUTORELEASE([[self alloc] initWithStatusCode:statusCode]);
}

+ (instancetype)responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  return ARC_AUTORELEASE([[self alloc] initWithRedirect:location permanent:permanent]);
}

- (instancetype)initWithStatusCode:(NSInteger)statusCode {
  if ((self = [self init])) {
    self.statusCode = statusCode;
  }
  return self;
}

- (instancetype)initWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  if ((self = [self init])) {
    self.statusCode = permanent ? kGCDWebServerHTTPStatusCode_MovedPermanently : kGCDWebServerHTTPStatusCode_TemporaryRedirect;
    [self setValue:[location absoluteString] forAdditionalHeader:@"Location"];
  }
  return self;
}

@end
