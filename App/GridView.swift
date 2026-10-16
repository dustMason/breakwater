import SwiftUI
import UniformTypeIdentifiers

struct GridView: View {
    @ObservedObject var audio: AudioModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showSettings = false
    @State private var showTempo = false
    @State private var tray = 0
    private var song: Song? { audio.songs.indices.contains(audio.selectedSong) ? audio.songs[audio.selectedSong] : nil }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                PlaybackContent(audio: audio, playback: audio.playback, song: song,
                                compact: geometry.size.width < 900 || typeSize.isAccessibilitySize,
                                showSettings: $showSettings, showTempo: $showTempo, tray: $tray)
            }
            .background(Color(uiColor: .systemBackground))
        }
        .sheet(isPresented: $showSettings) { SettingsView(audio: audio) }
        .sheet(isPresented: $showTempo) { TempoView(audio: audio) }
        .alert("Audio needs attention", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) {
            Button("Retry") { audio.error = nil; audio.retry() }
            Button("Dismiss", role: .cancel) { audio.error = nil }
        } message: { Text(audio.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Breakwater").font(.headline)
            Spacer(minLength: 4)
            if let song {
                Text(song.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("≈\(song.sourceBPM) BPM").font(.caption.monospacedDigit()).foregroundStyle(Palette.secondary)
                    .accessibilityIdentifier("sourceBPM")
            }
            Button("Use source") { if let song { audio.setTempo(Double(song.sourceBPM)) } }
                .buttonStyle(.bordered).frame(minHeight: 44).disabled(song == nil || audio.external)
                .accessibilityIdentifier("useSourceTempo")
                .accessibilityHint(audio.external ? "Turn off Follow MIDI clock to use the source tempo." : "Set the manual tempo to this folder's source tempo.")
            Button("Sound") { tray = tray == 0 ? 1 : 0 }
                .buttonStyle(.bordered).tint(tray == 1 ? Palette.accent : nil)
                .frame(minHeight: 44).accessibilityIdentifier("showSound")
        }.padding(.horizontal, 14).padding(.vertical, 2)
    }
}

private enum LibraryPlacement {
    case end, before, after, layer
    var accessibilityValue: String {
        switch self {
        case .end: return "Add to end"
        case .before: return "Insert before selected step"
        case .after: return "Insert after selected step"
        case .layer: return "Add as layer"
        }
    }
    var accessibilityHint: String {
        switch self {
        case .end: return "Add to the end of the timeline, or drag to place it"
        case .before: return "Insert before the selected step, or at the beginning if none is selected"
        case .after: return "Insert after the selected step, or at the end if none is selected"
        case .layer: return "Add as a layer to the selected step, or the last step if none is selected"
        }
    }
    var hint: String {
        switch self {
        case .end: return "Tap to add at end · drag to place"
        case .before: return "Tap to insert before selection"
        case .after: return "Tap to insert after selection"
        case .layer: return "Tap to layer on selection"
        }
    }
}

private struct LibrarySidebar: View {
    @ObservedObject var audio: AudioModel
    @State private var expanded: Set<String> = []
    @State private var placement = LibraryPlacement.end
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Library").font(.headline)
                Spacer(minLength: 0)
                Menu {
                    Button("Add to end") { placement = .end }
                    Button("Insert before selected step") { placement = .before }
                    Button("Insert after selected step") { placement = .after }
                    Button("Add as layer") { placement = .layer }
                } label: {
                    HStack(spacing: 2) { Text("Add"); Image(systemName: "chevron.down").font(.caption2) }
                        .frame(minHeight: 44)
                }.accessibilityLabel("Library tap action").accessibilityValue(placement.accessibilityValue).accessibilityIdentifier("placementMenu")
                Button(audio.editing ? "Done" : "Edit") { audio.editing.toggle() }
                    .frame(minHeight: 44).accessibilityIdentifier("editPads")
            }.padding(.horizontal, 10)
            Text(audio.editing ? "Tap to exclude or restore" : placement.hint)
                .font(.caption2).foregroundStyle(Palette.secondary).padding(.horizontal, 10).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(audio.songs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            if expanded.contains(song.id) { expanded.remove(song.id) } else { expanded.insert(song.id) }
                            audio.selectedSong = index
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: expanded.contains(song.id) ? "chevron.down" : "chevron.right").font(.caption2.weight(.semibold))
                                Text(song.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(index == audio.selectedSong ? Palette.accent : Color(uiColor: .label))
                        .padding(.horizontal, 10).accessibilityIdentifier("song_\(song.id)")
                        if expanded.contains(song.id) {
                            ForEach(song.loops) { sample in LibraryLoopRow(audio: audio, song: song, sample: sample, placement: placement) }
                        }
                        Divider()
                    }
                }
            }.accessibilityIdentifier("songList")
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .onAppear { if expanded.isEmpty, let first = audio.songs.first { expanded.insert(first.id) } }
        .onChange(of: audio.songs.count) { _, _ in if expanded.isEmpty, let first = audio.songs.first { expanded.insert(first.id) } }
    }
}

private struct LibraryLoopRow: View {
    @ObservedObject var audio: AudioModel
    let song: Song
    let sample: LoopSample
    let placement: LibraryPlacement
    private var excluded: Bool { audio.disabled.contains(sample.id) }
    var body: some View {
        Button {
            if let index = audio.songs.firstIndex(where: { $0.id == song.id }), index != audio.selectedSong { audio.selectedSong = index }
            if audio.editing { audio.toggleDisabled(sample.id) }
            else {
                let selected = audio.arrangement.firstIndex { $0.clips.contains { $0.id == audio.selectedClipID } }
                switch placement {
                case .end: audio.addSample(sample.id, at: audio.arrangement.count, layer: false)
                case .before: audio.addSample(sample.id, at: selected ?? 0, layer: false)
                case .after: audio.addSample(sample.id, at: selected.map { $0 + 1 } ?? audio.arrangement.count, layer: false)
                case .layer: audio.addSample(sample.id, at: selected ?? max(0, audio.arrangement.count - 1), layer: !audio.arrangement.isEmpty)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(sample.label).font(.caption.weight(.semibold).monospacedDigit()).frame(width: 23, alignment: .leading)
                ClipWaveform(sample: sample, mask: 15, active: false, original: true).frame(height: 18)
                Text("\(sample.beats / 4)b").font(.caption2).foregroundStyle(Palette.secondary)
            }.padding(.leading, 22).padding(.trailing, 8).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(excluded ? 0.45 : 1)
        .disabled(!audio.ready || (excluded && !audio.editing))
        .onDrag {
            if let index = audio.songs.firstIndex(where: { $0.id == song.id }), index != audio.selectedSong { audio.selectedSong = index }
            return NSItemProvider(object: String(sample.id) as NSString)
        }
        .accessibilityLabel("\(song.name), loop \(sample.label), \(sample.beats / 4) bars")
        .accessibilityValue(excluded ? "Excluded" : "Ready")
        .accessibilityHint(audio.editing ? "Toggle exclusion" : placement.accessibilityHint)
        .accessibilityAction(named: Text("Add as layer")) {
            if let index = audio.songs.firstIndex(where: { $0.id == song.id }), index != audio.selectedSong { audio.selectedSong = index }
            let index = audio.arrangement.firstIndex { $0.clips.contains { $0.id == audio.selectedClipID } } ?? max(0, audio.arrangement.count - 1)
            audio.addSample(sample.id, at: index, layer: !audio.arrangement.isEmpty)
        }
        .accessibilityAction(named: Text("Insert before selected step")) {
            if let index = audio.songs.firstIndex(where: { $0.id == song.id }), index != audio.selectedSong { audio.selectedSong = index }
            let index = audio.arrangement.firstIndex { $0.clips.contains { $0.id == audio.selectedClipID } } ?? 0
            audio.addSample(sample.id, at: index, layer: false)
        }
        .accessibilityAction(named: Text("Insert after selected step")) {
            if let index = audio.songs.firstIndex(where: { $0.id == song.id }), index != audio.selectedSong { audio.selectedSong = index }
            let index = audio.arrangement.firstIndex { $0.clips.contains { $0.id == audio.selectedClipID } }.map { $0 + 1 } ?? audio.arrangement.count
            audio.addSample(sample.id, at: index, layer: false)
        }
        .accessibilityIdentifier("pad_\(sample.id)")
    }
}

private struct PlaybackContent: View {
    @ObservedObject var audio: AudioModel
    @ObservedObject var playback: PlaybackMonitor
    let song: Song?
    let compact: Bool
    @Binding var showSettings: Bool
    @Binding var showTempo: Bool
    @Binding var tray: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                LibrarySidebar(audio: audio).frame(width: compact ? 180 : 220)
                Divider()
                ArrangementTray(audio: audio, playback: playback, tray: $tray)
                if tray != 0 {
                    Divider()
                    SoundTray(audio: audio, tray: $tray).frame(width: compact ? 220 : 250)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !audio.ready && audio.error == nil { ProgressView("Loading library").padding(8).accessibilityIdentifier("loading") }
            Divider()
            if compact {
                VStack(spacing: 4) {
                    HStack { transport; Spacer(); tempo; Spacer(); clock }
                    HStack { modePicker; Spacer(minLength: 4); nudge; Spacer(minLength: 4); settings }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            } else {
                HStack(spacing: 20) {
                    transport; dockDivider; tempo; dockDivider; clock; nudge
                    Spacer(minLength: 0); modePicker.frame(maxWidth: 230); dockDivider; settings
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }
    private var transport: some View {
        let canStop = audio.state.playing || audio.waitingForLoop
        return Button {
            if canStop { audio.stop() }
            else if audio.arrangement.isEmpty, let first = song?.loops.first(where: { !audio.disabled.contains($0.id) }) { audio.queue([first.id]) }
            else { audio.play() }
        } label: {
            Label(canStop ? "Stop" : "Play", systemImage: canStop ? "stop.fill" : "play.fill")
                .font(.headline).frame(minWidth: 75, minHeight: 44)
                .foregroundStyle(canStop ? Color.red : Palette.accent)
        }.disabled(!audio.ready).accessibilityIdentifier("transport")
    }
    private var tempo: some View {
        Button { showTempo = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("TEMPO").font(.caption2.weight(.medium)).foregroundStyle(Palette.secondary)
                Text(audio.state.bpm, format: .number.precision(.fractionLength(1)))
                    .font(.title2.monospacedDigit()).foregroundStyle(Color(uiColor: .label))
            }.frame(minWidth: 82, minHeight: 44)
        }.accessibilityLabel("Tempo \(audio.state.bpm, specifier: "%.1f") BPM")
            .accessibilityHint("Open tempo controls").accessibilityIdentifier("tempo")
    }
    private var clock: some View {
        Button { showSettings = true } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(audio.external ? "MIDI" : "CLOCK").font(.caption2.weight(.medium)).foregroundStyle(Palette.secondary)
                Label(audio.state.clockLabel, systemImage: audio.state.clockState == 2 ? "lock.fill" : "metronome")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(audio.state.clockState >= 3 ? Color.orange : Palette.accent)
            }.frame(minHeight: 44)
        }.accessibilityIdentifier("clockStatus")
    }
    private var nudge: some View {
        HStack(spacing: 0) {
            Button { audio.nudge(10) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Nudge loop earlier")
            .accessibilityHint("Tap or hold to adjust timing without changing the tempo.")
            .accessibilityIdentifier("nudgeEarlier")
            Text("NUDGE").font(.caption2.weight(.medium)).foregroundStyle(Palette.secondary)
                .accessibilityHidden(true)
            Button { audio.nudge(-10) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Nudge loop later")
            .accessibilityHint("Tap or hold to adjust timing without changing the tempo.")
            .accessibilityIdentifier("nudgeLater")
        }
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(Palette.accent)
        .disabled(!playback.state.playing || playback.state.active < 0)
    }
    private var modePicker: some View {
        Picker("Playback mode", selection: Binding(get: { audio.mode }, set: audio.setMode)) {
            Text("Tape").tag(0); Text("Slice").tag(1)
        }.pickerStyle(.segmented).frame(minWidth: 150, minHeight: 44).accessibilityIdentifier("modePicker")
    }
    private var settings: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape").font(.title2).frame(width: 44, height: 44)
        }.accessibilityLabel("Settings").accessibilityIdentifier("settings")
    }
    private var dockDivider: some View { Divider().frame(height: 34) }
}

private func receiveSample(_ providers: [NSItemProvider], audio: AudioModel, index: Int, layer: Bool) -> Bool {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
    provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let value = object as? String, let id = Int32(value) else { return }
        DispatchQueue.main.async { audio.addSample(id, at: index, layer: layer) }
    }
    return true
}

private struct ArrangementTray: View {
    @ObservedObject var audio: AudioModel
    @ObservedObject var playback: PlaybackMonitor
    @Binding var tray: Int
    @State private var zoom: CGFloat = 1
    private func beats(_ step: ArrangementStep) -> Int { step.clips.map { audio.sample($0.sampleID)?.beats ?? 4 }.max() ?? 4 }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timeline").font(.headline)
                    Text(audio.arrangementStatus ?? (audio.arrangement.isEmpty ? "Drag a loop here to start" : "Drop beneath a clip to layer"))
                        .font(.caption2).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if audio.arrangementStatus?.hasPrefix("A loop couldn't load") == true { Button("Retry") { audio.retrySamples() } }
                Button { zoom = max(1, zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44) }.accessibilityLabel("Zoom out timeline")
                Button("Fit") { zoom = 1 }.frame(minHeight: 44).accessibilityIdentifier("zoomFit")
                Button { zoom = min(128, zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44) }.accessibilityLabel("Zoom in timeline")
                Button("Clear") { audio.clearArrangement() }.disabled(audio.arrangement.isEmpty).frame(minHeight: 44).accessibilityIdentifier("clearArrangement")
            }.padding(.horizontal, 10)
            Divider()
            GeometryReader { geometry in
                let width = max(geometry.size.width, 100) * zoom
                let totalBeats = max(1, audio.arrangement.reduce(0) { $0 + beats($1) })
                let gapWidth = min(16, max(2, (width - 72) / CGFloat(max(1, audio.arrangement.count - 1) * 3)))
                let gaps = CGFloat(max(0, audio.arrangement.count - 1)) * gapWidth + 72
                let musicalWidth = max(0, width - gaps)
                let layers = audio.arrangement.map { $0.clips.count }.max() ?? 1
                let height = max(geometry.size.height, CGFloat(layers) * 80 + 85)
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        if audio.arrangement.isEmpty {
                            SequenceDropGap(audio: audio, index: 0, empty: true).frame(width: width, height: height)
                        } else {
                            ForEach(Array(audio.arrangement.enumerated()), id: \.element.id) { index, step in
                                SequenceDropGap(audio: audio, index: index, empty: false).frame(width: index == 0 ? 36 : gapWidth, height: height)
                                SequenceCard(audio: audio, playback: playback, step: step, index: index,
                                             width: musicalWidth * CGFloat(beats(step)) / CGFloat(totalBeats),
                                             bar: 1 + audio.arrangement.prefix(index).reduce(0) { $0 + beats($1) / 4 },
                                             tray: $tray)
                                    .frame(width: musicalWidth * CGFloat(beats(step)) / CGFloat(totalBeats), height: height)
                            }
                            SequenceDropGap(audio: audio, index: audio.arrangement.count, empty: false).frame(width: 36, height: height)
                        }
                    }.frame(width: width, height: height, alignment: .topLeading)
                }.background(Color(uiColor: .secondarySystemBackground))
            }
        }
    }
}

private struct SequenceDropGap: View {
    @ObservedObject var audio: AudioModel
    let index: Int
    let empty: Bool
    @State private var targeted = false
    var body: some View {
        ZStack(alignment: empty ? .center : .top) {
            Rectangle().fill(targeted ? Palette.accent.opacity(0.12) : Color.clear)
            Text(empty ? "Drag a loop here to start your sequence" : "+")
                .font(empty ? .subheadline : .title3).foregroundStyle(targeted ? Palette.accent : Palette.secondary)
                .padding(.top, empty ? 0 : 42)
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText], isTargeted: $targeted) { receiveSample($0, audio: audio, index: index, layer: false) }
        .accessibilityIdentifier("dropStep_\(index)")
    }
}

private struct SequenceCard: View {
    @ObservedObject var audio: AudioModel
    @ObservedObject var playback: PlaybackMonitor
    let step: ArrangementStep
    let index: Int
    let width: CGFloat
    let bar: Int
    @Binding var tray: Int
    @State private var targetPosition: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("BAR \(bar)").font(.caption2.weight(.semibold)).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(.horizontal, 6)
            Divider()
            ForEach(step.clips) { clip in
                if let sample = audio.sample(clip.sampleID), let song = audio.songForSample(clip.sampleID) {
                    let index = playback.state.activeTokens.firstIndex(of: clip.id)
                    ClipRow(audio: audio, clip: clip, sample: sample, song: song,
                            active: playback.state.playing && index != nil,
                            progress: index.flatMap { playback.state.activeProgress.indices.contains($0) ? playback.state.activeProgress[$0] : nil } ?? 0,
                            stepBeats: step.clips.map { audio.sample($0.sampleID)?.beats ?? 4 }.max() ?? 4,
                            stepNumber: self.index + 1,
                            tray: $tray).frame(height: 74).padding(.horizontal, 4)
                }
            }
            Text("+ Drop a layer").font(.caption2).foregroundStyle(targetPosition == -1 ? Palette.accent : Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 40)
            Spacer(minLength: 0)
        }
        .background(targetPosition == -1 ? Palette.accent.opacity(0.12) : Color(uiColor: .systemBackground).opacity(0.7))
        .overlay(Rectangle().strokeBorder(targetPosition == -1 ? Palette.accent : Color(uiColor: .separator).opacity(0.5)))
        .overlay(alignment: .leading) { if targetPosition == index { Rectangle().fill(Palette.accent).frame(width: 4) } }
        .overlay(alignment: .trailing) { if targetPosition == index + 1 { Rectangle().fill(Palette.accent).frame(width: 4) } }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText], delegate: SequenceDropDelegate(audio: audio, index: index, width: width, targetPosition: $targetPosition))
    }
}

private struct SequenceDropDelegate: DropDelegate {
    let audio: AudioModel
    let index: Int
    let width: CGFloat
    @Binding var targetPosition: Int?
    private func position(_ info: DropInfo) -> Int {
        let edge = min(24, width / 3)
        if info.location.x < edge { return index }
        if info.location.x > width - edge { return index + 1 }
        return -1
    }
    func dropEntered(info: DropInfo) { targetPosition = position(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { targetPosition = position(info); return DropProposal(operation: .copy) }
    func dropExited(info: DropInfo) { targetPosition = nil }
    func performDrop(info: DropInfo) -> Bool {
        let destination = position(info); targetPosition = nil
        return receiveSample(info.itemProviders(for: [UTType.plainText]), audio: audio,
                             index: destination < 0 ? index : destination, layer: destination < 0)
    }
}

private struct ClipRow: View {
    @ObservedObject var audio: AudioModel
    let clip: ArrangementClip
    let sample: LoopSample
    let song: Song
    let active: Bool
    let progress: Double
    let stepBeats: Int
    let stepNumber: Int
    @Binding var tray: Int
    var body: some View {
        HStack(spacing: 0) {
            Button { audio.selectedClipID = clip.id; tray = 1 } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(sample.label) · \(song.name)").font(.caption.weight(.semibold)).lineLimit(1)
                    ClipWaveform(sample: sample, mask: clip.mask, active: active, repeatInBeats: stepBeats).frame(maxHeight: .infinity)
                }.padding(6).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Edit \(song.name), loop \(sample.label), step \(stepNumber)")
            .accessibilityValue(active ? "Playing" : "Ready").accessibilityIdentifier("clip_\(clip.id)")
            Button { audio.removeClip(clip.id) } label: { Image(systemName: "xmark").font(.caption).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Remove \(song.name), loop \(sample.label)")
                .accessibilityIdentifier("removeClip_\(clip.id)")
        }
        .foregroundStyle(active ? Color.white : Color(uiColor: .label))
        .background(RoundedRectangle(cornerRadius: 4).fill(active ? Color(uiColor: Palette.playing) : Palette.accent.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(clip.id == audio.selectedClipID ? (active ? Color.white : Palette.accent) : Color(uiColor: .separator).opacity(0.5), lineWidth: clip.id == audio.selectedClipID ? 2 : 1))
        .overlay {
            if active { GeometryReader { geometry in Rectangle().fill(Color.white).frame(width: 2).offset(x: geometry.size.width * min(1, max(0, progress))) }.allowsHitTesting(false) }
        }
    }
}

private struct ClipWaveform: View {
    let sample: LoopSample
    let mask: Int
    let active: Bool
    var original = false
    var repeatInBeats: Int? = nil
    var body: some View {
        Canvas { context, size in
            let lanes = original ? [sample.waveform] : (sample.parts?.waveforms ?? [sample.waveform])
            for (index, values) in lanes.enumerated() where values.count > 1 {
                let laneHeight = size.height / CGFloat(lanes.count), middle = (CGFloat(index) + 0.5) * laneHeight
                var path = Path()
                let repeats = max(1, CGFloat(repeatInBeats ?? sample.beats) / CGFloat(sample.beats))
                let unitWidth = size.width / repeats
                for repeatIndex in 0..<Int(ceil(repeats)) {
                    for (i, value) in values.enumerated() {
                        let x = (CGFloat(repeatIndex) + CGFloat(i) / CGFloat(values.count - 1)) * unitWidth
                        let point = CGPoint(x: x, y: middle - CGFloat(value) * laneHeight * 0.45)
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    for i in values.indices.reversed() {
                        let x = (CGFloat(repeatIndex) + CGFloat(i) / CGFloat(values.count - 1)) * unitWidth
                        path.addLine(to: CGPoint(x: x, y: middle + CGFloat(values[i]) * laneHeight * 0.45))
                    }
                    path.closeSubpath()
                }
                let on = lanes.count == 1 || mask & (1 << index) != 0
                context.fill(path, with: .color((active ? Color.white : Color.secondary).opacity(on ? 0.9 : 0.16)))
            }
        }.accessibilityHidden(true)
    }
}

private struct SoundTray: View {
    @ObservedObject var audio: AudioModel
    @Binding var tray: Int
    private var slider: Binding<Double> {
        Binding(get: { log((audio.selectedClip?.filterCutoff ?? 1200) / 40) / log(18000 / 40) },
                set: { audio.setClipFilter(type: audio.selectedClip?.filterType ?? 0, cutoff: 40 * pow(18000 / 40, $0)) })
    }
    private var cutoffLabel: String {
        let hz = audio.selectedClip?.filterCutoff ?? 1200
        return hz >= 1000 ? String(format: "%.1f kHz", hz / 1000) : "\(Int(hz.rounded())) Hz"
    }
    private var masterSlider: Binding<Double> {
        Binding(get: { log(audio.filterCutoff / 40) / log(18000 / 40) },
                set: { audio.setFilter(type: audio.filterType, cutoff: 40 * pow(18000 / 40, $0)) })
    }
    private var masterCutoffLabel: String {
        let hz = audio.filterCutoff
        return hz >= 1000 ? String(format: "%.1f kHz", hz / 1000) : "\(Int(hz.rounded())) Hz"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sound").font(.headline)
                    Spacer()
                    Button { tray = 0 } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close sound controls")
                }
                Text("Parts").font(.subheadline.weight(.semibold))
                if let song = audio.selectedClipSong, let sample = audio.selectedSample, let clip = audio.selectedClip {
                    Text("\(song.name) · \(sample.label) · approximate layers may overlap.")
                        .font(.caption).foregroundStyle(Palette.secondary).lineLimit(2)
                    HStack {
                        Button("All off") { audio.setPartsMask(0) }
                        Spacer()
                        Button("All on") { audio.setPartsMask(15) }
                    }.font(.caption).frame(minHeight: 36)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                      ForEach(Array((song.partLabels ?? []).enumerated()), id: \.offset) { index, label in
                        let isOn = clip.mask & (1 << index) != 0
                        Button { audio.togglePart(index) } label: {
                            HStack(spacing: 3) { Text(label).lineLimit(1); Spacer(minLength: 0); Text(isOn ? "ON" : "OFF").font(.caption2.weight(.semibold)) }
                                .font(.caption).padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(Palette.accent)
                                .background(Capsule().fill(isOn ? Palette.accent.opacity(0.18) : Color.clear))
                                .overlay(Capsule().strokeBorder(Palette.accent, lineWidth: isOn ? 0 : 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(isOn ? "On" : "Off")
                        .accessibilityIdentifier("part_\(index)")
                      }
                    }
                    if let status = audio.partStatus {
                        Text(status).font(.caption).foregroundStyle(Palette.secondary).accessibilityIdentifier("partStatus")
                        if status.hasPrefix("Parts unavailable") { Button("Retry parts") { audio.retryParts() } }
                    }
                } else {
                    Text("Tap a sample in the sequence to edit its parts.").font(.caption).foregroundStyle(Palette.secondary)
                }
                Divider().padding(.vertical, 5)
                Text("Clip filter").font(.subheadline.weight(.semibold))
                Picker("Clip filter type", selection: Binding(get: { audio.selectedClip?.filterType ?? 0 }, set: { audio.setClipFilter(type: $0, cutoff: audio.selectedClip?.filterCutoff ?? 1200) })) {
                    Text("Off").tag(0); Text("LPF").tag(1); Text("BPF").tag(2); Text("HPF").tag(3)
                }.pickerStyle(.segmented).disabled(audio.selectedClip == nil).accessibilityIdentifier("filterMode")
                HStack { Text("Cutoff"); Spacer(); Text(cutoffLabel).monospacedDigit() }.font(.subheadline)
                Slider(value: slider, in: 0...1).disabled(audio.selectedClip == nil).accessibilityLabel("Clip filter cutoff").accessibilityValue(cutoffLabel).accessibilityIdentifier("filterCutoff")
                Divider().padding(.vertical, 5)
                Text("Master filter").font(.subheadline.weight(.semibold))
                Picker("Master filter type", selection: Binding(get: { audio.filterType }, set: { audio.setFilter(type: $0, cutoff: audio.filterCutoff) })) {
                    Text("Off").tag(0); Text("LPF").tag(1); Text("BPF").tag(2); Text("HPF").tag(3)
                }.pickerStyle(.segmented).accessibilityIdentifier("masterFilterMode")
                HStack { Text("Cutoff"); Spacer(); Text(masterCutoffLabel).monospacedDigit() }.font(.subheadline)
                Slider(value: masterSlider, in: 0...1).accessibilityLabel("Master filter cutoff").accessibilityValue(masterCutoffLabel)
            }.padding(.horizontal, 14).padding(.bottom, 12)
        }.accessibilityIdentifier("soundTray")
    }
}
