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

#import "GCDWebServerRequest.h"
#import "GCDWebServerResponse.h"

/**
 *  Log levels used by GCDWebServer.
 *
 *  @warning kGCDWebServerLogLevel_Debug is only available if "NDEBUG" is not
 *  defined when building.
 */
typedef NS_ENUM(int, GCDWebServerLogLevel) {
  kGCDWebServerLogLevel_Debug = 0,
  kGCDWebServerLogLevel_Verbose,
  kGCDWebServerLogLevel_Info,
  kGCDWebServerLogLevel_Warning,
  kGCDWebServerLogLevel_Error,
  kGCDWebServerLogLevel_Exception,
};

/**
 *  The GCDWebServerMatchBlock is called for every handler added to the
 *  GCDWebServer whenever a new HTTP request has started (i.e. HTTP headers have
 *  been received). The block is passed the basic info for the request (HTTP method,
 *  URL, headers...) and must decide if it wants to handle it or not.
 *
 *  If the handler can handle the request, the block must return a new
 *  GCDWebServerRequest instance created with the same basic info.
 *  Otherwise, it simply returns nil.
 */
typedef GCDWebServerRequest* (^GCDWebServerMatchBlock)(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery);

/**
 *  The GCDWebServerProcessBlock is called after the HTTP request has been fully
 *  received (i.e. the entire HTTP body has been read). The block is passed the
 *  GCDWebServerRequest created at the previous step by the GCDWebServerMatchBlock.
 *
 *  The block must return a GCDWebServerResponse or nil on error, which will
 *  result in a 500 HTTP status code returned to the client. It's however
 *  recommended to return a GCDWebServerErrorResponse on error so more useful
 *  information can be returned to the client.
 */
typedef GCDWebServerResponse* (^GCDWebServerProcessBlock)(GCDWebServerRequest* request);

/**
 *  The port used by the GCDWebServer (NSNumber / NSUInteger).
 *
 *  The default value is 0 i.e. let the OS pick a random port.
 */
extern NSString* const GCDWebServerOption_Port;

/**
 *  The Bonjour name used by the GCDWebServer (NSString).
 *
 *  The default value is an empty string i.e. use the computer / device name.
 */
extern NSString* const GCDWebServerOption_BonjourName;

/**
 *  The maximum number of incoming HTTP requests that can be queued waiting to
 *  be handled before new ones are dropped (NSNumber / NSUInteger).
 *
 *  The default value is 16.
 */
extern NSString* const GCDWebServerOption_MaxPendingConnections;

/**
 *  The value for "Server" HTTP header used by the GCDWebServer (NSString).
 *
 *  The default value is the GCDWebServer class name.
 */
extern NSString* const GCDWebServerOption_ServerName;

/**
 *  The authentication method used by the GCDWebServer
 *  (one of "GCDWebServerAuthenticationMethod_...").
 *
 *  The default value is nil i.e. authentication is disabled.
 */
extern NSString* const GCDWebServerOption_AuthenticationMethod;

/**
 *  The authentication realm used by the GCDWebServer (NSString).
 *
 *  The default value is the same as the GCDWebServerOption_ServerName option.
 */
extern NSString* const GCDWebServerOption_AuthenticationRealm;

/**
 *  The authentication accounts used by the GCDWebServer
 *  (NSDictionary of username / password pairs).
 *
 *  The default value is nil i.e. no accounts.
 */
extern NSString* const GCDWebServerOption_AuthenticationAccounts;

/**
 *  The class used by the GCDWebServer when instantiating GCDWebServerConnection
 *  (subclass of GCDWebServerConnection).
 *
 *  The default value is the GCDWebServerConnection class.
 */
extern NSString* const GCDWebServerOption_ConnectionClass;

/**
 *  Allow the GCDWebServer to pretend "HEAD" requests are actually "GET" ones
 *  and automatically discard the HTTP body of the response (NSNumber / BOOL).
 *
 *  The default value is YES.
 */
extern NSString* const GCDWebServerOption_AutomaticallyMapHEADToGET;

/**
 *  The interval expressed in seconds used by the GCDWebServer to decide how to
 *  coalesce calls to -webServerDidConnect: and -webServerDidDisconnect:
 *  (NSNumber / double). Coalescing will be disabled if the interval is <= 0.0.
 *
 *  The default value is 1.0 second.
 */
extern NSString* const GCDWebServerOption_ConnectedStateCoalescingInterval;

#if TARGET_OS_IPHONE

/**
 *  Enables the GCDWebServer to automatically suspend itself (as if -stop was
 *  called) when the iOS app goes into the background and the last
 *  GCDWebServerConnection is closed, then resume itself (as if -start was called)
 *  when the iOS app comes back to the foreground (NSNumber / BOOL).
 *
 *  See the README.md file for more information about this option.
 *
 *  The default value is YES.
 *
 *  @warning The running property will be NO while the GCDWebServer is suspended.
 */
extern NSString* const GCDWebServerOption_AutomaticallySuspendInBackground;

#endif

/**
 *  HTTP Basic Authentication scheme (see https://tools.ietf.org/html/rfc2617).
 *
 *  @warning Use of this authentication scheme is not recommended as the
 *  passwords are sent in clear.
 */
extern NSString* const GCDWebServerAuthenticationMethod_Basic;

/**
 *  HTTP Digest Access Authentication scheme (see https://tools.ietf.org/html/rfc2617).
 */
extern NSString* const GCDWebServerAuthenticationMethod_DigestAccess;

@class GCDWebServer;

/**
 *  Delegate methods for GCDWebServer.
 *
 *  @warning These methods are always called on the main thread in a serialized way.
 */
@protocol GCDWebServerDelegate <NSObject>
@optional

/**
 *  This method is called after the server has successfully started.
 */
- (void)webServerDidStart:(GCDWebServer*)server;

/**
 *  This method is called after the Bonjour registration for the server has
 *  successfully completed.
 */
- (void)webServerDidCompleteBonjourRegistration:(GCDWebServer*)server;

/**
 *  This method is called when the first GCDWebServerConnection is opened by the
 *  server to serve a series of HTTP requests.
 *
 *  A series of HTTP requests is considered ongoing as long as new HTTP requests
 *  keep coming (and new GCDWebServerConnection instances keep being opened),
 *  until before the last HTTP request has been responded to (and the
 *  corresponding last GCDWebServerConnection closed).
 */
- (void)webServerDidConnect:(GCDWebServer*)server;

/**
 *  This method is called when the last GCDWebServerConnection is closed after
 *  the server has served a series of HTTP requests.
 *
 *  The GCDWebServerOption_ConnectedStateCoalescingInterval option can be used
 *  to have the server wait some extra delay before considering that the series
 *  of HTTP requests has ended (in case there some latency between consecutive
 *  requests). This effectively coalesces the calls to -webServerDidConnect:
 *  and -webServerDidDisconnect:.
 */
- (void)webServerDidDisconnect:(GCDWebServer*)server;

/**
 *  This method is called after the server has stopped.
 */
- (void)webServerDidStop:(GCDWebServer*)server;

@end

/**
 *  The GCDWebServer class listens for incoming HTTP requests on a given port,
 *  then passes each one to a "handler" capable of generating an HTTP response
 *  for it, which is then sent back to the client.
 *
 *  See the README.md file for more information about the architecture of GCDWebServer.
 */
@interface GCDWebServer : NSObject

/**
 *  Sets the delegate for the server.
 */
@property(nonatomic, assign) id<GCDWebServerDelegate> delegate;

/**
 *  Returns YES if the server is currently running.
 */
@property(nonatomic, readonly, getter=isRunning) BOOL running;

/**
 *  Returns the port used by the server.
 *
 *  @warning This property is only valid if the server is running.
 */
@property(nonatomic, readonly) NSUInteger port;

/**
 *  Returns the Bonjour name used by the server.
 *
 *  @warning This property is only valid if the server is running and Bonjour
 *  registration has successfully completed, which can take up to a few seconds.
 */
@property(nonatomic, readonly) NSString* bonjourName;

/**
 *  This method is the designated initializer for the class.
 */
- (instancetype)init;

/**
 *  Adds a handler to the server to handle incoming HTTP requests.
 *
 *  Handlers are called in a LIFO queue, so if multiple handlers can potentially
 *  respond to a given request, the latest added one wins.
 *
 *  @warning Addling handlers while the server is running is not allowed.
 */
- (void)addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock;

/**
 *  Removes all handlers previously added to the server.
 *
 *  @warning Removing handlers while the server is running is not allowed.
 */
- (void)removeAllHandlers;

/**
 *  Starts the server with explicit options. This method is the designated way
 *  to start the server.
 *
 *  Returns NO if the server failed to start.
 */
- (BOOL)startWithOptions:(NSDictionary*)options;

/**
 *  Stops the server and prevents it to accepts new HTTP requests.
 *
 *  @warning Stopping the server does not abort GCDWebServerConnection instances
 *  currently handling already received HTTP requests. These connections will
 *  continue to execute normally until completion.
 */
- (void)stop;

@end

@interface GCDWebServer (Extensions)

/**
 *  Returns the server's URL.
 *
 *  @warning This property is only valid if the server is running.
 */
@property(nonatomic, readonly) NSURL* serverURL;

/**
 *  Returns the server's Bonjour URL.
 *
 *  @warning This property is only valid if the server is running and Bonjour
 *  registration has successfully completed, which can take up to a few seconds.
 */
@property(nonatomic, readonly) NSURL* bonjourServerURL;

/**
 *  Starts the server on port 8080 (OS X & iOS Simulator) or port 80 (iOS)
 *  using the computer / device name for as the Bonjour name.
 *
 *  Returns NO if the server failed to start.
 */
- (BOOL)start;

/**
 *  Starts the server on a given port and with a specific Bonjour name.
 *  Pass a nil Bonjour name to disable Bonjour entirely or an empty string to
 *  use the computer / device name.
 *
 *  Returns NO if the server failed to start.
 */
- (BOOL)startWithPort:(NSUInteger)port bonjourName:(NSString*)name;

#if !TARGET_OS_IPHONE

/**
 *  Runs the server synchronously using -startWithPort:bonjourName: until a
 *  SIGINT signal is received i.e. Ctrl-C. This method is intended to be used
 *  by command line tools.
 *
 *  Returns NO if the server failed to start.
 *
 *  @warning This method must be used from the main thread only.
 */
- (BOOL)runWithPort:(NSUInteger)port bonjourName:(NSString*)name;

/**
 *  Runs the server synchronously using -startWithOptions: until a SIGINT signal
 *  is received i.e. Ctrl-C. This method is intended to be used by command line
 *  tools.
 *
 *  Returns NO if the server failed to start.
 *
 *  @warning This method must be used from the main thread only.
 */
- (BOOL)runWithOptions:(NSDictionary*)options;

#endif

@end

@interface GCDWebServer (Handlers)

/**
 *  Adds a default handler to the server to handle all incoming HTTP requests
 *  with a given HTTP method.
 */
- (void)addDefaultHandlerForMethod:(NSString*)method requestClass:(Class)aClass processBlock:(GCDWebServerProcessBlock)block;

/**
 *  Adds a handler to the server to handle incoming HTTP requests with a given
 *  HTTP method and a specific case-insensitive path.
 */
- (void)addHandlerForMethod:(NSString*)method path:(NSString*)path requestClass:(Class)aClass processBlock:(GCDWebServerProcessBlock)block;

/**
 *  Adds a handler to the server to handle incoming HTTP requests with a given
 *  HTTP method and a path matching a case-insensitive regular expression.
 */
- (void)addHandlerForMethod:(NSString*)method pathRegex:(NSString*)regex requestClass:(Class)aClass processBlock:(GCDWebServerProcessBlock)block;

@end

@interface GCDWebServer (GETHandlers)

/**
 *  Adds a handler to the server to respond to incoming "GET" HTTP requests
 *  with a specific case-insensitive path with in-memory data.
 */
- (void)addGETHandlerForPath:(NSString*)path staticData:(NSData*)staticData contentType:(NSString*)contentType cacheAge:(NSUInteger)cacheAge;

/**
 *  Adds a handler to the server to respond to incoming "GET" HTTP requests
 *  with a specific case-insensitive path with a file.
 */
- (void)addGETHandlerForPath:(NSString*)path filePath:(NSString*)filePath isAttachment:(BOOL)isAttachment cacheAge:(NSUInteger)cacheAge allowRangeRequests:(BOOL)allowRangeRequests;

/**
 *  Adds a handler to the server to respond to incoming "GET" HTTP requests
 *  with a case-insensitive path inside a base path with the corresponding file
 *  inside a local directory. If no local file matches the request path, a 401
 *  HTTP status code is returned to the client.
 *
 *  The "indexFilename" argument allows to specify an "index" file name to use
 *  when the request path corresponds to a directory.
 */
- (void)addGETHandlerForBasePath:(NSString*)basePath directoryPath:(NSString*)directoryPath indexFilename:(NSString*)indexFilename cacheAge:(NSUInteger)cacheAge allowRangeRequests:(BOOL)allowRangeRequests;

@end

@interface GCDWebServer (Logging)

#ifndef __GCDWEBSERVER_LOGGING_HEADER__

/**
 *  Sets the current log level below which logged messages are discarded.
 *
 *  The default level is either DEBUG or INFO if "NDEBUG" is defined at build-time.
 *  It can also be set at runtime with the "logLevel" environment variable.
 */
+ (void)setLogLevel:(GCDWebServerLogLevel)level;

#endif

/**
 *  Logs a message with the kGCDWebServerLogLevel_Verbose level.
 */
- (void)logVerbose:(NSString*)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 *  Logs a message with the kGCDWebServerLogLevel_Info level.
 */
- (void)logInfo:(NSString*)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 *  Logs a message with the kGCDWebServerLogLevel_Warning level.
 */
- (void)logWarning:(NSString*)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 *  Logs a message with the kGCDWebServerLogLevel_Error level.
 */
- (void)logError:(NSString*)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 *  Logs an exception with the kGCDWebServerLogLevel_Exception level.
 */
- (void)logException:(NSException*)exception;

@end

#ifdef __GCDWEBSERVER_ENABLE_TESTING__

@interface GCDWebServer (Testing)

/**
 *  Activates recording of HTTP requests and responses which create files in the
 *  current directory containing the raw data for all requests and responses.
 *
 *  @warning The current directory must not contain any prior recording files.
 */
@property(nonatomic, getter=isRecordingEnabled) BOOL recordingEnabled;

/**
 *  Runs tests by playing back pre-recorded HTTP requests in the given directory
 *  and comparing the generated responses with the pre-recorded ones.
 *
 *  Returns the number of failed tests or -1 if server failed to start.
 */
- (NSInteger)runTestsWithOptions:(NSDictionary*)options inDirectory:(NSString*)path;

@end

#endif
