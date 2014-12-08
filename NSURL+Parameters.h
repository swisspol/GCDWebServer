//
//  NSURL+Parameters.h
//  NSURL+Parameters
//
//  Created by Carl Jahn on 16.09.13.
//  Copyright (c) 2013 Carl Jahn. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURL (Parameters)

@property (nonatomic, strong) NSDictionary *parameters;


- (NSString *)parameterForKey:(NSString *)key;

- (id)objectForKeyedSubscript:(id)key NS_AVAILABLE(10_8, 6_0);


@end
