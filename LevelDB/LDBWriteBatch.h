//
//  LDBWriteBatch.h
//  LevelDB
//
//  Copyright (c) 2015 Pyry Jahkola. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LDBWriteBatch : NSObject

- (NSData *)objectForKeyedSubscript:(NSData *)key;
- (void)setObject:(NSData *)data forKeyedSubscript:(NSData *)key;
- (void)setData:(NSData *)data forKey:(NSData *)key;
- (void)removeDataForKey:(NSData *)key;

- (void)enumerate:(void (^)(NSData *key, NSData *data))block;

@end