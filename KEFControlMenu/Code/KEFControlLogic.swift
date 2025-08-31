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

@Observable
class KEFControlLogic {
    var audioSystem: AudioSystem?
    var playbackInfo: PlaybackInfo? {
        didSet {
            self.volume = Double(playbackInfo.map(\.volume) ?? 0) / 100.0
        }
    }

    var volume: Double = 0

    @ObservationIgnored
    private let kefControl: KEFControl
    @ObservationIgnored
    private var kefEventsSubscription: AnyCancellable?

    init() {
        kefControl = .init(api: KEFNetworkApi())

        Task { @MainActor [self] in
            await kefControl.set(ip: "192.168.23.106", defaultInput: .optical, andStartStreaming: true)
            kefEventsSubscription = await kefControl.eventPublisher.sink { [weak self] event in
                guard let self else { return }

                Task { @MainActor in
                    switch event {
                        case .playback(let info):
                            self.playbackInfo = info
                            self.volume = Double(info.volume) / 100.0
                        case .system(let info):
                            self.audioSystem = info
                    }
                }
            }
            audioSystem = await self.kefControl.audioSystem
            playbackInfo = await self.kefControl.playbackInfo
        }

        KeyboardShortcuts.setShortcut(.init(.f17, modifiers: []), for: .volumeUp)
        KeyboardShortcuts.setShortcut(.init(.f19, modifiers: []), for: .volumeDown)

        KeyboardShortcuts.onKeyUp(for: .volumeUp) { [weak self] in
            guard let self else { return }

            Task {
                let newVolume = try await self.kefControl.changeVolume(by: -1)
                Task { @MainActor in
                    self.playbackInfo?.volume = newVolume
                }
            }
        }
        KeyboardShortcuts.onKeyUp(for: .volumeDown) { [weak self] in
            guard let self else { return }

            Task {
                let newVolume = try await self.kefControl.changeVolume(by: 1)
                Task { @MainActor in
                    self.playbackInfo?.volume = newVolume
                }
            }
        }
    }

    func update(input: PlaybackInfo.Source) {
        Task {
            await kefControl.update(defaultInput: input)
        }
    }
}
