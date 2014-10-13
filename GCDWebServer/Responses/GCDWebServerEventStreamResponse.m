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

@implementation GCDWebServerEventStreamResponse {
    NSMutableData *_eventBuffer;
}

static NSCharacterSet *kNewLineCharSet;
static NSRegularExpression *kNewLineRegExp;

+ (void)initialize
{
    if (self == [GCDWebServerEventStreamResponse class]) {
        NSError *error;
        kNewLineCharSet = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
        kNewLineRegExp = [NSRegularExpression regularExpressionWithPattern:@"(\r\n|\r|\n)"
                                                                   options:0
                                                                     error:&error];
    }
}
- (instancetype)init
{
    self = [super initWithContentType:@"text/event-stream"];
    if (self) {
        _eventBuffer = [NSMutableData dataWithCapacity:256];
    }
    return self;
}


- (void)sendMessage:(id)message {
    [self writeDataField:message];
    [self sendPendingEvent];
}

- (void)sendEventWithDictionary:(NSDictionary*)eventDict {
    // in case caller forgot to call sendPendingEvent
    [self writeField:@"event" withValue:[eventDict objectForKey:@"event"]];
    [self writeField:@"id" withValue:[eventDict objectForKey:@"id"]];
    [self writeField:@"retry" withValue:[eventDict objectForKey:@"retry"]];
    [self sendMessage:[eventDict objectForKey:@"data"]];
}

- (void)sendEventNamed:(NSString*)eventName withData:(id)eventData andID:(NSString*)eventID {
    [self writeField:@"event" withValue:eventName];
    [self writeField:@"id" withValue:eventID];
    [self sendMessage:eventData];
}

#pragma mark - GCDWebServerAsyncStreamedResponse

- (BOOL)usesChunkedTransferEncoding {
    return YES;
}

#pragma mark - Internal

- (BOOL)writeField:(NSString*)fieldName withValue:(id)fieldValue {
    if (fieldValue == nil) {
        return NO;
    }
    NSString *stringValue = nil;
    if ([fieldValue isKindOfClass:[NSString class]]) {
        stringValue = fieldValue;
    } else if ([fieldValue isKindOfClass:[NSNumber class]]) {
        stringValue = [fieldValue stringValue];
    } else {
        stringValue = [fieldValue description];
    }
    if (stringValue == nil) {
        return NO;
    }
    if ([stringValue rangeOfCharacterFromSet:kNewLineCharSet].location != NSNotFound) {
        [NSException raise:@"Invalid event field value"
                    format:@"%@ event field value cannot span multiple lines", fieldName];
    }
    NSString *msg = [NSString stringWithFormat:@"%@: %@\n", fieldName, stringValue];
    [_eventBuffer appendData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
    return YES;
}

- (BOOL)writeDataField:(id)data {
    if (data == nil) {
        return NO;
    }
    
    NSString *dataString = nil;
    NSError *error = nil;
    if ([data isKindOfClass:[NSString class]]) {
        dataString = data;
    } else if ([data isKindOfClass:[NSNumber class]]) {
        dataString = [data stringValue];
    } else if ([data isKindOfClass:[NSDictionary class]]) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
        if (!jsonData) {
            [NSException raise:@"Invalid JSON dictionary"
                        format:@"dataWithJSONObject error %@", error];
            return NO;
        }
        dataString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    } else {
        dataString = [data description];
    }
    
    if ([dataString rangeOfCharacterFromSet:kNewLineCharSet].location == NSNotFound) {
        // JSON without newlines, send as single data line
        NSString *dataLine = [NSString stringWithFormat:@"data: %@\n", dataString];
        [_eventBuffer appendData:[dataLine dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        // JSON has newlines, send as multiple data lines
        error = nil;
        NSString *dataLines = [kNewLineRegExp stringByReplacingMatchesInString:dataString
                                                                       options:0
                                                                         range:NSMakeRange(0, [dataString length])
                                                                  withTemplate:@"$1data: "];
        dataLines = [NSString stringWithFormat:@"data: %@\n", dataLines];
        [_eventBuffer appendData:[dataLines dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return YES;
}

- (void)sendPendingEvent {
    static char END_OF_EVENT_BYTES[] = { 0x0A };
    if ([_eventBuffer length] > 0) {
        [_eventBuffer appendBytes:END_OF_EVENT_BYTES length:sizeof(END_OF_EVENT_BYTES)];
        [self writeData:[_eventBuffer copy]];
        [_eventBuffer setLength:0];
    }
}

@end
