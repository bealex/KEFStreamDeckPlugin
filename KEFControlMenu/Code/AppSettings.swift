//
// AppSettings
// KEFControlMenu
//
// Created by Alexander Babaev on 22 July 2026.
// Copyright © 2026 Alexander Babaev. All rights reserved.
//

import Combine
import Foundation
import KEFControl
import KeyboardShortcuts
import Observation

@Observable @MainActor
final class AppSettings {
    private enum Key {
        static let speakerAddress: String = "kef.speakerAddress"
        static let speakerInstance: String = "kef.speakerInstance"
        static let model: String = "kef.model"
        static let defaultInput: String = "kef.defaultInput"
        static let outputDeviceNameHint: String = "kef.outputDeviceNameHint"
        static let didSetDefaultShortcuts: String = "shortcuts.didSetDefaults"
    }

    /// IP address or hostname of the speakers.
    var speakerAddress: String { didSet { didChange() } }
    /// Bonjour instance of the speakers we adopted, so they can be followed to a new address.
    var speakerInstance: String { didSet { didChange() } }
    var model: AudioSystem.Model { didSet { didChange() } }
    /// Input the speakers are switched to when they are woken up from standby.
    var defaultInput: PlaybackInfo.Source { didSet { didChange() } }
    /// Optional override for matching the speakers against the system output device, when the name is not obvious.
    var outputDeviceNameHint: String { didSet { didChange() } }

    var changePublisher: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        speakerAddress = defaults.string(forKey: Key.speakerAddress) ?? ""
        speakerInstance = defaults.string(forKey: Key.speakerInstance) ?? ""
        model = defaults.string(forKey: Key.model).flatMap(AudioSystem.Model.init(rawValue:)) ?? .unknown
        defaultInput = defaults.string(forKey: Key.defaultInput).flatMap(PlaybackInfo.Source.init(rawValue:)) ?? .usb
        outputDeviceNameHint = defaults.string(forKey: Key.outputDeviceNameHint) ?? ""

        setDefaultShortcutsIfNeeded()
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let changeSubject: PassthroughSubject<Void, Never> = .init()

    private func didChange() {
        defaults.set(speakerAddress, forKey: Key.speakerAddress)
        defaults.set(speakerInstance, forKey: Key.speakerInstance)
        defaults.set(model.rawValue, forKey: Key.model)
        defaults.set(defaultInput.rawValue, forKey: Key.defaultInput)
        defaults.set(outputDeviceNameHint, forKey: Key.outputDeviceNameHint)

        changeSubject.send()
    }

    /// Shortcuts are editable in the settings now, so the defaults may be written only once.
    private func setDefaultShortcutsIfNeeded() {
        guard !defaults.bool(forKey: Key.didSetDefaultShortcuts) else { return }

        KeyboardShortcuts.setShortcut(.init(.f19, modifiers: []), for: .volumeUp)
        KeyboardShortcuts.setShortcut(.init(.f17, modifiers: []), for: .volumeDown)
        defaults.set(true, forKey: Key.didSetDefaultShortcuts)
    }
}
