//
// KEFControlLogic
// KEFControlMenu
//
// Created by Alexander Babaev on 15 January 2024.
// Copyright © 2024 Alexander Babaev. All rights reserved.
//

import Combine
import KEFControl
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let volumeUp = Self("kef.volumeUp")
    static let volumeDown = Self("kef.volumeDown")
}

@Observable @MainActor
class KEFControlLogic {
    /// What the volume shortcuts currently drive.
    enum Target: Equatable {
        case kef
        case system(isSupported: Bool)
    }

    /// What the speakers are doing, as far as we can tell over the network.
    enum SpeakerState: Equatable {
        case notConfigured
        case unreachable
        case standby
        case playing(PlaybackInfo.Source)

        var title: String {
            switch self {
                case .notConfigured: "no address set"
                case .unreachable: "not reachable"
                case .standby: "standby"
                case .playing(let source): source.title
            }
        }

        var isAwake: Bool {
            if case .playing = self { true } else { false }
        }
    }

    let settings: AppSettings

    private(set) var audioSystem: AudioSystem?
    private(set) var playbackInfo: PlaybackInfo?

    private(set) var speakerState: SpeakerState = .notConfigured
    private(set) var target: Target = .system(isSupported: false)
    private(set) var outputDevice: AudioOutputDevice?

    var outputDeviceName: String? { outputDevice?.name }

    /// Symbol for the menu bar icon: the speakers when they are driven directly, the system output otherwise.
    var iconSymbolName: String {
        switch target {
            case .kef: "hifispeaker.2.fill"
            case .system: outputDevice?.kind.symbolName ?? "speaker.slash.fill"
        }
    }

    /// Volume of whatever is currently being controlled, in `0 ... 1`.
    private(set) var volume: Double = 0
    private(set) var isMuted: Bool = false

    init(settings: AppSettings) {
        self.settings = settings
        kefControl = .init(api: KEFNetworkApi())
        systemAudioControl = .init()

        systemEventsSubscription = systemAudioControl.eventPublisher.sink { [weak self] event in
            guard let self else { return }

            switch event {
                case .device: updateTarget()
                case .playback: refreshPlaybackValues()
            }
        }
        systemAudioControl.startMonitoring()

        settingsSubscription = settings.changePublisher.sink { [weak self] in
            self?.applySettings()
        }

        Task { [weak self] in
            guard let self else { return }

            kefEventsSubscription = await kefControl.eventPublisher.sink { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    switch event {
                        case .playback(let info):
                            playbackInfo = info
                            refreshPlaybackValues()
                            refreshSpeakerState()
                        case .system(let info):
                            // The device name arrives here, and it is what identifies the speakers in CoreAudio.
                            audioSystem = info
                            updateTarget()
                        case .reachability(let isReachable):
                            isSpeakerReachable = isReachable
                            refreshSpeakerState()
                    }
                }
            }
            await connectToSpeakers()
        }

        KeyboardShortcuts.onKeyUp(for: .volumeUp) { [weak self] in
            MainActor.assumeIsolated { self?.changeVolume(steps: 1) }
        }
        KeyboardShortcuts.onKeyUp(for: .volumeDown) { [weak self] in
            MainActor.assumeIsolated { self?.changeVolume(steps: -1) }
        }
    }

    func update(input: PlaybackInfo.Source) {
        Task { try? await kefControl.setInput(to: input) }
    }

    func wakeUpSpeakers() {
        Task { try? await kefControl.turnOnIfNeeded() }
    }

    func sendSpeakersToStandby() {
        Task { try? await kefControl.standBy() }
    }

    func toggleMute() {
        switch target {
            case .kef: Task { try? await kefControl.toggleMute() }
            case .system: systemAudioControl.toggleMute()
        }
    }

    @ObservationIgnored
    private let kefControl: KEFControl
    @ObservationIgnored
    private let systemAudioControl: SystemAudioControl
    @ObservationIgnored
    private var kefEventsSubscription: AnyCancellable?
    @ObservationIgnored
    private var systemEventsSubscription: AnyCancellable?
    @ObservationIgnored
    private var settingsSubscription: AnyCancellable?

    @ObservationIgnored
    private var connectedAddress: String?
    @ObservationIgnored
    private var isSpeakerReachable: Bool = false
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?

    private static let reconnectInterval: Duration = .seconds(15)

    private func changeVolume(steps: Int) {
        switch target {
            case .kef:
                Task { [weak self] in
                    guard let self else { return }

                    let delta = Int32(steps) * Int32(settings.kefVolumeStep)
                    guard let newVolume = try? await kefControl.changeVolume(by: delta) else { return }

                    playbackInfo?.volume = newVolume
                    refreshPlaybackValues()
                }
            case .system:
                let step = 1.0 / Double(settings.systemVolumeStepCount)
                volume = systemAudioControl.changeVolume(by: Double(steps) * step)
        }
    }

    private func applySettings() {
        Task { await connectToSpeakers() }
        updateTarget()
    }

    private func connectToSpeakers() async {
        let address = settings.speakerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        // Reconnecting restarts the event stream, so only do it when the address really changed.
        let isNewAddress = address != connectedAddress
        connectedAddress = address

        await kefControl.set(address: address, defaultInput: settings.defaultInput, andStartStreaming: isNewAddress)
        audioSystem = await kefControl.audioSystem
        playbackInfo = await kefControl.playbackInfo
        isSpeakerReachable = await kefControl.isReachable
        updateTarget()
    }

    private func updateTarget() {
        let device = systemAudioControl.device
        outputDevice = device
        let isKEF = device.map { isKEF($0) } ?? false
        target = isKEF ? .kef : .system(isSupported: systemAudioControl.isVolumeControlAvailable)
        refreshPlaybackValues()
        refreshSpeakerState()
    }

    private func refreshSpeakerState() {
        let address = settings.speakerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        speakerState = if address.isEmpty {
            .notConfigured
        } else if !isSpeakerReachable {
            .unreachable
        } else if let source = playbackInfo?.source, source != .standby {
            .playing(source)
        } else {
            .standby
        }

        if case .unreachable = speakerState {
            startReconnecting()
        } else {
            reconnectTask?.cancel()
            reconnectTask = nil
        }
    }

    /// The speakers may be asleep, off the network, or waiting for Local Network access to be granted, so keep trying.
    private func startReconnecting() {
        guard reconnectTask == nil else { return }

        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.reconnectInterval)
                guard !Task.isCancelled, let self else { return }

                await connectToSpeakers()
            }
        }
    }

    private func refreshPlaybackValues() {
        switch target {
            case .kef:
                volume = Double(playbackInfo?.volume ?? 0) / 100.0
                isMuted = playbackInfo?.isMuted ?? false
            case .system:
                volume = systemAudioControl.volume
                isMuted = systemAudioControl.isMuted
        }
    }

    /// The speakers show up in CoreAudio only over USB, under a name we have to recognise from what we know about them.
    private func isKEF(_ device: AudioOutputDevice) -> Bool {
        var names: [String] = [ "kef" ]
        names.append(contentsOf: settings.model.audioDeviceNameHints)
        names.append(contentsOf: audioSystem?.model.audioDeviceNameHints ?? [])
        if let name = audioSystem?.name.lowercased(), name.count >= 3 {
            names.append(name)
        }
        let hint = settings.outputDeviceNameHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !hint.isEmpty {
            names.append(hint)
        }

        let haystack = "\(device.name) \(device.uid)".lowercased()
        return names.contains { haystack.contains($0) }
    }
}
