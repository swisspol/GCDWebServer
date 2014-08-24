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

#import <os/object.h>

#if __has_feature(objc_arc)
#define ARC_BRIDGE __bridge
#define ARC_BRIDGE_RELEASE(__OBJECT__) CFBridgingRelease(__OBJECT__)
#define ARC_RETAIN(__OBJECT__) __OBJECT__
#define ARC_RELEASE(__OBJECT__)
#define ARC_AUTORELEASE(__OBJECT__) __OBJECT__
#define ARC_DEALLOC(__OBJECT__)
#if OS_OBJECT_USE_OBJC_RETAIN_RELEASE
#define ARC_DISPATCH_RETAIN(__OBJECT__)
#define ARC_DISPATCH_RELEASE(__OBJECT__)
#else
#define ARC_DISPATCH_RETAIN(__OBJECT__) dispatch_retain(__OBJECT__)
#define ARC_DISPATCH_RELEASE(__OBJECT__) dispatch_release(__OBJECT__)
#endif
#else
#define ARC_BRIDGE
#define ARC_BRIDGE_RELEASE(__OBJECT__) [(id)__OBJECT__ autorelease]
#define ARC_RETAIN(__OBJECT__) [__OBJECT__ retain]
#define ARC_RELEASE(__OBJECT__) [__OBJECT__ release]
#define ARC_AUTORELEASE(__OBJECT__) [__OBJECT__ autorelease]
#define ARC_DEALLOC(__OBJECT__) [__OBJECT__ dealloc]
#define ARC_DISPATCH_RETAIN(__OBJECT__) dispatch_retain(__OBJECT__)
#define ARC_DISPATCH_RELEASE(__OBJECT__) dispatch_release(__OBJECT__)
#endif

#import "GCDWebServerHTTPStatusCodes.h"
#import "GCDWebServerFunctions.h"

#import "GCDWebServer.h"
#import "GCDWebServerConnection.h"

#import "GCDWebServerDataRequest.h"
#import "GCDWebServerFileRequest.h"
#import "GCDWebServerMultiPartFormRequest.h"
#import "GCDWebServerURLEncodedFormRequest.h"

#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerStreamedResponse.h"

#ifdef __GCDWEBSERVER_LOGGING_HEADER__

// Define __GCDWEBSERVER_LOGGING_HEADER__ as a preprocessor constant to redirect GCDWebServer logging to your own system
#import __GCDWEBSERVER_LOGGING_HEADER__

#else

extern GCDWebServerLogLevel GCDLogLevel;
extern void GCDLogMessage(GCDWebServerLogLevel level, NSString* format, ...) NS_FORMAT_FUNCTION(2, 3);

#define LOG_VERBOSE(...) do { if (GCDLogLevel <= kGCDWebServerLogLevel_Verbose) GCDLogMessage(kGCDWebServerLogLevel_Verbose, __VA_ARGS__); } while (0)
#define LOG_INFO(...) do { if (GCDLogLevel <= kGCDWebServerLogLevel_Info) GCDLogMessage(kGCDWebServerLogLevel_Info, __VA_ARGS__); } while (0)
#define LOG_WARNING(...) do { if (GCDLogLevel <= kGCDWebServerLogLevel_Warning) GCDLogMessage(kGCDWebServerLogLevel_Warning, __VA_ARGS__); } while (0)
#define LOG_ERROR(...) do { if (GCDLogLevel <= kGCDWebServerLogLevel_Error) GCDLogMessage(kGCDWebServerLogLevel_Error, __VA_ARGS__); } while (0)
#define LOG_EXCEPTION(__EXCEPTION__) do { if (GCDLogLevel <= kGCDWebServerLogLevel_Exception) GCDLogMessage(kGCDWebServerLogLevel_Exception, @"%@", __EXCEPTION__); } while (0)

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
#define LOG_DEBUG(...) do { if (GCDLogLevel <= kGCDWebServerLogLevel_Debug) GCDLogMessage(kGCDWebServerLogLevel_Debug, __VA_ARGS__); } while (0)

#endif

#endif

#define kGCDWebServerDefaultMimeType @"application/octet-stream"
#define kGCDWebServerGCDQueue dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
#define kGCDWebServerErrorDomain @"GCDWebServerErrorDomain"

static inline BOOL GCDWebServerIsValidByteRange(NSRange range) {
  return ((range.location != NSUIntegerMax) || (range.length > 0));
}

static inline NSError* GCDWebServerMakePosixError(int code) {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:strerror(code)]}];
}

extern void GCDWebServerInitializeFunctions();
extern NSString* GCDWebServerNormalizeHeaderValue(NSString* value);
extern NSString* GCDWebServerTruncateHeaderValue(NSString* value);
extern NSString* GCDWebServerExtractHeaderValueParameter(NSString* header, NSString* attribute);
extern NSStringEncoding GCDWebServerStringEncodingFromCharset(NSString* charset);
extern BOOL GCDWebServerIsTextContentType(NSString* type);
extern NSString* GCDWebServerDescribeData(NSData* data, NSString* contentType);
extern NSString* GCDWebServerComputeMD5Digest(NSString* format, ...) NS_FORMAT_FUNCTION(1,2);

@interface GCDWebServerConnection ()
- (id)initWithServer:(GCDWebServer*)server localAddress:(NSData*)localAddress remoteAddress:(NSData*)remoteAddress socket:(CFSocketNativeHandle)socket;
@end

@interface GCDWebServer ()
@property(nonatomic, readonly) NSArray* handlers;
@property(nonatomic, readonly) NSString* serverName;
@property(nonatomic, readonly) NSString* authenticationRealm;
@property(nonatomic, readonly) NSDictionary* authenticationBasicAccounts;
@property(nonatomic, readonly) NSDictionary* authenticationDigestAccounts;
@property(nonatomic, readonly) BOOL shouldAutomaticallyMapHEADToGET;
- (void)willStartConnection:(GCDWebServerConnection*)connection;
- (void)didEndConnection:(GCDWebServerConnection*)connection;
@end

@interface GCDWebServerHandler : NSObject
@property(nonatomic, readonly) GCDWebServerMatchBlock matchBlock;
@property(nonatomic, readonly) GCDWebServerProcessBlock processBlock;
- (id)initWithMatchBlock:(GCDWebServerMatchBlock)matchBlock processBlock:(GCDWebServerProcessBlock)processBlock;
@end

@interface GCDWebServerRequest ()
@property(nonatomic, readonly) BOOL usesChunkedTransferEncoding;
- (void)prepareForWriting;
- (BOOL)performOpen:(NSError**)error;
- (BOOL)performWriteData:(NSData*)data error:(NSError**)error;
- (BOOL)performClose:(NSError**)error;
@end

@interface GCDWebServerResponse ()
@property(nonatomic, readonly) NSDictionary* additionalHeaders;
@property(nonatomic, readonly) BOOL usesChunkedTransferEncoding;
- (void)prepareForReading;
- (BOOL)performOpen:(NSError**)error;
- (NSData*)performReadData:(NSError**)error;
- (void)performClose;
@end
