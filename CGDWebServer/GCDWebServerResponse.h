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

@protocol GCDWebServerBodyReader <NSObject>
- (BOOL)open:(NSError**)error;  // Return NO on error ("error" is guaranteed to be non-NULL)
- (NSData*)readData:(NSError**)error;  // Must return nil on error or empty NSData if at end ("error" is guaranteed to be non-NULL)
- (void)close;
@end

@interface GCDWebServerResponse : NSObject <GCDWebServerBodyReader>
@property(nonatomic, copy) NSString* contentType;  // Default is nil i.e. no body (must be set if a body is present)
@property(nonatomic) NSUInteger contentLength;  // Default is NSNotFound i.e. undefined (if a body is present but length is undefined, chunked transfer encoding will be enabled)
@property(nonatomic) NSInteger statusCode;  // Default is 200
@property(nonatomic) NSUInteger cacheControlMaxAge;  // Default is 0 seconds i.e. "Cache-Control: no-cache"
@property(nonatomic, retain) NSDate* lastModifiedDate;  // Default is nil i.e. no "Last-Modified" header
@property(nonatomic, copy) NSString* eTag;  // Default is nil i.e. no "ETag" header
@property(nonatomic, getter=isGZipContentEncodingEnabled) BOOL gzipContentEncodingEnabled;  // Default is disabled
+ (instancetype)response;
- (instancetype)init;
- (void)setValue:(NSString*)value forAdditionalHeader:(NSString*)header;  // Pass nil value to remove header
- (BOOL)hasBody;  // Convenience method that checks if "contentType" is not nil
@end

@interface GCDWebServerResponse (Extensions)
+ (instancetype)responseWithStatusCode:(NSInteger)statusCode;
+ (instancetype)responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
- (instancetype)initWithStatusCode:(NSInteger)statusCode;
- (instancetype)initWithRedirect:(NSURL*)location permanent:(BOOL)permanent;
@end
