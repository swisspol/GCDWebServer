
#import <sys/stat.h>
#import "GCDWebServerPrivate.h"

@implementation GCDWebServerResponse		@synthesize 	additionalHeaders= _headers, statusCode=_status,
																			cacheControlMaxAge=_maxAge,  contentLength=_length,
																												  contentType=_type;

+(GCDWebServerResponse*) response 				{ return [[self.class.alloc init] autorelease]; }
- (id)init 												{ return [self initWithContentType:nil contentLength:0]; }
- (id)initWithContentType:(NSString*)type
				contentLength:(NSUInteger)length { if (self != super.init) return nil;

	_type = [type copy];	_length = length; _status = 200; _maxAge = 0; _headers = NSMutableDictionary.new;
	_type = _length && !_type ? [kGCDWebServerDefaultMimeType copy] : _type;			return self;
}
- (void) dealloc 								{ [_type release]; [_headers release]; [super dealloc]; }
- (void) setValue:	  (NSString*)val
	forAdditionalHeader:(NSString*)hdr 	{ [_headers setValue:val forKey:hdr]; }
- (BOOL) hasBody 								{  return _type ? YES : NO; }

#pragma mark - Subclassing

-      (BOOL) open													{ [self doesNotRecognizeSelector:_cmd]; return NO;  }
- (NSInteger) read:(void*)buf maxLength:(NSUInteger)len 	{ [self doesNotRecognizeSelector:_cmd]; return -1;  }
- 		 (BOOL) close 													{ [self doesNotRecognizeSelector:_cmd]; return NO;  }

#pragma mark - Extensions

+ (GCDWebServerResponse*)responseWithStatusCode:(NSInteger)statusCode {
  return [[self.alloc initWithStatusCode:statusCode] autorelease];
}
+ (GCDWebServerResponse*)responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  return [[self.alloc initWithRedirect:location permanent:permanent] autorelease];
}
- (id)initWithStatusCode:(NSInteger)statusCode {
  if ((self = [self initWithContentType:nil contentLength:0])) self.statusCode = statusCode; return self;
}
- (id)initWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  if ((self = [self initWithContentType:nil contentLength:0])) {
    self.statusCode = permanent ? 301 : 307;
    [self setValue:location.absoluteString forAdditionalHeader:@"Location"];
  }
  return self;
}
@end

@implementation GCDWebServerDataResponse

+ (GCDWebServerDataResponse*)responseWithData:(NSData*)data contentType:(NSString*)type {
  return [[[[self class] alloc] initWithData:data contentType:type] autorelease];
}
- (id)initWithData:(NSData*)data contentType:(NSString*)type {
 return !data ? DNOT_REACHED(), [self release], nil :
			(self = [super initWithContentType:type contentLength:data.length]) ?
			_data = [data retain], _offset = -1, self : self;
}
- (void) dealloc 	{ DCHECK(_offset < 0);  [_data release];   [super dealloc]; }
- (BOOL) open 		{ DCHECK(_offset < 0);	 _offset = 0;		  return YES; 		}
- (NSInteger)read:(void*)buffer maxLength:(NSUInteger)length {  DCHECK(_offset >= 0);
  NSInteger size = 0;
  if (_offset < _data.length) {  size = MIN(_data.length - _offset, length);
										bcopy((char*)_data.bytes   + _offset, buffer, size);
																			  _offset += size;
  } return size;
}
- (BOOL)close { DCHECK(_offset >= 0); _offset = -1; return YES;  }

@end

@implementation GCDWebServerDataResponse (Extensions)

+ (GCDWebServerDataResponse*)responseWithText:(NSString*)text {
  return [[self.alloc initWithText:text] autorelease];
}
+ (GCDWebServerDataResponse*)responseWithHTML:(NSString*)html {
  return [[self.alloc initWithHTML:html] autorelease];
}
+ (GCDWebServerDataResponse*)responseWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables {
  return [[self.alloc initWithHTMLTemplate:path variables:variables] autorelease];
}
- (id)initWithText:(NSString*)text {  NSData* data;
  return !(data = [text dataUsingEncoding:NSUTF8StringEncoding]) ? DNOT_REACHED(), [self release], nil
  		:	[self initWithData:data contentType:@"text/plain; charset=utf-8"];
}
- (id)initWithHTML:(NSString*)html { NSData* data;
  return !(data = [html dataUsingEncoding:NSUTF8StringEncoding])
  						?  DNOT_REACHED(), [self release], nil
						: [self initWithData:data contentType:@"text/html; charset=utf-8"];
}
- (id)initWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables {
  NSMutableString* html = [NSMutableString.alloc initWithContentsOfFile:path
																					encoding:NSUTF8StringEncoding error:NULL];
  [variables enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* value, BOOL* stop) {
    [html replaceOccurrencesOfString:[NSString stringWithFormat:@"%%%@%%", key] withString:value
																		  options:0 range:NSMakeRange(0, html.length)];
  }];
  id response = [self initWithHTML:html]; [html release];
  return response;
}
@end

@implementation GCDWebServerFileResponse

+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path {
  return [[self.class.alloc initWithFile:path] autorelease];
}
+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path isAttachment:(BOOL)attachment {
  return [[self.class.alloc initWithFile:path isAttachment:attachment] autorelease];
}
- (id)initWithFile:(NSString*)path { return [self initWithFile:path isAttachment:NO];  }
- (id)initWithFile:(NSString*)path isAttachment:(BOOL)attachment {  struct stat info;

  if (lstat([path fileSystemRepresentation], &info) || !(info.st_mode & S_IFREG)) {
    DNOT_REACHED();   [self release];   return nil;
  }
  NSString* type = GCDWebServerGetMimeTypeForExtension([path pathExtension]) ?: kGCDWebServerDefaultMimeType;
  if ((self = [super initWithContentType:type contentLength:info.st_size])) {
    _path = [path copy];
    if (attachment) {  // TODO: Use http://tools.ietf.org/html/rfc5987 to encode file names with special characters instead of using lossy conversion to ISO 8859-1
      NSData* data = [[path lastPathComponent] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
      NSString* fileName = data ? [NSString.alloc initWithData:data encoding:NSISOLatin1StringEncoding] : nil;
      if (fileName) {
        [self setValue:[NSString stringWithFormat:@"attachment; filename=\"%@\"", fileName] forAdditionalHeader:@"Content-Disposition"];
        [fileName release];
      } else  DNOT_REACHED();
    }
  }
  return self;
}
- (void)dealloc { DCHECK(_file <= 0); [_path release]; [super dealloc];  }
- (BOOL)open {  DCHECK(_file <= 0); _file = open([_path fileSystemRepresentation], O_NOFOLLOW | O_RDONLY);
  return (_file > 0 ? YES : NO);
}
- (NSInteger)read:(void*)buffer maxLength:(NSUInteger)length { DCHECK(_file > 0);
	return read(_file, buffer, length);
}
- (BOOL)close { DCHECK(_file > 0); int result = close(_file); _file = 0;  return (result == 0 ? YES : NO); }

@end
