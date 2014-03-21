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

#import <mach-o/getsect.h>

#import "GCDWebServer.h"

static NSData* _DataFromTEXTSection(const char* name) {
  unsigned long size = 0;
  char* ptr = getsectdata("__TEXT", name, &size);
  if (!ptr || !size) {
    abort();
  }
  return [NSData dataWithBytesNoCopy:ptr length:size freeWhenDone:NO];
}

int main(int argc, const char* argv[]) {
  BOOL success = NO;
  int mode = (argc == 2 ? MIN(MAX(atoi(argv[1]), 0), 3) : 0);
  @autoreleasepool {
    GCDWebServer* webServer = [[GCDWebServer alloc] init];
    switch (mode) {
      
      // Simply serve contents of home directory
      case 0: {
        [webServer addGETHandlerForBasePath:@"/" directoryPath:NSHomeDirectory() indexFilename:nil cacheAge:0 allowRangeRequests:YES];
        break;
      }
      
      // Renders a HTML page
      case 1: {
        [webServer addDefaultHandlerForMethod:@"GET"
                                 requestClass:[GCDWebServerRequest class]
                                 processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
          
        }];
        break;
      }
      
      // Implements an HTML form
      case 2: {
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
      
      // Implements drag & drop file upload using http://filedropjs.org (requires Chrome 13+, Firefox 3.6+, IE 10+ or Safari 6+)
      case 3: {
        [webServer addGETHandlerForPath:@"/"
                             staticData:_DataFromTEXTSection("_index_html_")
                            contentType:@"text/html; charset=utf-8"
                               cacheAge:0];
        [webServer addGETHandlerForPath:@"/filedrop-min.js"
                             staticData:_DataFromTEXTSection("_filedrop_js_")
                            contentType:@"application/javascript; charset=utf-8"
                               cacheAge:0];
        [webServer addHandlerForMethod:@"POST" path:@"/ajax-upload" requestClass:[GCDWebServerFileRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          NSString* fileName = GCDWebServerUnescapeURLString([request.headers objectForKey:@"X-File-Name"]);
          NSString* inPath = [(GCDWebServerFileRequest*)request filePath];
          NSString* outPath = [@"/tmp" stringByAppendingPathComponent:fileName];
          [[NSFileManager defaultManager] removeItemAtPath:outPath error:NULL];
          if ([[NSFileManager defaultManager] moveItemAtPath:inPath toPath:outPath error:NULL]) {
            NSString* message = [NSString stringWithFormat:@"File uploaded to \"%@\"", outPath];
            return [GCDWebServerDataResponse responseWithText:message];
          } else {
            return [GCDWebServerResponse responseWithStatusCode:500];
          }
          
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
