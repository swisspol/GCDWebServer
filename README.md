GCDWebServer
============

GCDWebServer is a lightweight GCD based HTTP 1.1 server for Mac & iOS apps written from scratch with the following goals in mind:
* Entirely built with an event-driven design using [Grand Central Dispatch](http://en.wikipedia.org/wiki/Grand_Central_Dispatch) for maximum performance and concurrency
* Well designed API for easy integration and customization
* Minimal number of source files and no dependencies on third-party source code
* Support for streaming large HTTP bodies for requests and responses to minimize memory usage
* Built-in parser for web forms submitted using "application/x-www-form-urlencoded" or "multipart/form-data"
* Available under a friendly [New BSD License](../master/LICENSE)

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

Implementing Handlers
=====================

GCDWebServer relies on "handlers" to process incoming web requests and generating responses. Handlers are implemented with GCD blocks which makes it very easy to provide your owns. However, they are executed on arbitrary threads within GCD so special attention must be paid to thread-safety.

Handlers require 2 GCD blocks:
* The 'GCDWebServerMatchBlock' is called on every handler added to the 'GCDWebServer' instance whenever a web request has started (i.e. HTTP headers have been received). It is passed the basic info for the web request (HTTP method, URL, headers...) and must decide if it wants to handle it or not. If yes, it must return a 'GCDWebServerRequest' instance which will be used to read (and optionally parse) the web request HTTP body. Otherwise, it simply returns nil. GCDWebServer provides several subclasses of 'GCDWebServerRequest' to handle common cases like storing the body in memory or to a file on disk. See [GCDWebServerRequest.h](../master/CGDWebServer/GCDWebServerRequest.h) for the full list.
* The 'GCDWebServerProcessBlock' is called after the web request has been fully received and is passed the 'GCDWebServerRequest' instance created at the previous step. It must return a 'GCDWebServerResponse' instance which will be used to send the reponse HTTP headers and body. GCDWebServer provides several subclasses of 'GCDWebServerResponse' to handle common cases like HTML text in memory or streaming a file from disk. See [GCDWebServerResponse.h](../master/CGDWebServer/GCDWebServerResponse.h) for the full list.

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

Advanced Example 3: WiFi Downloads and Uploads in iOS App
=========================================================

GCDWebServer was originally written for the [ComicFlow](http://itunes.apple.com/us/app/comicflow/id409290355?mt=8) comic reader app for iPad. It uses it to provide a web server for people to upload and download comic files directly over WiFi.

ComicFlow is [entirely open-source](https://code.google.com/p/comicflow/) and you can see how it uses GCDWebServer in the [AppDelegate.m](https://code.google.com/p/comicflow/source/browse/Classes/AppDelegate.m) file.
