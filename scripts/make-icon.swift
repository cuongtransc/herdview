// Draws Herdview's app icon and packs it into scripts/AppIcon.icns.
//
// The mark itself is not here: it is `Sources/App/HerdMark.swift`, the same file
// the menu bar item draws from, compiled into this tool by `mise run icon`. Four
// agents on a dark tile, one of them lit because it is asking for a person —
// which is the one thing the app is for.
//
// The icon is code rather than a checked-in design file for the same reason
// `AgentIcons.swift` embeds its SVGs: this project carries no resource bundle
// and no asset pipeline.
//
//   mise run icon                 # the default accent
//   mise run icon --color 5C43DC  # any other one (no `#`: the shell reads it as a comment)
//
// COLOR is the accent — the colour of the one agent that is asking. The tile
// stays dark whatever it is set to, so the mark cannot come out as a flat
// single-colour tile the way it would if the hex drove the whole icon.
//
// Compiled with `-parse-as-library`, hence `@main` rather than top-level code:
// Swift only allows statements at file scope in `main.swift`, and this tool is
// two files.

import AppKit
import Foundation

@main
enum MakeIcon {

    static let defaultHex = "#E07B00"

    static func main() throws {
        _ = NSApplication.shared

        var root = "."
        var hex = defaultHex
        var args = Array(CommandLine.arguments.dropFirst())
        while let arg = args.first {
            args.removeFirst()
            if arg == "--color" {
                guard let value = args.first else {
                    fail("--color needs a hex like #E07B00")
                }
                hex = value
                args.removeFirst()
            } else {
                root = arg
            }
        }

        guard let accent = parseHex(hex) else {
            fail("not a colour: \(hex) — use #RRGGBB")
        }

        let rootURL = URL(fileURLWithPath: root)
        let iconset = rootURL.appendingPathComponent("build/AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        for base in [16, 32, 128, 256, 512] {
            try render(pixels: base, accent: accent)
                .write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
            try render(pixels: base * 2, accent: accent)
                .write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }

        let icns = rootURL.appendingPathComponent("scripts/AppIcon.icns")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
        print("wrote \(icns.path), accent \(hex)")
    }

    static func parseHex(_ raw: String) -> NSColor? {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    /// Every size is drawn at its own pixel dimensions rather than downscaled
    /// from 1024, so the 16pt Dock icon keeps clean edges — and so `HerdMark`
    /// can drop the ring at the sizes where it has no room for one.
    static func render(pixels: Int, accent: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        HerdMark.draw(size: CGFloat(pixels), style: .tile(accent: accent))
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fail("could not encode \(pixels)px")
        }
        return png
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(2)
    }
}
