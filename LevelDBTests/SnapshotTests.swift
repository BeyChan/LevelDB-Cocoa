//
//  SnapshotTests.swift
//  LevelDB
//
//  Copyright (c) 2015 Pyry Jahkola. All rights reserved.
//

import XCTest
import LevelDB

infix operator |> { associativity left precedence 95 }

func |> <A, B>(a: A, f: A -> B) -> B { return f(a) }

class SnapshotTests : XCTestCase {

    var path = ""
    
    override func setUp() {
        super.setUp()
        path = tempDbPath()
    }
    
    override func tearDown() {
        destroyTempDb(path)
        super.tearDown()
    }
    
    func testSnapshot() {
        let db = LDBDatabase(path)!
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
        
        if true {
            XCTAssertEqual(snapshot["".UTF8], "".UTF8)
            XCTAssertEqual(snapshot["1".UTF8], "one".UTF8)
            XCTAssertNil(snapshot["2".UTF8])
        }
        
        let revPairs = Array(snapshot.reversed).map {(k, v) -> (String, String) in
            return (k.UTF8String, v.UTF8String)
        }
        XCTAssertEqual(revPairs, [("b",  "bar"),
                                  ("ab", "qux"),
                                  ("a",  "foo"),
                                  ("1",  "one"),
                                  ("",  "")])
        
        let clampPairs = Array(snapshot.clamp(from: "aa".UTF8, to: "c".UTF8)).map {
            (k, v) -> (String, String) in
            return (k.UTF8String, v.UTF8String)
        }

        XCTAssertEqual(clampPairs, [("ab", "qux"),
                                    ("b",  "bar")])

        let clampRevPairs = Array(snapshot.reversed.clamp(from: "1".UTF8, to: "a ".UTF8)).map {
            (k, v) -> (String, String) in
            return (k.UTF8String, v.UTF8String)
        }
        NSLog("%@", clampRevPairs.description)
        XCTAssertEqual(clampRevPairs, [("a",  "foo"),
                                       ("1",  "one")])

    }

    func testPrefix() {
        let db = Database<String, String>(path)!
        
        db["/z"]          = "end"
        db["/people/foo"] = "foo"
        db["/people/bar"] = "bar"
        db["/pets/cat"]   = "meow"
        db["/pets/dog"]   = "barf"
        db["/other"]      = "other"

        let snapshot = db.snapshot()
        
        XCTAssertEqual(snapshot.values.array, ["other", "bar", "foo", "meow", "barf", "end"])
        
        let people = snapshot.prefix("/people/")
        let pets   = snapshot.prefix("/pets/")
        let peh    = snapshot.prefix("/pe")
        let dehcat0 = snapshot["/people/deh" ..< "/pets/cat"]
        let dehcat1 = snapshot["/people/deh" ..< "/pets/cat "]
        let dehcat2 = snapshot["/people/deh" ... "/pets/cat"]
        let dehdog  = snapshot["/people/deh" ... "/pets/dog"]
        let postcat = snapshot.clamp(after: "/pets/cat", to: nil)
        
        XCTAssertEqual(people.values.array, ["bar", "foo"])
        XCTAssertEqual(pets.values.array, ["meow", "barf"])
        XCTAssertEqual(peh.values.array, ["bar", "foo", "meow", "barf"])
        XCTAssertEqual(dehcat0.values.array, ["foo"])
        XCTAssertEqual(dehcat1.values.array, ["foo", "meow"])
        XCTAssertEqual(dehcat2.values.array, ["foo", "meow"])
        XCTAssertEqual(dehdog.values.array, ["foo", "meow", "barf"])
        XCTAssertEqual(postcat.values.array, ["barf", "end"])
        
    }
    
    func testClamping() {
        let db = Database<String, String>(path)!
        let keys = map(0 ..< 100) {i in "\(i / 10)\(i % 10)"}
        let batch = WriteBatch<String, String>()
        for k in keys {
            batch[k] = ""
        }
        XCTAssert(db.write(batch, sync: false, error: nil))
        
        let snap = db.snapshot()

        XCTAssertEqual(snap.keys.array,                                   keys)

        XCTAssertEqual(snap["20" ..< "33"].keys.array,                    Array(keys[20 ..< 33]))
        XCTAssertEqual(snap["10" ... "20"].keys.array,                    Array(keys[10 ... 20]))

        XCTAssertEqual(snap.clamp(to:      "3"  ).keys.array,             Array(keys[ 0 ... 29]))
        XCTAssertEqual(snap.clamp(to:      "31" ).keys.array,             Array(keys[ 0 ... 30]))
        XCTAssertEqual(snap.clamp(through: "3"  ).keys.array,             Array(keys[ 0 ... 29]))
        XCTAssertEqual(snap.clamp(through: "31" ).keys.array,             Array(keys[ 0 ... 31]))
        XCTAssertEqual(snap.clamp(from:    "31" ).keys.array,             Array(keys[31 ... 99]))
        XCTAssertEqual(snap.clamp(from:    "311").keys.array,             Array(keys[32 ... 99]))
        XCTAssertEqual(snap.clamp(after:   "5"  ).keys.array,             Array(keys[50 ... 99]))
        XCTAssertEqual(snap.clamp(after:   "50" ).keys.array,             Array(keys[51 ... 99]))

        XCTAssertEqual(snap.clamp(from:  "50", to:      "55").keys.array, Array(keys[50 ... 54]))
        XCTAssertEqual(snap.clamp(from:  "50", through: "55").keys.array, Array(keys[50 ... 55]))
        XCTAssertEqual(snap.clamp(after: "50", to:      "55").keys.array, Array(keys[51 ... 54]))
        XCTAssertEqual(snap.clamp(after: "50", through: "55").keys.array, Array(keys[51 ... 55]))

        XCTAssertEqual(snap.clamp(from:   nil, to:      "55").keys.array, Array(keys[ 0 ... 54]))
        XCTAssertEqual(snap.clamp(from:   nil, through: "55").keys.array, Array(keys[ 0 ... 55]))
        XCTAssertEqual(snap.clamp(after:  nil, to:      "55").keys.array, Array(keys[ 0 ... 54]))
        XCTAssertEqual(snap.clamp(after:  nil, through: "55").keys.array, Array(keys[ 0 ... 55]))

        XCTAssertEqual(snap.clamp(from:  "50", to:       nil).keys.array, Array(keys[50 ... 99]))
        XCTAssertEqual(snap.clamp(from:  "50", through:  nil).keys.array, Array(keys[50 ... 99]))
        XCTAssertEqual(snap.clamp(after: "50", to:       nil).keys.array, Array(keys[51 ... 99]))
        XCTAssertEqual(snap.clamp(after: "50", through:  nil).keys.array, Array(keys[51 ... 99]))

        XCTAssertEqual(snap.clamp(from:   nil, to:       nil).keys.array, keys)
        XCTAssertEqual(snap.clamp(from:   nil, through:  nil).keys.array, keys)
        XCTAssertEqual(snap.clamp(after:  nil, to:       nil).keys.array, keys)
        XCTAssertEqual(snap.clamp(after:  nil, through:  nil).keys.array, keys)
    }
    
    func testReadOptions() {
        let db = Database<String, String>(path)!
        
        db["foo"] = "FOO"
        db["bar"] = "BAR"
        
        let snapshot = db.snapshot()
        
        let foo = snapshot.checksummed |> {snap in snap["foo"]}
        let bar = snapshot.noncaching  |> {snap in snap["bar"]}
        let all = snapshot.noncaching  |> {snap in snap.values.array}
        XCTAssertEqual(foo, "FOO")
        XCTAssertEqual(bar, "BAR")
        XCTAssertEqual(all, ["BAR", "FOO"])
    }
    
}