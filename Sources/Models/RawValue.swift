//
// RawValue
// Package
//
// Created by Alex Babaev on 22 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

public struct RawValue<Type: RawValueType>: Codable {
    public var value: Type?

    enum CodingKeys: CodingKey {
        case type
        case value(type: String)

        init?(stringValue: String) {
            self = stringValue == "type" ? .type : .value(type: stringValue)
        }

        var stringValue: String {
            switch self {
                case .type: return "type"
                case .value(let type): return type
            }
        }

        init?(intValue: Int) { nil }
        var intValue: Int? { nil }
    }

    public init(_ value: Type?) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedType = try container.decode(String.self, forKey: .type)
        guard decodedType == Type.encodingType else {
            let message = "Decoded type \(decodedType) != Generic type \(Type.encodingType)"
            throw DecodingError.dataCorruptedError(in: container, debugDescription: message)
        }

        value = try container.decode(Type?.self, forKey: CodingKeys.value(type: Type.encodingType))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Type.encodingType, forKey: .type)
        try container.encode(value, forKey: CodingKeys.value(type: Type.encodingType))
    }
}
