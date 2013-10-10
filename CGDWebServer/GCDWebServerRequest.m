/*
 Copyright (c) 2012-2013, Pierre-Olivier Latour
 All rights reserved.
 */

#import "GCDWebServer.h"

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

static NSString* _ExtractHeaderParameter(NSString* header, NSString* attribute) {
  NSString* value = nil;
  if (header) {
    NSScanner* scanner = [[NSScanner alloc] initWithString:header];
    NSString* string = [NSString stringWithFormat:@"%@=", attribute];
    if ([scanner scanUpToString:string intoString:NULL]) {
      [scanner scanString:string intoString:NULL];
      if ([scanner scanString:@"\"" intoString:NULL]) {
        [scanner scanUpToString:@"\"" intoString:&value];
      } else {
        [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&value];
      }
    }
  }
  return value;
}

// http://www.w3schools.com/tags/ref_charactersets.asp
static NSStringEncoding _StringEncodingFromCharset(NSString* charset) {
  NSStringEncoding encoding = kCFStringEncodingInvalidId;
  if (charset) {
    encoding = CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding((CFStringRef)charset));
  }
  return (encoding != kCFStringEncodingInvalidId ? encoding : NSUTF8StringEncoding);
}

@implementation GCDWebServerRequest : NSObject

@synthesize method=_method, URL=_url, headers=_headers, path=_path, query=_query, contentType=_type, contentLength=_length;

- (id)initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query {
  if ((self = [super init])) {
    _method = [method copy];
    _url = url;
    _headers = headers;
    _path = [path copy];
    _query = query;
    
    _type = [_headers objectForKey:@"Content-Type"];
    NSInteger length = [[_headers objectForKey:@"Content-Length"] integerValue];
    if (length < 0) {
      DNOT_REACHED();
      return nil;
    }
    _length = length;
    if ((_length > 0) && (_type == nil))  _type = [kGCDWebServerDefaultMimeType copy];
  }
  return self;
}
- (BOOL)hasBody {  return _type ? YES : NO;	}

#pragma mark - Subclassing

- (BOOL)open { return [self doesNotRecognizeSelector:_cmd], NO;  }
- (BOOL)close { return [self doesNotRecognizeSelector:_cmd], NO; }

- (NSInteger)write:(const void*)buffer maxLength:(NSUInteger)length {
	return [self doesNotRecognizeSelector:_cmd], -1;
}
@end

@implementation GCDWebServerDataRequest

@synthesize data=_data;

- (BOOL)open {
  DCHECK(_data == nil);
  _data = [[NSMutableData alloc] initWithCapacity:self.contentLength];
  return _data ? YES : NO;
}

- (NSInteger)write:(const void*)buffer maxLength:(NSUInteger)length {
  DCHECK(_data != nil);
  [_data appendBytes:buffer length:length];
  return length;
}

- (BOOL)close {
  DCHECK(_data != nil);
  return YES;
}

@end

@implementation GCDWebServerFileRequest

@synthesize filePath=_filePath;

- (id)initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query {
  if ((self = [super initWithMethod:method url:url headers:headers path:path query:query])) {
    _filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  }
  return self;
}

- (void)dealloc {	  DCHECK(_file < 0);
  unlink([_filePath fileSystemRepresentation]);
}

- (BOOL)open {
  DCHECK(_file == 0);
  _file = open([_filePath fileSystemRepresentation], O_CREAT | O_TRUNC | O_WRONLY, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
  return (_file > 0 ? YES : NO);
}

- (NSInteger)write:(const void*)buffer maxLength:(NSUInteger)length {
  DCHECK(_file > 0);
  return write(_file, buffer, length);
}

- (BOOL)close {
  DCHECK(_file > 0);
  int result = close(_file);
  _file = -1;
  return (result == 0 ? YES : NO);
}

@end

@implementation GCDWebServerURLEncodedFormRequest

@synthesize arguments=_arguments;

+ (NSString*)mimeType {
  return @"application/x-www-form-urlencoded";
}
- (BOOL)close {
  if (![super close]) {
    return NO;
  }
  
  NSString* charset = _ExtractHeaderParameter(self.contentType, @"charset");
  NSString* string = [[NSString alloc] initWithData:self.data encoding:_StringEncodingFromCharset(charset)];
  _arguments = GCDWebServerParseURLEncodedForm(string);
  return (_arguments ? YES : NO);
}

@end

@implementation GCDWebServerMultiPart

@synthesize contentType=_contentType, mimeType=_mimeType;

- (id)initWithContentType:(NSString*)contentType {
  if ((self = [super init])) {
    _contentType = [contentType copy];
    NSArray* components = 	  [_contentType componentsSeparatedByString:@";"];
    if (components.count)  	_mimeType = [components[0] lowercaseString];
    if (_mimeType == nil)	 	_mimeType = @"text/plain";
  }
  return self;
}
@end

@implementation GCDWebServerMultiPartArgument

@synthesize data=_data, string=_string;

- (id)initWithContentType:(NSString*)contentType data:(NSData*)data {
  if ((self = [super initWithContentType:contentType])) {
    _data = data;
    if ([self.mimeType hasPrefix:@"text/"])
      _string = [[NSString alloc] initWithData:_data encoding:_StringEncodingFromCharset(_ExtractHeaderParameter(self.contentType, @"charset"))];
  }
  return self;
}
- (NSString*)description { return [NSString stringWithFormat:@"<%@ | '%@' | %i bytes>", [self class], self.mimeType, (int)_data.length];	}
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
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@ | '%@' | '%@>'", [self class], self.mimeType, _fileName];
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

- (id)initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query {
  if ((self = [super initWithMethod:method url:url headers:headers path:path query:query])) {
    NSString* boundary = _ExtractHeaderParameter(self.contentType, @"boundary");
    if (boundary) {
      _boundary = [[NSString stringWithFormat:@"--%@", boundary] dataUsingEncoding:NSASCIIStringEncoding];
    }
    if (_boundary == nil) {
      DNOT_REACHED();
      return nil;
    }
    
    _arguments = [[NSMutableDictionary alloc] init];
    _files = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (BOOL)open {
  DCHECK(_parserData == nil);
  _parserData = [[NSMutableData alloc] initWithCapacity:kMultiPartBufferSize];
  _parserState = kParserState_Start;
  return YES;
}

// http://www.w3.org/TR/html401/interact/forms.html#h-17.13.4
- (BOOL)_parseData {
  BOOL success = YES;
  
  if (_parserState == kParserState_Headers) {
    NSRange range = [_parserData rangeOfData:_newlinesData options:0 range:NSMakeRange(0, _parserData.length)];
    if (range.location != NSNotFound) {
      _controlName = nil;
      _fileName = nil;
      _contentType = nil;
      _tmpPath = nil;
      CFHTTPMessageRef message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
      const char* temp = "GET / HTTP/1.0\r\n";
      CFHTTPMessageAppendBytes(message, (const UInt8*)temp, strlen(temp));
      CFHTTPMessageAppendBytes(message, _parserData.bytes, range.location + range.length);
      if (CFHTTPMessageIsHeaderComplete(message)) {
        NSString* controlName = nil;
        NSString* fileName = nil;
        NSDictionary* headers = (__bridge NSDictionary*)CFHTTPMessageCopyAllHeaderFields(message);
        NSString* contentDisposition = [headers objectForKey:@"Content-Disposition"];
        if ([[contentDisposition lowercaseString] hasPrefix:@"form-data;"]) {
          controlName = _ExtractHeaderParameter(contentDisposition, @"name");
          fileName = _ExtractHeaderParameter(contentDisposition, @"filename");
        }
        _controlName = [controlName copy];
        _fileName 	= [fileName copy];
        _contentType = [headers objectForKey:@"Content-Type"];
      }
      CFRelease(message);
      if (_controlName) {
        if (_fileName) {
          NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
          _tmpFile = open([path fileSystemRepresentation], O_CREAT | O_TRUNC | O_WRONLY, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
          if (_tmpFile > 0) _tmpPath = [path copy];
			 else {
            DNOT_REACHED();
            success = NO;
          }
        }
      } else {  DNOT_REACHED(); success = NO;   }
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
            int result = write(_tmpFile, dataBytes, dataLength);
            if (result == dataLength) {
              if (close(_tmpFile) == 0) {
                _tmpFile = 0;
                GCDWebServerMultiPartFile* file = [[GCDWebServerMultiPartFile alloc] initWithContentType:_contentType fileName:_fileName temporaryPath:_tmpPath];
                [_files setObject:file forKey:_controlName];
              } else {
                DNOT_REACHED();
                success = NO;
              }
            } else {
              DNOT_REACHED();
              success = NO;
            }
            _tmpPath = nil;
          } else {
            NSData* data = [[NSData alloc] initWithBytesNoCopy:(void*)dataBytes length:dataLength freeWhenDone:NO];
            GCDWebServerMultiPartArgument* argument = [[GCDWebServerMultiPartArgument alloc] initWithContentType:_contentType data:data];
            [_arguments setObject:argument forKey:_controlName];
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
        int result = write(_tmpFile, _parserData.bytes, length);
        if (result == length) {
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

- (NSInteger)write:(const void*)buffer maxLength:(NSUInteger)length {
  DCHECK(_parserData != nil);
  [_parserData appendBytes:buffer length:length];
  return ([self _parseData] ? length : -1);
}

- (BOOL)close {
  DCHECK(_parserData != nil);
  _parserData = nil;
  if (_tmpFile > 0) {
    close(_tmpFile);
    unlink([_tmpPath fileSystemRepresentation]);
  }
  return (_parserState == kParserState_End ? YES : NO);
}

- (void)dealloc {
  DCHECK(_parserData == nil);
}

@end
