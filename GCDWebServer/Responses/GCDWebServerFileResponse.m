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

#import <sys/stat.h>

#import "GCDWebServerPrivate.h"

#define kFileReadBufferSize (32 * 1024)

@interface GCDWebServerFileResponse () {
@private
  NSString* _path;
  NSUInteger _offset;
  NSUInteger _size;
  int _file;
}
@end

static inline NSError* _MakePosixError(int code) {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%s", strerror(code)]}];
}

@implementation GCDWebServerFileResponse

+ (instancetype)responseWithFile:(NSString*)path {
  return ARC_AUTORELEASE([[[self class] alloc] initWithFile:path]);
}

+ (instancetype)responseWithFile:(NSString*)path isAttachment:(BOOL)attachment {
  return ARC_AUTORELEASE([[[self class] alloc] initWithFile:path isAttachment:attachment]);
}

+ (instancetype)responseWithFile:(NSString*)path byteRange:(NSRange)range {
  return ARC_AUTORELEASE([[[self class] alloc] initWithFile:path byteRange:range]);
}

+ (instancetype)responseWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment {
  return ARC_AUTORELEASE([[[self class] alloc] initWithFile:path byteRange:range isAttachment:attachment]);
}

- (instancetype)initWithFile:(NSString*)path {
  return [self initWithFile:path byteRange:NSMakeRange(NSNotFound, 0) isAttachment:NO];
}

- (instancetype)initWithFile:(NSString*)path isAttachment:(BOOL)attachment {
  return [self initWithFile:path byteRange:NSMakeRange(NSNotFound, 0) isAttachment:attachment];
}

- (instancetype)initWithFile:(NSString*)path byteRange:(NSRange)range {
  return [self initWithFile:path byteRange:range isAttachment:NO];
}

static inline NSDate* _NSDateFromTimeSpec(const struct timespec* t) {
  return [NSDate dateWithTimeIntervalSince1970:((NSTimeInterval)t->tv_sec + (NSTimeInterval)t->tv_nsec / 1000000000.0)];
}

- (instancetype)initWithFile:(NSString*)path byteRange:(NSRange)range isAttachment:(BOOL)attachment {
  struct stat info;
  if (lstat([path fileSystemRepresentation], &info) || !(info.st_mode & S_IFREG)) {
    DNOT_REACHED();
    ARC_RELEASE(self);
    return nil;
  }
  if (GCDWebServerIsValidByteRange(range)) {
    if (range.location != NSNotFound) {
      range.location = MIN(range.location, (NSUInteger)info.st_size);
      range.length = MIN(range.length, (NSUInteger)info.st_size - range.location);
    } else {
      range.length = MIN(range.length, (NSUInteger)info.st_size);
      range.location = (NSUInteger)info.st_size - range.length;
    }
    if (range.length == 0) {
      ARC_RELEASE(self);
      return nil;  // TODO: Return 416 status code and "Content-Range: bytes */{file length}" header
    }
  }
  
  if ((self = [super init])) {
    _path = [path copy];
    if (range.location != NSNotFound) {
      _offset = range.location;
      _size = range.length;
      [self setStatusCode:kGCDWebServerHTTPStatusCode_PartialContent];
      [self setValue:[NSString stringWithFormat:@"bytes %i-%i/%i", (int)range.location, (int)(range.location + range.length - 1), (int)info.st_size] forAdditionalHeader:@"Content-Range"];
      LOG_DEBUG(@"Using content bytes range [%i-%i] for file \"%@\"", (int)range.location, (int)(range.location + range.length - 1), path);
    } else {
      _offset = 0;
      _size = (NSUInteger)info.st_size;
    }
    
    if (attachment) {
      NSString* fileName = [path lastPathComponent];
      NSData* data = [[fileName stringByReplacingOccurrencesOfString:@"\"" withString:@""] dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
      NSString* lossyFileName = data ? [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] : nil;
      if (lossyFileName) {
        NSString* value = [NSString stringWithFormat:@"attachment; filename=\"%@\"; filename*=UTF-8''%@", lossyFileName, GCDWebServerEscapeURLString(fileName)];
        [self setValue:value forAdditionalHeader:@"Content-Disposition"];
        ARC_RELEASE(lossyFileName);
      } else {
        DNOT_REACHED();
      }
    }
    
    self.contentType = GCDWebServerGetMimeTypeForExtension([path pathExtension]);
    self.contentLength = (range.location != NSNotFound ? range.length : (NSUInteger)info.st_size);
    self.lastModifiedDate = _NSDateFromTimeSpec(&info.st_mtimespec);
    self.eTag = [NSString stringWithFormat:@"%llu/%li/%li", info.st_ino, info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
  }
  return self;
}

- (void)dealloc {
  ARC_RELEASE(_path);
  
  ARC_DEALLOC(super);
}

- (BOOL)open:(NSError**)error {
  _file = open([_path fileSystemRepresentation], O_NOFOLLOW | O_RDONLY);
  if (_file <= 0) {
    *error = _MakePosixError(errno);
    return NO;
  }
  if (lseek(_file, _offset, SEEK_SET) != (off_t)_offset) {
    *error = _MakePosixError(errno);
    close(_file);
    return NO;
  }
  return YES;
}

- (NSData*)readData:(NSError**)error {
  size_t length = MIN((NSUInteger)kFileReadBufferSize, _size);
  NSMutableData* data = [[NSMutableData alloc] initWithLength:length];
  ssize_t result = read(_file, data.mutableBytes, length);
  if (result < 0) {
    *error = _MakePosixError(errno);
    return nil;
  }
  if (result > 0) {
    [data setLength:result];
    _size -= result;
  }
  return ARC_AUTORELEASE(data);
}

- (void)close {
  close(_file);
}

- (NSString*)description {
  NSMutableString* description = [NSMutableString stringWithString:[super description]];
  [description appendFormat:@"\n\n{%@}", _path];
  return description;
}

@end
