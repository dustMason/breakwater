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
    @Published var arrangement: [ArrangementStep] = []
    @Published var selectedClipID: Int32?
    @Published var arrangementStatus: String?
    @Published private(set) var waitingForLoop = false
    @Published var filterType = 0
    @Published var filterCutoff = 1200.0
    private let control = DispatchQueue(label: "Breakwater.control", qos: .userInteractive)
    private let partIO = DispatchQueue(label: "Breakwater.parts", qos: .userInitiated)
    private let sampleIO = DispatchQueue(label: "Breakwater.samples", qos: .userInitiated, attributes: .concurrent)
    private let sampleLimit = DispatchSemaphore(value: 4)
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
    private var nextClipID: Int32 = 1
    private var partCache: [Int32] = []
    private var partLoading: Set<Int32> = []
    private var partFailures: Set<Int32> = []
    private let defaults = UserDefaults.standard
    private var assets: AssetStore?
    private var loadedLoops: Set<Int32> = []
    private var loadingLoops: Set<Int32> = []
    private var failedLoops: Set<Int32> = []
    private var arrangementStartsPlayback = true
    private var libraryLoading = false

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
        loadLibrary()
    }

    private func loadLibrary() {
        guard !libraryLoading else { return }
        libraryLoading = true
        var base = Bundle.main.object(forInfoDictionaryKey: "BreakwaterAssetBaseURL") as? String ?? ""
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--asset-base-url"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
            base = ProcessInfo.processInfo.arguments[index + 1]
        }
        #endif
        let baseURLString = base
        sampleIO.async { [self] in
            do {
                let store = try AssetStore(baseString: baseURLString)
                let library = try store.catalog()
                DispatchQueue.main.async { [self] in
                    assets = store; songs = library; midiPads = library[0].midiPads
                    for song in library { for sample in song.loops { sampleByID[sample.id] = sample; songByLoop[sample.id] = song.id } }
                    libraryLoading = false; finishLoading()
                }
            } catch { DispatchQueue.main.async { [self] in libraryLoading = false; self.error = "The sample library could not load: \(error.localizedDescription)" } }
        }
    }
    enum LoadError: LocalizedError {
        case invalidSample
        var errorDescription: String? { "The sample data is incomplete or has an unsupported format." }
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
                let chord = self.midiChord
                DispatchQueue.main.async { [weak self] in self?.queue(chord) }
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
    func retry() { if songs.isEmpty { loadLibrary() } else { retryAudio() } }
    private func updateOutput() { outputName = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", ") }
    func queue(_ ids: [Int32]) {
        guard ready else { return }
        let accepted = ids.filter { !disabled.contains($0) }
        guard !accepted.isEmpty else { return }
        failedLoops.subtract(accepted)
        arrangement = accepted.map { ArrangementStep(clips: [makeClip($0)]) }
        selectedClipID = arrangement.first?.clips.first?.id
        submitArrangement()
    }
    var selectedClip: ArrangementClip? { arrangement.flatMap(\.clips).first { $0.id == selectedClipID } }
    var selectedSample: LoopSample? { selectedClip.flatMap { sampleByID[$0.sampleID] } }
    var selectedClipSong: Song? { selectedClip.flatMap { clip in songs.first { $0.id == songByLoop[clip.sampleID] } } }
    func sample(_ id: Int32) -> LoopSample? { sampleByID[id] }
    func songForSample(_ id: Int32) -> Song? { songs.first { $0.id == songByLoop[id] } }
    private func makeClip(_ id: Int32) -> ArrangementClip {
        let token = nextClipID; nextClipID = nextClipID == Int32.max ? 1 : nextClipID + 1
        return ArrangementClip(id: token, sampleID: id, mask: (partMasks[songByLoop[id] ?? ""] ?? 15) & 15)
    }
    func addSample(_ id: Int32, at index: Int, layer: Bool) {
        guard ready, !disabled.contains(id), sampleByID[id] != nil else { return }
        failedLoops.remove(id)
        guard arrangement.reduce(0, { $0 + $1.clips.count }) < 64 else { arrangementStatus = "The sequence can hold up to 64 samples."; return }
        if layer, arrangement.indices.contains(index), arrangement[index].clips.count >= 8 {
            arrangementStatus = "A step can contain up to 8 layers."; return
        }
        let clip = makeClip(id)
        if layer, arrangement.indices.contains(index) { arrangement[index].clips.append(clip) }
        else { arrangement.insert(ArrangementStep(clips: [clip]), at: min(arrangement.count, max(0, index))) }
        selectedClipID = clip.id; arrangementStatus = nil; submitArrangement()
    }
    func removeClip(_ token: Int32) {
        for i in arrangement.indices { arrangement[i].clips.removeAll { $0.id == token } }
        arrangement.removeAll { $0.clips.isEmpty }
        if selectedClipID == token { selectedClipID = nil }
        submitArrangement(startIfStopped: false)
    }
    func clearArrangement() {
        arrangement.removeAll(); selectedClipID = nil; arrangementStatus = nil
        submitArrangement(startIfStopped: false)
    }
    private func submitArrangement(startIfStopped: Bool = true) {
        arrangementStartsPlayback = startIfStopped
        let ids = Set(arrangement.flatMap(\.clips).map(\.sampleID))
        let missing = ids.subtracting(loadedLoops)
        if !missing.isEmpty {
            waitingForLoop = startIfStopped
            arrangementStatus = missing.contains(where: { failedLoops.contains($0) })
                ? "A loop couldn't load. Retry samples."
                : "Loading loops · current playback continues"
            for id in missing where !loadingLoops.contains(id) && !failedLoops.contains(id) {
                if let sample = sampleByID[id] { loadLoop(sample) }
            }
            return
        }
        waitingForLoop = false
        arrangementStatus = nil
        let clips = arrangement.enumerated().flatMap { step, group in
            group.clips.map { BWClipWithLevel(loop: $0.sampleID, token: $0.id, step: Int32(step), mask: Int32($0.mask), filterType: Int32($0.filterType), filterHz: Int32($0.filterCutoff.rounded()), levelMilli: Int32(($0.level * 1000).rounded())) }
        }
        control.async { [dsp] in clips.withUnsafeBufferPointer {
            if startIfStopped { bw_arrange_with_levels(dsp, $0.baseAddress, Int32($0.count)) }
            else { bw_edit_arrangement_with_levels(dsp, $0.baseAddress, Int32($0.count)) }
        } }
    }
    func retrySamples() { failedLoops.removeAll(); submitArrangement(startIfStopped: arrangementStartsPlayback) }

    private func loadLoop(_ sample: LoopSample) {
        guard let assets else { return }
        loadingLoops.insert(sample.id)
        sampleIO.async { [self] in
            sampleLimit.wait(); defer { sampleLimit.signal() }
            do {
                let url = try assets.file(sample.file)
                let file = try AVAudioFile(forReading: url)
                guard file.processingFormat.sampleRate == 48000, file.processingFormat.channelCount == 2,
                      file.length == sample.frames,
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw LoadError.invalidSample }
                try file.read(into: buffer)
                guard buffer.frameLength == sample.frames, let channels = buffer.floatChannelData else { throw LoadError.invalidSample }
                var pcm = [Float](repeating: 0, count: sample.frames * 2)
                for frame in 0..<sample.frames { pcm[frame*2] = channels[0][frame]; pcm[frame*2+1] = channels[1][frame] }
                let result = pcm.withUnsafeBufferPointer { audio in sample.sliceFrames.withUnsafeBufferPointer { cuts in
                    bw_load_loop(dsp, sample.id, audio.baseAddress, Int32(sample.frames), Int32(sample.beats), cuts.baseAddress, Int32(cuts.count))
                } }
                guard result == 1 else { throw LoadError.invalidSample }
                DispatchQueue.main.async { [self] in
                    loadingLoops.remove(sample.id); loadedLoops.insert(sample.id)
                    if arrangement.flatMap(\.clips).contains(where: { $0.sampleID == sample.id }) {
                        submitArrangement(startIfStopped: arrangementStartsPlayback); refreshParts()
                    }
                }
            } catch {
                DispatchQueue.main.async { [self] in
                    loadingLoops.remove(sample.id); failedLoops.insert(sample.id)
                    if arrangement.flatMap(\.clips).contains(where: { $0.sampleID == sample.id }) {
                        submitArrangement(startIfStopped: arrangementStartsPlayback)
                    }
                }
            }
        }
    }
    func toggleDisabled(_ id: Int32) {
        if disabled.contains(id) { disabled.remove(id) } else { disabled.insert(id) }
        defaults.set(disabled.map(Int.init).sorted(), forKey: "disabledLoops")
        let enabled: Int32 = disabled.contains(id) ? 0 : 1
        control.async { [dsp] in bw_enable(dsp, id, enabled) }
        if enabled == 0 {
            for i in arrangement.indices { arrangement[i].clips.removeAll { $0.sampleID == id } }
            arrangement.removeAll { $0.clips.isEmpty }
            if selectedClip == nil { selectedClipID = nil }
            submitArrangement(startIfStopped: false)
        }
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
    func togglePart(_ index: Int, clipID token: Int32) {
        guard (0..<4).contains(index), let clip = arrangement.flatMap(\.clips).first(where: { $0.id == token }) else { return }
        setPartsMask(clip.mask ^ (1 << index), clipID: token)
    }
    func setPartsMask(_ mask: Int, clipID token: Int32) {
        guard arrangement.contains(where: { $0.clips.contains(where: { $0.id == token }) }) else { return }
        selectedClipID = token
        for i in arrangement.indices { for j in arrangement[i].clips.indices where arrangement[i].clips[j].id == token { arrangement[i].clips[j].mask = mask & 15 } }
        control.async { [dsp] in bw_clip_mask(dsp, token, Int32(mask & 15)) }
        refreshParts()
    }
    func setFilter(type: Int, cutoff: Double) {
        filterType = min(3, max(0, type)); filterCutoff = min(18000, max(40, cutoff))
        let t = Int32(filterType), hz = filterCutoff
        control.async { [dsp] in bw_filter(dsp, t, hz) }
    }
    func setClipFilter(_ token: Int32, type: Int, cutoff: Double) {
        guard cutoff.isFinite, arrangement.contains(where: { $0.clips.contains(where: { $0.id == token }) }) else { return }
        selectedClipID = token
        let kind = min(3, max(0, type)), hz = min(18000, max(40, cutoff))
        for i in arrangement.indices { for j in arrangement[i].clips.indices where arrangement[i].clips[j].id == token {
            arrangement[i].clips[j].filterType = kind
            arrangement[i].clips[j].filterCutoff = hz
        } }
        control.async { [dsp] in bw_clip_filter(dsp, token, Int32(kind), hz) }
    }
    func setClipLevel(_ token: Int32, level: Double) {
        guard level.isFinite else { return }
        let value = min(1, max(0, level))
        for i in arrangement.indices { for j in arrangement[i].clips.indices where arrangement[i].clips[j].id == token {
            arrangement[i].clips[j].level = value
        } }
        control.async { [dsp] in bw_clip_level(dsp, token, value) }
    }
    func retryParts() { partFailures.removeAll(); partStatus = nil; refreshParts() }
    var gridMasks: [Int32: Int] {
        var masks: [Int32: Int] = [:]
        for clip in arrangement.flatMap(\.clips) where state.activeTokens.contains(clip.id) { masks[clip.sampleID] = clip.mask }
        if let clip = selectedClip { masks[clip.sampleID] = clip.mask }
        return masks
    }
    var gridOrders: [Int32: Int] {
        var orders: [Int32: Int] = [:]
        for (index, step) in arrangement.enumerated() {
            for clip in step.clips where orders[clip.sampleID] == nil { orders[clip.sampleID] = index + 1 }
        }
        return orders
    }
    private var upcomingParts: [ArrangementClip] {
        guard !arrangement.isEmpty else { return [] }
        let index = arrangement.firstIndex { step in step.clips.contains { state.activeTokens.contains($0.id) } } ?? 0
        var clips = arrangement[index].clips + arrangement[(index + 1) % arrangement.count].clips
        if let selectedClip { clips.append(selectedClip) }
        return clips
    }
    private func refreshParts() {
        for id in Set(upcomingParts.filter { $0.mask != 15 }.map(\.sampleID)) {
            guard let sample = sampleByID[id], sample.parts != nil else { continue }
            prepareParts(sample)
        }
        let status: String?
        if let clip = selectedClip, clip.mask != 15, !partCache.contains(clip.sampleID) {
            status = partFailures.contains(clip.sampleID) ? "Parts unavailable. Retry to use the selected layers." : (clip.mask == 0 ? "Preparing parts · all layers are off" : "Preparing parts · full mix plays until ready")
        } else { status = nil }
        if partStatus != status { partStatus = status }
    }
    private func prepareParts(_ sample: LoopSample) {
        guard loadedLoops.contains(sample.id), let assets,
              !partCache.contains(sample.id), !partLoading.contains(sample.id), !partFailures.contains(sample.id),
              let parts = sample.parts, parts.files.count == 4 else { return }
        partLoading.insert(sample.id)
        partIO.async { [self] in
            do {
                var pcm = [Float](repeating: 0, count: sample.frames * 8)
                for (part, path) in parts.files.enumerated() {
                    let url = try assets.file(path)
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
                    let protected = Set(state.activeLoops + upcomingParts.map(\.sampleID))
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
    func stop() {
        // A selection may still be downloading when the user stops or audio is interrupted.
        // Install it when ready without restarting transport.
        arrangementStartsPlayback = false
        waitingForLoop = false
        control.async { [dsp] in bw_transport(dsp,0) }
    }
    func play() { if !arrangement.isEmpty { submitArrangement() }; control.async { [dsp] in bw_transport(dsp,2) } }
    func nudge(_ milliseconds: Double) { control.async { [dsp] in bw_nudge(dsp, milliseconds) } }
    func align() { control.async { [dsp] in bw_transport(dsp,3) } }
    private func poll() {
        var s=BWSnapshot(); bw_snapshot(dsp,&s)
        let count=Int(s.queueCount)
        let ids=withUnsafePointer(to:&s.queue) { pointer in pointer.withMemoryRebound(to:Int32.self,capacity:64) { Array(UnsafeBufferPointer(start:$0,count:count)) } }
        let activeCount = Int(s.activeCount)
        let activeLoops = withUnsafePointer(to:&s.activeLoops) { pointer in pointer.withMemoryRebound(to:Int32.self,capacity:8) { Array(UnsafeBufferPointer(start:$0,count:activeCount)) } }
        let activeTokens = withUnsafePointer(to:&s.activeTokens) { pointer in pointer.withMemoryRebound(to:Int32.self,capacity:8) { Array(UnsafeBufferPointer(start:$0,count:activeCount)) } }
        let activeProgress = withUnsafePointer(to:&s.activeProgress) { pointer in pointer.withMemoryRebound(to:Double.self,capacity:8) { Array(UnsafeBufferPointer(start:$0,count:activeCount)) } }
        playback.state=PlaybackState(beat:s.beat,bpm:s.bpm,progress:s.loopProgress,playing:s.playing != 0,active:s.activeLoop,pending:s.pending != 0,queue:ids,activeLoops:activeLoops,activeTokens:activeTokens,activeProgress:activeProgress,activeStep:Int(s.activeStep),clockState:Int(s.clockState))
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
