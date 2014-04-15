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

@protocol GCDWebServerBodyWriter <NSObject>
- (BOOL)open:(NSError**)error;  // Return NO on error ("error" is guaranteed to be non-NULL)
- (BOOL)writeData:(NSData*)data error:(NSError**)error;  // Return NO on error ("error" is guaranteed to be non-NULL)
- (BOOL)close:(NSError**)error;  // Return NO on error ("error" is guaranteed to be non-NULL)
@end

@interface GCDWebServerRequest : NSObject <GCDWebServerBodyWriter>
@property(nonatomic, readonly) NSString* method;
@property(nonatomic, readonly) NSURL* URL;
@property(nonatomic, readonly) NSDictionary* headers;
@property(nonatomic, readonly) NSString* path;
@property(nonatomic, readonly) NSDictionary* query;  // May be nil
@property(nonatomic, readonly) NSString* contentType;  // Automatically parsed from headers (nil if request has no body or set to "application/octet-stream" if a body is present without a "Content-Type" header)
@property(nonatomic, readonly) NSUInteger contentLength;  // Automatically parsed from headers (NSNotFound if request has no "Content-Length" header)
@property(nonatomic, readonly) NSDate* ifModifiedSince;  // Automatically parsed from headers (nil if request has no "If-Modified-Since" header or it is malformatted)
@property(nonatomic, readonly) NSString* ifNoneMatch;  // Automatically parsed from headers (nil if request has no "If-None-Match" header)
@property(nonatomic, readonly) NSRange byteRange;  // Automatically parsed from headers ([NSNotFound, 0] if request has no "Range" header, [offset, length] for byte range from beginning or [NSNotFound, -length] from end)
@property(nonatomic, readonly) BOOL acceptsGzipContentEncoding;  // Automatically parsed from headers
- (instancetype)initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query;
- (BOOL)hasBody;  // Convenience method that checks if "contentType" is not nil
- (BOOL)hasByteRange;  // Convenience method that checks "byteRange"
@end
