//
//  LDBDatabase.mm
//  LevelDB
//
//  Copyright (c) 2015 Pyry Jahkola. All rights reserved.
//

#import "LDBDatabase.h"

#import "LDBInterval.h"
#import "LDBSnapshot.h"
#import "LDBWriteBatch.h"
#import "LDBPrivate.hpp"
#import "LDBLogger.h"

#include <libkern/OSAtomic.h>

#include <memory>
#include "helpers/memenv/memenv.h"
#include "leveldb/cache.h"
#include "leveldb/db.h"
#include "leveldb/env.h"
#include "leveldb/filter_policy.h"

// -----------------------------------------------------------------------------
#pragma mark - Constants

NSString * const LDBOptionCreateIfMissing      = @"LDBOptionCreateIfMissing";
NSString * const LDBOptionErrorIfExists        = @"LDBOptionErrorIfExists";
NSString * const LDBOptionParanoidChecks       = @"LDBOptionParanoidChecks";
// - no `env` option yet
NSString * const LDBOptionInfoLog              = @"LDBOptionInfoLog";
NSString * const LDBOptionWriteBufferSize      = @"LDBOptionWriteBufferSize";
NSString * const LDBOptionMaxOpenFiles         = @"LDBOptionMaxOpenFiles";
NSString * const LDBOptionCacheCapacity        = @"LDBOptionCacheCapacity";
NSString * const LDBOptionBlockSize            = @"LDBOptionBlockSize";
NSString * const LDBOptionBlockRestartInterval = @"LDBOptionBlockRestartInterval";
NSString * const LDBOptionCompression          = @"LDBOptionCompression";
NSString * const LDBOptionReuseLogs            = @"LDBOptionReuseLogs";
NSString * const LDBOptionBloomFilterBits      = @"LDBOptionBloomFilterBits";


// -----------------------------------------------------------------------------
#pragma mark - LDBDatabase

@interface LDBDatabase () {
    std::unique_ptr<leveldb::Env>                 _env;
    LDBLogger                                    *_logger;
    std::unique_ptr<leveldb::FilterPolicy const>  _filter_policy;
    std::unique_ptr<leveldb::Cache>               _cache;
    std::unique_ptr<leveldb::DB>                  _db;
}

@end

@implementation LDBDatabase

+ (BOOL)
    destroyDatabaseAtPath:(NSString *)path
    error:(NSError * __autoreleasing *)error
{
    auto options = leveldb::Options{};
    auto status = leveldb::DestroyDB(path.UTF8String, options);
    return leveldb_objc::objc_result(status, error);
}

+ (BOOL)
    repairDatabaseAtPath:(NSString *)path
    error:(NSError * __autoreleasing *)error;
{
    auto options = leveldb::Options{};
    auto status = leveldb::RepairDB(path.UTF8String, options);
    return leveldb_objc::objc_result(status, error);
}

- (instancetype)init
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _env = std::unique_ptr<leveldb::Env>(
        leveldb::NewMemEnv(leveldb::Env::Default()));
    auto options = leveldb::Options{};
    options.env = _env.get();
    options.create_if_missing = true;

    static std::int64_t counter = 0;
    auto name = "leveldb-" + std::to_string(OSAtomicIncrement64(&counter));
    
    leveldb::DB *db = nullptr;
    auto status = leveldb::DB::Open(options, name, &db);

    if (!status.ok()) {
        return nil;
    }

    _db = std::unique_ptr<leveldb::DB>(db);

    return self;
}

- (instancetype)
    initWithPath:(NSString *)path
    error:(NSError * __autoreleasing *)error
{
    auto options = @{
        LDBOptionCreateIfMissing: @YES,
        LDBOptionBloomFilterBits: @10
    };
    return [self initWithPath:path options:options error:error];
}

- (instancetype)
    initWithPath:(NSString *)path
    options:(NSDictionary *)optionsDictionary
    error:(NSError * __autoreleasing *)error
{
    if (!(self = [super init])) {
        return nil;
    }
    
    auto options = leveldb::Options{};
    [self _readOptions:options optionsDictionary:optionsDictionary];
    leveldb::DB *db = nullptr;
    auto status = leveldb::DB::Open(options, path.UTF8String, &db);
    _db.reset(db);

    if (!status.ok()) {
        if (error) {
            *error = leveldb_objc::to_NSError(status);
        }
        return nil;
    } else {
        return self;
    }
}

- (NSData *)dataForKey:(NSData *)key
{
    if (!key) {
        return nil;
    }
    
    std::string value;
    auto status = _db->Get(leveldb::ReadOptions{},
                           leveldb_objc::to_Slice(key),
                           &value);
    if (status.ok()) {
        return [NSData dataWithBytes:value.data() length:value.size()];
    } else {
        return nil;
    }
}

- (NSData *)objectForKeyedSubscript:(NSData *)key
{
    return [self dataForKey:key];
}

- (LDBSnapshot *)snapshot
{
    return [[LDBSnapshot alloc] initWithDatabase:self];
}

- (BOOL)setData:(NSData *)data forKey:(NSData *)key
{
    if (!key) {
        return NO;
    }

    if (data) {
        auto status = _db->Put(leveldb::WriteOptions{},
                               leveldb_objc::to_Slice(key),
                               leveldb_objc::to_Slice(data));
        return status.ok();
    } else {
        auto status = _db->Delete(leveldb::WriteOptions{},
                                  leveldb_objc::to_Slice(key));
        return status.ok();
    }
}

- (BOOL)setObject:(NSData *)data forKeyedSubscript:(NSData *)key
{
    return [self setData:data forKey:key];
}

- (BOOL)removeDataForKey:(NSData *)key
{
    return [self setData:nil forKey:key];
}

- (BOOL)
    write:(LDBWriteBatch *)batch
    sync:(BOOL)sync
    error:(NSError * __autoreleasing *)error
{
    auto writeOptions = leveldb::WriteOptions{};
    writeOptions.sync = sync;
    auto status = _db->Write(writeOptions, batch.private_batch);
    return leveldb_objc::objc_result(status, error);
}


- (NSString *)propertyNamed:(NSString *)name
{
    std::string value;
    NSData *property = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (_db->GetProperty(leveldb_objc::to_Slice(property), &value)) {
        return [NSString stringWithUTF8String:value.c_str()];
    } else {
        return nil;
    }
}

- (NSArray <NSNumber *> *)approximateSizesForIntervals:(NSArray <LDBInterval *> *)intervals
{
    std::vector<leveldb::Range> ranges;
    std::vector<uint64_t> sizes(intervals.count);
    ranges.reserve(intervals.count);
    for (LDBInterval *interval in intervals) {
        NSParameterAssert([interval isKindOfClass:LDBInterval.class]);
        ranges.push_back(leveldb::Range(leveldb_objc::to_Slice(interval.start),
                                        leveldb_objc::to_Slice(interval.end)));
    }
    NSAssert(ranges.size() == sizes.size(), @"");
    _db->GetApproximateSizes(&ranges[0], static_cast<int>(sizes.size()), &sizes[0]);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:sizes.size()];
    for (auto n : sizes) {
        [result addObject:@(n)];
    }
    return [result copy];
}

- (void)compactInterval:(LDBInterval *)interval
{
    if (leveldb_objc::compare(interval.start, interval.end) >= 0) return;
    
    auto const start = leveldb_objc::to_Slice(interval.start);
    if (interval.end) {
        auto const end = leveldb_objc::to_Slice(interval.end);
        _db->CompactRange(&start, &end);
    } else {
        _db->CompactRange(&start, nullptr);
    }
}

- (void)pruneCache
{
    if (_cache) {
        _cache->Prune();
    }
}

// -----------------------------------------------------------------------------
#pragma mark - Private parts

/// Parse database options and set `_logger`, `_filter_policy` and `_cache` if
/// needed.
- (void)
    _readOptions:(leveldb::Options &)opts
    optionsDictionary:(NSDictionary *)dict
{
    void (^parse)(NSString *key, void (^block)(id value, NSString **error)) =
        ^(NSString *key, void (^block)(id value, NSString **error))
    {
        if (id value = dict[key]) {
            NSString *error;
            block(value, &error);
            if (error && error.length) {
                NSLog(@"[WARN] invalid LDBDatabase option %@ for key %@, %@", dict[key], key, error);
            } else if (error) {
                NSLog(@"[WARN] invalid LDBDatabase option %@ for key %@", dict[key], key);
            }
        }
    };
    
    void (^parse_bool)(NSString *key, bool &option) = ^(NSString *key, bool &option) {
        parse(key, ^(id value, NSString **error) {
            if (auto number = [NSNumber ldb_cast:value].ldb_bool) {
                option = number.boolValue;
            } else {
                *error = @"";
            }
        });
    };

    void (^parse_int)(NSString *key, int &option) = ^(NSString *key, int &option) {
        parse(key, ^(id value, NSString **error) {
            if (auto number = [NSNumber ldb_cast:value]) {
                option = number.intValue;
            } else {
                *error = @"";
            }
        });
    };

    void (^parse_size_t)(NSString *key, size_t &option) = ^(NSString *key, size_t &option) {
        parse(key, ^(id value, NSString **error) {
            if (auto number = [NSNumber ldb_cast:value]) {
                option = number.unsignedLongValue;
            } else {
                *error = @"";
            }
        });
    };

    parse_bool(LDBOptionCreateIfMissing, opts.create_if_missing);
    parse_bool(LDBOptionErrorIfExists, opts.error_if_exists);
    parse_bool(LDBOptionParanoidChecks, opts.paranoid_checks);
    parse_bool(LDBOptionReuseLogs, opts.reuse_logs);
    parse_int(LDBOptionMaxOpenFiles, opts.max_open_files);
    parse_int(LDBOptionBlockRestartInterval, opts.block_restart_interval);
    parse_size_t(LDBOptionWriteBufferSize, opts.write_buffer_size);
    parse_size_t(LDBOptionBlockSize, opts.block_size);
    
    // info log
    parse(LDBOptionInfoLog, ^(id value, NSString **error) {
        if (auto logger = [LDBLogger ldb_cast:value]) {
            _logger = logger;
            opts.info_log = logger.private_logger;
        }
    });
    
    // block cache (cache capacity)
    parse(LDBOptionCacheCapacity, ^(id value, NSString **error) {
        if (auto number = [NSNumber ldb_cast:value]) {
            if (size_t capacity = number.unsignedLongValue) {
                using ptr_t = std::unique_ptr<leveldb::Cache>;
                _cache = ptr_t(leveldb::NewLRUCache(capacity));
                opts.block_cache = _cache.get();
            }
        } else {
            *error = @"";
        }
    });
    
    // compression
    parse(LDBOptionCompression, ^(id value, NSString **error) {
        if (auto number = [NSNumber ldb_cast:value]) {
            if ([number compare:@(LDBCompressionNoCompression)] == NSOrderedSame) {
                opts.compression = leveldb::kNoCompression;
            } else if ([number compare:@(LDBCompressionSnappyCompression)] == NSOrderedSame) {
                opts.compression = leveldb::kSnappyCompression;
            } else {
                *error = @"unrecognized compression type";
            }
        } else {
            *error = @"";
        }
    });
    
    // filter policy (bloom filter bits)
    parse(LDBOptionBloomFilterBits, ^(id value, NSString **error) {
        if (auto number = [NSNumber ldb_cast:value]) {
            int bits_per_key = number.intValue;
            if (bits_per_key > 0) {
                using ptr_t = std::unique_ptr<leveldb::FilterPolicy const>;
                _filter_policy = ptr_t(leveldb::NewBloomFilterPolicy(bits_per_key));
                opts.filter_policy = _filter_policy.get();
            }
        } else {
            *error = @"";
        }
    });
}

@end // LDBDatabase

@implementation LDBDatabase (Private)

- (leveldb::DB *)private_database
{
    return _db.get();
}

@end // LDBDatabase (Private)
