GCDWebServer
============

GCDWebServer is a lightweight GCD based HTTP 1.1 server for Mac & iOS apps written from scratch with the following goals in mind:
* Entirely built with an event-driven design using [Grand Central Dispatch](http://en.wikipedia.org/wiki/Grand_Central_Dispatch) for maximum performance and concurrency
* Well designed API for easy integration and customization
* Minimal number of source files and no dependencies on third-party source code
* Support for streaming large HTTP bodies for requests and responses to minimize memory usage
* Built-in parser for web forms submitted using "application/x-www-form-urlencoded" or "multipart/form-data"
* Available under a friendly New BSD License

What's not supported (yet?):
* Keep-alive connections
* Authentication
* HTTPS
* Web forms submitted using "multipart/mixed"

Requirements:
* OS X 10.7 or later
* iOS 5.0 or later

Hello World
===========

A simple HTTP server that runs on port 8080 and returns a "Hello World" HTML page to any request:

```objectivec
#import "GCDWebServer.h"

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    
    // Create server and add default handler
    GCDWebServer* webServer = [[GCDWebServer alloc] init];
    [webServer addDefaultHandlerForMethod:@"GET"
                             requestClass:[GCDWebServerRequest class]
                             processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
      
    }];
    
    // Run server on port 8080 until SIGINT received
    [webServer runWithPort:8080];
    
    // Destroy server
    [webServer release];
    
  }
  return 0;
}
```

Serving a Static Website
========================

GCDWebServer includes a built-in handler that can recursively serve a directory (it also lets you control how the "Cache-Control" header should be set):

```objectivec
#import "GCDWebServer.h"

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    
    GCDWebServer* webServer = [[GCDWebServer alloc] init];
    [webServer addHandlerForBasePath:@"/" localPath:NSHomeDirectory() indexFilename:nil cacheAge:3600];
    [webServer runWithPort:8080];
    [webServer release];
    
  }
  return 0;
}
```

Using GCDWebServer
==================

You start by creating an instance of the 'GCDWebServer' class. Note that you can have multiple web servers running in the same app as long as they listen on different ports.

Then you add one or more "handlers" to the server: each handler gets a chance to handle an incoming web request and provide a response. Handlers are called in a LIFO queue, so the latest added handler overrides any previously added ones.

Finally you start the server on a given port. Note that even if built on GCD, GCDWebServer still requires a runloop to be around (by default the main thread runloop is used). This is because there is no CGD API at this point to handle listening sockets, so it must be done using CFSocket which requires a runloop. However, the runloop is only used to accept the connection: immediately afterwards, the connection handling is dispatched to GCD queues.

Understanding Requests and Responses
====================================

TBD

Advanced Example 1: Implementing HTTP Redirects
===============================================

Here's an example handler that redirects "/" to "/index.html" using the convenience method on 'GCDWebServerResponse' (it sets the HTTP status code and 'Location' header automatically):

```objectivec
[self addHandlerForMethod:@"GET"
                     path:@"/"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
  return [GCDWebServerResponse responseWithRedirect:[NSURL URLWithString:@"index.html" relativeToURL:request.URL] permanent:NO];
    
}];
```

Advanced Example 2: Implementing Forms
======================================

To implement an HTTP form, you need a pair of handlers:
* The GET handler does not expect any body in the HTTP request and therefore uses the 'GCDWebServerRequest' class. The handler generates a response containing a simple HTML form.
* The POST handler expects the form values to be in the body of the HTTP request and percent-encoded. Fortunately, GCDWebServer provides the request class 'GCDWebServerURLEncodedFormRequest' which can automatically parse such bodies. The handler simply echoes back the value from the user submitted form.

```objectivec
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
```
