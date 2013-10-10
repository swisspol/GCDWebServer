
#import <Foundation/Foundation.h>

@interface GCDWebServerRequest : NSObject {	@private

									NSURL * _url;
						  NSDictionary * _headers,
											* _query;
								NSString * _method,
											* _path,
											* _type;
							 NSUInteger   _length;		}

@property(readonly)     NSString * method,
										   * path,
											* contentType;  	// Automa. parsed from headers (nil if request has no body)
@property(readonly) NSDictionary * headers,
											* query; 		 	// May be nil;
@property(readonly) 			NSURL * URL;
@property(readonly) 	 NSUInteger   contentLength;  // Automatically parsed from headers
@property(readonly) 			 BOOL   hasBody;  		// Convenience method

- (id)initWithMethod:(NSString*)method 	   url:(NSURL*)url
				 headers:(NSDictionary*)headers path:(NSString*)path
														 query:(NSDictionary*)query;
#pragma mark - Subclassing

- (NSInteger) write:(const void*)buffer maxLength:(NSUInteger)length;  	// Implementation required
-      (BOOL) open;  																	// Implementation required
- 		 (BOOL) close; 																	// Implementation required
@end

@interface 	  	GCDWebServerDataRequest : GCDWebServerRequest {	@private  NSMutableData* _data; }
@property(readonly) 				  NSData * data;  // Only valid after open / write / close sequence
@end

@interface 		GCDWebServerFileRequest : GCDWebServerRequest { @private  NSString* _filePath;  int _file; }
@property(readonly)			   NSString * filePath;  // Only valid after open / write / close sequence
@end

@interface GCDWebServerURLEncodedFormRequest : GCDWebServerDataRequest { @private  NSDictionary* _arguments; }
@property(readonly)			     NSDictionary * arguments;  // Only valid after open / write / close sequence
+ (NSString*)mimeType;
@end

@interface 		  GCDWebServerMultiPart : NSObject { @private NSString* _contentType;  NSString* _mimeType; }
@property(readonly) 			   NSString * contentType,  // May be nil
													* mimeType;  // Defaults to "text/plain" per specifications if undefined
@end

@interface GCDWebServerMultiPartArgument : GCDWebServerMultiPart { @private  NSData* _data; NSString* _string; }
@property(readonly) 					 NSData * data;
@property(readonly) 				  NSString * string;  // May be nil (only valid for text mime types
@end

@interface     GCDWebServerMultiPartFile : GCDWebServerMultiPart { @private NSString * _fileName;
																									 NSString * _temporaryPath;	}
@property(readonly) 				  NSString * fileName,  // May be nil
												     * temporaryPath;
@end

@interface GCDWebServerMultiPartFormRequest : GCDWebServerRequest {	@private
  								NSMutableDictionary * _arguments,
														  * _files;
												 NSData * _boundary;
									   NSMutableData * _parserData;
										     NSString * _controlName,
														  * _fileName,
														  * _contentType,
														  * _tmpPath;
											NSUInteger   _parserState;
													 int   _tmpFile;				}

@property(readonly) 				 NSDictionary * arguments, // Only valid after open / write / close sequence
														  * files;  	// Only valid after open / write / close sequence
+ (NSString*)mimeType;
@end
