//
// RawValueTests
// KEFControl
//
// Created by Alex Babaev on 09 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation
import XCTest
import KEFControl

class RawValueTests: XCTestCase {
    private let decoder: JSONDecoder = .init()
    private let encoder: JSONEncoder = .init()

    func testStringDecoding() throws {
        let test = "correct result"
        let jsonData = """
                       { "type": "string_", "string_": "\(test)" }
                       """
        let value: RawValue<String> = try decoder.decode(RawValue<String>.self, from: Data(jsonData.utf8))
        XCTAssertEqual(test, value.value)
    }

    func testInt32Decoding() throws {
        let test: Int32 = 42
        let jsonData = """
                       { "type": "i32_", "i32_": \(test) }
                       """
        let value: RawValue<Int32> = try decoder.decode(RawValue<Int32>.self, from: Data(jsonData.utf8))
        XCTAssertEqual(test, value.value)
    }

    func testBoolDecoding() throws {
        let test: Bool = false
        let jsonData = """
                       { "type": "bool_", "bool_": \(test) }
                       """
        let value: RawValue<Bool> = try decoder.decode(RawValue<Bool>.self, from: Data(jsonData.utf8))
        XCTAssertEqual(test, value.value)
    }

    func testPhysicalSource() throws {
        let test: PlaybackInfo.Source = .standby
        let jsonData = """
                       { "type": "kefPhysicalSource", "kefPhysicalSource": "standby" }
                       """
        let value: RawValue<PlaybackInfo.Source> = try decoder.decode(RawValue<PlaybackInfo.Source>.self, from: Data(jsonData.utf8))
        XCTAssertEqual(test, value.value)
    }

    func testOptionalBoolDecoding() throws {
        let jsonData = """
                       { "type": "bool_", "bool_": null }
                       """
        let value: RawValue<Bool> = try decoder.decode(RawValue<Bool>.self, from: Data(jsonData.utf8))
        XCTAssertEqual(nil, value.value)
    }

    func testStringEncoding() throws {
        let test = "correct result"
        let value: RawValue<String> = .init(test)
        let encoded = try encoder.encode(value)
        let testResult: [String: Any] = [ "type": "string_", "string_": test ]
        try compare(test: testResult, result: encoded)
    }

    func testInt32Encoding() throws {
        let test: Int32 = 42
        let value: RawValue<Int32> = .init(test)
        let encoded = try encoder.encode(value)
        let testResult: [String: Any] = [ "type": "i32_", "i32_": test ]
        try compare(test: testResult, result: encoded)
    }

    func testBoolEncoding() throws {
        let test: Bool = true
        let value: RawValue<Bool> = .init(test)
        let encoded = try encoder.encode(value)
        let testResult: [String: Any] = [ "type": "bool", "bool_": test ]
        try compare(test: testResult, result: encoded)
    }

    private func compare(test: [String: Any], result: Data) throws {
        let resultJson = try JSONSerialization.jsonObject(with: result) as? [String: Any]
        guard
            let resultJson,
            resultJson.count == test.count,
            try test.contains(where: { key, value in
                let result = try JSONSerialization.data(withJSONObject: resultJson[key] ?? "", options: .fragmentsAllowed)
                let test = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
                return result == test
            })
        else { return XCTFail("result is not same as the test: \nresult:\n\(resultJson ?? [:])\ntest\n\(test)") }
    }
}
