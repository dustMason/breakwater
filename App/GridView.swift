import SwiftUI
import UniformTypeIdentifiers

struct GridView: View {
    @ObservedObject var audio: AudioModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showSettings = false
    @State private var showTempo = false
    @State private var showSongs = false
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
        .sheet(isPresented: $showSongs) {
            SongPickerView(songs: audio.songs, selectedSong: audio.selectedSong) { index in
                audio.selectedSong = index
            }
        }
        .alert("Audio needs attention", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) {
            Button("Retry audio") { audio.error = nil; audio.retryAudio() }
            Button("Dismiss", role: .cancel) { audio.error = nil }
        } message: { Text(audio.error ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { showSongs = true } label: {
                HStack(spacing: 9) {
                    Text(song?.name ?? "Breakwater").font(.title2.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.body.weight(.semibold))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Song: \(song?.name ?? "none")")
            .accessibilityIdentifier("songMenu")
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("SOURCE BPM").font(.caption2.weight(.medium)).foregroundStyle(Palette.secondary)
                Text("≈\(song?.sourceBPM ?? 0)").font(.title2.monospacedDigit()).accessibilityIdentifier("sourceBPM")
            }.accessibilityElement(children: .combine)
            Button("Use source") {
                if let song { audio.setTempo(Double(song.sourceBPM)) }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(song == nil || audio.external)
            .accessibilityIdentifier("useSourceTempo")
            .accessibilityHint(audio.external ? "Turn off Follow MIDI clock to use the source tempo." : "Set the manual tempo to this song's source tempo.")
            Button("Parts & FX") { tray = tray == 0 ? 1 : 0 }
                .buttonStyle(.bordered).tint(tray == 1 ? Palette.accent : nil)
                .frame(minHeight: 44).accessibilityIdentifier("showSound")
        }.padding(.horizontal, 18).padding(.vertical, 4)
    }
}

private struct SongPickerView: View {
    let songs: [Song]
    let selectedSong: Int
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        select(index)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.name).font(.headline)
                                Text(song.artist).font(.subheadline).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Text("≈\(song.sourceBPM) BPM").font(.subheadline.monospacedDigit()).foregroundStyle(Palette.secondary)
                            if index == selectedSong { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("song_\(song.id)")
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("songList")
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
                if let song {
                    PadGrid(samples: song.loops, state: playback.state, disabled: audio.disabled,
                            editing: audio.editing, ready: audio.ready, partMasks: audio.gridMasks, orders: audio.gridOrders,
                            queue: audio.queue, toggle: audio.toggleDisabled,
                            append: { audio.addSample($0, at: audio.arrangement.count, layer: false) },
                            layer: { id in
                                let index = audio.arrangement.firstIndex { $0.clips.contains { $0.id == audio.selectedClipID } } ?? max(0, audio.arrangement.count - 1)
                                audio.addSample(id, at: index, layer: !audio.arrangement.isEmpty)
                            })
                        .padding(.horizontal, 12).padding(.bottom, 10)
                } else {
                    ContentUnavailableView("Sample library unavailable", systemImage: "waveform", description: Text("Relaunch Breakwater to load the bundled samples."))
                }
                if tray != 0 {
                    Divider()
                    SoundTray(audio: audio, tray: $tray)
                        .frame(width: compact ? 220 : 250)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !audio.ready && audio.error == nil {
                ProgressView("Loading samples", value: audio.loadProgress)
                    .padding(.horizontal, 20).padding(.bottom, 12).accessibilityIdentifier("loading")
            }
            if audio.editing {
                Text("Tap pads to exclude or restore them. Changes are saved.")
                    .font(.callout).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 8).accessibilityIdentifier("editHint")
            }
            ArrangementTray(audio: audio, playback: playback, tray: $tray)
            Divider()
            if compact {
                VStack(spacing: 4) {
                    HStack { transport; Spacer(); tempo; Spacer(); clock }
                    HStack { modePicker; Spacer(minLength: 4); nudge; Spacer(minLength: 4); edit; settings }
                }.padding(.horizontal, 16).padding(.vertical, 6)
            } else {
                HStack(spacing: 20) {
                    transport; dockDivider; tempo; dockDivider; clock; nudge
                    Spacer(minLength: 0); modePicker.frame(maxWidth: 230)
                    dockDivider; edit; settings
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }
    private var transport: some View {
        Button {
            if audio.state.playing { audio.stop() }
            else if audio.arrangement.isEmpty, let first = song?.loops.first(where: { !audio.disabled.contains($0.id) }) { audio.queue([first.id]) }
            else { audio.play() }
        } label: {
            Label(audio.state.playing ? "Stop" : "Play", systemImage: audio.state.playing ? "stop.fill" : "play.fill")
                .font(.headline).frame(minWidth: 75, minHeight: 44)
                .foregroundStyle(audio.state.playing ? Color.red : Palette.accent)
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
    private var edit: some View {
        Button { audio.editing.toggle() } label: {
            Label(audio.editing ? "Done" : "Edit pads", systemImage: audio.editing ? "checkmark" : "pencil")
                .font(.body.weight(.medium)).frame(minHeight: 44)
        }.accessibilityIdentifier("editPads")
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
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("Sequence").font(.subheadline.weight(.semibold))
                Text(audio.arrangementStatus ?? "Drop on a step to layer · between steps to sequence")
                    .font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                Spacer(minLength: 2)
                Button("Clear") { audio.clearArrangement() }.disabled(audio.arrangement.isEmpty)
                    .font(.subheadline).frame(minHeight: 36).accessibilityIdentifier("clearArrangement")
            }.padding(.horizontal, 14)
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        if audio.arrangement.isEmpty {
                            SequenceDropGap(audio: audio, index: 0, empty: true).frame(width: max(180, geometry.size.width), height: 102)
                        } else {
                            ForEach(Array(audio.arrangement.enumerated()), id: \.element.id) { index, step in
                                SequenceDropGap(audio: audio, index: index, empty: false).frame(width: 44, height: 102)
                                SequenceCard(audio: audio, playback: playback, step: step, index: index, tray: $tray)
                                    .frame(width: 190, height: 102)
                            }
                            SequenceDropGap(audio: audio, index: audio.arrangement.count, empty: false).frame(width: 44, height: 102)
                        }
                    }.padding(.horizontal, 10)
                }.scrollIndicators(.visible)
            }.frame(height: 104)
        }
        .padding(.bottom, 5)
        .overlay(alignment: .top) { Divider() }
        .accessibilityIdentifier("arrangement")
    }
}

private struct SequenceDropGap: View {
    @ObservedObject var audio: AudioModel
    let index: Int
    let empty: Bool
    @State private var targeted = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(targeted ? Palette.accent.opacity(0.12) : Color.clear)
            RoundedRectangle(cornerRadius: 7).strokeBorder(targeted ? Palette.accent : Color(uiColor: .separator).opacity(empty ? 0.6 : 0), style: StrokeStyle(lineWidth: 1, dash: [4]))
            Text(empty ? "Drag a sample here to start" : "+")
                .font(empty ? .subheadline : .title3).foregroundStyle(targeted ? Palette.accent : Palette.secondary)
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
    @Binding var tray: Int
    @State private var targeted = false
    private var active: Bool { playback.state.playing && step.clips.contains { playback.state.activeTokens.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("STEP \(String(format: "%02d", index + 1)) · \(step.clips.count) \(step.clips.count == 1 ? "SAMPLE" : "LAYERS")")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.secondary)
            ScrollView(.vertical) {
                VStack(spacing: 3) {
                    ForEach(step.clips) { clip in
                        if let sample = audio.sample(clip.sampleID), let song = audio.songForSample(clip.sampleID) {
                            ClipRow(audio: audio, clip: clip, sample: sample, song: song,
                                    active: playback.state.playing && playback.state.activeTokens.contains(clip.id), tray: $tray)
                        }
                    }
                }
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 7).fill(targeted ? Palette.accent.opacity(0.12) : Color(uiColor: .secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(targeted || active ? Palette.accent : Color(uiColor: .separator).opacity(0.5)))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText], isTargeted: $targeted) { receiveSample($0, audio: audio, index: index, layer: true) }
        .accessibilityIdentifier("sequenceStep_\(index)")
    }
}

private struct ClipRow: View {
    @ObservedObject var audio: AudioModel
    let clip: ArrangementClip
    let sample: LoopSample
    let song: Song
    let active: Bool
    @Binding var tray: Int
    var body: some View {
        HStack(spacing: 0) {
            Button {
                audio.selectedClipID = clip.id; tray = 1
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(song.name) · \(sample.label)").font(.caption.weight(.semibold)).lineLimit(1)
                    ClipWaveform(sample: sample, mask: clip.mask, active: active).frame(height: 16)
                }
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading).padding(.leading, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Edit parts for \(song.name), loop \(sample.label)")
            .accessibilityIdentifier("clip_\(clip.id)")
            Button { audio.removeClip(clip.id) } label: { Image(systemName: "xmark").font(.caption).frame(width: 40, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Remove \(song.name), loop \(sample.label)")
                .accessibilityIdentifier("removeClip_\(clip.id)")
        }
        .foregroundStyle(active ? Color.white : Color(uiColor: .label))
        .background(RoundedRectangle(cornerRadius: 5).fill(active ? Color(uiColor: Palette.playing) : Color(uiColor: .systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(clip.id == audio.selectedClipID ? (active ? Color.white : Palette.accent) : Color(uiColor: .separator).opacity(0.5), lineWidth: clip.id == audio.selectedClipID ? 2 : 1))
    }
}

private struct ClipWaveform: View {
    let sample: LoopSample
    let mask: Int
    let active: Bool
    var body: some View {
        Canvas { context, size in
            let lanes = sample.parts?.waveforms ?? [sample.waveform]
            for (index, values) in lanes.enumerated() where values.count > 1 {
                let laneHeight = size.height / CGFloat(lanes.count), middle = (CGFloat(index) + 0.5) * laneHeight
                var path = Path()
                for (i, value) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * size.width / CGFloat(values.count - 1), y: middle - CGFloat(value) * laneHeight * 0.45)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                for i in values.indices.reversed() { path.addLine(to: CGPoint(x: CGFloat(i) * size.width / CGFloat(values.count - 1), y: middle + CGFloat(values[i]) * laneHeight * 0.45)) }
                path.closeSubpath()
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
        Binding(get: { log(audio.filterCutoff / 40) / log(18000 / 40) },
                set: { audio.setFilter(type: audio.filterType, cutoff: 40 * pow(18000 / 40, $0)) })
    }
    private var cutoffLabel: String {
        audio.filterCutoff >= 1000 ? String(format: "%.1f kHz", audio.filterCutoff / 1000) : "\(Int(audio.filterCutoff.rounded())) Hz"
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
                                .font(.caption).padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 40)
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
                    Text("Filter").font(.subheadline.weight(.semibold))
                    Text("Shape the full output.").font(.caption).foregroundStyle(Palette.secondary)
                    Picker("Filter type", selection: Binding(get: { audio.filterType }, set: { audio.setFilter(type: $0, cutoff: audio.filterCutoff) })) {
                        Text("Off").tag(0); Text("LPF").tag(1); Text("BPF").tag(2); Text("HPF").tag(3)
                    }.pickerStyle(.segmented).accessibilityIdentifier("filterMode")
                    HStack { Text("Cutoff"); Spacer(); Text(cutoffLabel).monospacedDigit() }.font(.subheadline)
                    Slider(value: slider, in: 0...1).accessibilityLabel("Filter cutoff").accessibilityValue(cutoffLabel).accessibilityIdentifier("filterCutoff")
            }.padding(.horizontal, 14).padding(.bottom, 12)
        }.accessibilityIdentifier("soundTray")
    }
}
