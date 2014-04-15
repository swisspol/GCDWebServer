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

@interface GCDWebServerFileResponse : GCDWebServerResponse
+ (instancetype)responseWithFile:(NSString*)path;
+ (instancetype)responseWithFile:(NSString*)path isAttachment:(BOOL)attachment;
+ (instancetype)responseWithFile:(NSString*)path byteRange:(NSRange)range;
+ (instancetype)responseWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment;
- (instancetype)initWithFile:(NSString*)path;
- (instancetype)initWithFile:(NSString*)path isAttachment:(BOOL)attachment;  // If in attachment mode, "Content-Disposition" header will be set accordingly
- (instancetype)initWithFile:(NSString*)path byteRange:(NSRange)range;  // Pass [NSNotFound, 0] to disable byte range entirely, [offset, length] to enable byte range from beginning of file or [NSNotFound, -length] from end of file
- (instancetype)initWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment;
@end
