//
// Volume
// Package
//
// Created by Alex Babaev on 22 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Combine
import Foundation
import KEFControl
import Memoirs
import StreamDeck

class Volume: Action {
    struct Settings: Codable, Hashable {
        var ip: String?
    }

    private lazy var memoir: TracedMemoir = TracedMemoir(object: self, memoir: basicMemoir)

    private var kefControl: KEFControl = .init(api: KEFNetworkApi())

    private(set) static var name: String = "KEF Volume"
    private(set) static var tooltip: String? = "Controls Volume"
    private(set) static var uuid: String = "com.lonelybytes.sdplugin.kef.volume"
    private(set) static var icon: String = "volumeIcon"
    private(set) static var states: [PluginActionState]? = [ .init(image: "actionVolume") ]
    private(set) static var controllers: [ControllerType] = [ .keypad, .encoder ]
    private(set) static var encoder: RotaryEncoder? = RotaryEncoder(
        layout: .indicator,
        triggerDescription: .init(rotate: "Change Volume", push: "Mute")
    )

    private(set) var context: String = ""
    private(set) var coordinates: Coordinates? = nil

    private(set) static var propertyInspectorPath: String? = "PropertyInspector.Volume/index.html"

    private var subscriptions: [Any] = []

    required init(context: String, coordinates: Coordinates?) {
        self.context = context
        self.coordinates = coordinates

        getSettings()

        Task {
            await subscriptions.append(kefControl.eventPublisher
                .sink { [self] event in
                    switch event {
                        case .playback(let info):
                            displayedPlaybackInfo = info
                        case .system(let system):
                            displayedAudioSystemName = system.name
                    }
                    updateDisplay()
                })
            memoir.debug("Async init finished")
        }

        memoir.debug("")
    }

    private var displayedAudioSystemName: String = "KEF"
    private var displayedPlaybackInfo: PlaybackInfo = .init()

    private func updateDisplay() {
        let isAudioSystemOn = displayedPlaybackInfo.source != .standby
        let volume = displayedPlaybackInfo.volume

        let value: [String: Any] = [
            "enabled": isAudioSystemOn,
            "opacity": isAudioSystemOn ? 1.0 : 0.0,
            "value": isAudioSystemOn ? "\(volume)%" as Any : "" as Any,
        ]
        let indicator: [String: Any] = [
            "enabled": isAudioSystemOn,
            "opacity": isAudioSystemOn ? 1.0 : 0.0,
            "value": isAudioSystemOn ? volume as Any : 0 as Any,
        ]
        let payload: [String: Any] = [
            "title": "\(displayedAudioSystemName)\(isAudioSystemOn ? "" : " (off)")",
            "icon": (displayedPlaybackInfo.isMuted || !isAudioSystemOn)
                ? "volumeMute.png"
                : (volume < 33 ? "volumeLow.png" : (volume < 67 ? "volumeMedium.png" : "volumeHigh.png")),
            "value": value,
            "indicator": indicator
        ]
        memoir.debug("Payload: \(payload)")
        setFeedback(payload)
    }

    // MARK: - KEF Control

    private func sendMuteUpdate() {
        Task {
            do {
                try await kefControl.toggleMute()
            } catch {
                memoir.error(error)
            }
        }
    }

    private func sendVolumeUpdate(dVolume: Int32) {
        Task {
            do {
                displayedPlaybackInfo.volume = try await kefControl.changeVolume(by: dVolume)
                updateDisplay()
            } catch {
                memoir.error(error)
            }
        }
    }

    // MARK: - Stream Deck Methods.

    func keyUp(device: String, payload: KeyEvent<Settings>) {
        memoir.debug("KeyUp: \(payload)")
        sendMuteUpdate()
    }

    private var firstRotateEventTime: TimeInterval = 0
    private var lastRotateEventTime: TimeInterval = 0
    private var totalNumberOfTicks: Int = 1
    private var lastTickSignum: Int = 0

    func dialRotate(device: String, payload: EncoderEvent<Settings>) {
        memoir.debug("Rotation: \(payload)")

        let timestamp = Date.timeIntervalSinceReferenceDate
        if payload.ticks.signum() != lastTickSignum || timestamp - lastRotateEventTime > 0.2 {
            firstRotateEventTime = timestamp
            totalNumberOfTicks = 1
        } else {
            totalNumberOfTicks += 1
        }
        lastTickSignum = payload.ticks.signum()
        lastRotateEventTime = timestamp

        let overallRotationTime = lastRotateEventTime - firstRotateEventTime
        let rotatingScale = 1 + min(5, sqrt(overallRotationTime) * 3)

        sendVolumeUpdate(dVolume: Int32(Double(payload.ticks) * rotatingScale))
    }

    func dialPress(device: String, payload: EncoderPressEvent<Settings>) {
        memoir.debug("DialPress: \(payload)")
        guard payload.pressed else { return }

        if displayedPlaybackInfo.source != .standby {
            sendMuteUpdate()
        } else {
            Task {
                try await kefControl.turnOnIfNeeded()
            }
        }
    }

    func touchTap(device: String, payload: TouchTapEvent<Settings>) {
        memoir.debug("TouchTap: \(payload)")
    }

    private let ipCheckRegex: Regex = try! .init("\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}")

    func sentToPlugin(payload: [String: String]) {
        memoir.debug("SentToPlugin: \(payload)")
        if let ip = payload["ip"], ip.wholeMatch(of: ipCheckRegex) != nil {
            memoir.debug("Got ip setting: \(ip)")
            update(ip: ip)
        }
    }

    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        memoir.debug("")
        if let ip = payload.settings.ip {
            Task {
                await kefControl.set(ip: ip, andStartStreaming: true)
            }
        }
    }

    private var isVisible: Bool = false

    func willAppear(device: String, payload: AppearEvent<Settings>) {
        memoir.debug("")
        isVisible = true
        Task {
            try await kefControl.startEventListening()
        }
    }

    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        memoir.debug("")
        isVisible = false
        Task {
            try await kefControl.stopEventListening()
        }
    }

    func titleParametersDidChange(device: String, info: TitleInfo<Settings>) {
        memoir.debug("Title parameters changed: \(info)")
    }

    func propertyInspectorDidAppear(device: String) {
        memoir.debug("Property inspector appeared: \(device)")
    }

    func propertyInspectorDidDisappear(device: String) {
        memoir.debug("Property inspector disappeared: \(device)")
    }

    // MARK: - Settings

    private func update(ip: String) {
        let settings = Settings(ip: ip)
        setSettings(to: settings)
        memoir.debug("Set settings: \(settings)")
        Task {
            await kefControl.set(ip: ip, andStartStreaming: true)
        }
    }
}
