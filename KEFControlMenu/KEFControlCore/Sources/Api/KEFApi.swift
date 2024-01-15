//
// KEFApi
// Package
//
// Created by Alex Babaev on 26 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

public enum KEFValue {
    case volume(Int32)
    case isMuted(Bool)
    case source(PlaybackInfo.Source)
    case name(String)
    case model(AudioSystem.Model)
}

public struct KEFValueOptions {
    var volume: Int32 = 0
    var isMuted: Bool = false
    var physicalSource: PlaybackInfo.Source = .unsupported
    var name: String = "KEF"
    var model: AudioSystem.Model = .unknown
}

public protocol KEFApi {
    func set<Type: RawValueType>(value: Type, for path: KeyPath<KEFValueOptions, Type>, ip: String) async throws
    func get<Type>(_ path: KeyPath<KEFValueOptions, Type>, ip: String) async throws -> Type

    func events(for ip: String) throws -> (AsyncStream<KEFValue>, id: String)
    func terminateEventsStream(id: String)
}
