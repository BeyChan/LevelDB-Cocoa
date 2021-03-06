//
//  NSDataTests.swift
//  LevelDB
//
//  Copyright (c) 2015 Pyry Jahkola. All rights reserved.
//

import Foundation
import XCTest
import LevelDB

class NSDataTests : XCTestCase {

    func testLexicographicalNextSibling() {
        XCTAssertEqual(NSData().ldb_lexicographicalNextSibling(),        nil)

        XCTAssertEqual("A".UTF8.ldb_lexicographicalNextSibling(), "B".UTF8)
        XCTAssertEqual("Ab".UTF8.ldb_lexicographicalNextSibling(), "Ac".UTF8)
        XCTAssertEqual("x 8".UTF8.ldb_lexicographicalNextSibling(), "x 9".UTF8)

        let m = UInt8.max
        XCTAssertEqual(NSData(bytes: m).ldb_lexicographicalNextSibling(),       nil)
        XCTAssertEqual(NSData(bytes: m, m).ldb_lexicographicalNextSibling(),    nil)
        XCTAssertEqual(NSData(bytes: m, m, m).ldb_lexicographicalNextSibling(), nil)
        XCTAssertEqual(NSData(bytes: m, m, 9).ldb_lexicographicalNextSibling(), NSData(bytes: m, m, 10))
        XCTAssertEqual(NSData(bytes: m, 0, m).ldb_lexicographicalNextSibling(), NSData(bytes: m, 1, 0))
        XCTAssertEqual(NSData(bytes: m, 1, m).ldb_lexicographicalNextSibling(), NSData(bytes: m, 2, 0))
        XCTAssertEqual(NSData(bytes: 5, m, m).ldb_lexicographicalNextSibling(), NSData(bytes: 6, 0, 0))
    }
    
    func testLexicographicalFirstChild() {
        XCTAssertEqual(NSData().ldb_lexicographicalFirstChild(),        NSData(bytes: 0))

        XCTAssertEqual(NSData(bytes: 0).ldb_lexicographicalFirstChild(),      NSData(bytes: 0, 0))
        XCTAssertEqual(NSData(bytes: 10).ldb_lexicographicalFirstChild(),     NSData(bytes: 10, 0))
        XCTAssertEqual(NSData(bytes: 10, 20).ldb_lexicographicalFirstChild(), NSData(bytes: 10, 20, 0))

        let m = UInt8.max
        XCTAssertEqual(NSData(bytes: m).ldb_lexicographicalFirstChild(),       NSData(bytes: m, 0))
        XCTAssertEqual(NSData(bytes: m, m).ldb_lexicographicalFirstChild(),    NSData(bytes: m, m, 0))
        XCTAssertEqual(NSData(bytes: m, m, m).ldb_lexicographicalFirstChild(), NSData(bytes: m, m, m, 0))
        XCTAssertEqual(NSData(bytes: m, m, 9).ldb_lexicographicalFirstChild(), NSData(bytes: m, m, 9, 0))
    }

}
