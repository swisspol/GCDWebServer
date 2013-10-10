
#import "GCDWebServer.h"

@interface GCDWebServerConnection : NSObject {
@private     GCDWebServerResponse * _response;
  	           GCDWebServerRequest * _request;
  							GCDWebServer * _server;
									NSData * _address;
  				 CFSocketNativeHandle   _socket;
  							  NSUInteger   _bytesRead,
							  					_bytesWritten;
					   CFHTTPMessageRef  _requestMessage,
												_responseMessage;		}

@property(readonly)   GCDWebServer * server;
@property(readonly)         NSData * address;  			// struct sockaddr
@property(readonly) 	   NSUInteger   totalBytesRead,
												 totalBytesWritten;
#pragma mark - Subclassing

- (void) open;
- (void) close;
- (GCDWebServerResponse*)processRequest:(GCDWebServerRequest*)request
									   withBlock:(GCDWebServerProcessBlock)block;

@end
