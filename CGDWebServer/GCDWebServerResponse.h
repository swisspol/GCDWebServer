/*
 Copyright (c) 2012-2013, Pierre-Olivier Latour
 All rights reserved.
 */

#import <Foundation/Foundation.h>

@interface GCDWebServerResponse : NSObject {	@private

				              NSString * _type;
								 NSInteger   _status;
			               NSUInteger   _length, _maxAge;
				   NSMutableDictionary * _headers;
}
@property (readonly)      NSString * contentType;
@property (readonly) 	NSUInteger 	 contentLength;
@property(nonatomic) 	 NSInteger 	 statusCode;  // Default is 200
@property(nonatomic)    NSUInteger 	 cacheControlMaxAge;  // Default is 0 seconds i.e. "no-cache"
@property (readonly)  NSDictionary * additionalHeaders;
@property (readonly)          BOOL   hasBody;  // Convenience method

+ (instancetype) response;

- (id) initWithContentType:(NSString*)type
				 contentLength:(NSUInteger)length;  // Pass nil contentType to indicate empty body

- (void)		  setValue:(NSString*)value
	forAdditionalHeader:(NSString*)header;

#pragma mark - Subclassing

-      (BOOL) open;  // Implementation required
- (NSInteger) read:(void*)buffer maxLength:(NSUInteger)length;  // Implementation required
-      (BOOL) close;  // Implementation required

#pragma mark - Extensions

+ (instancetype) responseWithStatusCode:(NSInteger)statusCode;
+ (instancetype) responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
- (id)initWithStatusCode:(NSInteger)statusCode;
- (id)initWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
@end

@interface GCDWebServerDataResponse : GCDWebServerResponse {
@private
  NSData* _data;
  NSInteger _offset;
}
+ (GCDWebServerDataResponse*)responseWithData:(NSData*)data contentType:(NSString*)type;
- (id)initWithData:(NSData*)data contentType:(NSString*)type;
@end

@interface GCDWebServerDataResponse (Extensions)
+ (GCDWebServerDataResponse*)responseWithText:(NSString*)text;
+ (GCDWebServerDataResponse*)responseWithHTML:(NSString*)html;
+ (GCDWebServerDataResponse*)responseWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;
- (id)initWithText:(NSString*)text;  // Encodes using UTF-8
- (id)initWithHTML:(NSString*)html;  // Encodes using UTF-8
- (id)initWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;  // Simple template system that replaces all occurences of "%variable%" with corresponding value (encodes using UTF-8)
@end

@interface GCDWebServerFileResponse : GCDWebServerResponse {
@private
  NSString* _path;
  int _file;
}
+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path;
+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path isAttachment:(BOOL)attachment;
- (id)initWithFile:(NSString*)path;
- (id)initWithFile:(NSString*)path isAttachment:(BOOL)attachment;
@end
