//
// SettingsScreen.Component
// KEFControlMenu
//
// Created by Alexander Babaev on 22 July 2026.
// Copyright © 2026 Alexander Babaev. All rights reserved.
//

import AppKit
import KEFControl
import KeyboardShortcuts
import SwiftUI

enum SettingsScreen {
}

extension SettingsScreen {
    struct Component: View {
        @Bindable
        var settings: AppSettings

        let logic: KEFControlLogic
        let outputDeviceName: String?
        let isControllingKEF: Bool

        var body: some View {
            Form {
                Section("Speakers on the network") {
                    if logic.discoveredSpeakers.isEmpty {
                        HStack {
                            Text(logic.isDiscovering ? "Looking for speakers…" : "None found")
                                .foregroundStyle(.secondary)
                            Spacer()
                            searchButton
                        }
                    }
                    ForEach(Array(logic.discoveredSpeakers.enumerated()), id: \.element.id) { index, speaker in
                        HStack(spacing: 8) {
                            Button(
                                action: { logic.use(speaker) },
                                label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: speaker.instanceName == settings.speakerInstance
                                            ? "checkmark.circle.fill"
                                            : "hifispeaker")
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(speaker.name)
                                            Text("\(speaker.model.title) · \(speaker.address)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                            )
                            .buttonStyle(.plain)
                            if index == 0 {
                                searchButton
                            }
                        }
                    }
                }

                Section("Connection") {
                    TextField("Address", text: $settings.speakerAddress, prompt: Text("192.168.0.1"))
                        .textFieldStyle(.roundedBorder)
                    Picker(
                        "Model",
                        selection: $settings.model,
                        content: {
                            ForEach(AudioSystem.Model.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    )
                    Picker(
                        "Wake up with input",
                        selection: $settings.defaultInput,
                        content: {
                            ForEach(PlaybackInfo.Source.selectable, id: \.self) { Text($0.title).tag($0) }
                        }
                    )
                    Text("Filled in by the search above; edit it only if the speakers are not found automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("System output") {
                    LabeledContent("Current output", value: outputDeviceName ?? "—")
                    LabeledContent("Volume goes to", value: isControllingKEF ? "Speakers" : "System output")
                    TextField("Speaker name in Sound settings", text: $settings.outputDeviceNameHint, prompt: Text("Optional"))
                        .textFieldStyle(.roundedBorder)
                    Text(hintExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Shortcuts") {
                    KeyboardShortcuts.Recorder("Volume up", name: .volumeUp)
                    KeyboardShortcuts.Recorder("Volume down", name: .volumeDown)
                }
            }
            .formStyle(.grouped)
            .frame(width: 460)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                // The app is an accessory, so its settings window does not come forward on its own.
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }

        private var searchButton: some View {
            Button(logic.isDiscovering ? "Searching…" : "Search") {
                Task { await logic.discoverSpeakers() }
            }
            .disabled(logic.isDiscovering)
        }

        private var hintExplanation: String {
            "The speakers appear as a system output device only over USB. Fill this in if their name in Sound settings "
                + "is not recognised automatically."
        }
    }
}

#Preview {
    let settings: AppSettings = .init(defaults: .init())
    return SettingsScreen.Component(
        settings: settings,
        logic: .init(settings: settings),
        outputDeviceName: "Built-in Output",
        isControllingKEF: false
    )
}
