Overview
========

GCDWebServer is a lightweight GCD based HTTP 1.1 server designed to be embedded in Mac & iOS apps. It was written from scratch with the following goals in mind:
* Entirely built with an event-driven design using [Grand Central Dispatch](http://en.wikipedia.org/wiki/Grand_Central_Dispatch) for maximum performance and concurrency
* Well designed API for easy integration and customization
* Support for streaming large HTTP bodies for requests and responses to minimize memory usage
* Built-in parser for web forms submitted using "application/x-www-form-urlencoded" or "multipart/form-data" encodings (including file uploads)
* Minimal number of source files and no dependencies on third-party source code
* Available under a friendly [New BSD License](GCDWebServer/blob/master/LICENSE)

What's not available out of the box but can be implemented on top of the API:
* Authentication like Basic Authentication
* Web forms submitted using "multipart/mixed"

What's not supported (but not really required from an embedded HTTP server):
* Keep-alive connections
* HTTPS

Requirements:
* OS X 10.7 or later
* iOS 5.0 or later

Hello World
===========

This code snippet shows how to implement a custom HTTP server that runs on port 8080 and returns a "Hello World" HTML page to any request &mdash; Because GCDWebServer uses GCD blocks to handle requests, no subclassing or delegates are needed:

```objectivec
#import "GCDWebServer.h"

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    
    // Create server
    GCDWebServer* webServer = [[GCDWebServer alloc] init];
    
    // Add a handler to respond to requests on any URL
    [webServer addDefaultHandlerForMethod:@"GET"
                             requestClass:[GCDWebServerRequest class]
                             processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      
      return [GCDWebServerDataResponse responseWithHTML:@"<html><body><p>Hello World</p></body></html>"];
      
    }];
    
    // Use convenience method that runs server on port 8080 until SIGINT received
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

Finally you start the server on a given port.

Understanding GCDWebServer Architecture
=======================================

GCDWebServer is made of only 4 core classes:
* 'GCDWebServer' manages the socket that listens for new HTTP connections and the list of handlers used by the server.
* 'GCDWebServerConnection' is instantiated by 'GCDWebServer' to handle each new HTTP connection. Each instance stays alive until the connection is closed. You cannot use this class directly, but it is exposed so you can subclass it to override some hooks.
* 'GCDWebServerRequest' is created by the 'GCDWebServerConnection' instance after HTTP headers have been received. It wraps the request and handles the HTTP body if any. GCDWebServer comes with several subclasses of 'GCDWebServerRequest' to handle common cases like storing the body in memory or stream it to a file on disk. See [GCDWebServerRequest.h](GCDWebServer/blob/master/CGDWebServer/GCDWebServerRequest.h) for the full list.
* 'GCDWebServerResponse' is created by the request handler and wraps the response HTTP headers and optional body. GCDWebServer provides several subclasses of 'GCDWebServerResponse' to handle common cases like HTML text in memory or streaming a file from disk. See [GCDWebServerResponse.h](GCDWebServer/blob/master/CGDWebServer/GCDWebServerResponse.h) for the full list.

Implementing Handlers
=====================

GCDWebServer relies on "handlers" to process incoming web requests and generating responses. Handlers are implemented with GCD blocks which makes it very easy to provide your owns. However, they are executed on arbitrary threads within GCD so __special attention must be paid to thread-safety and re-entrancy__.

Handlers require 2 GCD blocks:
* The 'GCDWebServerMatchBlock' is called on every handler added to the 'GCDWebServer' instance whenever a web request has started (i.e. HTTP headers have been received). It is passed the basic info for the web request (HTTP method, URL, headers...) and must decide if it wants to handle it or not. If yes, it must return a 'GCDWebServerRequest' instance (see above). Otherwise, it simply returns nil.
* The 'GCDWebServerProcessBlock' is called after the web request has been fully received and is passed the 'GCDWebServerRequest' instance created at the previous step. It must return a 'GCDWebServerResponse' instance (see above) or nil on error.

Note that most methods on 'GCDWebServer' to add handlers only require the 'GCDWebServerProcessBlock' as they already provide a built-in 'GCDWebServerMatchBlock' e.g. to match a URL path with a Regex.

Advanced Example 1: Implementing HTTP Redirects
===============================================

Here's an example handler that redirects "/" to "/index.html" using the convenience method on 'GCDWebServerResponse' (it sets the HTTP status code and 'Location' header automatically):

```objectivec
[self addHandlerForMethod:@"GET"
                     path:@"/"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
  return [GCDWebServerResponse responseWithRedirect:[NSURL URLWithString:@"index.html" relativeToURL:request.URL]
                                          permanent:NO];
    
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

Advanced Example 3: Serving a Dynamic Website
=============================================

GCDWebServer provides an extension to the 'GCDWebServerDataResponse' class that can return HTML content generated from a template and a set of variables (using the format '%variable%'). It is a very basic template system and is really intended as a starting point to building more advanced template systems by subclassing 'GCDWebServerResponse'.

Assuming you have a website directory in your app containing HTML template files along with the corresponding CSS, scripts and images, it's pretty easy to turn it into a dynamic website:

```objectivec
// Get the path to the website directory
NSString* websitePath = [[NSBundle mainBundle] pathForResource:@"Website" ofType:nil];

// Add a default handler to serve static files (i.e. anything other than HTML files)
[self addHandlerForBasePath:@"/" localPath:websitePath indexFilename:nil cacheAge:3600];

// Add an override handler for all requests to "*.html" URLs to do the special HTML templatization
[self addHandlerForMethod:@"GET"
                pathRegex:@"/.*\.html"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    NSDictionary* variables = [NSDictionary dictionaryWithObjectsAndKeys:@"value", @"variable", nil];
    return [GCDWebServerDataResponse responseWithHTMLTemplate:[websitePath stringByAppendingPathComponent:request.path]
                                                    variables:variables];
    
}];

// Add an override handler to redirect "/" URL to "/index.html"
[self addHandlerForMethod:@"GET"
                     path:@"/"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    return [GCDWebServerResponse responseWithRedirect:[NSURL URLWithString:@"index.html" relativeToURL:request.URL]
                                            permanent:NO];
    
];

```

Final Example: File Downloads and Uploads From iOS App
======================================================

GCDWebServer was originally written for the [ComicFlow](http://itunes.apple.com/us/app/comicflow/id409290355?mt=8) comic reader app for iPad. It uses it to provide a web server for people to upload and download comic files directly over WiFi to and from the app.

ComicFlow is [entirely open-source](https://code.google.com/p/comicflow/) and you can see how it uses GCDWebServer in the [WebServer.m](http://code.google.com/p/comicflow/source/browse/Classes/WebServer.m) file.
