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

        let outputDeviceName: String?
        let isControllingKEF: Bool

        var body: some View {
            Form {
                Section("Speakers") {
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

                Section("Volume") {
                    Stepper(value: $settings.kefVolumeStep, in: 1 ... 10) {
                        LabeledContent("Speaker step", value: "\(settings.kefVolumeStep) of 100")
                    }
                    Stepper(value: $settings.systemVolumeStepCount, in: 4 ... 32) {
                        LabeledContent("System steps", value: "\(settings.systemVolumeStepCount)")
                    }
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

        private var hintExplanation: String {
            "The speakers appear as a system output device only over USB. Fill this in if their name in Sound settings "
                + "is not recognised automatically."
        }
    }
}

#Preview {
    SettingsScreen.Component(settings: .init(defaults: .init()), outputDeviceName: "Built-in Output", isControllingKEF: false)
}
