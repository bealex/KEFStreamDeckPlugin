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
    private(set) var discoveredSpeakers: [DiscoveredSpeaker] = []
    private(set) var isDiscovering: Bool = false
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
            startMonitoring()
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

    @discardableResult
    func discoverSpeakers() async -> [DiscoveredSpeaker] {
        guard !isDiscovering else { return discoveredSpeakers }

        isDiscovering = true
        discoveredSpeakers = await discovery.speakers()
        isDiscovering = false
        return discoveredSpeakers
    }

    /// Adopting a found speaker rewrites the settings, which reconnects through the usual path.
    func use(_ speaker: DiscoveredSpeaker) {
        settings.model = speaker.model
        settings.speakerInstance = speaker.instanceName
        settings.speakerAddress = speaker.address
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
    private let discovery: KEFDiscovery = .init()
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
    private var monitorTask: Task<Void, Never>?

    /// KEF volume is `0 ... 100`; one point per press matches how fine its own remote is.
    private static let kefVolumeStep: Int32 = 1
    /// Presses from silence to full on the system output. macOS itself uses 16.
    private static let systemVolumeStepCount: Double = 16

    private static let monitorInterval: Duration = .seconds(15)
    /// Ticks between full re-reads while connected, in case the event stream stops delivering.
    private static let refreshEveryTicks: Int = 4

    private func changeVolume(steps: Int) {
        switch target {
            case .kef:
                Task { [weak self] in
                    guard let self else { return }

                    let delta = Int32(steps) * Self.kefVolumeStep
                    guard let newVolume = try? await kefControl.changeVolume(by: delta) else { return }

                    playbackInfo?.volume = newVolume
                    refreshPlaybackValues()
                }
            case .system:
                let step = 1.0 / Self.systemVolumeStepCount
                volume = systemAudioControl.changeVolume(by: Double(steps) * step)
        }
    }

    private func applySettings() {
        Task { await connectToSpeakers() }
        updateTarget()
    }

    private func connectToSpeakers() async {
        let address = await resolvedAddress()
        guard !address.isEmpty else { return }
        // Reconnecting restarts the event stream, so only do it when the address really changed.
        let isNewAddress = address != connectedAddress
        connectedAddress = address

        await kefControl.set(address: address, defaultInput: settings.defaultInput, andStartStreaming: isNewAddress)
        await readSpeakerState()
        updateTarget()
    }

    /// Bonjour decides the address when it can; a manually entered one is the fallback for when nothing answers.
    private func resolvedAddress() async -> String {
        let manual = settings.speakerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = await discoverSpeakers()

        // Speakers we already adopted, wherever they moved to since.
        if let known = found.first(where: { $0.instanceName == settings.speakerInstance }) {
            if known.address != manual {
                use(known)
            }
            return known.address
        }
        // An address typed by hand that turns out to be a speaker we can see: adopt it, so it can be followed later.
        if let sameAddress = found.first(where: { $0.address == manual }) {
            use(sameAddress)
            return sameAddress.address
        }
        // Nothing adopted yet, and exactly one candidate is not a guess.
        if manual.isEmpty, found.count == 1, let only = found.first {
            use(only)
            return only.address
        }

        return manual
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

    }

    /// Reconnects while the speakers are away, and re-reads periodically once they are back, so the menu cannot
    /// sit on stale state if the event stream stops delivering.
    private func startMonitoring() {
        guard monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.monitorInterval)
                guard !Task.isCancelled, let self else { return }

                tick += 1
                if isSpeakerReachable {
                    guard tick % Self.refreshEveryTicks == 0 else { continue }

                    await kefControl.refresh()
                    await readSpeakerState()
                } else {
                    await connectToSpeakers()
                }
            }
        }
    }

    private func readSpeakerState() async {
        audioSystem = await kefControl.audioSystem
        playbackInfo = await kefControl.playbackInfo
        isSpeakerReachable = await kefControl.isReachable
        refreshPlaybackValues()
        refreshSpeakerState()
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
