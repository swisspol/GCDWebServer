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

@interface GCDWebServerRequest () {
@private
  NSString* _method;
  NSURL* _url;
  NSDictionary* _headers;
  NSString* _path;
  NSDictionary* _query;
  NSString* _type;
  NSUInteger _length;
  NSRange _range;
  
  BOOL _opened;
  NSMutableArray* _decoders;
  id<GCDWebServerBodyWriter> __unsafe_unretained _writer;
}
@end

@implementation GCDWebServerRequest : NSObject

@synthesize method=_method, URL=_url, headers=_headers, path=_path, query=_query, contentType=_type, contentLength=_length, byteRange=_range;

- (id)initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query {
  if ((self = [super init])) {
    _method = [method copy];
    _url = ARC_RETAIN(url);
    _headers = ARC_RETAIN(headers);
    _path = [path copy];
    _query = ARC_RETAIN(query);
    
    _type = ARC_RETAIN([_headers objectForKey:@"Content-Type"]);
    NSString* lengthHeader = [_headers objectForKey:@"Content-Length"];
    if (_type) {
      NSInteger length = [lengthHeader integerValue];
      if ((lengthHeader == nil) || (length < 0)) {
        DNOT_REACHED();
        ARC_RELEASE(self);
        return nil;
      }
      _length = length;
    } else if (lengthHeader) {
      DNOT_REACHED();
      ARC_RELEASE(self);
      return nil;
    }
    
    _range = NSMakeRange(NSNotFound, 0);
    NSString* rangeHeader = [[_headers objectForKey:@"Range"] lowercaseString];
    if (rangeHeader) {
      if ([rangeHeader hasPrefix:@"bytes="]) {
        NSArray* components = [[rangeHeader substringFromIndex:6] componentsSeparatedByString:@","];
        if (components.count == 1) {
          components = [[components firstObject] componentsSeparatedByString:@"-"];
          if (components.count == 2) {
            NSString* startString = [components objectAtIndex:0];
            NSInteger startValue = [startString integerValue];
            NSString* endString = [components objectAtIndex:1];
            NSInteger endValue = [endString integerValue];
            if (startString.length && (startValue >= 0) && endString.length && (endValue >= startValue)) {  // The second 500 bytes: "500-999"
              _range.location = startValue;
              _range.length = endValue - startValue + 1;
            } else if (startString.length && (startValue >= 0)) {  // The bytes after 9500 bytes: "9500-"
              _range.location = startValue;
              _range.length = NSUIntegerMax;
            } else if (endString.length && (endValue > 0)) {  // The final 500 bytes: "-500"
              _range.location = NSNotFound;
              _range.length = endValue;
            }
          }
        }
      }
      if ((_range.location == NSNotFound) && (_range.length == 0)) {  // Ignore "Range" header if syntactically invalid
        LOG_WARNING(@"Failed to parse 'Range' header \"%@\" for url: %@", rangeHeader, url);
      }
    }
    
    _decoders = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_method);
  ARC_RELEASE(_url);
  ARC_RELEASE(_headers);
  ARC_RELEASE(_path);
  ARC_RELEASE(_query);
  ARC_RELEASE(_type);
  ARC_RELEASE(_decoders);
  
  ARC_DEALLOC(super);
}

- (BOOL)hasBody {
  return _type ? YES : NO;
}

- (BOOL)open:(NSError**)error {
  return YES;
}

- (BOOL)writeData:(NSData*)data error:(NSError**)error {
  [self doesNotRecognizeSelector:_cmd];
  return NO;
}

- (BOOL)close:(NSError**)error {
  return YES;
}

- (BOOL)performOpen:(NSError**)error {
  if (_opened) {
    DNOT_REACHED();
    return NO;
  }
  _opened = YES;
  
  _writer = self;
  // TODO: Inject decoders
  return [_writer open:error];
}

- (BOOL)performWriteData:(NSData*)data error:(NSError**)error {
  return [_writer writeData:data error:error];
}

- (BOOL)performClose:(NSError**)error {
  return [_writer close:error];
}

@end
