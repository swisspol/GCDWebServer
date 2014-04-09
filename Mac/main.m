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

#import "GCDWebServerDataRequest.h"
#import "GCDWebServerURLEncodedFormRequest.h"

#import "GCDWebServerDataResponse.h"
#import "GCDWebServerStreamingResponse.h"

#import "GCDWebDAVServer.h"

#import "GCDWebUploader.h"

int main(int argc, const char* argv[]) {
  BOOL success = NO;
  int mode = (argc == 2 ? MIN(MAX(atoi(argv[1]), 0), 5) : 0);
  @autoreleasepool {
    GCDWebServer* webServer = nil;
    switch (mode) {
      
      // Simply serve contents of home directory
      case 0: {
        webServer = [[GCDWebServer alloc] init];
        [webServer addGETHandlerForBasePath:@"/" directoryPath:NSHomeDirectory() indexFilename:nil cacheAge:0 allowRangeRequests:YES];
        break;
      }
      
      // Renders a HTML page
      case 1: {
        webServer = [[GCDWebServer alloc] init];
        [webServer addDefaultHandlerForMethod:@"GET"
                                 requestClass:[GCDWebServerRequest class]
                                 processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
          
        }];
        break;
      }
      
      // Implements an HTML form
      case 2: {
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
      
      case 3: {
        webServer = [[GCDWebDAVServer alloc] initWithUploadDirectory:[[NSFileManager defaultManager] currentDirectoryPath]];
        break;
      }
      
      case 4: {
        webServer = [[GCDWebUploader alloc] initWithUploadDirectory:[[NSFileManager defaultManager] currentDirectoryPath]];
        break;
      }
      
      case 5: {
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
    success = [webServer runWithPort:8080];
#if !__has_feature(objc_arc)
    [webServer release];
#endif
  }
  return success ? 0 : -1;
}
