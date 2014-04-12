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

#import "GCDWebServerResponse.h"

@interface GCDWebServerDataResponse : GCDWebServerResponse
+ (instancetype)responseWithData:(NSData*)data contentType:(NSString*)type;
- (instancetype)initWithData:(NSData*)data contentType:(NSString*)type;
@end

@interface GCDWebServerDataResponse (Extensions)
+ (instancetype)responseWithText:(NSString*)text;
+ (instancetype)responseWithHTML:(NSString*)html;
+ (instancetype)responseWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;
+ (instancetype)responseWithJSONObject:(id)object;
+ (instancetype)responseWithJSONObject:(id)object contentType:(NSString*)type;
- (instancetype)initWithText:(NSString*)text;  // Encodes using UTF-8
- (instancetype)initWithHTML:(NSString*)html;  // Encodes using UTF-8
- (instancetype)initWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables;  // Simple template system that replaces all occurences of "%variable%" with corresponding value (encodes using UTF-8)
- (instancetype)initWithJSONObject:(id)object;
- (instancetype)initWithJSONObject:(id)object contentType:(NSString*)type;
@end
