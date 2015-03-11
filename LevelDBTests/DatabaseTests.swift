//
//  DatabaseTests.swift
//  DatabaseTests
//
//  Copyright (c) 2015 Pyrtsa. All rights reserved.
//

import Foundation
import XCTest
import LevelDB

class DatabaseTests : XCTestCase {

    var path = ""
    
    override func setUp() {
        super.setUp()
        path = tempDbPath()
    }
    
    override func tearDown() {
        destroyTempDb(path)
        super.tearDown()
    }
    
    func testInMemory() {
        let db: LDBDatabase = LDBDatabase()
        XCTAssertNil(db[NSData()])
        db[NSData()] = NSData()
        XCTAssertNotNil(db[NSData()])
        db[NSData()] = nil
        XCTAssertNil(db[NSData()])
    }
    
    func testOnDisk() {
        let maybeDb: LDBDatabase? = LDBDatabase(path)
        XCTAssertNotNil(maybeDb)
        
        if maybeDb == nil { return }
        let db = maybeDb!
        XCTAssertNil(db[NSData()])
        
        db[NSData()] = NSData()
        XCTAssertNotNil(db[NSData()])

        NSLog("approximate size: %u", db.approximateSizesForIntervals([
            LDBInterval(start: NSData(), end: nil)
        ]))
        
        db[NSData()] = nil
        XCTAssertNil(db[NSData()])
    }
    
    func testStringDatabase() {
    
        let db = Database<String, String>()
        
        db["foo"] = "bar"
        
        let rawDb = db.object

        XCTAssertEqual(db["foo"],         Optional("bar"))
        XCTAssertEqual(rawDb["foo".UTF8], Optional("bar".UTF8))

        db["foo"] = nil
    
        XCTAssertNil(db["foo"])

    }
    
    func testWriteBatch() {
    
        let batch = WriteBatch<String, String>()
        
        batch["foo"] = "bar"
        batch["foo"] = nil
        
        XCTAssertEqual(batch.diff, [("foo", nil)])

        batch["qux"] = "abc"
        batch["def"] = nil
        batch["bar"] = nil
        batch["foo"] = "def"

        XCTAssertEqual(batch.diff, [("bar", nil),
                                    ("def", nil),
                                    ("foo", "def"),
                                    ("qux", "abc")])
    
        let db1 = Database<String, String>()
        
        db1["bar"] = "ghi"
        db1["baz"] = "jkl"
        
        XCTAssertEqual(db1["bar"], "ghi")
        XCTAssertEqual(db1["baz"], "jkl")
        
        if true {
            var error: NSError?
            XCTAssert(db1.write(batch, sync: false, error: &error))
            XCTAssertNil(error)
        }
        
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
        
        if true {
            var error: NSError?
            XCTAssert(db2.write(batch, sync: false, error: &error))
            XCTAssertNil(error)
        }
        
        XCTAssertEqual(db2["bar"], nil)
        XCTAssertEqual(db2["baz"], "jkl")
        XCTAssertEqual(db2["def"], nil)
        XCTAssertEqual(db2["foo"], "def")
        XCTAssertEqual(db2["qux"], "abc")
        
    }
    
    func testOpenFailures() {
        if true {
            var error: NSError?
            XCTAssertNil(LDBDatabase(path: path, error: &error))
            XCTAssertNotNil(error, "should fail with `createIfMissing: false`")
        }
        if true {
            var error: NSError?
            XCTAssertNotNil(LDBDatabase(path: path, error: &error, createIfMissing: true))
            XCTAssertNil(error, "should succeed with `createIfMissing: true`")
        }
        if true {
            var error: NSError?
            XCTAssertNil(LDBDatabase(path: path, error: &error, errorIfExists: true))
            XCTAssertNotNil(error, "should fail with `errorIfExists: true`")
        }
    }
    
    func testFilterPolicyOption() {
        var error: NSError?
        let maybeDb = LDBDatabase(path: path, error: &error,
            createIfMissing: true,
            bloomFilterBits: 10)
        if let error = error {
            XCTFail("Database.open failed with error: \(error)")
            return
        }
        let db = maybeDb!
        
        db["foo".UTF8] = "bar".UTF8
        
        XCTAssertEqual(db["foo".UTF8], "bar".UTF8)
    }
    
    func testCacheOption() {
        var error: NSError?
        let maybeDb = LDBDatabase(path: path, error: &error,
            createIfMissing: true,
            cacheCapacity: 2 << 20)
        if let error = error {
            XCTFail("Database.open failed with error: \(error)")
            return
        }
        let db = maybeDb!
        
        db["foo".UTF8] = "bar".UTF8
        
        XCTAssertEqual(db["foo".UTF8], "bar".UTF8)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
