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

#import <libgen.h>

#import "GCDWebServer.h"

#import "GCDWebServerDataRequest.h"
#import "GCDWebServerURLEncodedFormRequest.h"

#import "GCDWebServerDataResponse.h"
#import "GCDWebServerStreamingResponse.h"

#import "GCDWebDAVServer.h"

#import "GCDWebUploader.h"

#ifndef __GCDWEBSERVER_ENABLE_TESTING__
#error __GCDWEBSERVER_ENABLE_TESTING__ must be defined
#endif

typedef enum {
  kMode_WebServer = 0,
  kMode_HTMLPage,
  kMode_HTMLForm,
  kMode_WebDAV,
  kMode_WebUploader,
  kMode_StreamingResponse
} Mode;

@interface Delegate : NSObject <GCDWebServerDelegate, GCDWebDAVServerDelegate, GCDWebUploaderDelegate>
@end

@implementation Delegate

- (void)_logDelegateCall:(SEL)selector {
  fprintf(stdout, "<DELEGATE METHOD \"%s\" CALLED>\n", [NSStringFromSelector(selector) UTF8String]);
}

- (void)webServerDidStart:(GCDWebServer*)server {
  [self _logDelegateCall:_cmd];
}

- (void)webServerDidConnect:(GCDWebServer*)server {
  [self _logDelegateCall:_cmd];
}

- (void)webServerDidDisconnect:(GCDWebServer*)server {
  [self _logDelegateCall:_cmd];
}

- (void)webServerDidStop:(GCDWebServer*)server {
  [self _logDelegateCall:_cmd];
}

- (void)davServer:(GCDWebDAVServer*)server didDownloadFileAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

- (void)davServer:(GCDWebDAVServer*)server didUploadFileAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

- (void)davServer:(GCDWebDAVServer*)server didMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  [self _logDelegateCall:_cmd];
}

- (void)davServer:(GCDWebDAVServer*)server didCopyItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  [self _logDelegateCall:_cmd];
}

- (void)davServer:(GCDWebDAVServer*)server didDeleteItemAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

- (void)davServer:(GCDWebDAVServer*)server didCreateDirectoryAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

- (void)webUploader:(GCDWebUploader*)uploader didDownloadFileAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

- (void)webUploader:(GCDWebUploader*)uploader didUploadFileAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

- (void)webUploader:(GCDWebUploader*)uploader didMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  [self _logDelegateCall:_cmd];
}

- (void)webUploader:(GCDWebUploader*)uploader didDeleteItemAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

- (void)webUploader:(GCDWebUploader*)uploader didCreateDirectoryAtPath:(NSString*)path {
  [self _logDelegateCall:_cmd];
}

@end

int main(int argc, const char* argv[]) {
  int result = -1;
  @autoreleasepool {
    Mode mode = kMode_WebServer;
    BOOL recording = NO;
    NSString* rootDirectory = NSHomeDirectory();
    NSString* testDirectory = nil;
    
    if (argc == 1) {
      fprintf(stdout, "Usage: %s [-mode webServer | htmlPage | htmlForm | webDAV | webUploader | streamingResponse] [-record] [-root directory] [-tests directory]\n\n", basename((char*)argv[0]));
    } else {
      for (int i = 1; i < argc; ++i) {
        if (argv[i][0] != '-') {
          continue;
        }
        if (!strcmp(argv[i], "-mode") && (i + 1 < argc)) {
          ++i;
          if (!strcmp(argv[i], "webServer")) {
            mode = kMode_WebServer;
          } else if (!strcmp(argv[i], "htmlPage")) {
            mode = kMode_HTMLPage;
          } else if (!strcmp(argv[i], "htmlForm")) {
            mode = kMode_HTMLForm;
          } else if (!strcmp(argv[i], "webDAV")) {
            mode = kMode_WebDAV;
          } else if (!strcmp(argv[i], "webUploader")) {
            mode = kMode_WebUploader;
          } else if (!strcmp(argv[i], "streamingResponse")) {
            mode = kMode_StreamingResponse;
          }
        } else if (!strcmp(argv[i], "-record")) {
          recording = YES;
        } else if (!strcmp(argv[i], "-root") && (i + 1 < argc)) {
          ++i;
          rootDirectory = [[[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[i] length:strlen(argv[i])] stringByStandardizingPath];
        } else if (!strcmp(argv[i], "-tests") && (i + 1 < argc)) {
          ++i;
          testDirectory = [[[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[i] length:strlen(argv[i])] stringByStandardizingPath];
        }
      }
    }
    
    GCDWebServer* webServer = nil;
    switch (mode) {
      
      // Simply serve contents of home directory
      case kMode_WebServer: {
        fprintf(stdout, "Running in Web Server mode from \"%s\"", [rootDirectory UTF8String]);
        webServer = [[GCDWebServer alloc] init];
        [webServer addGETHandlerForBasePath:@"/" directoryPath:rootDirectory indexFilename:nil cacheAge:0 allowRangeRequests:YES];
        break;
      }
      
      // Renders a HTML page
      case kMode_HTMLPage: {
        fprintf(stdout, "Running in HTML Page mode");
        webServer = [[GCDWebServer alloc] init];
        [webServer addDefaultHandlerForMethod:@"GET"
                                 requestClass:[GCDWebServerRequest class]
                                 processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
          
        }];
        break;
      }
      
      // Implements an HTML form
      case kMode_HTMLForm: {
        fprintf(stdout, "Running in HTML Form mode");
        webServer = [[GCDWebServer alloc] init];
        [webServer addHandlerForMethod:@"GET"
                                  path:@"/"
                          requestClass:[GCDWebServerRequest class]
                          processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          NSString* html = @" \
            <html><body> \
              <form name=\"input\" action=\"/\" method=\"post\" enctype=\"application/x-www-form-urlencoded\"> \
              Value: <input type=\"text\" name=\"value\"> \
              <input type=\"submit\" value=\"Submit\"> \
              </form> \
            </body></html> \
          ";
          return [GCDWebServerDataResponse responseWithHTML:html];
          
        }];
        [webServer addHandlerForMethod:@"POST"
                                  path:@"/"
                          requestClass:[GCDWebServerURLEncodedFormRequest class]
                          processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          NSString* value = [[(GCDWebServerURLEncodedFormRequest*)request arguments] objectForKey:@"value"];
          NSString* html = [NSString stringWithFormat:@"<html><body><p>%@</p></body></html>", value];
          return [GCDWebServerDataResponse responseWithHTML:html];
          
        }];
        break;
      }
      
      // Serve home directory through WebDAV
      case kMode_WebDAV: {
        fprintf(stdout, "Running in WebDAV mode from \"%s\"", [rootDirectory UTF8String]);
        webServer = [[GCDWebDAVServer alloc] initWithUploadDirectory:rootDirectory];
        break;
      }
      
      // Serve home directory through web uploader
      case kMode_WebUploader: {
        fprintf(stdout, "Running in Web Uploader mode from \"%s\"", [rootDirectory UTF8String]);
        webServer = [[GCDWebUploader alloc] initWithUploadDirectory:rootDirectory];
        break;
      }
      
      // Test streaming responses
      case kMode_StreamingResponse: {
        fprintf(stdout, "Running in Streaming Response mode");
        webServer = [[GCDWebServer alloc] init];
        [webServer addHandlerForMethod:@"GET"
                                  path:@"/"
                          requestClass:[GCDWebServerRequest class]
                          processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          __block int countDown = 10;
          return [GCDWebServerStreamingResponse responseWithContentType:@"text/plain" streamBlock:^NSData *(NSError** error) {
            
            usleep(100 * 1000);
            if (countDown) {
              return [[NSString stringWithFormat:@"%i\n", countDown--] dataUsingEncoding:NSUTF8StringEncoding];
            } else {
              return [NSData data];
            }
            
          }];
          
        }];
        break;
      }
      
    }
#if __has_feature(objc_arc)
    fprintf(stdout, " (ARC is ON)\n");
#else
    fprintf(stdout, " (ARC is OFF)\n");
#endif
    
    if (webServer) {
      Delegate* delegate = [[Delegate alloc] init];
      webServer.delegate = delegate;
      if (testDirectory) {
        fprintf(stdout, "<RUNNING TESTS FROM \"%s\">\n\n", [testDirectory UTF8String]);
        result = (int)[webServer runTestsInDirectory:testDirectory withPort:8080];
      } else {
        if (recording) {
          fprintf(stdout, "<RECORDING ENABLED>\n");
          webServer.recordingEnabled = YES;
        }
        fprintf(stdout, "\n");
        if ([webServer runWithPort:8080]) {
          result = 0;
        }
      }
#if !__has_feature(objc_arc)
      [webServer release];
      [delegate release];
#endif
    }
  }
  return result;
}
