/*
 Copyright (c) 2012-2013, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the <organization> nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>

@interface GCDWebServerRequest : NSObject {
@private
  NSString* _method;
  NSURL* _url;
  NSDictionary* _headers;
  NSString* _path;
  NSDictionary* _query;
  NSString* _type;
  NSUInteger _length;
}
@property(nonatomic, readonly) NSString* method;
@property(nonatomic, readonly) NSURL* URL;
@property(nonatomic, readonly) NSDictionary* headers;
@property(nonatomic, readonly) NSString* path;
@property(nonatomic, readonly) NSDictionary* query;  // May be nil
@property(nonatomic, readonly) NSString* contentType;  // Automatically parsed from headers (nil if request has no body)
@property(nonatomic, readonly) NSUInteger contentLength;  // Automatically parsed from headers
- (id)initWithMethod:(NSString*)method url:(NSURL*)url headers:(NSDictionary*)headers path:(NSString*)path query:(NSDictionary*)query;
- (BOOL)hasBody;  // Convenience method
@end

@interface GCDWebServerRequest (Subclassing)
- (BOOL)open;  // Implementation required
- (NSInteger)write:(const void*)buffer maxLength:(NSUInteger)length;  // Implementation required
- (BOOL)close;  // Implementation required
@end

@interface GCDWebServerDataRequest : GCDWebServerRequest {
@private
  NSMutableData* _data;
}
@property(nonatomic, readonly) NSData* data;  // Only valid after open / write / close sequence
@end

@interface GCDWebServerFileRequest : GCDWebServerRequest {
@private
  NSString* _filePath;
  int _file;
}
@property(nonatomic, readonly) NSString* filePath;  // Only valid after open / write / close sequence
@end

@interface GCDWebServerURLEncodedFormRequest : GCDWebServerDataRequest {
@private
  NSDictionary* _arguments;
}
@property(nonatomic, readonly) NSDictionary* arguments;  // Only valid after open / write / close sequence
+ (NSString*)mimeType;
@end

@interface GCDWebServerMultiPart : NSObject {
@private
  NSString* _contentType;
  NSString* _mimeType;
}
@property(nonatomic, readonly) NSString* contentType;  // May be nil
@property(nonatomic, readonly) NSString* mimeType;  // Defaults to "text/plain" per specifications if undefined
@end

@interface GCDWebServerMultiPartArgument : GCDWebServerMultiPart {
@private
  NSData* _data;
  NSString* _string;
}
@property(nonatomic, readonly) NSData* data;
@property(nonatomic, readonly) NSString* string;  // May be nil (only valid for text mime types
@end

@interface GCDWebServerMultiPartFile : GCDWebServerMultiPart {
@private
  NSString* _fileName;
  NSString* _temporaryPath;
}
@property(nonatomic, readonly) NSString* fileName;  // May be nil
@property(nonatomic, readonly) NSString* temporaryPath;
@end

@interface GCDWebServerMultiPartFormRequest : GCDWebServerRequest {
@private
  NSData* _boundary;
  
  NSUInteger _parserState;
  NSMutableData* _parserData;
  NSString* _controlName;
  NSString* _fileName;
  NSString* _contentType;
  NSString* _tmpPath;
  int _tmpFile;
  
  NSMutableDictionary* _arguments;
  NSMutableDictionary* _files;
}
@property(nonatomic, readonly) NSDictionary* arguments;  // Only valid after open / write / close sequence
@property(nonatomic, readonly) NSDictionary* files;  // Only valid after open / write / close sequence
+ (NSString*)mimeType;
@end
