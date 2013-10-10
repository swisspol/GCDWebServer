// Define __GCDWEBSERVER_LOGGING_HEADER__ as a preprocessor constant to
//														redirect GCDWebServer logging to your own system

#import "GCDWebServerConnection.h"
#ifdef __GCDWEBSERVER_LOGGING_HEADER__
#import __GCDWEBSERVER_LOGGING_HEADER__
#else
static inline void __LogMessage(long level, NSString* format, ...) {
  static const char* levelNames[] = {"DEBUG", "VERBOSE", "INFO", "WARNING", "ERROR", "EXCEPTION"};
  static long minLevel = -1;
  if (minLevel < 0) {  const char* logLevel = getenv("logLevel"); minLevel = logLevel ? atoi(logLevel) : 0; }
  if (level >= minLevel) {   va_list arguments;   va_start(arguments, format);
    NSString* message = [NSString.alloc initWithFormat:format arguments:arguments];
    va_end(arguments);
    printf("[%s] %s\n", levelNames[level], message.UTF8String); [message release];
  }
}

#define LOG_VERBOSE(...) __LogMessage(1, __VA_ARGS__)
#define LOG_INFO(...) __LogMessage(2, __VA_ARGS__)
#define LOG_WARNING(...) __LogMessage(3, __VA_ARGS__)
#define LOG_ERROR(...) __LogMessage(4, __VA_ARGS__)
#define LOG_EXCEPTION(__EXCEPTION__) __LogMessage(5, @"%@", __EXCEPTION__)

#ifdef NDEBUG

#define DCHECK(__CONDITION__)
#define DNOT_REACHED()
#define LOG_DEBUG(...)

#else

#define DCHECK(__CONDITION__) \
  do { \
    if (!(__CONDITION__)) { \
      abort(); \
    } \
  } while (0)
#define DNOT_REACHED() abort()
#define LOG_DEBUG(...) __LogMessage(0, __VA_ARGS__)

#endif

#endif

#define kGCDWebServerDefaultMimeType @"application/octet-stream"
#define kGCDWebServerGCDQueue dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

#ifdef __cplusplus
extern "C" {
#endif

NSString* GCDWebServerGetMimeTypeForExtension(NSString* extension);
NSString* GCDWebServerUnescapeURLString(NSString* string);
NSDictionary* GCDWebServerParseURLEncodedForm(NSString* form);

#ifdef __cplusplus
}
#endif

@interface GCDWebServerConnection ()
- (id)initWithServer:(GCDWebServer*)server address:(NSData*)address socket:(CFSocketNativeHandle)socket;
@end

@interface GCDWebServer ()
@property(nonatomic, readonly) NSArray* handlers;
@end

@interface GCDWebServerHandler : NSObject {
@private
  GCDWebServerMatchBlock _matchBlock;
  GCDWebServerProcessBlock _processBlock;
}
@property(nonatomic, readonly) GCDWebServerMatchBlock matchBlock;
@property(nonatomic, readonly) GCDWebServerProcessBlock processBlock;
- (id)initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock;
@end
