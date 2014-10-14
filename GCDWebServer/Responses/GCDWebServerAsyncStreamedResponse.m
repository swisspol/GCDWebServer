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

#import "GCDWebServerPrivate.h"

@interface GCDWebServerAsyncStreamedResponse () {
@private
  GCDWebServerBodyReaderBlock _readerBlock;
  BOOL _finished;
}
@end

@implementation GCDWebServerAsyncStreamedResponse

+ (instancetype)responseWithContentType:(NSString*)type {
  return ARC_AUTORELEASE([[[self class] alloc] initWithContentType:type]);
}

- (instancetype)initWithContentType:(NSString*)type {
  if ((self = [super init])) {
    self.contentType = type;
    _finished = NO;
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_readerBlock);
  
  ARC_DEALLOC(super);
}

- (NSData*)readData:(NSError**)error {
  [NSException raise:@"Invalid method call" format:@"asyncReadData must be used when available"];
  return nil;
}

- (void)asyncReadData:(GCDWebServerBodyReaderBlock)readerBlock {
  _readerBlock = readerBlock;
}

- (void)writeData:(NSData*)data {
  if ([data length] == 0) {
    [self finish];
  }
  else if (_readerBlock && !_finished) {
    _readerBlock(data, nil);
  }
}

- (void)finish {
  if (_readerBlock && !_finished) {
    _readerBlock([NSData data], nil);
    _finished = YES;
  }
}

- (void)finishWithError:(NSError*)error {
  if (_readerBlock && !_finished) {
    _readerBlock(nil, error);
    _finished = YES;
  }
}

- (NSString*)description {
  NSMutableString* description = [NSMutableString stringWithString:[super description]];
  [description appendString:@"\n\n<STREAM>"];
  return description;
}

@end
