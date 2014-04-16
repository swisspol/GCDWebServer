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

@class GCDWebDAVServer;

// These methods are always called on main thread
@protocol GCDWebDAVServerDelegate <GCDWebServerDelegate>
@optional
- (void)davServer:(GCDWebDAVServer*)server didDownloadFileAtPath:(NSString*)path;
- (void)davServer:(GCDWebDAVServer*)server didUploadFileAtPath:(NSString*)path;
- (void)davServer:(GCDWebDAVServer*)server didMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath;
- (void)davServer:(GCDWebDAVServer*)server didCopyItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath;
- (void)davServer:(GCDWebDAVServer*)server didDeleteItemAtPath:(NSString*)path;
- (void)davServer:(GCDWebDAVServer*)server didCreateDirectoryAtPath:(NSString*)path;
@end

@interface GCDWebDAVServer : GCDWebServer
@property(nonatomic, readonly) NSString* uploadDirectory;
@property(nonatomic, assign) id<GCDWebDAVServerDelegate> delegate;
@property(nonatomic, copy) NSArray* allowedFileExtensions;  // Default is nil i.e. all file extensions are allowed
@property(nonatomic) BOOL showHiddenFiles;  // Default is NO
- (instancetype)initWithUploadDirectory:(NSString*)path;
@end

// These methods can be called from any thread
@interface GCDWebDAVServer (Subclassing)
- (BOOL)shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath;  // Default implementation returns YES
- (BOOL)shouldMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath;  // Default implementation returns YES
- (BOOL)shouldCopyItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath;  // Default implementation returns YES
- (BOOL)shouldDeleteItemAtPath:(NSString*)path;  // Default implementation returns YES
- (BOOL)shouldCreateDirectoryAtPath:(NSString*)path;  // Default implementation returns YES
@end
