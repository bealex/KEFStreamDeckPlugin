//
// PlaybackInfo
// KEFControl
//
// Created by Alex Babaev on 04 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

public struct PlaybackInfo: Equatable {
    public enum Source: String, Hashable {
        case standby
        case usb
        case optical

        case unsupported

        /// Inputs the user can switch to; `standby` and `unsupported` are states, not choices.
        public static let selectable: [Source] = [ .usb, .optical ]

        public var title: String {
            switch self {
                case .standby: "Standby"
                case .usb: "USB"
                case .optical: "Optical"
                case .unsupported: "Unsupported"
            }
        }
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
