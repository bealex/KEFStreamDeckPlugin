//
// RawValue
// Package
//
// Created by Alex Babaev on 18 August 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

public protocol RawValueType: Codable {
    static var encodingType: String { get }
}

extension String: RawValueType {
    public static let encodingType: String = "string_"
}

extension Int32: RawValueType {
    public static let encodingType: String = "i32_"
}

extension Bool: RawValueType {
    public static let encodingType: String = "bool_"
}

extension PlaybackInfo.Source: RawValueType {
    public static let encodingType: String = "kefPhysicalSource"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        switch string {
            case "usb": self = .usb
            case "standby": self = .standby
            default: self = .unsupported
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .usb: try container.encode("usb")
            case .standby: try container.encode("standby")
            case .unsupported:
                throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "Can't encode uncnown source"))
        }
    }
}
