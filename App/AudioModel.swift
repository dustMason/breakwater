import SwiftUI
import AVFoundation
import CoreMIDI
import Darwin

/// Fast playback snapshots have their own publisher so they do not rebuild
/// navigation and modal controls thirty times per second.
final class PlaybackMonitor: ObservableObject {
    @Published var state = PlaybackState()
}

final class AudioModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var selectedSong = 0 {
        didSet {
            guard songs.indices.contains(selectedSong) else { return }
            let ids = songs[selectedSong].midiPads
            control.async { [weak self] in self?.midiPads = ids; self?.heldNotes.removeAll(); self?.midiChord.removeAll() }
        }
    }
    let playback = PlaybackMonitor()
    var state: PlaybackState { playback.state }
    @Published var ready = false
    @Published var loadProgress = 0.0
    @Published var error: String?
    @Published var editing = false
    @Published var disabled: Set<Int32> = []
    @Published var mode = 0
    @Published var external = false
    @Published var manualBPM = 120.0
    @Published var syncOffset = 0.0
    @Published var midiSources: [MIDISource] = []
    @Published var midiSourceID: Int32 = 0
    @Published var outputName = "iPad audio"
    @Published var partMasks: [String: Int] = [:]
    @Published var partStatus: String?
    @Published var filterType = 0
    @Published var filterCutoff = 1200.0
    private let control = DispatchQueue(label: "Breakwater.control", qos: .userInteractive)
    private let partIO = DispatchQueue(label: "Breakwater.parts", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let dsp: BWEngine
    private var node: AVAudioSourceNode?
    private var midi: MIDIInput?
    private var timer: Timer?
    #if DEBUG
    private var testClockTimer: Timer?
    #endif
    private var observers: [NSObjectProtocol] = []
    private var midiPads: [Int32: Int32] = [:]
    private var heldNotes: Set<Int32> = []
    private var midiChord: [Int32] = []
    private var startAttempted = false
    private var warnedOverflow = false
    private var hostScale = 0.0
    private var sampleByID: [Int32: LoopSample] = [:]
    private var songByLoop: [Int32: String] = [:]
    private var partCache: [Int32] = []
    private var partLoading: Set<Int32> = []
    private var partFailures: Set<Int32> = []
    private let defaults = UserDefaults.standard

    init() {
        dsp = bw_create(48000)!
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-preferences") {
            defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        }
        #endif
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
        hostScale = Double(info.numer) / Double(info.denom) / 1_000_000_000
        disabled = Set((defaults.array(forKey: "disabledLoops") as? [Int] ?? []).map(Int32.init))
        mode = defaults.integer(forKey: "playbackMode")
        external = defaults.bool(forKey: "externalClock")
        manualBPM = defaults.object(forKey: "manualBPM") as? Double ?? 120
        syncOffset = defaults.double(forKey: "syncOffset")
        midiSourceID = Int32(defaults.integer(forKey: "midiSourceID"))
        partMasks = defaults.dictionary(forKey: "partMasks") as? [String: Int] ?? [:]
        do {
            let url = Bundle.main.resourceURL!.appendingPathComponent("Samples/catalog.json")
            songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: url))
            let ids = songs.flatMap(\.loops).map(\.id)
            guard !songs.isEmpty, songs.allSatisfy({ !$0.loops.isEmpty }),
                  Set(ids).count == ids.count, ids.allSatisfy({ $0 >= 0 && $0 < 1024 }) else { throw LoadError.invalidCatalog }
            midiPads = songs[0].midiPads
            for song in songs { for sample in song.loops { sampleByID[sample.id] = sample; songByLoop[sample.id] = song.id } }
        } catch { self.error = "The sample library could not load: \(error.localizedDescription)"; return }
        let all = songs.flatMap(\.loops), handle = dsp
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let retainedSelf = self else { return }
            defer { withExtendedLifetime(retainedSelf) {} }
            do {
                for (index, sample) in all.enumerated() {
                    let url = Bundle.main.resourceURL!.appendingPathComponent("Samples/" + sample.file)
                    let file = try AVAudioFile(forReading: url)
                    guard file.processingFormat.sampleRate == 48000, file.processingFormat.channelCount == 2,
                          file.length == sample.frames,
                          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw LoadError.invalidSample }
                    try file.read(into: buffer)
                    guard let channels = buffer.floatChannelData else { throw LoadError.invalidSample }
                    var pcm = [Float](repeating: 0, count: sample.frames * 2)
                    for frame in 0..<sample.frames { pcm[frame*2] = channels[0][frame]; pcm[frame*2+1] = channels[1][frame] }
                    let result = pcm.withUnsafeBufferPointer { audio in sample.sliceFrames.withUnsafeBufferPointer { cuts in
                        bw_load_loop(handle, sample.id, audio.baseAddress, Int32(sample.frames), Int32(sample.beats), cuts.baseAddress, Int32(cuts.count))
                    } }
                    guard result == 1 else { throw LoadError.invalidSample }
                    DispatchQueue.main.async { self?.loadProgress = Double(index + 1) / Double(all.count) }
                }
                DispatchQueue.main.async { self?.finishLoading() }
            } catch { DispatchQueue.main.async { self?.error = "Sample loading failed: \(error.localizedDescription). Relaunch to retry." } }
        }
    }
    enum LoadError: LocalizedError {
        case invalidCatalog, invalidSample
        var errorDescription: String? { "The bundled sample data is incomplete or has an unsupported format." }
    }
    private func finishLoading() {
        setMode(mode); setTempo(manualBPM); setExternal(external); setOffset(syncOffset)
        setFilter(type: filterType, cutoff: filterCutoff)
        for song in songs { sendPartMask(song) }
        for id in disabled { control.async { [dsp] in bw_enable(dsp, id, 0) } }
        do { try startAudio(); ready = true } catch { self.error = "Audio could not start: \(error.localizedDescription). Check the output connection and tap Retry audio." }
        midi = MIDIInput(queue: control) { [weak self] status, value, time in
            guard let self else { return }
            if status >= 0xF0 { bw_midi(self.dsp, status, value, time); return }
            let note = value & 0xFF, velocity = value >> 8, kind = status & 0xF0
            guard let id = self.midiPads[note] else { return }
            if kind == 0x90 && velocity > 0 {
                if self.heldNotes.isEmpty { self.midiChord = [] }
                self.heldNotes.insert(note)
                if !self.midiChord.contains(id) { self.midiChord.append(id) }
                self.midiChord.withUnsafeBufferPointer { bw_queue(self.dsp, $0.baseAddress, Int32($0.count)) }
            } else if kind == 0x80 || kind == 0x90 { self.heldNotes.remove(note) }
        }
        midi?.sourcesChanged = { [weak self] in self?.midiSources = $0 }
        midi?.selectedID = midiSourceID; midi?.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            if type == .began { self.stop(); self.engine.pause(); self.error = "Audio was interrupted. Resume when you're ready." }
            else { self.retryAudio() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            self.updateOutput()
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.stop(); self.error = "Audio output disconnected. Check your connection, then press Play." }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.startAttempted else { return }
            self.stop(); self.retryAudio()
        })
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-midi-clock") {
            setExternal(true)
            control.async { [dsp, hostScale] in bw_midi(dsp, 0xFA, 0, Double(mach_absolute_time()) * hostScale) }
            testClockTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 48.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                let time = Double(mach_absolute_time()) * self.hostScale
                self.control.async { [dsp = self.dsp] in bw_midi(dsp, 0xF8, 0, time) }
            }
            RunLoop.main.add(testClockTimer!, forMode: .common)
        }
        if ProcessInfo.processInfo.arguments.contains("--snapshot-demo") {
            setExternal(false)
            queue([5])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.queue([8, 13]) }
        }
        #endif
    }
    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredSampleRate(48000)
        try session.setPreferredIOBufferDuration(256/48000)
        try session.setActive(true)
        if node == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            let handle = dsp, scale = hostScale
            let source = AVAudioSourceNode(format: format) { _, timestamp, frames, list in
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                guard buffers.count >= 2, let l = buffers[0].mData, let r = buffers[1].mData else { return kAudio_ParamError }
                let host = timestamp.pointee.mHostTime == 0 ? mach_absolute_time() : timestamp.pointee.mHostTime
                bw_render(handle, l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames, Double(host)*scale)
                return noErr
            }
            node = source; engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.85
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--mute-audio") {
                engine.mainMixerNode.outputVolume = 0
            }
            #endif
        }
        try engine.start(); startAttempted = true; updateOutput()
    }
    func retryAudio() {
        do { try startAudio(); ready = true } catch { self.error = "Audio is unavailable: \(error.localizedDescription). Check your output and retry." }
    }
    private func updateOutput() { outputName = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", ") }
    func queue(_ ids: [Int32]) {
        guard ready else { return }
        let accepted = ids.filter { !disabled.contains($0) }
        guard !accepted.isEmpty else { return }
        control.async { [dsp] in accepted.withUnsafeBufferPointer { bw_queue(dsp, $0.baseAddress, Int32($0.count)) } }
    }
    func toggleDisabled(_ id: Int32) {
        if disabled.contains(id) { disabled.remove(id) } else { disabled.insert(id) }
        defaults.set(disabled.map(Int.init).sorted(), forKey: "disabledLoops")
        let enabled: Int32 = disabled.contains(id) ? 0 : 1
        control.async { [dsp] in bw_enable(dsp, id, enabled) }
    }
    func enableSong() { guard songs.indices.contains(selectedSong) else { return }; for loop in songs[selectedSong].loops where disabled.contains(loop.id) { toggleDisabled(loop.id) } }
    func setMode(_ value: Int) { mode = value; defaults.set(value, forKey: "playbackMode"); control.async { [dsp] in bw_mode(dsp, Int32(value)) } }
    func setTempo(_ value: Double) { manualBPM = min(300,max(30,value)); defaults.set(manualBPM, forKey: "manualBPM"); let bpm=manualBPM; control.async { [dsp] in bw_tempo(dsp, bpm) } }
    func setExternal(_ value: Bool) { external=value; defaults.set(value, forKey:"externalClock"); let bpm=manualBPM; control.async { [dsp] in bw_external(dsp, value ? 1 : 0); if !value { bw_tempo(dsp, bpm) } } }
    func setOffset(_ value: Double) { syncOffset=value; defaults.set(value,forKey:"syncOffset"); control.async { [dsp] in bw_offset(dsp,value) } }
    func partMask(_ song: Song) -> Int { (partMasks[song.id] ?? 15) & 15 }
    private func sendPartMask(_ song: Song) {
        let mask = Int32(partMask(song)), ids = song.loops.map(\.id)
        control.async { [dsp] in for id in ids { bw_part_mask(dsp, id, mask) } }
    }
    func togglePart(_ index: Int, song: Song) {
        guard (0..<4).contains(index) else { return }
        setPartsMask(partMask(song) ^ (1 << index), song: song)
    }
    func setPartsMask(_ mask: Int, song: Song) {
        partMasks[song.id] = mask & 15
        defaults.set(partMasks, forKey: "partMasks")
        sendPartMask(song)
        refreshParts()
    }
    func setFilter(type: Int, cutoff: Double) {
        filterType = min(3, max(0, type)); filterCutoff = min(18000, max(40, cutoff))
        let t = Int32(filterType), hz = filterCutoff
        control.async { [dsp] in bw_filter(dsp, t, hz) }
    }
    func retryParts() { partFailures.removeAll(); partStatus = nil; refreshParts() }
    private func refreshParts() {
        let candidates = [state.active] + Array(state.queue.prefix(3))
        for id in Set(candidates) {
            guard id >= 0, let songID = songByLoop[id], (partMasks[songID] ?? 15) != 15,
                  let sample = sampleByID[id], sample.parts != nil else { continue }
            prepareParts(sample)
        }
        let status: String?
        if state.playing, let songID = songByLoop[state.active], (partMasks[songID] ?? 15) != 15,
           !partCache.contains(state.active) {
            status = partFailures.contains(state.active) ? "Parts unavailable. Retry to use the selected layers." : ((partMasks[songID] ?? 15) == 0 ? "Preparing parts · all layers are off" : "Preparing parts · full mix plays until ready")
        } else { status = nil }
        if partStatus != status { partStatus = status }
    }
    private func prepareParts(_ sample: LoopSample) {
        guard !partCache.contains(sample.id), !partLoading.contains(sample.id), !partFailures.contains(sample.id),
              let parts = sample.parts, parts.files.count == 4 else { return }
        partLoading.insert(sample.id)
        partIO.async { [self] in
            do {
                var pcm = [Float](repeating: 0, count: sample.frames * 8)
                for (part, path) in parts.files.enumerated() {
                    let url = Bundle.main.resourceURL!.appendingPathComponent("Samples/" + path)
                    let file = try AVAudioFile(forReading: url)
                    guard file.processingFormat.sampleRate == 48000, file.processingFormat.channelCount == 2,
                          file.length >= sample.frames,
                          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(sample.frames)) else { throw LoadError.invalidSample }
                    try file.read(into: buffer, frameCount: AVAudioFrameCount(sample.frames))
                    guard buffer.frameLength == sample.frames, let channels = buffer.floatChannelData else { throw LoadError.invalidSample }
                    let base = part * sample.frames * 2
                    for frame in 0..<sample.frames { pcm[base + frame*2] = channels[0][frame]; pcm[base + frame*2+1] = channels[1][frame] }
                }
                let bank = pcm.withUnsafeBufferPointer { bw_create_parts($0.baseAddress, Int32(sample.frames)) }
                guard let bank else { throw LoadError.invalidSample }
                DispatchQueue.main.async { [self] in
                    partLoading.remove(sample.id)
                    partCache.append(sample.id)
                    control.async { [dsp] in bw_set_parts(dsp, sample.id, bank) }
                    let protected = Set([state.active] + Array(state.queue.prefix(3)))
                    while partCache.count > 6, let index = partCache.firstIndex(where: { !protected.contains($0) }) {
                        let old = partCache.remove(at: index)
                        control.async { [dsp] in bw_set_parts(dsp, old, nil) }
                    }
                    refreshParts()
                }
            } catch {
                DispatchQueue.main.async { [self] in partLoading.remove(sample.id); partFailures.insert(sample.id); refreshParts() }
            }
        }
    }
    func selectMIDI(_ id: Int32) { midiSourceID=id; defaults.set(Int(id),forKey:"midiSourceID"); stop(); midi?.selectedID=id; midi?.refresh() }
    func stop() { control.async { [dsp] in bw_transport(dsp,0) } }
    func play() { control.async { [dsp] in bw_transport(dsp,2) } }
    func nudge(_ milliseconds: Double) { control.async { [dsp] in bw_nudge(dsp, milliseconds) } }
    func align() { control.async { [dsp] in bw_transport(dsp,3) } }
    private func poll() {
        var s=BWSnapshot(); bw_snapshot(dsp,&s)
        let count=Int(s.queueCount)
        let ids=withUnsafePointer(to:&s.queue) { pointer in pointer.withMemoryRebound(to:Int32.self,capacity:64) { Array(UnsafeBufferPointer(start:$0,count:count)) } }
        playback.state=PlaybackState(beat:s.beat,bpm:s.bpm,progress:s.loopProgress,playing:s.playing != 0,active:s.activeLoop,pending:s.pending != 0,queue:ids,clockState:Int(s.clockState))
        refreshParts()
        if s.droppedCommands>0 && !warnedOverflow { warnedOverflow=true; error="MIDI input overflowed. Check for a MIDI feedback loop, then restart the app."; stop() }
    }
    deinit {
        timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver)
        #if DEBUG
        testClockTimer?.invalidate()
        #endif
        engine.stop(); midi=nil
        let handle=dsp
        control.async { bw_destroy(handle) }
    }
}
