//
// AudioSystem
// KEFControl
//
// Created by Alex Babaev on 04 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

public struct AudioSystem: Equatable {
    public enum Model: Equatable {
        case lsxII
        case ls50
        case ls60
        case unknown
    }

    public var name: String
    public var model: Model
}
