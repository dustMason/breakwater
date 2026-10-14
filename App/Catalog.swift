import Foundation

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
    var label: String { String(format: "%02d", number) }
}
struct Song: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String
    let sourceBPM: Int
    let sourceURL: URL
    let loops: [LoopSample]
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
