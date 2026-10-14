import AppKit
import Foundation

// The icon is data geometry: the actual sg06 amplitude envelope and playhead.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Samples/catalog.json"))) as! [[String: Any]]
let loops = catalog[0]["loops"] as! [[String: Any]]
let peaks = loops[5]["waveform"] as! [Double]
let size = 1024
let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
NSColor(srgbRed: 0, green: 0.30, blue: 0.79, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
NSColor.white.withAlphaComponent(0.13).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 585, height: size)).fill()
let waveform=NSBezierPath()
for (i,peak) in peaks.enumerated() {
 let p=NSPoint(x:110+804*Double(i)/Double(peaks.count-1),y:512+peak*260)
 if i==0 { waveform.move(to:p) } else { waveform.line(to:p) }
}
for i in peaks.indices.reversed() { waveform.line(to:NSPoint(x:110+804*Double(i)/Double(peaks.count-1),y:512-peaks[i]*260)) }
waveform.close(); NSColor.white.setFill(); waveform.fill()
NSBezierPath(rect:NSRect(x:582,y:110,width:6,height:804)).fill()
NSGraphicsContext.restoreGraphicsState()
let rep = NSBitmapImageRep(cgImage: bitmap.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
