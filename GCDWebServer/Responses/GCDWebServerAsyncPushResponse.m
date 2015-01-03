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

#if !__has_feature(objc_arc)
#error GCDWebServer requires ARC
#endif

#import "GCDWebServerPrivate.h"

@interface GCDWebServerAsyncPushResponse () {
@private
  NSMutableData* _buffer;
  GCDWebServerBodyReaderCompletionBlock _pendingReadBlock;
  NSError* _pendingError;
  BOOL _haveFinished;
}
@end

@implementation GCDWebServerAsyncPushResponse

- (instancetype)initWithContentType:(NSString *)type {
  if ((self = [super init])) {
    self.contentType = type;
    _buffer = [[NSMutableData alloc] init];
    
    _haveFinished = NO;
    _pendingError = nil;
    _pendingReadBlock = nil;
  }
  
  return self;
}

- (void)asyncReadDataWithCompletion:(GCDWebServerBodyReaderCompletionBlock)block {
  //The server has asked us for data
  //Provide the contents of the buffer if we can, otherwise defer providing the server
  //data until later
  @synchronized(_buffer) {
    if (_pendingError != nil) {
      //Case #1: we have a problem
      block(nil, _pendingError);
      _pendingReadBlock = nil;
      
    } else if (_buffer.length > 0){
      //Case #2: we have data
      block([_buffer copy], nil);
      _buffer.length = 0; //clear the buffer
      _pendingReadBlock = nil;
      
    } else if (_haveFinished == YES) {
      //Case #3: we are done, and the buffer is now empty
      block([[NSData alloc] init], nil);
      _pendingReadBlock = nil;
      
    } else {
      //Case #4: we have none of these things; deferr our response until later
      _pendingReadBlock = block;
    }
  }
}

- (void)pumpPendingRead {
  if (_pendingReadBlock != nil) {
    [self asyncReadDataWithCompletion:_pendingReadBlock];
  }
}

- (void)sendWithData:(NSData *)data {
  @synchronized(_buffer) {
    [_buffer appendData:data];
    [self pumpPendingRead];
  }
}

- (void)completeWithErorr:(NSError *)error {
  @synchronized(_buffer) {
    if (error == nil) {
      _haveFinished = YES;
    } else {
      _pendingError = error;
    }
    [self pumpPendingRead];
  }
}

@end