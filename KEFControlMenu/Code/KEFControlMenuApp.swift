//
//  KEFControlMenuApp.swift
//  KEFControlMenu
//
//  Created by Alexander Babaev on 11/1/24.
//

import KEFControl
import SwiftUI

@MainActor
@main
struct KEFControlMenuApp: App {
    @State
    var logic: KEFControlLogic = .init(settings: .init())

    var body: some Scene {
        MenuBarExtra {
            Text("Output: \(logic.outputDeviceName ?? "—")")
            Text(controlledTargetTitle)
            if isVolumeControllable {
                Text("Volume: \(Int(round(logic.volume * 100)))%\(logic.isMuted ? " (muted)" : "")")
            }
            Text("Speakers: \(logic.speakerState.title)")

            Divider()

            switch logic.speakerState {
                case .standby: Button("Wake up") { logic.wakeUpSpeakers() }
                case .playing: Button("Send to standby") { logic.sendSpeakersToStandby() }
                case .notConfigured, .unreachable: EmptyView()
            }
            Button(logic.isMuted ? "Unmute" : "Mute") { logic.toggleMute() }
                .disabled(!isVolumeControllable)

            Picker(
                "Speaker input",
                selection: Binding(get: { logic.playbackInfo?.source ?? .standby }, set: { logic.update(input: $0) }),
                content: {
                    ForEach(PlaybackInfo.Source.selectable, id: \.self) { Text($0.title).tag($0) }
                }
            )

            Divider()

            SettingsLink { Label("Settings…", systemImage: "gearshape") }
                .keyboardShortcut(",")
            Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "door.right.hand.open") }
                .keyboardShortcut("Q")
        } label: {
            Label(title: { Text("") }, icon: { icon })
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsScreen.Component(
                settings: logic.settings,
                outputDeviceName: logic.outputDeviceName,
                isControllingKEF: logic.target == .kef
            )
        }
    }

    private var isVolumeControllable: Bool {
        switch logic.target {
            case .kef: true
            case .system(let isSupported): isSupported
        }
    }

    private var controlledTargetTitle: String {
        switch logic.target {
            case .kef:
                let system = logic.audioSystem
                return "Controls: \(system.map { "\($0.name) (\($0.model.title))" } ?? "the speakers")"
            case .system(let isSupported):
                return isSupported ? "Controls: system volume" : "This output has no volume control"
        }
    }

    private var icon: some View {
        Image(nsImage: MenuBarIcon.image(
            symbolName: logic.iconSymbolName,
            volume: logic.volume,
            isMuted: logic.isMuted,
            isDimmed: logic.target == .kef && !logic.speakerState.isAwake
        ))
            .accessibilityLabel(Text("Volume \(Int(round(logic.volume * 100))) percent"))
    }
}
