//
// PlaybackInfo
// KEFControl
//
// Created by Alex Babaev on 04 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

public struct PlaybackInfo {
    public enum Source: Hashable {
        case standby
        case usb

        case unsupported
    }

    public var source: Source = .standby
    public var volume: Int32 = 0
    public var isMuted: Bool = false

    public init(source: Source = .standby, volume: Int32 = 0, isMuted: Bool = false) {
        self.source = source
        self.volume = volume
        self.isMuted = isMuted
    }
}
