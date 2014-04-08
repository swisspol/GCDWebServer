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

// WebDAV specifications: http://webdav.org/specs/rfc4918.html

#import <libxml/parser.h>

#import "GCDWebDAVServer.h"

#import "GCDWebServerDataRequest.h"
#import "GCDWebServerFileRequest.h"

#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#import "GCDWebServerFileResponse.h"

#define kXMLParseOptions (XML_PARSE_NONET | XML_PARSE_RECOVER | XML_PARSE_NOBLANKS | XML_PARSE_COMPACT | XML_PARSE_NOWARNING | XML_PARSE_NOERROR)

typedef NS_ENUM(NSInteger, DAVProperties) {
  kDAVProperty_ResourceType = (1 << 0),
  kDAVProperty_CreationDate = (1 << 1),
  kDAVProperty_LastModified = (1 << 2),
  kDAVProperty_ContentLength = (1 << 3),
  kDAVAllProperties = kDAVProperty_ResourceType | kDAVProperty_CreationDate | kDAVProperty_LastModified | kDAVProperty_ContentLength
};

@interface GCDWebDAVServer () {
@private
  NSString* _uploadDirectory;
  id<GCDWebDAVServerDelegate> __unsafe_unretained _delegate;
  NSArray* _allowedExtensions;
  BOOL _showHidden;
}
@end

@implementation GCDWebDAVServer (Methods)

- (BOOL)_checkFileExtension:(NSString*)fileName {
  if (_allowedExtensions && ![_allowedExtensions containsObject:[[fileName pathExtension] lowercaseString]]) {
    return NO;
  }
  return YES;
}

- (GCDWebServerResponse*)performOPTIONS:(GCDWebServerRequest*)request {
  GCDWebServerResponse* response = [GCDWebServerResponse response];
  [response setValue:@"1" forAdditionalHeader:@"DAV"];  // Class 1
  return response;
}

- (GCDWebServerResponse*)performHEAD:(GCDWebServerRequest*)request {
  NSString* relativePath = request.path;
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
  if (![absolutePath hasPrefix:_uploadDirectory] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  
  NSError* error = nil;
  NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:absolutePath error:&error];
  if (!attributes) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound underlyingError:error message:@"Failed retrieving attributes for \"%@\"", relativePath];
  }
  
  GCDWebServerResponse* response = [GCDWebServerResponse response];
  if ([[attributes fileType] isEqualToString:NSFileTypeRegular]) {
    [response setValue:GCDWebServerGetMimeTypeForExtension([absolutePath pathExtension]) forAdditionalHeader:@"Content-Type"];
    [response setValue:[NSString stringWithFormat:@"%llu", [attributes fileSize]] forAdditionalHeader:@"Content-Length"];
  }
  return response;
}

- (GCDWebServerResponse*)performGET:(GCDWebServerRequest*)request {
  NSString* relativePath = request.path;
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
  BOOL isDirectory = YES;
  if (![absolutePath hasPrefix:_uploadDirectory] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  if (isDirectory) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is not a file", relativePath];
  }
  
  if ([_delegate respondsToSelector:@selector(davServer:didDownloadFileAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [_delegate davServer:self didDownloadFileAtPath:absolutePath];
    });
  }
  return [GCDWebServerFileResponse responseWithFile:absolutePath];
}

- (GCDWebServerResponse*)performPUT:(GCDWebServerFileRequest*)request {
  if ([request hasByteRange]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Range uploads not supported"];
  }
  
  NSString* relativePath = request.path;
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
  if (![absolutePath hasPrefix:_uploadDirectory]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  BOOL isDirectory;
  if (![[NSFileManager defaultManager] fileExistsAtPath:[absolutePath stringByDeletingLastPathComponent] isDirectory:&isDirectory] || !isDirectory) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Conflict message:@"Missing intermediate collection(s) for \"%@\"", relativePath];
  }
  
  BOOL existing = [[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory];
  if (existing && isDirectory) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_MethodNotAllowed message:@"PUT not allowed on existing collection \"%@\"", relativePath];
  }
  
  NSString* fileName = [absolutePath lastPathComponent];
  if (([fileName hasPrefix:@"."] && !_showHidden) || ![self _checkFileExtension:fileName]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploaded file name \"%@\" is not allowed", fileName];
  }
  
  if (![self shouldUploadFileAtPath:absolutePath withTemporaryFile:request.filePath]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploading file to \"%@\" is not allowed", relativePath];
  }
  
  [[NSFileManager defaultManager] removeItemAtPath:absolutePath error:NULL];
  NSError* error = nil;
  if (![[NSFileManager defaultManager] moveItemAtPath:request.filePath toPath:absolutePath error:&error]) {
    return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving uploaded file to \"%@\"", relativePath];
  }
  
  if ([_delegate respondsToSelector:@selector(davServer:didUploadFileAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [_delegate davServer:self didUploadFileAtPath:absolutePath];
    });
  }
  return [GCDWebServerResponse responseWithStatusCode:(existing ? kGCDWebServerHTTPStatusCode_NoContent : kGCDWebServerHTTPStatusCode_Created)];
}

- (GCDWebServerResponse*)performDELETE:(GCDWebServerRequest*)request {
  NSString* depthHeader = [request.headers objectForKey:@"Depth"];
  if (depthHeader && ![depthHeader isEqualToString:@"infinity"]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Unsupported 'Depth' header: %@", depthHeader];
  }
  
  NSString* relativePath = request.path;
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
  if (![absolutePath hasPrefix:_uploadDirectory]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  
  if (![self shouldDeleteItemAtPath:absolutePath]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting \"%@\" is not allowed", relativePath];
  }
  
  NSError* error = nil;
  if (![[NSFileManager defaultManager] removeItemAtPath:absolutePath error:&error]) {
    return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed deleting \"%@\"", relativePath];
  }
  
  if ([_delegate respondsToSelector:@selector(davServer:didDeleteItemAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [_delegate davServer:self didDeleteItemAtPath:absolutePath];
    });
  }
  return [GCDWebServerResponse responseWithStatusCode:kGCDWebServerHTTPStatusCode_NoContent];
}

- (GCDWebServerResponse*)performMKCOL:(GCDWebServerDataRequest*)request {
  if ([request hasBody] && (request.contentLength > 0)) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_UnsupportedMediaType message:@"Unexpected request body for MKCOL method"];
  }
  
  NSString* relativePath = request.path;
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
  if (![absolutePath hasPrefix:_uploadDirectory]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  BOOL isDirectory;
  if (![[NSFileManager defaultManager] fileExistsAtPath:[absolutePath stringByDeletingLastPathComponent] isDirectory:&isDirectory] || !isDirectory) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Conflict message:@"Missing intermediate collection(s) for \"%@\"", relativePath];
  }
  
  NSString* directoryName = [absolutePath lastPathComponent];
  if (!_showHidden && [directoryName hasPrefix:@"."]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Directory name \"%@\" is not allowed", directoryName];
  }
  
  if (![self shouldCreateDirectoryAtPath:absolutePath]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory \"%@\" is not allowed", relativePath];
  }
  
  NSError* error = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:absolutePath withIntermediateDirectories:NO attributes:nil error:&error]) {
    return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed creating directory \"%@\"", relativePath];
  }
  
  if ([_delegate respondsToSelector:@selector(davServer:didCreateDirectoryAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [_delegate davServer:self didCreateDirectoryAtPath:absolutePath];
    });
  }
  return [GCDWebServerResponse responseWithStatusCode:kGCDWebServerHTTPStatusCode_Created];
}

- (GCDWebServerResponse*)performCOPY:(GCDWebServerRequest*)request isMove:(BOOL)isMove {
  if (!isMove) {
    NSString* depthHeader = [request.headers objectForKey:@"Depth"];  // TODO: Support "Depth: 0"
    if (depthHeader && ![depthHeader isEqualToString:@"infinity"]) {
      return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Unsupported 'Depth' header: %@", depthHeader];
    }
  }
  
  NSString* srcRelativePath = request.path;
  NSString* srcAbsolutePath = [_uploadDirectory stringByAppendingPathComponent:srcRelativePath];
  if (![srcAbsolutePath hasPrefix:_uploadDirectory]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", srcRelativePath];
  }
  
  NSString* dstRelativePath = [request.headers objectForKey:@"Destination"];
  NSRange range = [dstRelativePath rangeOfString:[request.headers objectForKey:@"Host"]];
  if ((dstRelativePath == nil) || (range.location == NSNotFound)) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Malformed 'Destination' header: %@", dstRelativePath];
  }
  dstRelativePath = [[dstRelativePath substringFromIndex:(range.location + range.length)] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  NSString* dstAbsolutePath = [_uploadDirectory stringByAppendingPathComponent:dstRelativePath];
  if (![dstAbsolutePath hasPrefix:_uploadDirectory]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", srcRelativePath];
  }
  
  BOOL isDirectory;
  if (![[NSFileManager defaultManager] fileExistsAtPath:[dstAbsolutePath stringByDeletingLastPathComponent] isDirectory:&isDirectory] || !isDirectory) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Conflict message:@"Invalid destination \"%@\"", dstRelativePath];
  }
  
  NSString* fileName = [dstAbsolutePath lastPathComponent];
  if ((!_showHidden && [fileName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:fileName])) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Destination name \"%@\" is not allowed", fileName];
  }
  
  NSString* overwriteHeader = [request.headers objectForKey:@"Overwrite"];
  BOOL existing = [[NSFileManager defaultManager] fileExistsAtPath:dstAbsolutePath];
  if (existing && ((isMove && ![overwriteHeader isEqualToString:@"T"]) || (!isMove && [overwriteHeader isEqualToString:@"F"]))) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_PreconditionFailed message:@"Destination \"%@\" already exists", dstRelativePath];
  }
  
  if (isMove) {
    if (![self shouldMoveItemFromPath:srcAbsolutePath toPath:dstAbsolutePath]) {
      return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving \"%@\" to \"%@\" is not allowed", srcRelativePath, dstRelativePath];
    }
  } else {
    if (![self shouldCopyItemFromPath:srcAbsolutePath toPath:dstAbsolutePath]) {
      return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Copying \"%@\" to \"%@\" is not allowed", srcRelativePath, dstRelativePath];
    }
  }
  
  NSError* error = nil;
  if (isMove) {
    [[NSFileManager defaultManager] removeItemAtPath:dstAbsolutePath error:NULL];
    if (![[NSFileManager defaultManager] moveItemAtPath:srcAbsolutePath toPath:dstAbsolutePath error:&error]) {
      return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden underlyingError:error message:@"Failed copying \"%@\" to \"%@\"", srcRelativePath, dstRelativePath];
    }
  } else {
    if (![[NSFileManager defaultManager] copyItemAtPath:srcAbsolutePath toPath:dstAbsolutePath error:&error]) {
      return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden underlyingError:error message:@"Failed copying \"%@\" to \"%@\"", srcRelativePath, dstRelativePath];
    }
  }
  
  if (isMove) {
    if ([_delegate respondsToSelector:@selector(davServer:didMoveItemFromPath:toPath:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate davServer:self didMoveItemFromPath:srcAbsolutePath toPath:dstAbsolutePath];
      });
    }
  } else {
    if ([_delegate respondsToSelector:@selector(davServer:didCopyItemFromPath:toPath:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [_delegate davServer:self didCopyItemFromPath:srcAbsolutePath toPath:dstAbsolutePath];
      });
    }
  }
  
  return [GCDWebServerResponse responseWithStatusCode:(existing ? kGCDWebServerHTTPStatusCode_NoContent : kGCDWebServerHTTPStatusCode_Created)];
}

static inline xmlNodePtr _XMLChildWithName(xmlNodePtr child, const xmlChar* name) {
  while (child) {
    if ((child->type == XML_ELEMENT_NODE) && !xmlStrcmp(child->name, name)) {
      return child;
    }
    child = child->next;
  }
  return NULL;
}

- (void)_addPropertyResponseForItem:(NSString*)itemPath resource:(NSString*)resourcePath properties:(DAVProperties)properties xmlString:(NSMutableString*)xmlString {
  CFStringRef escapedPath = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)resourcePath, NULL, CFSTR("<&>?+"), kCFStringEncodingUTF8);
  if (escapedPath) {
    NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:NULL];
    NSString* type = [attributes objectForKey:NSFileType];
    BOOL isFile = [type isEqualToString:NSFileTypeRegular];
    BOOL isDirectory = [type isEqualToString:NSFileTypeDirectory];
    if ((isFile && [self _checkFileExtension:itemPath]) || isDirectory) {
      [xmlString appendString:@"<D:response>"];
      [xmlString appendFormat:@"<D:href>%@</D:href>", escapedPath];
      [xmlString appendString:@"<D:propstat>"];
      [xmlString appendString:@"<D:prop>"];
      
      if (properties & kDAVProperty_ResourceType) {
        if (isDirectory) {
          [xmlString appendString:@"<D:resourcetype><D:collection/></D:resourcetype>"];
        } else {
          [xmlString appendString:@"<D:resourcetype/>"];
        }
      }
      
      if ((properties & kDAVProperty_CreationDate) && [attributes objectForKey:NSFileCreationDate]) {
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'+00:00'";
        [xmlString appendFormat:@"<D:creationdate>%@</D:creationdate>", [formatter stringFromDate:[attributes fileCreationDate]]];
      }
      
      if ((properties & kDAVProperty_LastModified) && [attributes objectForKey:NSFileModificationDate]) {
        NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
        formatter.dateFormat = @"EEE', 'd' 'MMM' 'yyyy' 'HH:mm:ss' GMT'";
        [xmlString appendFormat:@"<D:getlastmodified>%@</D:getlastmodified>", [formatter stringFromDate:[attributes fileModificationDate]]];
      }
      
      if ((properties & kDAVProperty_ContentLength) && !isDirectory && [attributes objectForKey:NSFileSize]) {
        [xmlString appendFormat:@"<D:getcontentlength>%llu</D:getcontentlength>", [attributes fileSize]];
      }
      
      [xmlString appendString:@"</D:prop>"];
      [xmlString appendString:@"<D:status>HTTP/1.1 200 OK</D:status>"];
      [xmlString appendString:@"</D:propstat>"];
      [xmlString appendString:@"</D:response>\n"];
    }
    CFRelease(escapedPath);
  }
}

- (GCDWebServerResponse*)performPROPFIND:(GCDWebServerDataRequest*)request {
  NSInteger depth;
  NSString* depthHeader = [request.headers objectForKey:@"Depth"];
  if ([depthHeader isEqualToString:@"0"]) {
    depth = 0;
  } else if ([depthHeader isEqualToString:@"1"]) {
    depth = 1;
  } else {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"Unsupported 'Depth' header: %@", depthHeader];  // TODO: Return 403 / propfind-finite-depth for "infinity" depth
  }
  
  DAVProperties properties = 0;
  if (request.data.length) {
    xmlDocPtr document = xmlReadMemory(request.data.bytes, (int)request.data.length, NULL, NULL, kXMLParseOptions);
    if (document) {
      xmlNodePtr rootNode = _XMLChildWithName(document->children, (const xmlChar*)"propfind");
      xmlNodePtr allNode = rootNode ? _XMLChildWithName(rootNode->children, (const xmlChar*)"allprop") : NULL;
      xmlNodePtr propNode = rootNode ? _XMLChildWithName(rootNode->children, (const xmlChar*)"prop") : NULL;
      if (allNode) {
        properties = kDAVAllProperties;
      } else if (propNode) {
        xmlNodePtr node = propNode->children;
        while (node) {
          if (!xmlStrcmp(node->name, (const xmlChar*)"resourcetype")) {
            properties |= kDAVProperty_ResourceType;
          } else if (!xmlStrcmp(node->name, (const xmlChar*)"creationdate")) {
            properties |= kDAVProperty_CreationDate;
          } else if (!xmlStrcmp(node->name, (const xmlChar*)"getlastmodified")) {
            properties |= kDAVProperty_LastModified;
          } else if (!xmlStrcmp(node->name, (const xmlChar*)"getcontentlength")) {
            properties |= kDAVProperty_ContentLength;
          } else {
            [self logWarning:@"Unknown DAV property requested \"%s\"", node->name];
          }
          node = node->next;
        }
      } else {
        NSString* string = [[NSString alloc] initWithData:request.data encoding:NSUTF8StringEncoding];
        [self logError:@"Invalid DAV properties\n%@", string];
#if !__has_feature(objc_arc)
        [string release];
#endif
      }
      xmlFreeDoc(document);
    }
  } else {
    properties = kDAVAllProperties;
  }
  
  NSString* relativePath = request.path;
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:relativePath];
  if (![absolutePath hasPrefix:_uploadDirectory] || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath]) {
    return [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  
  NSError* error = nil;
  NSArray* items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:absolutePath error:&error];
  if (items == nil) {
    return [GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed listing directory \"%@\"", relativePath];
  }
  
  NSMutableString* xmlString = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"utf-8\" ?>"];
  [xmlString appendString:@"<D:multistatus xmlns:D=\"DAV:\">\n"];
  if (![relativePath hasPrefix:@"/"]) {
    relativePath = [@"/" stringByAppendingString:relativePath];
  }
  [self _addPropertyResponseForItem:absolutePath resource:relativePath properties:properties xmlString:xmlString];
  if (depth == 1) {
    if (![relativePath hasSuffix:@"/"]) {
      relativePath = [relativePath stringByAppendingString:@"/"];
    }
    for (NSString* item in items) {
      if (_showHidden || ![item hasPrefix:@"."]) {
        [self _addPropertyResponseForItem:[absolutePath stringByAppendingPathComponent:item] resource:[relativePath stringByAppendingString:item] properties:properties xmlString:xmlString];
      }
    }
  }
  [xmlString appendString:@"</D:multistatus>"];
  
  GCDWebServerDataResponse* response = [GCDWebServerDataResponse responseWithData:[xmlString dataUsingEncoding:NSUTF8StringEncoding]
                                                                      contentType:@"application/xml; charset=\"utf-8\""];
  response.statusCode = kGCDWebServerHTTPStatusCode_MultiStatus;
  return response;
}

@end

@implementation GCDWebDAVServer

@synthesize uploadDirectory=_uploadDirectory, delegate=_delegate, allowedFileExtensions=_allowedExtensions, showHiddenFiles=_showHidden;

- (id)initWithUploadDirectory:(NSString*)path {
  if ((self = [super init])) {
    _uploadDirectory = [[path stringByStandardizingPath] copy];
    GCDWebDAVServer* __unsafe_unretained server = self;
    
    // 9.1 PROPFIND method
    [self addDefaultHandlerForMethod:@"PROPFIND" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performPROPFIND:(GCDWebServerDataRequest*)request];
    }];
    
    // 9.3 MKCOL Method
    [self addDefaultHandlerForMethod:@"MKCOL" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performMKCOL:(GCDWebServerDataRequest*)request];
    }];
    
    // 9.4 HEAD method
    [self addDefaultHandlerForMethod:@"HEAD" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performHEAD:request];
    }];
    
    // 9.4 GET method
    [self addDefaultHandlerForMethod:@"GET" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performGET:request];
    }];
    
    // 9.6 DELETE method
    [self addDefaultHandlerForMethod:@"DELETE" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performDELETE:request];
    }];
    
    // 9.7 PUT method
    [self addDefaultHandlerForMethod:@"PUT" requestClass:[GCDWebServerFileRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performPUT:(GCDWebServerFileRequest*)request];
    }];
    
    // 9.8 COPY method
    [self addDefaultHandlerForMethod:@"COPY" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performCOPY:request isMove:NO];
    }];
    
    // 9.9 MOVE method
    [self addDefaultHandlerForMethod:@"MOVE" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performCOPY:request isMove:YES];
    }];
    
    // 10.1 OPTIONS method / DAV Header
    [self addDefaultHandlerForMethod:@"OPTIONS" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
      return [server performOPTIONS:request];
    }];
    
  }
  return self;
}

#if !__has_feature(objc_arc)

- (void)dealloc {
  [_uploadDirectory release];
  [_allowedExtensions release];
  
  [super dealloc];
}

#endif

@end

@implementation GCDWebDAVServer (Subclassing)

- (BOOL)shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath {
  return YES;
}

- (BOOL)shouldMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  return YES;
}

- (BOOL)shouldCopyItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  return YES;
}

- (BOOL)shouldDeleteItemAtPath:(NSString*)path {
  return YES;
}

- (BOOL)shouldCreateDirectoryAtPath:(NSString*)path {
  return YES;
}

@end
