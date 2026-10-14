import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Package the committed lettering artwork as an opaque, sRGB iOS app icon.
// Run from the repository root: swift Scripts/generate_icon.swift
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Docs/Design/app-icon-source.png")
let promptURL = root.appendingPathComponent("Docs/Design/app-icon-prompt.md")
let outputURL = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)!
let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)!
precondition(artwork.width == artwork.height, "App icon source must be square")

let size = 1024
let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
bitmap.setFillColor(CGColor(red: 0.07, green: 0.04, blue: 0.02, alpha: 1))
bitmap.fill(CGRect(x: 0, y: 0, width: size, height: size))
bitmap.interpolationQuality = .high
bitmap.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))

let prompt = try String(contentsOf: promptURL, encoding: .utf8)
let metadata: [CFString: Any] = [
    kCGImagePropertyPNGDictionary: [
        kCGImagePropertyPNGDescription: "Breakwater app icon. Original artwork generated with the built-in image_gen tool.\n\n\(prompt)",
        kCGImagePropertyPNGSoftware: "Breakwater Scripts/generate_icon.swift"
    ]
]
let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, bitmap.makeImage()!, metadata as CFDictionary)
precondition(CGImageDestinationFinalize(destination), "Failed to write app icon")
print("Wrote opaque 1024×1024 sRGB app icon to \(outputURL.path)")
