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

@class GCDWebUploader;

@protocol GCDWebUploaderDelegate <NSObject>
@optional
- (void)webUploader:(GCDWebUploader*)uploader didDownloadFileAtPath:(NSString*)path;
- (void)webUploader:(GCDWebUploader*)uploader didUploadFileAtPath:(NSString*)path;
- (void)webUploader:(GCDWebUploader*)uploader didMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath;
- (void)webUploader:(GCDWebUploader*)uploader didDeleteItemAtPath:(NSString*)path;
- (void)webUploader:(GCDWebUploader*)uploader didCreateDirectoryAtPath:(NSString*)path;
@end

@interface GCDWebUploader : GCDWebServer
@property(nonatomic, readonly) NSString* uploadDirectory;
@property(nonatomic, assign) id<GCDWebUploaderDelegate> delegate;
@property(nonatomic, copy) NSArray* allowedFileExtensions;  // Default is nil i.e. all file extensions are allowed
@property(nonatomic) BOOL showHiddenFiles;  // Default is NO
@property(nonatomic, copy) NSString* title;  // Default is application name (must be HTML escaped)
@property(nonatomic, copy) NSString* header;  // Default is same as title (must be HTML escaped)
@property(nonatomic, copy) NSString* prologue;  // Default is mini help (must be raw HTML)
@property(nonatomic, copy) NSString* epilogue;  // Default is nothing (must be raw HTML)
@property(nonatomic, copy) NSString* footer;  // Default is application name and version (must be HTML escaped)
- (instancetype)initWithUploadDirectory:(NSString*)path;
@end

@interface GCDWebUploader (Subclassing)
- (BOOL)shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath;  // Default implementation returns YES
- (BOOL)shouldMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath;  // Default implementation returns YES
- (BOOL)shouldDeleteItemAtPath:(NSString*)path;  // Default implementation returns YES
- (BOOL)shouldCreateDirectoryAtPath:(NSString*)path;  // Default implementation returns YES
@end
