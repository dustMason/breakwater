import SwiftUI

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
                                compact: geometry.size.width < 720 || typeSize.isAccessibilitySize,
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
            Button("Parts") { tray = tray == 1 ? 0 : 1 }
                .buttonStyle(.bordered).tint(tray == 1 ? Palette.accent : nil)
                .frame(minHeight: 44).accessibilityIdentifier("showParts")
            Button("FX") { tray = tray == 2 ? 0 : 2 }
                .buttonStyle(.bordered).tint(tray == 2 ? Palette.accent : nil)
                .frame(minHeight: 44).accessibilityIdentifier("showFX")
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
                            editing: audio.editing, ready: audio.ready, partMask: audio.partMask(song), showParts: tray == 1,
                            queue: audio.queue, toggle: audio.toggleDisabled)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                } else {
                    ContentUnavailableView("Sample library unavailable", systemImage: "waveform", description: Text("Relaunch Breakwater to load the bundled samples."))
                }
                if tray != 0, let song {
                    Divider()
                    SoundTray(audio: audio, song: song, tray: $tray)
                        .frame(width: compact ? 180 : 220)
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
            Divider()
            if compact {
                VStack(spacing: 4) {
                    HStack { transport; Spacer(); tempo; Spacer(); clock }
                    HStack { modePicker; Spacer(); edit; settings }
                }.padding(.horizontal, 16).padding(.vertical, 6)
            } else {
                HStack(spacing: 20) {
                    transport; dockDivider; tempo; dockDivider; clock
                    Spacer(minLength: 0); modePicker.frame(maxWidth: 230)
                    dockDivider; edit; settings
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
    }
    private var transport: some View {
        Button {
            if audio.state.playing { audio.stop() }
            else if audio.state.active < 0, let first = song?.loops.first(where: { !audio.disabled.contains($0.id) }) { audio.queue([first.id]) }
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

private struct SoundTray: View {
    @ObservedObject var audio: AudioModel
    let song: Song
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
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(tray == 1 ? "Parts" : "Filter").font(.headline)
                    Spacer()
                    Button { tray = 0 } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close sound controls")
                }
                if tray == 1 {
                    Text("Approximate layers from this song. Some sounds may overlap.")
                        .font(.caption).foregroundStyle(Palette.secondary)
                    HStack {
                        Button("All off") { audio.setPartsMask(0, song: song) }
                        Spacer()
                        Button("All on") { audio.setPartsMask(15, song: song) }
                    }.font(.subheadline).frame(minHeight: 44)
                    ForEach(Array((song.partLabels ?? []).enumerated()), id: \.offset) { index, label in
                        let isOn = audio.partMask(song) & (1 << index) != 0
                        Button { audio.togglePart(index, song: song) } label: {
                            HStack { Text(label); Spacer(); Text(isOn ? "ON" : "OFF").font(.caption.weight(.semibold)) }
                                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(Palette.accent)
                                .background(Capsule().fill(isOn ? Palette.accent.opacity(0.18) : Color.clear))
                                .overlay(Capsule().strokeBorder(Palette.accent, lineWidth: isOn ? 0 : 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(isOn ? "On" : "Off")
                        .accessibilityIdentifier("part_\(index)")
                    }
                    if let status = audio.partStatus {
                        Text(status).font(.caption).foregroundStyle(Palette.secondary).accessibilityIdentifier("partStatus")
                        if status.hasPrefix("Parts unavailable") { Button("Retry parts") { audio.retryParts() } }
                    }
                } else {
                    Text("Shape the full output.").font(.caption).foregroundStyle(Palette.secondary)
                    Picker("Filter type", selection: Binding(get: { audio.filterType }, set: { audio.setFilter(type: $0, cutoff: audio.filterCutoff) })) {
                        Text("Off").tag(0); Text("LPF").tag(1); Text("BPF").tag(2); Text("HPF").tag(3)
                    }.pickerStyle(.segmented).accessibilityIdentifier("filterMode")
                    HStack { Text("Cutoff"); Spacer(); Text(cutoffLabel).monospacedDigit() }.font(.subheadline)
                    Slider(value: slider, in: 0...1).accessibilityLabel("Filter cutoff").accessibilityValue(cutoffLabel).accessibilityIdentifier("filterCutoff")
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
        }.accessibilityIdentifier("soundTray")
    }
}
