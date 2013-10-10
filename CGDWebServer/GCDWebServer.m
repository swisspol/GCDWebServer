
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif
#import <netinet/in.h>
#import "GCDWebServer.h"

#define kMaxPendingConnections 16

@interface GCDWebServerConnection ()
- (id)initWithServer:(GCDWebServer*)server address:(NSData*)address socket:(CFSocketNativeHandle)socket;
@end


static BOOL _run;

NSString* GCDWebServerGetMimeTypeForExtension(NSString* extension) {

	static NSDictionary* _overrides = nil; _overrides = _overrides ?: @{@"css":@"text/css"};

	return  extension.length ? _overrides[extension.lowercaseString] :
	(id)CFBridgingRelease(UTTypeCopyPreferredTagWithClass(
													 UTTypeCreatePreferredIdentifierForTag(	kUTTagClassFilenameExtension,
																										(__bridge CFStringRef)extension, NULL),
													 kUTTagClassMIMEType));
}

NSString* GCDWebServerUnescapeURLString(NSString* string) {

	return (id)CFBridgingRelease(CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault,
																							  (CFStringRef)string, CFSTR(""),
																							  kCFStringEncodingUTF8));
}

NSDictionary* GCDWebServerParseURLEncodedForm(NSString* form) {

	NSMutableDictionary* parameters 	= @{}.mutableCopy;
	NSScanner* scanner 					= [NSScanner.alloc initWithString:form];
	[scanner setCharactersToBeSkipped:nil];
	while (1) {
		NSString* key = nil;
		if (![scanner scanUpToString:@"=" intoString:&key] || [scanner isAtEnd])  break;
		[scanner setScanLocation:([scanner scanLocation] + 1)];
		NSString* value = nil;
		if (![scanner scanUpToString:@"&" intoString:&value]) break;

		key 		= [key stringByReplacingOccurrencesOfString:@"+" withString:@" "];
		value 	= [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
		[parameters setObject:GCDWebServerUnescapeURLString(value) forKey:GCDWebServerUnescapeURLString(key)];

		if ([scanner isAtEnd])  break;
		[scanner setScanLocation:([scanner scanLocation] + 1)];
	}
	return parameters;
}

static void _SignalHandler(int signal) {  _run = NO;  printf("\n"); }

@implementation GCDWebServerHandler

@synthesize matchBlock=_matchBlock, processBlock=_processBlock;

- (id)initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock
				processBlock:(GCDWebServerProcessBlock)processBlock {	if (self != super.init) return nil;
_matchBlock = [matchBlock copy];
	_processBlock = [processBlock copy]; 													return self; }


@end

@implementation GCDWebServer



+ (void)initialize {
	[GCDWebServerConnection class];  // Initialize class immediately to make sure it happens on the main thread
}

- (id)init { if (self != super.init) return nil; _handlers = NSMutableArray.new; return self; }

- (void)dealloc {  if (_source) [self stop];    }

- (void)addHandlerWithMatchBlock:(GCDWebServerMatchBlock)matchBlock
						  processBlock:(GCDWebServerProcessBlock)handlerBlock {  DCHECK(_source == NULL);

	[_handlers insertObject:
	 [GCDWebServerHandler.alloc initWithMatchBlock:matchBlock processBlock:handlerBlock] atIndex:0];
}
- (void)removeAllHandlers { DCHECK(_source == NULL); [_handlers removeAllObjects]; }
- (BOOL)start {  return [self startWithPort:8080 bonjourName:@""];
}

static void _NetServiceClientCallBack(CFNetServiceRef service, CFStreamError* error, void* info) {
	@autoreleasepool {  error->error ?
      LOG_ERROR(@"Bonjour error %i (domain %i)", error->error, (int)error->domain) :
      LOG_VERBOSE(@"Registered Bonjour service \"%@\" with type '%@' on port %i", CFNetServiceGetName(service), CFNetServiceGetType(service), CFNetServiceGetPortNumber(service));
	}
}

- (BOOL)startWithPort:(NSUInteger)port bonjourName:(NSString*)name {  DCHECK(_source == NULL);

	int listeningSocket = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (listeningSocket > 0) {
		int yes = 1;
		setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
		setsockopt(listeningSocket, SOL_SOCKET, SO_REUSEPORT, &yes, sizeof(yes));
		struct sockaddr_in addr4;
		bzero(&addr4, sizeof(addr4));
		addr4.sin_len 			= sizeof(addr4);
		addr4.sin_family 		= AF_INET;
		addr4.sin_port 			= htons(port);
		addr4.sin_addr.s_addr 	= htonl(INADDR_ANY);
		if (bind(listeningSocket, (void*)&addr4, sizeof(addr4)) == 0) {
			if (listen(listeningSocket, kMaxPendingConnections) == 0) {
				_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, listeningSocket, 0, kGCDWebServerGCDQueue);
				dispatch_source_set_cancel_handler(_source, ^{	@autoreleasepool {
					close(listeningSocket) != 0 ? LOG_ERROR(@"Failed closing socket (%i): %s", errno, strerror(errno))
					: LOG_DEBUG(@"Closed listening socket");
				}
				});
				dispatch_source_set_event_handler(_source, ^{ @autoreleasepool {
						struct sockaddr addr;
						socklen_t addrlen 		  = sizeof(addr);
						int socket 					  = accept(listeningSocket, &addr, &addrlen);
						if (socket > 0) {	int yes = 1;
							setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));  // Make sure this socket cannot generate SIG_PIPE
							NSData* data = [NSData dataWithBytes:&addr length:addrlen];
							Class connectionClass = [self.class connectionClass];
							//	GCDWebServerConnection* connection =
							[[connectionClass.alloc initWithServer:self address:data socket:socket] self];
							// Connection will automatically retain itself while opened
						} else LOG_ERROR(@"Failed accepting socket (%i): %s", errno, strerror(errno));
					}
				});

				if (port == 0) {  // Determine the actual port we are listening on
					struct sockaddr addr;
					socklen_t    addrlen = sizeof(addr);
					if (getsockname(listeningSocket, &addr, &addrlen) == 0) {
						struct sockaddr_in* sockaddr = (struct sockaddr_in*)&addr;
						_port = ntohs(sockaddr->sin_port);
					} else LOG_ERROR(@"Failed retrieving socket address (%i): %s", errno, strerror(errno));
				} else _port = port;
				if (name) {
					_service = CFNetServiceCreate(kCFAllocatorDefault, CFSTR("local."), CFSTR("_http._tcp"), (__bridge CFStringRef)name, _port);
					if (_service) {
						CFNetServiceClientContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
						CFNetServiceSetClient(_service, _NetServiceClientCallBack, &context);
						CFNetServiceScheduleWithRunLoop(_service, CFRunLoopGetMain(), kCFRunLoopCommonModes);
						CFStreamError error = {0};
						CFNetServiceRegisterWithOptions(_service, 0, &error);
					} else LOG_ERROR(@"Failed creating CFNetService");
				}
				dispatch_resume(_source);
				LOG_VERBOSE(@"%@ started on port %i", [self class], (int)_port);
			} else {
				LOG_ERROR(@"Failed listening on socket (%i): %s", errno, strerror(errno));
				close(listeningSocket);
			}
		} else {
			LOG_ERROR(@"Failed binding socket (%i): %s", errno, strerror(errno));
			close(listeningSocket);
		}
	} else LOG_ERROR(@"Failed creating socket (%i): %s", errno, strerror(errno));
	return (_source);
}

- (BOOL)isRunning { return (_source);	}

- (void)stop { DCHECK(_source != NULL);
	if (_source) {	if (_service) {
			CFNetServiceUnscheduleFromRunLoop(_service, CFRunLoopGetMain(), kCFRunLoopCommonModes);
			CFNetServiceSetClient(_service, NULL, NULL);
			CFRelease(_service);
			_service = NULL;
		}
		dispatch_source_cancel(_source);  // This will close the socket
		dispatch_release(_source);
		_source = NULL;
		LOG_VERBOSE(@"%@ stopped", [self class]);
	}
	_port = 0;
}

#pragma mark - Subclassing

+ (Class)connectionClass { return [GCDWebServerConnection class]; }
+ (NSString*)serverName {	return NSStringFromClass(self);        }

#pragma mark - Extensions

- (BOOL)runWithPort:(NSUInteger)port {	BOOL success = NO;	_run = YES;
	void* handler = signal(SIGINT, _SignalHandler);
	if (handler != SIG_ERR) {
		if ([self startWithPort:port bonjourName:@""]) {
			while (_run) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, true);
			[self stop];
			success = YES;
		}
		signal(SIGINT, handler);
	}
	return success;
}

#pragma mark - Handlers

- (void)addDefaultHandlerForMethod:(NSString*)method
							 requestClass:(Class)class
							 processBlock:(GCDWebServerProcessBlock)block {

	[self addHandlerWithMatchBlock:^GCDWebServerRequest *(	NSString * requestMethod,
																					NSURL * requestURL,
																		  NSDictionary * requestHeaders,
																		      NSString * urlPath,
																		  NSDictionary * urlQuery) {
	return [class.alloc initWithMethod:requestMethod
											  url:requestURL
										 headers:requestHeaders
											 path:urlPath
											query:urlQuery];	} processBlock:block];
}

- (GCDWebServerResponse*)_responseWithContentsOfFile:(NSString*)path {
	return [GCDWebServerFileResponse responseWithFile:path];
}

- (GCDWebServerResponse*)_responseWithContentsOfDirectory:(NSString*)path {
	NSDirectoryEnumerator* enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
	if (enumerator == nil) {
		return nil;
	}
	NSMutableString* html = [NSMutableString string];
	[html appendString:@"<html><body>\n"];
	[html appendString:@"<ul>\n"];
	for (NSString* file in enumerator) {
		if (![file hasPrefix:@"."]) {
			NSString* type = [[enumerator fileAttributes] objectForKey:NSFileType];
			NSString* escapedFile = [file stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
			DCHECK(escapedFile);
			if ([type isEqualToString:NSFileTypeRegular]) {
				[html appendFormat:@"<li><a href=\"%@\">%@</a></li>\n", escapedFile, file];
			} else if ([type isEqualToString:NSFileTypeDirectory]) {
				[html appendFormat:@"<li><a href=\"%@/\">%@/</a></li>\n", escapedFile, file];
			}
		}
		[enumerator skipDescendents];
	}
	[html appendString:@"</ul>\n"];
	[html appendString:@"</body></html>\n"];
	return [GCDWebServerDataResponse responseWithHTML:html];
}

- (void)addHandlerForBasePath:(NSString*)basePath localPath:(NSString*)localPath indexFilename:(NSString*)indexFilename cacheAge:(NSUInteger)cacheAge {
	if ([basePath hasPrefix:@"/"] && [basePath hasSuffix:@"/"]) {
		__weak GCDWebServer *bSelf = self;
		[self addHandlerWithMatchBlock:^GCDWebServerRequest *(NSString* requestMethod, NSURL* requestURL, NSDictionary* requestHeaders, NSString* urlPath, NSDictionary* urlQuery) {

			return ![requestMethod isEqualToString:@"GET"] || ![urlPath hasPrefix:basePath] ? nil :
					  [GCDWebServerRequest.alloc initWithMethod:requestMethod url:requestURL
					  												 headers:requestHeaders path:urlPath
																		query:urlQuery];

		} processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {

			GCDWebServerResponse* response = nil;
			NSString* filePath = [localPath stringByAppendingPathComponent:[request.path substringFromIndex:basePath.length]];
			BOOL isDirectory;
			if ([NSFileManager.defaultManager fileExistsAtPath:filePath isDirectory:&isDirectory]) {
				if (isDirectory) {
					if (indexFilename) {
						NSString* indexPath = [filePath stringByAppendingPathComponent:indexFilename];
						if ([NSFileManager.defaultManager fileExistsAtPath:indexPath isDirectory:&isDirectory] && !isDirectory)
							return [bSelf _responseWithContentsOfFile:indexPath];
					}
						 		response = [bSelf _responseWithContentsOfDirectory:filePath];
				} else 		response = [bSelf _responseWithContentsOfFile:filePath];
			}
			if (response) 	response.cacheControlMaxAge = cacheAge;
			else				response = [GCDWebServerResponse responseWithStatusCode:404];
			return response;
		}];
	} else DNOT_REACHED();
}

- (void)addHandlerForMethod:(NSString*)method 	 path:(NSString*)path
					requestClass:(Class)class processBlock:(GCDWebServerProcessBlock)block {

	if ([path hasPrefix:@"/"] && [class isSubclassOfClass:[GCDWebServerRequest class]]) {
		[self addHandlerWithMatchBlock:^GCDWebServerRequest *(	NSString * requestMethod,
																						NSURL * requestURL,
																			  NSDictionary * requestHeaders,
																			      NSString * urlPath,
																			  NSDictionary * urlQuery) {

			return ![requestMethod isEqualToString:method] ||
					  [urlPath caseInsensitiveCompare:path] != NSOrderedSame ? nil
					: [class.alloc initWithMethod:requestMethod url:requestURL headers:requestHeaders path:urlPath query:urlQuery];

		} processBlock:block];
	} else DNOT_REACHED();
}
- (void)addHandlerForMethod:(NSString*)method pathRegex:(NSString*)regex
				   requestClass:(Class)class   processBlock:(GCDWebServerProcessBlock)block {

	NSRegularExpression* expression = [NSRegularExpression regularExpressionWithPattern:regex
												  options:NSRegularExpressionCaseInsensitive error:NULL];

	if (expression && [class isSubclassOfClass:GCDWebServerRequest.class]) {
		[self addHandlerWithMatchBlock:^GCDWebServerRequest *(	NSString * requestMethod,
																					   NSURL * requestURL,
																			  NSDictionary * requestHeaders,
																			      NSString * urlPath,
																			  NSDictionary * urlQuery) {

			return ![requestMethod isEqualToString:method] ||
					 ![expression firstMatchInString:urlPath options:0 range:NSMakeRange(0, urlPath.length)]
				?   nil
				:    [class.alloc initWithMethod:requestMethod url:requestURL
												  headers:requestHeaders path:urlPath query:urlQuery];

		} processBlock:block];
	} else DNOT_REACHED();
}

@end
