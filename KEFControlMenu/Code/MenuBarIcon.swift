//
// MenuBarIcon
// KEFControlMenu
//
// Created by Alexander Babaev on 22 July 2026.
// Copyright © 2026 Alexander Babaev. All rights reserved.
//

import AppKit
import KEFControl

/// Menu bar image: the output device glyph with a four-segment volume bar underneath.
enum MenuBarIcon {
    /// Volume thresholds the bar shows, as the upper bound of each segment.
    static let levels: [Double] = [ 0.2, 0.5, 0.7, 1.0 ]

    private static let size: NSSize = .init(width: 18, height: 18)
    private static let barHeight: CGFloat = 2.5
    /// Transparent gap that keeps the bar visually separate from the glyph above it.
    private static let barBorder: CGFloat = 1.5
    private static let segmentGap: CGFloat = 0.75
    private static let dimmedAlpha: CGFloat = 0.3

    /// `isDimmed` is for speakers that are asleep: the glyph fades, and the bar shows nothing.
    static func image(symbolName: String, volume: Double, isMuted: Bool, isDimmed: Bool = false) -> NSImage {
        let filledSegments = isMuted || isDimmed ? 0 : segmentCount(for: volume)

        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }
        guard let context = NSGraphicsContext.current else { return image }

        context.imageInterpolation = .high
        draw(symbolName: symbolName, alpha: isDimmed ? dimmedAlpha : 1)
        // Punch the bar area out of the glyph, so the two never touch whatever the glyph's shape is.
        NSRect(x: 0, y: 0, width: size.width, height: barHeight + barBorder).fill(using: .clear)
        drawBar(filledSegments: filledSegments)

        return image
    }

    static func segmentCount(for volume: Double) -> Int {
        guard volume > 0 else { return 0 }

        return (levels.firstIndex { volume <= $0 } ?? levels.count - 1) + 1
    }

    private static func draw(symbolName: String, alpha: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }

        let available = NSRect(
            x: 0, y: barHeight + barBorder, width: size.width, height: size.height - barHeight - barBorder
        ).insetBy(dx: 0.5, dy: 0)
        let scale = min(available.width / symbol.size.width, available.height / symbol.size.height)
        let scaled = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let origin = NSPoint(
            x: available.midX - scaled.width / 2,
            y: available.midY - scaled.height / 2
        )
        symbol.draw(
            in: NSRect(origin: origin, size: scaled), from: .zero, operation: .sourceOver, fraction: alpha
        )
    }

    private static func drawBar(filledSegments: Int) {
        let count = CGFloat(levels.count)
        let segmentWidth = (size.width - segmentGap * (count + 1)) / count
        let radius = barHeight / 5

        for index in 0 ..< levels.count {
            let rect = NSRect(
                x: segmentGap + (segmentWidth + segmentGap) * CGFloat(index),
                y: 0,
                width: segmentWidth,
                height: barHeight
            )
            NSColor.black.withAlphaComponent(index < filledSegments ? 1 : dimmedAlpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }
}

extension AudioOutputDevice.Kind {
    /// Closest public symbol to what macOS shows for this kind of output.
    var symbolName: String {
        switch self {
            case .builtInSpeakers: "laptopcomputer"
            case .headphones: "headphones"
            case .bluetooth: "headphones"
            case .airPlay: "airplayaudio"
            case .display: "display"
            case .external: "hifispeaker.fill"
            case .virtual: "waveform"
            case .unknown: "speaker.wave.2.fill"
        }
    }
}
