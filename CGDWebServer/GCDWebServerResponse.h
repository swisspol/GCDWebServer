/*
 Copyright (c) 2012-2013, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the <organization> nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>

@interface GCDWebServerResponse : NSObject {
@private
  NSString* _type;
  NSUInteger _length;
  NSInteger _status;
  NSUInteger _maxAge;
  NSMutableDictionary* _headers;
}
@property(nonatomic, readonly) NSString* contentType;
@property(nonatomic, readonly) NSUInteger contentLength;
@property(nonatomic) NSInteger statusCode;  // Default is 200
@property(nonatomic) NSUInteger cacheControlMaxAge;  // Default is 0 seconds i.e. "no-cache"
@property(nonatomic, readonly) NSDictionary* additionalHeaders;
+ (GCDWebServerResponse*) response;
- (id)init;
- (id)initWithContentType:(NSString*)type contentLength:(NSUInteger)length;  // Pass nil contentType to indicate empty body
- (void)setValue:(NSString*)value forAdditionalHeader:(NSString*)header;
- (BOOL)hasBody;  // Convenience method
@end

@interface GCDWebServerResponse (Subclassing)
- (BOOL)open;  // Implementation required
- (NSInteger)read:(void*)buffer maxLength:(NSUInteger)length;  // Implementation required
- (BOOL)close;  // Implementation required
@end

@interface GCDWebServerResponse (Extensions)
+ (GCDWebServerResponse*)responseWithStatusCode:(NSInteger)statusCode;
+ (GCDWebServerResponse*)responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
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
