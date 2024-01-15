//
// Source
// Package
//
// Created by Alex Babaev on 28 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Combine
import Foundation
import KEFControl
import Memoirs
import StreamDeck

class Source: Action {
    struct Settings: Codable, Hashable {
        var ip: String?
    }

    private lazy var memoir: TracedMemoir = TracedMemoir(object: self, memoir: basicMemoir)

    private var kefControl: KEFControl = .init(api: KEFNetworkApi())

    private(set) static var name: String = "KEF Source"
    private(set) static var tooltip: String? = "Selects Audio Source"
    private(set) static var uuid: String = "com.lonelybytes.sdplugin.kef.source"
    private(set) static var icon: String = "volumeIcon"
    private(set) static var states: [PluginActionState]? = [
        .init(image: "actionVolume", title: "ON"),
        .init(image: "actionVolume", title: "OFF"),
    ]
    private(set) static var controllers: [ControllerType] = [ .keypad ]
    private(set) static var encoder: RotaryEncoder?

    private(set) var context: String = ""
    private(set) var coordinates: Coordinates? = nil

    private(set) static var propertyInspectorPath: String? = "PropertyInspector.Source/index.html"

    required init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
    }
}
