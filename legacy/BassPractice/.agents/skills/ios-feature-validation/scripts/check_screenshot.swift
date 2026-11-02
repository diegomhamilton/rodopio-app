#!/usr/bin/env -S xcrun swift -module-cache-path /tmp/ios-feature-validation-module-cache

import AppKit
import CoreGraphics
import Foundation

enum ExitCode: Int32 {
    case accepted = 0
    case invalidInput = 1
    case likelyBootScreen = 2
}

func finish(_ code: ExitCode, _ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code.rawValue)
}

guard CommandLine.arguments.count == 2 else {
    finish(.invalidInput, "usage: check_screenshot.swift <screenshot.png>")
}

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    finish(.invalidInput, "error: could not decode image: \(path)")
}

let sampleWidth = 96
let sampleHeight = 192
let bytesPerPixel = 4
let bytesPerRow = sampleWidth * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

let rendered = pixels.withUnsafeMutableBytes { storage -> Bool in
    guard let context = CGContext(
        data: storage.baseAddress,
        width: sampleWidth,
        height: sampleHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return false
    }

    context.interpolationQuality = .low
    context.draw(source, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
    return true
}

guard rendered else {
    finish(.invalidInput, "error: could not sample image: \(path)")
}

var dark = 0
var bright = 0
var borderDark = 0
var borderCount = 0
var centerBright = 0
var centerCount = 0

for y in 0..<sampleHeight {
    for x in 0..<sampleWidth {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let red = Double(pixels[offset])
        let green = Double(pixels[offset + 1])
        let blue = Double(pixels[offset + 2])
        let luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0
        let isDark = luminance < 0.08
        let isBright = luminance > 0.82

        if isDark { dark += 1 }
        if isBright { bright += 1 }

        let isBorder = x < sampleWidth / 10 || x >= sampleWidth * 9 / 10
            || y < sampleHeight / 10 || y >= sampleHeight * 9 / 10
        if isBorder {
            borderCount += 1
            if isDark { borderDark += 1 }
        }

        let isCenter = x >= sampleWidth / 4 && x < sampleWidth * 3 / 4
            && y >= sampleHeight / 5 && y < sampleHeight * 4 / 5
        if isCenter {
            centerCount += 1
            if isBright { centerBright += 1 }
        }
    }
}

let total = Double(sampleWidth * sampleHeight)
let darkRatio = Double(dark) / total
let brightRatio = Double(bright) / total
let borderDarkRatio = Double(borderDark) / Double(borderCount)
let centerBrightRatio = Double(centerBright) / Double(centerCount)

let nearlyBlack = darkRatio > 0.94 && brightRatio < 0.005
let appleBootPattern = darkRatio > 0.72
    && borderDarkRatio > 0.90
    && brightRatio > 0.005
    && brightRatio < 0.20
    && centerBrightRatio > 0.01

let metrics = String(
    format: "dark=%.3f bright=%.3f borderDark=%.3f centerBright=%.3f",
    darkRatio,
    brightRatio,
    borderDarkRatio,
    centerBrightRatio
)

if nearlyBlack || appleBootPattern {
    finish(.likelyBootScreen, "reject: likely Apple boot screen (\(metrics))")
}

print("accept: screenshot is not a likely Apple boot screen (\(metrics))")
