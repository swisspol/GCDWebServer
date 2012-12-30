GCDWebServer
============

A lightweight GCD based HTTP 1.1 server for Mac & iOS apps written from scratch with the following goals in mind:
* Entirely built on [Grand Central Dispatch](http://en.wikipedia.org/wiki/Grand_Central_Dispatch) for best performance and no-hassle multithreading
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

Example 1: Hello World
======================

A simple HTTP server that runs on port 8080 and returns a "Hello World" HTML page to any request:

```objectivec
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
```
