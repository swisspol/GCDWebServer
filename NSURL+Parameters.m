//
//  NSURL+Parameters.m
//  NSURL+Parameters
//
//  Created by Carl Jahn on 16.09.13.
//  Copyright (c) 2013 Carl Jahn. All rights reserved.
//

#import "NSURL+Parameters.h"
#import <objc/runtime.h>

static void *kURLParametersDictionaryKey;

@implementation NSURL (Parameters)

- (void)scanParameters {
  
  if (self.isFileURL) {
    return;
  }
  
  NSScanner *scanner = [NSScanner scannerWithString: self.absoluteString];
  [scanner setCharactersToBeSkipped: [NSCharacterSet characterSetWithCharactersInString:@"&?"] ];
  //skip to ?
  [scanner scanUpToString:@"?" intoString: nil];
  
  
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  NSString *tmpValue;
  while ([scanner scanUpToString:@"&" intoString:&tmpValue]) {
    
    NSArray *components = [tmpValue componentsSeparatedByString:@"="];
    
    if (components.count >= 2) {
      NSString *key = [components[0] stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
      NSString *value = [components[1] stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
      
      parameters[key] = value;
    }
  }
  
  self.parameters = parameters;
}

- (id)objectForKeyedSubscript:(id)key {
  
  return self.parameters[key];
}


- (NSString *)parameterForKey:(NSString *)key {
  
  return self.parameters[key];
}

- (NSDictionary *)parameters {
  
  NSDictionary *result = objc_getAssociatedObject(self, &kURLParametersDictionaryKey);

  if (!result) {
    [self scanParameters];
  }
  
  return objc_getAssociatedObject(self, &kURLParametersDictionaryKey);
}

- (void)setParameters:(NSDictionary *)parameters {
  
  objc_setAssociatedObject(self, &kURLParametersDictionaryKey, parameters, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

}

@end
