//
//  LDBPrivate.mm
//  LevelDB
//
//  Copyright (c) 2015 Pyry Jahkola. All rights reserved.
//

#import "LDBPrivate.hpp"
#import "LDBError.h"
#import "leveldb/status.h"
#include <type_traits>

@implementation NSObject (LevelDB)
+ (instancetype)ldb_cast:(id)object
{
    return [object isKindOfClass:self] ? object : nil;
}
@end


@implementation NSNumber (LevelDB)
- (NSNumber *)ldb_bool
{
    if ((![self compare:@YES] && !strcmp(self.objCType, @YES.objCType)) ||
        (![self compare:@NO] && !strcmp(self.objCType, @NO.objCType)))
    {
        return self;
    } else {
        return nil;
    }
}
@end


BOOL leveldb_objc::objc_result(leveldb::Status const &status,
                               NSError * __autoreleasing *error)
{
    if (!status.ok()) {
        if (error) {
            *error = to_NSError(status);
        }
        return NO;
    } else {
        return YES;
    }
}


NSError *leveldb_objc::to_NSError(leveldb::Status const &status)
{
    if (status.ok()) {
        return nil;
    }

    auto message = [NSString stringWithUTF8String:status.ToString().c_str()];
    auto userInfo = @{
        LDBErrorMessageKey: message,
        NSLocalizedDescriptionKey: message
    };

    LDBError const code = status.IsNotFound()   ? LDBErrorNotFound
                        : status.IsCorruption() ? LDBErrorCorruption
                        : status.IsIOError()    ? LDBErrorIOError
                                                : LDBErrorOther;

    return [NSError errorWithDomain:LDBErrorDomain code:code userInfo:userInfo];
}


leveldb::Slice leveldb_objc::to_Slice(NSData *data)
{
    return leveldb::Slice{static_cast<char const *>(data.bytes), data.length};
}


NSData *leveldb_objc::to_NSData(leveldb::Slice const &slice)
{
    return [NSData dataWithBytes:slice.data() length:slice.size()];
}


NSComparisonResult leveldb_objc::compare(NSData *left, NSData *right)
{
    if (!left && !right) return NSOrderedSame;
    if (!right) return NSOrderedAscending;
    if (!left) return NSOrderedDescending;
    auto a = left.length;
    auto b = right.length;
    auto c = memcmp(static_cast<char const *>(left.bytes),
                    static_cast<char const *>(right.bytes), MIN(a, b));
    return c < 0 ? NSOrderedAscending
         : c > 0 ? NSOrderedDescending
         : a < b ? NSOrderedAscending
         : a > b ? NSOrderedDescending
                 : NSOrderedSame;
}


NSData *leveldb_objc::min(NSData *left, NSData *right)
{
    return leveldb_objc::compare(left, right) <= 0 ? left : right;
}


NSData *leveldb_objc::max(NSData *left, NSData *right)
{
    return leveldb_objc::compare(left, right) >= 0 ? left : right;
}

NSData *leveldb_objc::lexicographicalNextSibling(NSData *data)
{
    if (!data) return nil;
    auto result = [NSMutableData dataWithData:data];
    auto bytes = static_cast<unsigned char *>(result.mutableBytes);
    auto const n = result.length;
    for (NSUInteger i = n; i > 0; i--) {
        if (bytes[i - 1] < 0xff) {
            bytes[i - 1]++;
            return [result copy];
        } else {
            bytes[i - 1] = 0;
        }
    }
    return nil;
}

NSData *leveldb_objc::lexicographicalFirstChild(NSData *data)
{
    if (!data) return nil;
    auto result = [NSMutableData dataWithCapacity:data.length + 1];
    [result setData:data];
    char const zero = 0;
    [result appendBytes:&zero length:1];
    return [result copy];
}

NSData *leveldb_objc::dropLength(NSUInteger length, NSData *data)
{
    if (!length) {
        return data;
    } else if (data.length <= length) {
        return data ? [NSData data] : nil;
    } else {
        return [data subdataWithRange:NSMakeRange(length, data.length - length)];
    }
}

NSData *leveldb_objc::cutPrefix(NSData *prefix, NSData *data)
{
    namespace ldb = leveldb_objc;
    if (ldb::compare(data, prefix) <= 0) {
        return [NSData data]; // before prefix
    }
    auto stop = ldb::lexicographicalNextSibling(prefix);
    if (ldb::compare(data, stop) < 0) {
        return ldb::dropLength(prefix.length, data); // within prefix
    }
    return nil; // past the end
}

NSData *leveldb_objc::concat(NSData *left, NSData *right)
{
    if (!left.length) return right;
    if (!right.length) return left;
    auto data = [[NSMutableData alloc] initWithCapacity:left.length + right.length];
    [data appendData:left];
    [data appendData:right];
    return [data copy];
}
