//
//  LDBSnapshot.h
//  LevelDB
//
//  Copyright (c) 2015 Pyry Jahkola. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LDBDatabase;
@class LDBEnumerator;
@class LDBInterval;

@interface LDBSnapshot : NSObject

- (instancetype)init __attribute__((unavailable("init not available")));
- (instancetype)initWithDatabase:(LDBDatabase *)database;

@property (nonatomic, readonly) LDBSnapshot *noncaching;
@property (nonatomic, readonly) LDBSnapshot *checksummed;
@property (nonatomic, readonly) LDBSnapshot *reversed;
@property (nonatomic, readonly) NSData *startKey;
@property (nonatomic, readonly) NSData *endKey;
@property (nonatomic, readonly) BOOL isNoncaching;
@property (nonatomic, readonly) BOOL isChecksummed;
@property (nonatomic, readonly) BOOL isReversed;

- (LDBSnapshot *)clampStart:(NSData *)startKey end:(NSData *)endKey;
- (LDBSnapshot *)clampToInterval:(LDBInterval *)interval;
- (LDBSnapshot *)after:(NSData *)exclusiveStartKey;
- (LDBSnapshot *)prefix:(NSData *)keyPrefix;

- (NSData *)dataForKey:(NSData *)key;
- (NSData *)objectForKeyedSubscript:(NSData *)key;

- (void)enumerate:(void (^)(NSData *key, NSData *data, BOOL *stop))block;

- (LDBEnumerator *)enumerator;

@end
