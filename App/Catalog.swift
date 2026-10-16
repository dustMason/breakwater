import Foundation

struct LoopParts: Codable {
    let files: [String]
    let waveforms: [[Float]]
}
struct LoopSample: Codable, Identifiable {
    let id: Int32
    let number: Int
    let file: String
    let bars: Int
    let beats: Int
    let bpm: Double
    let frames: Int
    let sampleRate: Int
    let sourceStart: String
    let sourceEnd: String
    let waveform: [Float]
    let sliceFrames: [Int32]
    let parts: LoopParts?
    var label: String { String(format: "%02d", number) }
}
struct Song: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String
    let sourceBPM: Int
    let sourceURL: URL
    let loops: [LoopSample]
    let partLabels: [String]?
    var midiPads: [Int32: Int32] {
        Dictionary(uniqueKeysWithValues: loops.filter { (1...30).contains($0.number) }
            .map { (Int32(35 + $0.number), $0.id) })
    }
}
struct PlaybackState {
    var beat = 0.0
    var bpm = 120.0
    var progress = 0.0
    var playing = false
    var active: Int32 = -1
    var pending = false
    var queue: [Int32] = []
    var clockState = 0
    var clockLabel: String {
        ["INTERNAL", "WAITING", "LOCKED", "FREEWHEEL", "CLOCK LOST"][min(4, max(0, clockState))]
    }
}
