#!/usr/bin/env swift
// Regenerate the AppIcon asset catalog from the canonical transparent Sawti mark:
//   swift scripts/generate_sawti_app_icons.swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO

let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceURL = repositoryRoot.appendingPathComponent("app/MeetingTranscriber/Sources/Resources/SawtiLogo.png")
let outputDirectory = repositoryRoot.appendingPathComponent("app/MeetingTranscriber/Sources/Assets.xcassets/AppIcon.appiconset")

guard let sourceImage = NSImage(contentsOf: sourceURL),
      let sourceCGImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let pixelContext = CGContext(
          data: nil,
          width: sourceCGImage.width,
          height: sourceCGImage.height,
          bitsPerComponent: 8,
          bytesPerRow: sourceCGImage.width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    fatalError("Could not load the canonical Sawti logo at \(sourceURL.path)")
}

pixelContext.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: sourceCGImage.width, height: sourceCGImage.height))
let pixels = pixelContext.data!.assumingMemoryBound(to: UInt8.self)
var minX = sourceCGImage.width
var minY = sourceCGImage.height
var maxX = -1
var maxY = -1
for y in 0 ..< sourceCGImage.height {
    for x in 0 ..< sourceCGImage.width where pixels[(y * sourceCGImage.width + x) * 4 + 3] > 0 {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}
guard maxX >= minX, maxY >= minY,
      let mark = sourceCGImage.cropping(to: CGRect(
          x: minX,
          y: minY,
          width: maxX - minX + 1,
          height: maxY - minY + 1
      ))
else {
    fatalError("The canonical Sawti logo has no visible pixels")
}

let iconSizes: [(filename: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let markAspectRatio = CGFloat(mark.width) / CGFloat(mark.height)
for item in iconSizes {
    let size = item.pixels
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create \(size)x\(size) icon bitmap")
    }

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.22
    let roundedSquare = CGPath(
        roundedRect: canvas,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    context.addPath(roundedSquare)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fillPath()

    // A clean white tile keeps the black official mark legible on both light
    // and dark desktop surfaces. The transparent padding is cropped before
    // scaling so the artwork is balanced within the macOS icon silhouette.
    let markWidth = CGFloat(size) * 0.86
    let markHeight = markWidth / markAspectRatio
    let markRect = CGRect(
        x: (CGFloat(size) - markWidth) / 2,
        y: (CGFloat(size) - markHeight) / 2,
        width: markWidth,
        height: markHeight
    )
    context.interpolationQuality = .high
    context.draw(mark, in: markRect)

    let outputURL = outputDirectory.appendingPathComponent(item.filename)
    guard let cgImage = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil)
    else {
        fatalError("Could not write \(outputURL.path)")
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not finalize \(outputURL.path)")
    }
    print("Wrote \(item.filename) (\(size)x\(size))")
}
