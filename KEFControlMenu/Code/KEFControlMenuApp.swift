//
//  KEFControlMenuApp.swift
//  KEFControlMenu
//
//  Created by Alexander Babaev on 11/1/24.
//

import SwiftUI

@MainActor
@main
struct KEFControlMenuApp: App {
    @State
    var logic: KEFControlLogic = .init()

    var body: some Scene {
        MenuBarExtra {
            Text("LSX System")
            Text("Model: \(logic.audioSystem.map { "\($0.model)" } ?? "—")")
            Text("Name: \(logic.audioSystem.map { "\($0.name)" } ?? "—")")
            Text("Current volume: \(logic.playbackInfo.map { "\($0.volume)" } ?? "0")")

            Divider()

            Menu("Input") {
                Button(
                    action: { logic.update(input: .usb) },
                    label: {
                        Label(title: { Text("USB") }, icon: { logic.playbackInfo?.source == .usb ? Image(systemName: "checkmark") : Image("") })
                    }
                )
                Button(
                    action: { logic.update(input: .optical) },
                    label: {
                        Label(title: { Text("Optical") }, icon: { logic.playbackInfo?.source == .optical ? Image(systemName: "checkmark") : Image("") })
                    }
                )
            }

            Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "door.right.hand.open") }
                .keyboardShortcut("Q")
        } label: {
            Label(title: { Text("") }, icon: { icon })
        }
        .menuBarExtraStyle(.menu)
    }

    private var icon: some View {
        return Image(systemName: "waveform", variableValue: min(1, logic.volume * 2))
            .font(.system(size: 20).weight(.black))

//        let volumeText = Int(round(logic.volume * 99))
//        let height: CGFloat = 20
//        let size = NSSize(width: height, height: height)
//        let volumeDegrees = 360 * logic.volume
//        let isOn = !(logic.playbackInfo?.isMuted ?? true || logic.playbackInfo?.source != .usb)
//        return Image(size: size, label: Text("Volume is \(volumeText)\(isOn ? "" : ", muted")"), opaque: true, colorMode: .linear) { context in
//            let frame = NSRect(origin: .zero, size: size)
//            let radius = size.width / 2
//            let center = CGPoint(x: radius, y: radius)
//
//            let color = isOn ? Color.primary : Color.gray
//
//            var arc = Path()
//            arc.move(to: center)
//            arc.addArc(center: center, radius: radius - 1, startAngle: .radians(0), endAngle: .degrees(volumeDegrees), clockwise: false, transform: .identity)
//            arc.closeSubpath()
//            context.fill(arc, with: .color(color.opacity(0.1)))
//
//            var circle = Path()
//            circle.addEllipse(in: frame.insetBy(dx: 1, dy: 1))
//            context.stroke(circle, with: .color(color), lineWidth: 1)
//
//            context.blendMode = .difference
//
//            let valueString = Text("\(volumeText)")
//                .foregroundStyle(color)
//                .font(.system(size: 10, weight: .medium, design: .monospaced))
//            context.draw(valueString, at: .init(x: 9.25, y: 9), anchor: .center)
//        }
    }
}
