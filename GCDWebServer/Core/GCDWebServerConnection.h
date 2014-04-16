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

#import "GCDWebServer.h"

@class GCDWebServerHandler;

@interface GCDWebServerConnection : NSObject
@property(nonatomic, readonly) GCDWebServer* server;
@property(nonatomic, readonly) NSData* localAddressData;  // struct sockaddr
@property(nonatomic, readonly) NSString* localAddressString;
@property(nonatomic, readonly) NSData* remoteAddressData;  // struct sockaddr
@property(nonatomic, readonly) NSString* remoteAddressString;
@property(nonatomic, readonly) NSUInteger totalBytesRead;
@property(nonatomic, readonly) NSUInteger totalBytesWritten;
@end

// These methods can be called from any thread
@interface GCDWebServerConnection (Subclassing)
- (BOOL)open;  // Return NO to reject connection e.g. after validating local or remote addresses
- (void)didReadBytes:(const void*)bytes length:(NSUInteger)length;  // Called after data has been read from the connection
- (void)didWriteBytes:(const void*)bytes length:(NSUInteger)length;  // Called after data has been written to the connection
- (GCDWebServerResponse*)processRequest:(GCDWebServerRequest*)request withBlock:(GCDWebServerProcessBlock)block;  // Only called if the request can be processed
- (GCDWebServerResponse*)replaceResponse:(GCDWebServerResponse*)response forRequest:(GCDWebServerRequest*)request;  // Default implementation replaces any response matching the "ETag" or "Last-Modified-Date" header of the request by a barebone "Not-Modified" (304) one
- (void)abortRequest:(GCDWebServerRequest*)request withStatusCode:(NSInteger)statusCode;  // If request headers was malformed, "request" will be nil
- (void)close;
@end
