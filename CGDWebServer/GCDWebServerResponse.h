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

#import <Foundation/Foundation.h>

typedef NSData* (^GCDWebServerStreamBlock)(NSError** error);

@protocol GCDWebServerBodyReader <NSObject>
- (BOOL)open:(NSError**)error;
- (NSData*)readData:(NSError**)error;  // Return nil on error or empty NSData if at end
- (void)close;
@end

@interface GCDWebServerResponse : NSObject <GCDWebServerBodyReader>
@property(nonatomic, copy) NSString* contentType;  // Default is nil i.e. no body
@property(nonatomic) NSUInteger contentLength;  // Default is NSNotFound i.e. undefined
@property(nonatomic) NSInteger statusCode;  // Default is 200
@property(nonatomic) NSUInteger cacheControlMaxAge;  // Default is 0 seconds i.e. "no-cache"
@property(nonatomic) BOOL gzipContentEncoding;
@property(nonatomic) BOOL chunkedTransferEncoding;
+ (GCDWebServerResponse*) response;
- (id)init;
- (void)setValue:(NSString*)value forAdditionalHeader:(NSString*)header;
- (BOOL)hasBody;  // Convenience method
@end

@interface GCDWebServerResponse (Extensions)
+ (GCDWebServerResponse*)responseWithStatusCode:(NSInteger)statusCode;
+ (GCDWebServerResponse*)responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
- (id)initWithStatusCode:(NSInteger)statusCode;
- (id)initWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
@end

@interface GCDWebServerDataResponse : GCDWebServerResponse
+ (GCDWebServerDataResponse*)responseWithData:(NSData*)data contentType:(NSString*)type;
- (id)initWithData:(NSData*)data contentType:(NSString*)type;
@end

@interface GCDWebServerDataResponse (Extensions)
+ (GCDWebServerDataResponse*)responseWithText:(NSString*)text;
+ (GCDWebServerDataResponse*)responseWithHTML:(NSString*)html;
+ (GCDWebServerDataResponse*)responseWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;
+ (GCDWebServerDataResponse*)responseWithJSONObject:(id)object;
+ (GCDWebServerDataResponse*)responseWithJSONObject:(id)object contentType:(NSString*)type;
- (id)initWithText:(NSString*)text;  // Encodes using UTF-8
- (id)initWithHTML:(NSString*)html;  // Encodes using UTF-8
- (id)initWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;  // Simple template system that replaces all occurences of "%variable%" with corresponding value (encodes using UTF-8)
- (id)initWithJSONObject:(id)object;
- (id)initWithJSONObject:(id)object contentType:(NSString*)type;
@end

@interface GCDWebServerFileResponse : GCDWebServerResponse
+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path;
+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path isAttachment:(BOOL)attachment;
+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path byteRange:(NSRange)range;
+ (GCDWebServerFileResponse*)responseWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment;
- (id)initWithFile:(NSString*)path;
- (id)initWithFile:(NSString*)path isAttachment:(BOOL)attachment;
- (id)initWithFile:(NSString*)path byteRange:(NSRange)range;  // Pass [NSNotFound, 0] to disable byte range entirely, [offset, length] to enable byte range from beginning of file or [NSNotFound, -bytes] from end of file
- (id)initWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment;
@end

@interface GCDWebServerStreamResponse : GCDWebServerResponse  // Forces chunked transfer encoding
+ (GCDWebServerStreamResponse*)responseWithContentType:(NSString*)type streamBlock:(GCDWebServerStreamBlock)block;
- (id)initWithContentType:(NSString*)type streamBlock:(GCDWebServerStreamBlock)block;  // Block must return empty NSData when done or nil on error
@end
