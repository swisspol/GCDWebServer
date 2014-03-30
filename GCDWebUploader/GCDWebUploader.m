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

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <SystemConfiguration/SystemConfiguration.h>
#endif

#import "GCDWebUploader.h"

@interface GCDWebUploader () {
@private
  NSString* _uploadDirectory;
  id<GCDWebUploaderDelegate> delegate;
  NSArray* _allowedExtensions;
  BOOL _showHidden;
  NSString* _title;
  NSString* _header;
  NSString* _footer;
}
@end

static NSDictionary* _GetInfoForFile(NSString* path) {
  NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
  if ([[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) {
    NSString* name = [path lastPathComponent];
    NSString* file = GCDWebServerEscapeURLString(name);
    return @{
             @"url": [@"/download?file=" stringByAppendingString:file],
             @"name": name,
             @"size": [attributes objectForKey:NSFileSize],
             @"type": GCDWebServerGetMimeTypeForExtension([name pathExtension]),
             @"deleteType": @"DELETE",
             @"deleteUrl": [@"/delete?file=" stringByAppendingString:file]
             };
  }
  return nil;
}

@implementation GCDWebUploader

@synthesize uploadDirectory=_uploadDirectory, delegate=_delegate, allowedFileExtensions=_allowedExtensions, showHiddenFiles=_showHidden, title=_title, header=_header, footer=_footer;

- (BOOL)_checkFileExtension:(NSString*)fileName {
  if (_allowedExtensions && ![_allowedExtensions containsObject:[[fileName pathExtension] lowercaseString]]) {
    return NO;
  }
  return YES;
}

- (id)initWithUploadDirectory:(NSString*)path {
  if ((self = [super init])) {
    NSBundle* siteBundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"GCDWebUploader" ofType:@"bundle"]];
    if (siteBundle == nil) {
#if !__has_feature(objc_arc)
      [self release];
#endif
      return nil;
    }
    _uploadDirectory = [[path stringByStandardizingPath] copy];
    GCDWebUploader* __unsafe_unretained uploader = self;  // Avoid retain-cycles with self
    
    // Resource files
    [self addGETHandlerForBasePath:@"/" directoryPath:[siteBundle resourcePath] indexFilename:nil cacheAge:3600 allowRangeRequests:NO];
    
    // Web page
    [self addHandlerForMethod:@"GET" path:@"/" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      NSString* title = uploader.title;
      if (title == nil) {
        title = [NSString stringWithFormat:[siteBundle localizedStringForKey:@"TITLE" value:@"" table:nil],
                 [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"]];
      }
      NSString* header = uploader.header;
      if (header == nil) {
        header = [siteBundle localizedStringForKey:@"HEADER" value:@"" table:nil];
      }
      NSString* footer = uploader.footer;
      if (footer == nil) {
#if TARGET_OS_IPHONE
        NSString* name = [[UIDevice currentDevice] name];
#else
        CFStringRef name = SCDynamicStoreCopyComputerName(NULL, NULL);
#endif
        footer = [NSString stringWithFormat:[siteBundle localizedStringForKey:@"FOOTER" value:@"" table:nil],
                  [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                  [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                  name];
      }
      return [GCDWebServerDataResponse responseWithHTMLTemplate:[siteBundle pathForResource:@"index" ofType:@"html"]
                                                      variables:@{
                                                                  @"title": title,
                                                                  @"header": header,
                                                                  @"footer": footer
                                                                  }];
      
    }];
    
    // File listing
    [self addHandlerForMethod:@"GET" path:@"/list" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      NSString* basePath = uploader.uploadDirectory;
      BOOL showHidden = uploader.showHiddenFiles;
      NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:basePath error:NULL];
      if (contents) {
        NSMutableArray* files = [NSMutableArray array];
        for (NSString* path in [contents sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
          if (showHidden || ![path hasPrefix:@"."]) {
            if ([uploader _checkFileExtension:path]) {
              NSDictionary* info = _GetInfoForFile([basePath stringByAppendingPathComponent:path]);
              if (info) {
                [files addObject:info];
              }
            }
          }
        }
        return [GCDWebServerDataResponse responseWithJSONObject:@{@"files": files}];
      } else {
        return [GCDWebServerResponse responseWithStatusCode:500];
      }
      
    }];
    
    // File download
    [self addHandlerForMethod:@"GET" path:@"/download" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      NSString* file = [[request query] objectForKey:@"file"];
      NSString* path = [uploader.uploadDirectory stringByAppendingPathComponent:file];
      BOOL isDirectory;
      if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
        return [GCDWebServerFileResponse responseWithFile:path isAttachment:YES];
      } else {
        return [GCDWebServerResponse responseWithStatusCode:404];
      }
      
    }];
    
    // File upload
    [self addHandlerForMethod:@"POST" path:@"/upload" requestClass:[GCDWebServerMultiPartFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      // Required when using iFrame transport (see https://github.com/blueimp/jQuery-File-Upload/wiki/Setup)
      NSRange range = [[request.headers objectForKey:@"Accept"] rangeOfString:@"application/json" options:NSCaseInsensitiveSearch];
      NSString* contentType = (range.location != NSNotFound ? @"application/json" : @"text/plain; charset=utf-8");
      
      GCDWebServerMultiPartFile* file = [[(GCDWebServerMultiPartFormRequest*)request files] objectForKey:@"files[]"];
      NSString* fileName = file.fileName;
      if ([uploader _checkFileExtension:fileName]) {
        NSString* path = nil;
        int retries = 0;
        while (1) {
          if (retries > 0) {
            path = [uploader.uploadDirectory stringByAppendingPathComponent:[[[fileName stringByDeletingPathExtension] stringByAppendingFormat:@" (%i)", retries] stringByAppendingPathExtension:[fileName pathExtension]]];
          } else {
            path = [uploader.uploadDirectory stringByAppendingPathComponent:fileName];
          }
          if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            break;
          }
          ++retries;
        }
        NSError* error = nil;
        if ([[NSFileManager defaultManager] moveItemAtPath:file.temporaryPath toPath:path error:&error]) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [uploader.delegate webUploader:uploader didUploadFile:[path lastPathComponent]];
          });
          NSDictionary* info = _GetInfoForFile(path);
          return [GCDWebServerDataResponse responseWithJSONObject:@{@"files": @[info]} contentType:contentType];
        } else {
          return [GCDWebServerDataResponse responseWithJSONObject:@{
                                                                    @"files": @[@{
                                                                                  @"name": fileName,
                                                                                  @"size": @0,
                                                                                  @"error": [error localizedDescription]
                                                                                  }]
                                                                    } contentType:contentType];
        }
      } else {
        return [GCDWebServerDataResponse responseWithJSONObject:@{
                                                                  @"files": @[@{
                                                                                @"name": fileName,
                                                                                @"size": @0,
                                                                                @"error": [siteBundle localizedStringForKey:@"UNSUPPORTED_FILE_EXTENSION" value:@"" table:nil]
                                                                                }]
                                                                  } contentType:contentType];
      }
      
    }];
    
    // File deletion
    [self addHandlerForMethod:@"DELETE" path:@"/delete" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      NSString* file = [[request query] objectForKey:@"file"];
      NSString* path = [uploader.uploadDirectory stringByAppendingPathComponent:file];
      BOOL isDirectory;
      if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory) {
        BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        if (success) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [uploader.delegate webUploader:uploader didDeleteFile:file];
          });
        }
        return [GCDWebServerResponse responseWithStatusCode:(success ? 204 : 500)];
        // TODO: Contrary to the documentation at https://github.com/blueimp/jQuery-File-Upload/wiki/Setup, jquery.fileupload-ui.js ignores the returned JSON
        // return [GCDWebServerDataResponse responseWithJSONObject:@{@"files": @[@{file: [NSNumber numberWithBool:success]}]}];
      } else {
        return [GCDWebServerResponse responseWithStatusCode:404];
      }
      
    }];
    
  }
  return self;
}

#if !__has_feature(objc_arc)

- (void)dealloc {
  [_uploadDirectory release];
  [_allowedExtensions release];
  [_title release];
  [_header release];
  [_footer release];
  
  [super dealloc];
}

#endif

@end
