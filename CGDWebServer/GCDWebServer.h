

#import "GCDWebServerRequest.h"
#import "GCDWebServerResponse.h"

typedef GCDWebServerResponse *(^GCDWebServerProcessBlock)(GCDWebServerRequest * request);
typedef GCDWebServerRequest  *(^GCDWebServerMatchBlock  )(           NSString * requestMethod,
																								NSURL * requestURL,
																					  NSDictionary * requestHeaders,
																							NSString * urlPath,
																					  NSDictionary * urlQuery);
@interface 							GCDWebServer : NSObject 	{
@private							 NSMutableArray * _handlers;
									 	  NSUInteger   _port;
								 dispatch_source_t   _source;
								   CFNetServiceRef   _service;	}

@property(readonly,getter=isRunning)  BOOL   running;
@property(readonly) 				  NSUInteger   port;

- (void) stop;		- (BOOL) start;  // Default is 8080 port and computer name
- (void) removeAllHandlers;
// Pass nil name to disable Bonjour or empty string to use computer name
- (BOOL) startWithPort:(NSUInteger)port bonjourName:(NSString*)name;

- (void) addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock
							processBlock:(GCDWebServerProcessBlock)processBlock;

#pragma mark - Subclassing
+     (Class) connectionClass;
+ (NSString*) serverName;  // Default is class name

#pragma mark -  Extensions
// Starts then automatically stops on SIGINT i.e. Ctrl-C (use on main thread only)
- (BOOL)	runWithPort:(NSUInteger)port;

#pragma mark - Handlers

- (void) addDefaultHandlerForMethod:(NSString*)method
						     requestClass:(Class)class
							  processBlock:(GCDWebServerProcessBlock)block;

- (void) addHandlerForBasePath:(NSString*)basePath 		// Base path is recursive and case-sensitive
						   localPath:(NSString*)localPath
					  indexFilename:(NSString*)indexFilename
					       cacheAge:(NSUInteger)cacheAge;

- (void) addHandlerForMethod:(NSString*)method				// Path is case-insensitive
							   path:(NSString*)path
					 requestClass:(Class)class
					 processBlock:(GCDWebServerProcessBlock)block;

- (void) addHandlerForMethod:(NSString*)method				 // Regular expression is case-insensitive
						 pathRegex:(NSString*)regex
					 requestClass:(Class)class
					 processBlock:(GCDWebServerProcessBlock)block;
@end
