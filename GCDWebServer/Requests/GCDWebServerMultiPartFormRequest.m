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

#define kMultiPartBufferSize (256 * 1024)

enum {
  kParserState_Undefined = 0,
  kParserState_Start,
  kParserState_Headers,
  kParserState_Content,
  kParserState_End
};

static NSData* _newlineData = nil;
static NSData* _newlinesData = nil;
static NSData* _dashNewlineData = nil;

@interface GCDWebServerMultiPart () {
@private
  NSString* _contentType;
  NSString* _mimeType;
}
@end

@implementation GCDWebServerMultiPart

@synthesize contentType=_contentType, mimeType=_mimeType;

- (id)initWithContentType:(NSString*)contentType {
  if ((self = [super init])) {
    _contentType = [contentType copy];
    _mimeType = ARC_RETAIN(GCDWebServerTruncateHeaderValue(_contentType));
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_contentType);
  ARC_RELEASE(_mimeType);
  
  ARC_DEALLOC(super);
}

@end

@interface GCDWebServerMultiPartArgument () {
@private
  NSData* _data;
  NSString* _string;
}
@end

@implementation GCDWebServerMultiPartArgument

@synthesize data=_data, string=_string;

- (id)initWithContentType:(NSString*)contentType data:(NSData*)data {
  if ((self = [super initWithContentType:contentType])) {
    _data = ARC_RETAIN(data);
    
    if ([self.contentType hasPrefix:@"text/"]) {
      NSString* charset = GCDWebServerExtractHeaderValueParameter(self.contentType, @"charset");
      _string = [[NSString alloc] initWithData:_data encoding:GCDWebServerStringEncodingFromCharset(charset)];
    }
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_data);
  ARC_RELEASE(_string);
  
  ARC_DEALLOC(super);
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@ | '%@' | %lu bytes>", [self class], self.mimeType, (unsigned long)_data.length];
}

@end

@interface GCDWebServerMultiPartFile () {
@private
  NSString* _fileName;
  NSString* _temporaryPath;
}
@end

@implementation GCDWebServerMultiPartFile

@synthesize fileName=_fileName, temporaryPath=_temporaryPath;

- (id)initWithContentType:(NSString*)contentType fileName:(NSString*)fileName temporaryPath:(NSString*)temporaryPath {
  if ((self = [super initWithContentType:contentType])) {
    _fileName = [fileName copy];
    _temporaryPath = [temporaryPath copy];
  }
  return self;
}

- (void)dealloc {
  unlink([_temporaryPath fileSystemRepresentation]);
  
  ARC_RELEASE(_fileName);
  ARC_RELEASE(_temporaryPath);
  
  ARC_DEALLOC(super);
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@ | '%@' | '%@>'", [self class], self.mimeType, _fileName];
}

@end

@interface GCDWebServerMultiPartFormRequest () {
@private
  NSData* _boundary;
  
  NSUInteger _parserState;
  NSMutableData* _parserData;
  NSString* _controlName;
  NSString* _fileName;
  NSString* _contentType;
  NSString* _tmpPath;
  int _tmpFile;
  
  NSMutableDictionary* _arguments;
  NSMutableDictionary* _files;
}
@end

@implementation GCDWebServerMultiPartFormRequest

@synthesize arguments=_arguments, files=_files;

+ (void)initialize {
  if (_newlineData == nil) {
    _newlineData = [[NSData alloc] initWithBytes:"\r\n" length:2];
    DCHECK(_newlineData);
  }
  if (_newlinesData == nil) {
    _newlinesData = [[NSData alloc] initWithBytes:"\r\n\r\n" length:4];
    DCHECK(_newlinesData);
  }
  if (_dashNewlineData == nil) {
    _dashNewlineData = [[NSData alloc] initWithBytes:"--\r\n" length:4];
    DCHECK(_dashNewlineData);
  }
}

+ (NSString*)mimeType {
  return @"multipart/form-data";
}

- (instancetype)initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query {
  if ((self = [super initWithMethod:method url:url headers:headers path:path query:query])) {
    NSString* boundary = GCDWebServerExtractHeaderValueParameter(self.contentType, @"boundary");
    if (boundary) {
      NSData* data = [[NSString stringWithFormat:@"--%@", boundary] dataUsingEncoding:NSASCIIStringEncoding];
      _boundary = ARC_RETAIN(data);
    }
    if (_boundary == nil) {
      DNOT_REACHED();
      ARC_RELEASE(self);
      return nil;
    }
    
    _arguments = [[NSMutableDictionary alloc] init];
    _files = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_arguments);
  ARC_RELEASE(_files);
  ARC_RELEASE(_boundary);
  
  ARC_DEALLOC(super);
}

- (BOOL)open:(NSError**)error {
  _parserData = [[NSMutableData alloc] initWithCapacity:kMultiPartBufferSize];
  _parserState = kParserState_Start;
  return YES;
}

// http://www.w3.org/TR/html401/interact/forms.html#h-17.13.4.2
- (BOOL)_parseData {
  BOOL success = YES;
  
  if (_parserState == kParserState_Headers) {
    NSRange range = [_parserData rangeOfData:_newlinesData options:0 range:NSMakeRange(0, _parserData.length)];
    if (range.location != NSNotFound) {
      
      ARC_RELEASE(_controlName);
      _controlName = nil;
      ARC_RELEASE(_fileName);
      _fileName = nil;
      ARC_RELEASE(_contentType);
      _contentType = nil;
      ARC_RELEASE(_tmpPath);
      _tmpPath = nil;
      NSString* headers = [[NSString alloc] initWithData:[_parserData subdataWithRange:NSMakeRange(0, range.location)] encoding:NSUTF8StringEncoding];
      if (headers) {
        for (NSString* header in [headers componentsSeparatedByString:@"\r\n"]) {
          NSRange subRange = [header rangeOfString:@":"];
          if (subRange.location != NSNotFound) {
            NSString* name = [header substringToIndex:subRange.location];
            NSString* value = [[header substringFromIndex:(subRange.location + subRange.length)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([name caseInsensitiveCompare:@"Content-Type"] == NSOrderedSame) {
              _contentType = ARC_RETAIN(GCDWebServerNormalizeHeaderValue(value));
            } else if ([name caseInsensitiveCompare:@"Content-Disposition"] == NSOrderedSame) {
              NSString* contentDisposition = GCDWebServerNormalizeHeaderValue(value);
              if ([GCDWebServerTruncateHeaderValue(contentDisposition) isEqualToString:@"form-data"]) {
                _controlName = ARC_RETAIN(GCDWebServerExtractHeaderValueParameter(contentDisposition, @"name"));
                _fileName = ARC_RETAIN(GCDWebServerExtractHeaderValueParameter(contentDisposition, @"filename"));
              }
            }
          } else {
            DNOT_REACHED();
          }
        }
        if (_contentType == nil) {
          _contentType = @"text/plain";
        }
        ARC_RELEASE(headers);
      } else {
        LOG_ERROR(@"Failed decoding headers in part of 'multipart/form-data'");
        DNOT_REACHED();
      }
      if (_controlName) {
        if (_fileName) {
          NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
          _tmpFile = open([path fileSystemRepresentation], O_CREAT | O_TRUNC | O_WRONLY, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
          if (_tmpFile > 0) {
            _tmpPath = [path copy];
          } else {
            DNOT_REACHED();
            success = NO;
          }
        }
      } else {
        DNOT_REACHED();
        success = NO;
      }
      
      [_parserData replaceBytesInRange:NSMakeRange(0, range.location + range.length) withBytes:NULL length:0];
      _parserState = kParserState_Content;
    }
  }
  
  if ((_parserState == kParserState_Start) || (_parserState == kParserState_Content)) {
    NSRange range = [_parserData rangeOfData:_boundary options:0 range:NSMakeRange(0, _parserData.length)];
    if (range.location != NSNotFound) {
      NSRange subRange = NSMakeRange(range.location + range.length, _parserData.length - range.location - range.length);
      NSRange subRange1 = [_parserData rangeOfData:_newlineData options:NSDataSearchAnchored range:subRange];
      NSRange subRange2 = [_parserData rangeOfData:_dashNewlineData options:NSDataSearchAnchored range:subRange];
      if ((subRange1.location != NSNotFound) || (subRange2.location != NSNotFound)) {
        
        if (_parserState == kParserState_Content) {
          const void* dataBytes = _parserData.bytes;
          NSUInteger dataLength = range.location - 2;
          if (_tmpPath) {
            ssize_t result = write(_tmpFile, dataBytes, dataLength);
            if (result == (ssize_t)dataLength) {
              if (close(_tmpFile) == 0) {
                _tmpFile = 0;
                GCDWebServerMultiPartFile* file = [[GCDWebServerMultiPartFile alloc] initWithContentType:_contentType fileName:_fileName temporaryPath:_tmpPath];
                [_files setObject:file forKey:_controlName];
                ARC_RELEASE(file);
              } else {
                DNOT_REACHED();
                success = NO;
              }
            } else {
              DNOT_REACHED();
              success = NO;
            }
            ARC_RELEASE(_tmpPath);
            _tmpPath = nil;
          } else {
            NSData* data = [[NSData alloc] initWithBytes:(void*)dataBytes length:dataLength];
            GCDWebServerMultiPartArgument* argument = [[GCDWebServerMultiPartArgument alloc] initWithContentType:_contentType data:data];
            [_arguments setObject:argument forKey:_controlName];
            ARC_RELEASE(argument);
            ARC_RELEASE(data);
          }
        }
        
        if (subRange1.location != NSNotFound) {
          [_parserData replaceBytesInRange:NSMakeRange(0, subRange1.location + subRange1.length) withBytes:NULL length:0];
          _parserState = kParserState_Headers;
          success = [self _parseData];
        } else {
          _parserState = kParserState_End;
        }
      }
    } else {
      NSUInteger margin = 2 * _boundary.length;
      if (_tmpPath && (_parserData.length > margin)) {
        NSUInteger length = _parserData.length - margin;
        ssize_t result = write(_tmpFile, _parserData.bytes, length);
        if (result == (ssize_t)length) {
          [_parserData replaceBytesInRange:NSMakeRange(0, length) withBytes:NULL length:0];
        } else {
          DNOT_REACHED();
          success = NO;
        }
      }
    }
  }
  return success;
}

- (BOOL)writeData:(NSData*)data error:(NSError**)error {
  [_parserData appendBytes:data.bytes length:data.length];
  if (![self _parseData]) {
    *error = [NSError errorWithDomain:kGCDWebServerErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed parsing multipart form data"}];
    return NO;
  }
  return YES;
}

- (BOOL)close:(NSError**)error {
  ARC_RELEASE(_parserData);
  _parserData = nil;
  ARC_RELEASE(_controlName);
  _controlName = nil;
  ARC_RELEASE(_fileName);
  _fileName = nil;
  ARC_RELEASE(_contentType);
  _contentType = nil;
  if (_tmpFile > 0) {
    close(_tmpFile);
    unlink([_tmpPath fileSystemRepresentation]);
    _tmpFile = 0;
  }
  ARC_RELEASE(_tmpPath);
  _tmpPath = nil;
  if (_parserState != kParserState_End) {
    *error = [NSError errorWithDomain:kGCDWebServerErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Failed parsing multipart form data"}];
    return NO;
  }
  return YES;
}

- (NSString*)description {
  NSMutableString* description = [NSMutableString stringWithString:[super description]];
  if (_arguments.count) {
    [description appendString:@"\n"];
    for (NSString* key in [[_arguments allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      GCDWebServerMultiPartArgument* argument = [_arguments objectForKey:key];
      [description appendFormat:@"\n%@ (%@)\n", key, argument.contentType];
      [description appendString:GCDWebServerDescribeData(argument.data, argument.contentType)];
    }
  }
  if (_files.count) {
    [description appendString:@"\n"];
    for (NSString* key in [[_files allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      GCDWebServerMultiPartFile* file = [_files objectForKey:key];
      [description appendFormat:@"\n%@ (%@): %@\n{%@}", key, file.contentType, file.fileName, file.temporaryPath];
    }
  }
  return description;
}

@end
