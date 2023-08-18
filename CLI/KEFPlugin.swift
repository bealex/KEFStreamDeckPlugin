//
// kefcli
// KEFControl
//
// Created by Alex Babaev on 09 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation
import KEFControl
import Memoirs
import StreamDeck

@main
class KEFPlugin: PluginDelegate {
    private lazy var memoir: TracedMemoir = TracedMemoir(object: self, memoir: basicMemoir)

    private(set) static var name: String = "com.lonelybytes.sdplugin.kef"
    private(set) static var description: String = "Provides KEF LSX II, LS50, LS60 control."
    private(set) static var author: String = "Alex Babaev"
    private(set) static var icon: String = "pluginIcon"
    private(set) static var version: String = "1.0"
    private(set) static var os: [PluginOS] = [ .mac(minimumVersion: "11") ]
    private(set) static var actions: [any Action.Type] = [ Volume.self, Source.self ]

    private(set) static var url: URL? = URL(string: "https://github.com/bealex/StreamDeckKEFPlugin")
    private(set) static var category: String? = "KEF"
    private(set) static var categoryIcon: String? = "category"

    required init() {
        memoir.debug("")
    }

    func didReceiveGlobalSettings(_ settings: [String: String]) {
        memoir.debug("")
    }

    func deviceDidConnect(_ device: String, deviceInfo: DeviceInfo) {
        memoir.debug("")
    }

    func deviceDidDisconnect(_ device: String) {
        memoir.debug("")
    }

    func systemDidWakeUp() {
        memoir.debug("")
    }

    static func pluginWasCreated() {
        #if DEBUG
        print("\(FileManager.default.currentDirectoryPath)")
        #endif
    }

    func sentToPlugin(context: String, action: String, payload: [String: String]) {
        memoir.debug("\(context); \(action); \(payload)")
    }
}
