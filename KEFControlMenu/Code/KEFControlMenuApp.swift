//
//  KEFControlMenuApp.swift
//  KEFControlMenu
//
//  Created by Alexander Babaev on 11/1/24.
//

import SwiftUI

@main
@MainActor
struct KEFControlMenuApp: App {
    @State
    var keyboardConfig: KeyboardControl = .init()

    var body: some Scene {
        MenuBarExtra {
            Text("LSX System")
            Text("Model: \(keyboardConfig.audioSystem.map { "\($0.model)" } ?? "—")")
            Text("Name: \(keyboardConfig.audioSystem.map { "\($0.name)" } ?? "—")")
            Divider()
            Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "door.right.hand.open") }
                .keyboardShortcut("Q")
        } label: {
            let height: CGFloat = 18
            let size = NSSize(width: height, height: height)
            let volumeDegrees = 360 * keyboardConfig.volume
            let volumeText = Int(round(keyboardConfig.volume * 99))
            let isOn = !(keyboardConfig.playbackInfo?.isMuted ?? true || keyboardConfig.playbackInfo?.source != .usb)
            Image(size: size) { context in
                let frame = NSRect(origin: .zero, size: size)
                let radius = size.width / 2
                let center = CGPoint(x: radius, y: radius)

                let color = isOn ? Color.primary : Color.gray

                var arc = Path()
                arc.move(to: center)
                arc.addArc(center: center, radius: radius - 1, startAngle: .radians(0), endAngle: .degrees(volumeDegrees), clockwise: false, transform: .identity)
                arc.closeSubpath()
                context.fill(arc, with: .color(color.opacity(0.1)))

                var circle = Path()
                circle.addEllipse(in: frame.insetBy(dx: 1, dy: 1))
                context.stroke(circle, with: .color(color), lineWidth: 1)

                context.blendMode = .difference

                let valueString = Text("\(volumeText)")
                    .foregroundStyle(color)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                context.draw(valueString, at: .init(x: 9.25, y: 9), anchor: .center)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
struct VolumeIcon: View {
    var body: some View {
        Circle()
            .fill(.white)
    }
}

extension NSImage {
    static func volumeLevel(_ level: Double, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()

        color.setFill()

        let frame = NSRect(origin: .zero, size: CGSize(width: 50, height: 50))
        image.draw(at: .zero, from: frame, operation: .sourceOver, fraction: 1)

        image.unlockFocus()
        return image
    }
}
