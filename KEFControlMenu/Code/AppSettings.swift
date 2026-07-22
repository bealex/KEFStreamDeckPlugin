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
        static let model: String = "kef.model"
        static let defaultInput: String = "kef.defaultInput"
        static let outputDeviceNameHint: String = "kef.outputDeviceNameHint"
        static let kefVolumeStep: String = "kef.volumeStep"
        static let systemVolumeStepCount: String = "system.volumeStepCount"
        static let didSetDefaultShortcuts: String = "shortcuts.didSetDefaults"
    }

    /// IP address or hostname of the speakers.
    var speakerAddress: String { didSet { didChange() } }
    var model: AudioSystem.Model { didSet { didChange() } }
    /// Input the speakers are switched to when they are woken up from standby.
    var defaultInput: PlaybackInfo.Source { didSet { didChange() } }
    /// Optional override for matching the speakers against the system output device, when the name is not obvious.
    var outputDeviceNameHint: String { didSet { didChange() } }
    /// Step for the KEF volume, which is `0 ... 100`.
    var kefVolumeStep: Int { didSet { didChange() } }
    /// Number of steps the system volume takes from silence to maximum. macOS itself uses 16.
    var systemVolumeStepCount: Int { didSet { didChange() } }

    var changePublisher: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        speakerAddress = defaults.string(forKey: Key.speakerAddress) ?? ""
        model = defaults.string(forKey: Key.model).flatMap(AudioSystem.Model.init(rawValue:)) ?? .unknown
        defaultInput = defaults.string(forKey: Key.defaultInput).flatMap(PlaybackInfo.Source.init(rawValue:)) ?? .usb
        outputDeviceNameHint = defaults.string(forKey: Key.outputDeviceNameHint) ?? ""
        kefVolumeStep = defaults.object(forKey: Key.kefVolumeStep) as? Int ?? 1
        systemVolumeStepCount = defaults.object(forKey: Key.systemVolumeStepCount) as? Int ?? 16

        setDefaultShortcutsIfNeeded()
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let changeSubject: PassthroughSubject<Void, Never> = .init()

    private func didChange() {
        defaults.set(speakerAddress, forKey: Key.speakerAddress)
        defaults.set(model.rawValue, forKey: Key.model)
        defaults.set(defaultInput.rawValue, forKey: Key.defaultInput)
        defaults.set(outputDeviceNameHint, forKey: Key.outputDeviceNameHint)
        defaults.set(kefVolumeStep, forKey: Key.kefVolumeStep)
        defaults.set(systemVolumeStepCount, forKey: Key.systemVolumeStepCount)

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
