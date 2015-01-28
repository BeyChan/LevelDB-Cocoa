//
//  LevelDBTests.swift
//  LevelDBTests
//
//  Created by Pyry Jahkola on 26.01.2015.
//  Copyright (c) 2015 Pyrtsa. All rights reserved.
//

import Foundation
import XCTest
import LevelDB

extension String {
    var UTF8: NSData {
        return dataUsingEncoding(NSUTF8StringEncoding)!
    }
}

private func forkEqualRange<Ix : RandomAccessIndexType>
    (range: Range<Ix>, ord: Ix -> Ordering) -> (lower: Range<Ix>,
                                                upper: Range<Ix>)
{
    var (lo, hi) = (range.startIndex, range.endIndex)
    while lo < hi {
        let m = midIndex(lo, hi)
        switch ord(m) {
        case .LT: lo = m.successor()
        case .EQ: return (lo ..< m, m ..< hi)
        case .GT: hi = m
        }
    }
    return (lo ..< lo, lo ..< lo)
}

private func midIndex<Ix : RandomAccessIndexType>(start: Ix, end: Ix) -> Ix {
    return start.advancedBy(start.distanceTo(end) / 2)
}

extension WriteBatch {
    
    var diff: [(Key, Value?)] {
        var diffs: [(Key, Value?)] = []
        enumerate {key, value in
            let (lower, upper) = forkEqualRange(indices(diffs)) {i in
                return diffs[i].0.threeWayCompare(key)
            }
            if lower.startIndex != upper.endIndex {
                diffs[lower.endIndex] = (key, value)
            } else {
                diffs.insert((key, value), atIndex: lower.endIndex)
            }
        }
        return diffs
    }
    
}

extension NSData {
    var UTF8String: String {
        return NSString(data: self, encoding: NSUTF8StringEncoding)!
    }
}

func XCTAssertEqual<A : Equatable>(x: A?, y: A?, _ message: String = "", file: String = __FILE__, line: UInt = __LINE__) {
    XCTAssert(x == y, "\(x) is not equal to \(y) -- \(message)", file: file, line: line)
}

func XCTAssertEqual<A : Equatable, B : Equatable>(xs: [(A, B)], ys: [(A, B)], _ message: String = "", file: String = __FILE__, line: UInt = __LINE__) {
    XCTAssertEqual(xs.count, ys.count, message, file: file, line: line)
    for (x, y) in Zip2(xs, ys) {
        XCTAssertEqual(x.0, y.0, message, file: file, line: line)
        XCTAssertEqual(x.1, y.1, message, file: file, line: line)
    }
}

func XCTAssertEqual<A : Equatable, B : Equatable>(xs: [(A, B?)], ys: [(A, B?)], _ message: String = "", file: String = __FILE__, line: UInt = __LINE__) {
    XCTAssertEqual(xs.count, ys.count, message, file: file, line: line)
    for (x, y) in Zip2(xs, ys) {
        XCTAssertEqual(x.0, y.0, message, file: file, line: line)
        XCTAssertEqual(x.1, y.1, message, file: file, line: line)
    }
}

class LevelDBTests: XCTestCase {

    var path = ""
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        path = NSTemporaryDirectory().stringByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString)
        // NSLog("using temp path: %@", path)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        destroyDatabase(path)
        assert(!NSFileManager.defaultManager().fileExistsAtPath(path))
        super.tearDown()
    }
    
    func testInMemory() {
        let db = ByteDatabase()
        XCTAssertNil(db[NSData()])
        db[NSData()] = NSData()
        XCTAssertNotNil(db[NSData()])
        db[NSData()] = nil
        XCTAssertNil(db[NSData()])
    }
    
    func testOnDisk() {
        let maybeDb = ByteDatabase(path)
        XCTAssertNotNil(maybeDb)
        
        if maybeDb == nil { return }
        let db = maybeDb!
        XCTAssertNil(db[NSData()])
        
        db[NSData()] = NSData()
        XCTAssertNotNil(db[NSData()])
        
        db[NSData()] = nil
        XCTAssertNil(db[NSData()])
    }
    
    func testSnapshot() {
        let db = ByteDatabase(path)!
        for (k, v) in db.snapshot() {
            XCTFail("Expected empty database")
        }
        
        db[NSData()]  = NSData()
        db["a".UTF8]  = "foo".UTF8
        db["b".UTF8]  = "bar".UTF8
        db["ab".UTF8] = "qux".UTF8
        db["1".UTF8]  = "one".UTF8
        
        let snapshot = db.snapshot()
        db["2".UTF8]  = "two".UTF8
        let pairs = Array(snapshot).map {(k, v) -> (String, String) in
            db[k] = k
            return (k.UTF8String, v.UTF8String)
        }

        XCTAssertEqual(pairs, [("",  ""),
                               ("1",  "one"),
                               ("a",  "foo"),
                               ("ab", "qux"),
                               ("b",  "bar")])
        
        let revPairs = Array(snapshot.reverse).map {(k, v) -> (String, String) in
            return (k.UTF8String, v.UTF8String)
        }
        XCTAssertEqual(revPairs, [("b",  "bar"),
                                  ("ab", "qux"),
                                  ("a",  "foo"),
                                  ("1",  "one"),
                                  ("",  "")])
        
        let clampPairs = Array(snapshot["aa".UTF8 ... "c".UTF8]).map {(k, v) -> (String, String) in
            return (k.UTF8String, v.UTF8String)
        }

        XCTAssertEqual(clampPairs, [("ab", "qux"),
                                    ("b",  "bar")])

        let clampRevPairs = Array(snapshot.reverse["1".UTF8 ... "a".UTF8]).map {(k, v) -> (String, String) in
            return (k.UTF8String, v.UTF8String)
        }

        XCTAssertEqual(clampRevPairs, [("a",  "foo"),
                                       ("1",  "one")])

    }
    
    func testStringDatabase() {
    
        let db = Database<String, String>()
        
        db["foo"] = "bar"
        
        let byteValued = db.cast() as Database<String, NSData>
        let byteKeyed = db.cast() as Database<NSData, String>
        let byteDb = db.cast() as Database<NSData, NSData>

        XCTAssertEqual(db["foo"],             Optional("bar"))
        XCTAssertEqual(byteValued["foo"],     Optional("bar".UTF8))
        XCTAssertEqual(byteKeyed["foo".UTF8], Optional("bar"))
        XCTAssertEqual(byteDb["foo".UTF8],    Optional("bar".UTF8))

        db["foo"] = nil
    
        XCTAssertNil(db["foo"])

    }
    
    func testWriteBatch() {
    
        let batch = WriteBatch<String, String>()
        
        batch.put("foo", "bar")
        batch.delete("foo")
        
        XCTAssertEqual(batch.diff, [("foo", nil)])

        batch.put("qux", "abc")
        batch.delete("def")
        batch.delete("bar")
        batch.put("foo", "def")

        XCTAssertEqual(batch.diff, [("bar", nil),
                                    ("def", nil),
                                    ("foo", "def"),
                                    ("qux", "abc")])
    
        let db1 = Database<String, String>()
        
        db1["bar"] = "ghi"
        db1["baz"] = "jkl"
        
        XCTAssertEqual(db1["bar"], "ghi")
        XCTAssertEqual(db1["baz"], "jkl")
        
        XCTAssertNil(db1.write(batch).justError)
        
        XCTAssertEqual(db1["bar"], nil)
        XCTAssertEqual(db1["baz"], "jkl")
        XCTAssertEqual(db1["def"], nil)
        XCTAssertEqual(db1["foo"], "def")
        XCTAssertEqual(db1["qux"], "abc")

        let db2 = Database<String, String>(path)!
        
        db2["def"] = "ghi"
        db2["baz"] = "jkl"
        
        XCTAssertEqual(db2["def"], "ghi")
        XCTAssertEqual(db2["baz"], "jkl")
        
        XCTAssertNil(db2.write(batch).justError)
        
        XCTAssertEqual(db2["bar"], nil)
        XCTAssertEqual(db2["baz"], "jkl")
        XCTAssertEqual(db2["def"], nil)
        XCTAssertEqual(db2["foo"], "def")
        XCTAssertEqual(db2["qux"], "abc")
        
    }
    
    func testNextAfter() {
        XCTAssertEqual(nextAfter(AddBounds.min),       AddBounds(NSData()))
        XCTAssertEqual(nextAfter(AddBounds(NSData())), AddBounds.max)
        XCTAssertEqual(nextAfter(AddBounds.max),       AddBounds.max)

        XCTAssertEqual(nextAfter(AddBounds("A".UTF8)),   AddBounds("B".UTF8))
        XCTAssertEqual(nextAfter(AddBounds("Ab".UTF8)),  AddBounds("Ac".UTF8))
        XCTAssertEqual(nextAfter(AddBounds("x 8".UTF8)), AddBounds("x 9".UTF8))

        let bytes = {(var array: [UInt8]) -> AddBounds<NSData> in
            AddBounds(NSData(bytes: &array, length: array.count))
        }
        
        let m = UInt8.max
        XCTAssertEqual(nextAfter(bytes([m])),       AddBounds.max)
        XCTAssertEqual(nextAfter(bytes([m, m])),    AddBounds.max)
        XCTAssertEqual(nextAfter(bytes([m, m, m])), AddBounds.max)
        XCTAssertEqual(nextAfter(bytes([m, m, 9])), bytes([m, m, 10]))
        XCTAssertEqual(nextAfter(bytes([m, 0, m])), bytes([m, 1, 0]))
        XCTAssertEqual(nextAfter(bytes([m, 1, m])), bytes([m, 2, 0]))
        XCTAssertEqual(nextAfter(bytes([5, m, m])), bytes([6, 0, 0]))
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
