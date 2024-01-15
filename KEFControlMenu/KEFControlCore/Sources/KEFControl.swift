//
// KEFControl
// KEFControl
//
// Created by Alex Babaev on 04 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Combine
import Foundation
import Memoirs

public actor KEFControl {
    public enum Event {
        case playback(PlaybackInfo)
        case system(AudioSystem)
    }

    public var eventPublisher: AnyPublisher<Event, Never> { eventSubject.eraseToAnyPublisher() }

    private var api: KEFApi
    private var ip: String?

    private(set) public var audioSystem: AudioSystem = .init(name: "KEF", model: .unknown)
    private(set) public var playbackInfo: PlaybackInfo = .init()

    public init(api: KEFApi) {
        self.api = api
    }

    public func set(ip: String, andStartStreaming: Bool) async {
        self.ip = ip

        do {
            if streamingStarted || andStartStreaming {
                try stopEventListening()
                try await startEventListening()
            } else {
                try await updateInformationFromAudioSystem()
            }
        } catch {
            memoir.error(error)
        }
    }

    private lazy var memoir: TracedMemoir = TracedMemoir(object: self, memoir: basicMemoir)
    private let eventSubject: PassthroughSubject<Event, Never> = .init()

    public func toggleMute() async throws {
        guard let ip else { throw KEFProblem.isNotSetup("No ip address") }

        try await turnOnIfNeeded()
        Task.detached { [self] in
            do {
                try await api.set(value: !playbackInfo.isMuted, for: \.isMuted, ip: ip)
            } catch {
                await memoir.error(error)
            }
        }
    }

    public func changeVolume(by dVolume: Int32) async throws -> Int32 {
        guard let ip else { throw KEFProblem.isNotSetup("No ip address") }

        try await turnOnIfNeeded()
        let newVolume = min(100, max(0, playbackInfo.volume + dVolume))
        if playbackInfo.volume != newVolume {
            playbackInfo.volume = newVolume
            Task.detached { [self] in
                do {
                    try await api.set(value: newVolume, for: \.volume, ip: ip)
                } catch {
                    await memoir.error(error)
                }
            }
        }
        return newVolume
    }

    public func turnOnIfNeeded() async throws {
        guard let ip else { throw KEFProblem.isNotSetup("No ip address") }
        guard playbackInfo.source == .standby else { return }

        try await api.set(value: .usb, for: \.physicalSource, ip: ip)
    }

    private var lastGotVolume: Int32 = -1
    private var volumeUpdatedTask: Task<Void, Error>?
    private var streamingStarted: Bool = false
    private var eventStreamId: String?

    public func startEventListening() async throws {
        guard let ip else { throw KEFProblem.isNotSetup("No ip address") }
        guard !streamingStarted else { return memoir.warning("Already listening to the events") }

        streamingStarted = true

        do {
            try await updateInformationFromAudioSystem()
            let (stream, id) = try api.events(for: ip)
            eventStreamId = id

            memoir.debug("Started listening to events; subscription: \(id)")

            Task.detached { [self] in
                for await value in stream {
                    try await process(value: value)
                }
            }
        } catch {
            memoir.error(error)
        }

        streamingStarted = false
        eventStreamId = nil
    }

    private func updateInformationFromAudioSystem() async throws {
        guard let ip else { throw KEFProblem.isNotSetup("No ip address") }

        audioSystem.name = try await api.get(\.name, ip: ip)
        audioSystem.model = try await api.get(\.model, ip: ip)
        eventSubject.send(.system(audioSystem))

        playbackInfo.isMuted = try await api.get(\.isMuted, ip: ip)
        playbackInfo.volume = try await api.get(\.volume, ip: ip)
        playbackInfo.source = try await api.get(\.physicalSource, ip: ip)
        eventSubject.send(.playback(playbackInfo))
    }

    private func process(value: KEFValue) async throws {
        memoir.debug("Got event \(value)")

        var playbackUpdated = false
        var audioSystemUpdated = false
        switch value {
            case .source(let source) where playbackInfo.source != source:
                playbackInfo.source = source
                playbackUpdated = true
            case .volume(let volume):
                lastGotVolume = volume
                volumeUpdatedTask?.cancel()
                volumeUpdatedTask = Task {
                    volumeUpdatedTask = nil
                    try await Task.sleep(for: .seconds(1))
                    playbackInfo.volume = lastGotVolume
                    eventSubject.send(.playback(playbackInfo))
                }
            case .isMuted(let isMuted) where playbackInfo.isMuted != isMuted:
                playbackInfo.isMuted = isMuted
                playbackUpdated = true
            case .name(let name) where audioSystem.name != name:
                audioSystem.name = name
                audioSystemUpdated = true
            case .model(let model) where audioSystem.model != model:
                audioSystem.model = model
                audioSystemUpdated = true
            default:
                break
        }
        if playbackUpdated {
            eventSubject.send(.playback(playbackInfo))
        }
        if audioSystemUpdated {
            eventSubject.send(.system(audioSystem))
        }
    }

    public func stopEventListening() throws {
        guard streamingStarted, let eventStreamId else { return }

        api.terminateEventsStream(id: eventStreamId)
        memoir.warning("Stopped listening to events; subscription: \(eventStreamId)")
    }
}
