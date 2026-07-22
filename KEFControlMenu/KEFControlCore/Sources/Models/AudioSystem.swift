//
// AudioSystem
// KEFControl
//
// Created by Alex Babaev on 04 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

public struct AudioSystem: Equatable {
    public enum Model: String, CaseIterable, Equatable {
        case lsxII
        case ls50
        case ls60
        case unknown

        public var title: String {
            switch self {
                case .lsxII: "LSX II"
                case .ls50: "LS50 Wireless II"
                case .ls60: "LS60 Wireless"
                case .unknown: "Unknown"
            }
        }

        /// Fragments of a CoreAudio device name/uid that identify these speakers when they are connected over USB.
        public var audioDeviceNameHints: [String] {
            switch self {
                case .lsxII: [ "lsx" ]
                case .ls50: [ "ls50" ]
                case .ls60: [ "ls60" ]
                case .unknown: []
            }
        }
    }

    public var name: String
    public var model: Model

    public init(name: String, model: Model) {
        self.name = name
        self.model = model
    }
}
