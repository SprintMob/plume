#!/usr/bin/env swift
// Rasterise an SVG to PNG at a given size, using AppKit.
//
// This exists because make-icns.sh should work on a clean checkout. librsvg is
// not a macOS default and installing Homebrew to regenerate an icon is a poor
// trade, so make-icns.sh prefers rsvg-convert when it is there and falls back
// here when it is not. NSImage decodes SVG natively, which the menu bar glyph
// already depends on.
//
//   swift scripts/render-svg.swift <input.svg> <size> <output.png> [more sizes/outputs...]
//
// Sizes and outputs come in pairs so one invocation can render a whole
// iconset, since `swift file.swift` compiles on every run.

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, (arguments.count - 1) % 2 == 0 else {
    FileHandle.standardError.write(Data(
        "usage: render-svg.swift <input.svg> <size> <output.png> [<size> <output.png>...]\n".utf8))
    exit(64)
}

let source = URL(fileURLWithPath: arguments[0])
guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write(Data("could not decode \(source.path)\n".utf8))
    exit(1)
}

var index = 1
while index < arguments.count {
    guard let size = Int(arguments[index]), size > 0 else {
        FileHandle.standardError.write(Data("not a size: \(arguments[index])\n".utf8))
        exit(64)
    }
    let output = URL(fileURLWithPath: arguments[index + 1])
    index += 2

    // A bitmap rep built at the exact pixel size, so nothing is resampled
    // twice: the SVG is drawn straight into it at its final resolution.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write(Data("could not allocate a \(size)px bitmap\n".utf8))
        exit(1)
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        FileHandle.standardError.write(Data("could not make a drawing context\n".utf8))
        exit(1)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode PNG\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: output)
    } catch {
        FileHandle.standardError.write(Data("could not write \(output.path): \(error)\n".utf8))
        exit(1)
    }
    print("  \(size)px → \(output.lastPathComponent)")
}
