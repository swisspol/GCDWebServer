/* Copyright (c) 2012-2013, Pierre-Olivier Latour */

#import "GCDWebServer.h"

int main(int argc, const char* argv[]) {
  BOOL success = NO;
  @autoreleasepool {
    GCDWebServer* webServer = [[GCDWebServer alloc] init];
    switch (0) {
      
      case 0: {
        [webServer addHandlerForBasePath:@"/" localPath:NSHomeDirectory() indexFilename:nil cacheAge:0];
        break;
      }
      
      case 1: {
        [webServer addDefaultHandlerForMethod:@"GET"
                                 requestClass:[GCDWebServerRequest class]
                                 processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
          
          return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
          
        }];
        break;
      }
      
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
      
    }
    success = [webServer runWithPort:9999];
    [webServer release];
  }
  return success ? 0 : -1;
}
