//
//  LevelDB.swift
//  LevelDB
//
//  Copyright (c) 2015 Pyry Jahkola. All rights reserved.
//

import Foundation.NSError
import Foundation.NSData
import LevelDB

public extension LDBDatabase {

    /// TODO
    public typealias Element = (key: NSData, value: NSData)
    
    /// TODO
    public convenience init?(_ path: String) {
        self.init(path: path)
    }
    
    /// TODO
    public convenience init?(path:                 String,
                             inout error:          NSError?,
                             createIfMissing:      Bool?           = nil,
                             errorIfExists:        Bool?           = nil,
                             paranoidChecks:       Bool?           = nil,
                             infoLog:              (String -> ())? = nil,
                             writeBufferSize:      Int?            = nil,
                             maxOpenFiles:         Int?            = nil,
                             cacheCapacity:        Int?            = nil,
                             blockSize:            Int?            = nil,
                             blockRestartInterval: Int?            = nil,
                             compression:          LDBCompression? = nil,
                             bloomFilterBits:      Int?            = nil)
    {
        var opts = [String: AnyObject]()
        if let x = createIfMissing { opts[LDBOptionCreateIfMissing] = x }
        if let x = errorIfExists   { opts[LDBOptionErrorIfExists] = x }
        if let x = paranoidChecks  { opts[LDBOptionParanoidChecks] = x }
        if let f = infoLog         { opts[LDBOptionInfoLog] = LDBLogger {s in f(s)} }
        if let x = writeBufferSize { opts[LDBOptionWriteBufferSize] = x }
        if let x = maxOpenFiles    { opts[LDBOptionMaxOpenFiles] = x }
        if let x = cacheCapacity   { opts[LDBOptionCacheCapacity] = x }
        if let x = blockSize       { opts[LDBOptionBlockSize] = x }
        if let x = blockRestartInterval { opts[LDBOptionBlockRestartInterval] = x }
        if let x = compression     { opts[LDBOptionCompression] = x.rawValue }
        if let x = bloomFilterBits { opts[LDBOptionBloomFilterBits] = x }
        self.init(path: path, options: opts, error: &error)
    }
    
}

extension LDBEnumerator : GeneratorType {

    public typealias Element = LDBDatabase.Element
    
    public func next() -> Element? {
        if let k = key {
            if let v = value {
                self.step()
                return (k, v)
            }
        }
        return nil
    }

}

extension LDBSnapshot : SequenceType {
    
    public typealias Generator = LDBEnumerator
    
    public func generate() -> Generator {
        return enumerator()
    }
}

extension LDBSnapshot {

    public typealias Element = (key: NSData, value: NSData)
    
    public func clamp(#from: NSData?, to: NSData?) -> LDBSnapshot {
        return clampStart(from, end: to)
    }

    public func clamp(#from: NSData?, through: NSData?) -> LDBSnapshot {
        return clampStart(from, end: through?.ldb_lexicographicalFirstChild())
    }
    
    public func clamp(#after: NSData?, to: NSData?) -> LDBSnapshot {
        return clampStart(after?.ldb_lexicographicalFirstChild(), end: to)
    }
    
    public func clamp(#after: NSData?, through: NSData?) -> LDBSnapshot {
        return clampStart(after?.ldb_lexicographicalFirstChild(),
                          end: through?.ldb_lexicographicalFirstChild())
    }
    
    public var keys: LazySequence<MapSequenceView<LDBSnapshot, NSData>> {
        return lazy(self).map {k, _ in k}
    }

    public var values: LazySequence<MapSequenceView<LDBSnapshot, NSData>> {
        return lazy(self).map {_, v in v}
    }
    
    public var first: Element? {
        var g = generate()
        return g.next()
    }
    
    public var last: Element? {
        let r = reversed
        var g = r.generate()
        return g.next()
    }
    
}

extension LDBWriteBatch {

    /// TODO
    public func put<K : DataSerializable,
                    V : DataSerializable>(key: K, _ value: V)
    {
        self[key.serializedData] = value.serializedData
    }
    
    /// TODO
    public func delete<K : DataSerializable>(key: K) {
        self[key.serializedData] = nil
    }

    public func enumerate<K : DataSerializable,
                          V : DataSerializable>(block: (K, V?) -> ()) {
        enumerate {k, v in
            if let key = K(serializedData: k) {
                if let data = v {
                    if let value = V(serializedData: data) {
                        block(key, value)
                    } else {
                        // skipped
                    }
                } else {
                    block(key, nil)
                }
            } else {
                // skipped
            }
        }
    }

}

public final class Database<K : protocol<DataSerializable, Comparable>,
                            V : DataSerializable>
{
    public typealias Key = K
    public typealias Value = V
    public typealias Element = (key: Key, value: Value)
    
    private let _object: LDBDatabase?
    public var object: LDBDatabase {
        return _object!
    }
    
    public init() {
        self._object = LDBDatabase()
    }
    
    public init?(_ path: String) {
        self._object = LDBDatabase(path)
        if _object == nil {
            return nil
        }
    }
    
    public init(_ database: LDBDatabase) {
        self._object = database
    }
    
    public subscript(key: Key) -> Value? {
        get {
            if let data = object[key.serializedData] {
                return Value(serializedData: data)
            } else {
                return nil
            }
        }
        set {
            object[key.serializedData] = newValue?.serializedData
        }
    }
    
    public func snapshot() -> Snapshot<Key, Value> {
        return Snapshot(object.snapshot())
    }
    
    public func write(batch: WriteBatch<Key, Value>,
                      sync: Bool,
                      inout error: NSError?) -> Bool
    {
        return object.write(batch.object, sync: sync, error: &error)
    }
    
    public func approximateSizes(intervals: [(Key?, Key?)]) -> [UInt64] {
        let dataIntervals = intervals.map {start, end in
            LDBInterval(start: start?.serializedData,
                        end: end?.serializedData)
        }
        return object.approximateSizesForIntervals(dataIntervals).map {n in
            // FIXME: Swift 1.1 compatible cast. Replace with `as!` once in 1.2.
            (n as? NSNumber)!.unsignedLongLongValue
        }
    }

    public func approximateSize(start: Key?, _ end: Key?) -> UInt64 {
        return approximateSizes([(start, end)])[0]
    }

    public func compactInterval(start: Key?, _ end: Key?) {
        object.compactInterval(LDBInterval(start: start?.serializedData,
                                           end:   end?.serializedData))
    }
}

public struct Snapshot<K : protocol<DataSerializable, Comparable>,
                       V : DataSerializable>
{
    public typealias Key = K
    public typealias Value = V
    public typealias Element = (key: Key, value: Value)
    
    public let object: LDBSnapshot
    
    public init(_ snapshot: LDBSnapshot) {
        self.object = snapshot
    }
    
    public var noncaching:  Snapshot { return Snapshot(object.noncaching) }
    public var checksummed: Snapshot { return Snapshot(object.checksummed) }
    public var reversed:    Snapshot { return Snapshot(object.reversed) }
    
    public var isNoncaching:  Bool { return object.isNoncaching }
    public var isChecksummed: Bool { return object.isChecksummed }
    public var isReversed:    Bool { return object.isReversed }
    
    public func prefix(prefixKey: Key) -> Snapshot {
        return Snapshot(object.prefix(prefixKey.serializedData))
    }
    
    public func clamp(#from: Key?, to: Key?) -> Snapshot {
        return Snapshot(object.clamp(from: from?.serializedData,
                                     to:   to?.serializedData))
    }
    
    public func clamp(#from: Key?, through: Key?) -> Snapshot {
        return Snapshot(object.clamp(from:    from?.serializedData,
                                     through: through?.serializedData))
    }
    
    public func clamp(#after: Key?, to: Key?) -> Snapshot {
        return Snapshot(object.clamp(after: after?.serializedData,
                                     to:    to?.serializedData))
    }
    
    public func clamp(#after: Key?, through: Key?) -> Snapshot {
        return Snapshot(object.clamp(after:   after?.serializedData,
                                     through: through?.serializedData))
    }
    
    public subscript(key: Key) -> Value? {
        if let data = object[key.serializedData] {
            return Value(serializedData: data)
        } else {
            return nil
        }
    }
    
    public subscript(interval: HalfOpenInterval<Key>) -> Snapshot {
        return clamp(from: interval.start, to: interval.end)
    }
    
    public subscript(interval: ClosedInterval<Key>) -> Snapshot {
        return clamp(from: interval.start, through: interval.end)
    }
    
}

public struct SnapshotGenerator<K : protocol<DataSerializable, Comparable>,
                                V : DataSerializable> : GeneratorType
{
    public typealias Key = K
    public typealias Value = V
    public typealias Element = (key: Key, value: Value)

    private let enumerator: LDBEnumerator
    
    internal init(snapshot: Snapshot<K, V>) {
        self.enumerator = snapshot.object.enumerator()
    }
    
    public func next() -> Element? {
        while let (k, v) = enumerator.next() {
            if let key = Key(serializedData: k) {
                if let value = Value(serializedData: v) {
                    return (key: key, value: value)
                }
            }
        }
        return nil
    }
}

extension Snapshot : SequenceType {

    public typealias Generator = SnapshotGenerator<K, V>

    public func generate() -> Generator {
        return Generator(snapshot: self)
    }
}

extension Snapshot {
    
    public var keys: LazySequence<MapSequenceView<Snapshot, Key>> {
        return lazy(self).map {k, _ in k}
    }

    public var values: LazySequence<MapSequenceView<Snapshot, Value>> {
        return lazy(self).map {_, v in v}
    }
    
    public var first: Element? {
        var g = generate()
        return g.next()
    }
    
    public var last: Element? {
        let r = reversed
        var g = r.generate()
        return g.next()
    }
    
}

public final class WriteBatch<K : protocol<DataSerializable, Comparable>,
                              V : DataSerializable>
{
    public typealias Key = K
    public typealias Value = V
    public typealias Element = (key: Key, value: Value)

    public let object: LDBWriteBatch
    
    public init() {
        self.object = LDBWriteBatch()
    }
    
    public init(_ batch: LDBWriteBatch) {
        self.object = batch
    }
    
    public subscript(key: Key) -> Value? {
        get { return nil }
        set {
            object[key.serializedData] = newValue?.serializedData
        }
    }
    
    public func enumerate(block: (Key, Value?) -> ()) {
        object.enumerate {k, v in
            if let key = Key(serializedData: k) {
                if let data = v {
                    if let value = Value(serializedData: data) {
                        block(key, value)
                    }
                } else {
                    block(key, nil)
                }
            }
        }
    }
}
