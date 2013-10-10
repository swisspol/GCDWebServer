

#import "GCDWebServerRequest.h"
#import "GCDWebServerResponse.h"


typedef GCDWebServerResponse *(^GCDWebServerProcessBlock)(GCDWebServerRequest * request);
typedef GCDWebServerRequest  *(^GCDWebServerMatchBlock  )(           NSString * requestMethod,
																								NSURL * requestURL,
																					  NSDictionary * requestHeaders,
																							NSString * urlPath,
																					  NSDictionary * urlQuery);
@interface 			   GCDWebServerHandler : NSObject
@property(copy)   GCDWebServerMatchBlock   matchBlock;
@property(copy) GCDWebServerProcessBlock   processBlock;
- (id) initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock
			    processBlock:(GCDWebServerProcessBlock)processBlock;
@end

@interface 							GCDWebServer : NSObject 	{
@private						 dispatch_source_t   _source;
								   CFNetServiceRef   _service;	}

@property(readonly,getter=isRunning)  BOOL   running;
@property(readonly) 				  NSUInteger   port;
@property(nonatomic) 		 NSMutableArray * handlers;

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


// Define __GCDWEBSERVER_LOGGING_HEADER__ as a preprocessor constant to
//														redirect GCDWebServer logging to your own system

#import "GCDWebServerConnection.h"
#ifdef 	__GCDWEBSERVER_LOGGING_HEADER__
#import 	__GCDWEBSERVER_LOGGING_HEADER__
#else
static inline void __LogMessage(long level, NSString* format, ...) {
  static const char* levelNames[] = {"DEBUG", "VERBOSE", "INFO", "WARNING", "ERROR", "EXCEPTION"};
  static long minLevel = -1;
  if (minLevel < 0) {  const char* logLevel = getenv("logLevel"); minLevel = logLevel ? atoi(logLevel) : 0; }
  if (level >= minLevel) {   va_list arguments;   va_start(arguments, format);
    NSString* message = [NSString.alloc initWithFormat:format arguments:arguments];
    va_end(arguments);
    printf("[%s] %s\n", levelNames[level], message.UTF8String); 
  }
}

#define LOG_VERBOSE(...) 					__LogMessage(1, __VA_ARGS__)
#define LOG_INFO(...) 						__LogMessage(2, __VA_ARGS__)
#define LOG_WARNING(...) 					__LogMessage(3, __VA_ARGS__)
#define LOG_ERROR(...) 						__LogMessage(4, __VA_ARGS__)
#define LOG_EXCEPTION(__EXCEPTION__) 	__LogMessage(5, @"%@", __EXCEPTION__)

#ifdef NDEBUG
#define DCHECK(__CONDITION__)
#define DNOT_REACHED()
#define LOG_DEBUG(...)
#else
#define DCHECK(__CONDITION__) do { if (!(__CONDITION__)) { abort(); } } while (0)
#define DNOT_REACHED() 			abort()
#define LOG_DEBUG(...) 			__LogMessage(0, __VA_ARGS__)
#endif
#endif

#define kGCDWebServerDefaultMimeType @"application/octet-stream"
#define kGCDWebServerGCDQueue dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

#ifdef __cplusplus
extern "C" {
#endif
NSString* GCDWebServerGetMimeTypeForExtension(NSString* extension);
NSString* GCDWebServerUnescapeURLString		(NSString* string);
NSDictionary* GCDWebServerParseURLEncodedForm(NSString* form);

#ifdef __cplusplus
}
#endif

