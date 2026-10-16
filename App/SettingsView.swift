import SwiftUI

struct SettingsView: View {
    @ObservedObject var audio: AudioModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Follow MIDI clock", isOn: Binding(get: { audio.external }, set: audio.setExternal)).accessibilityIdentifier("externalClock")
                    Picker("MIDI input", selection: Binding(get: { audio.midiSourceID }, set: audio.selectMIDI)) {
                        Text("First available").tag(Int32(0))
                        ForEach(audio.midiSources) { source in Text(source.name).tag(source.id) }
                        if audio.midiSourceID != 0 && !audio.midiSources.contains(where: { $0.id == audio.midiSourceID }) {
                            Text("Disconnected input").tag(audio.midiSourceID)
                        }
                    }
                    LabeledContent("Status") { LiveClockStatus(playback: audio.playback) }
                    if audio.midiSources.isEmpty { Text("Connect your USB MIDI adapter to the iPad. Connect the adapter’s receiving plug to your synth or sequencer’s MIDI OUT port.").foregroundStyle(Palette.secondary) }
                } header: { Text("Sync") } footer: {
                    Text("MIDI Start resets to the downbeat. Continue resumes; Stop silences playback. Brief clock gaps freewheel; a two-second gap stops playback. Press Start on the master to resync.").foregroundStyle(Palette.secondary)
                }
                Section {
                    HStack { Text("Timing offset"); Spacer(); Text("\(Int(audio.syncOffset)) ms").monospacedDigit() }
                    Slider(value: Binding(get: { audio.syncOffset }, set: audio.setOffset), in: -200...200, step: 1).accessibilityLabel("Timing offset")
                    Button("Reset offset") { audio.setOffset(0) }
                    Button("Align downbeat now") { audio.align() }.accessibilityIdentifier("alignDownbeat")
                } footer: { Text("Positive offset brings the loops earlier. Use a wired audio output, then adjust by ear alongside your synth.").foregroundStyle(Palette.secondary) }
                Section("Playback") {
                    Picker("Tempo matching", selection: Binding(get: { audio.mode }, set: audio.setMode)) { Text("Tape").tag(0); Text("Slice").tag(1) }
                    Text(audio.mode == 0 ? "Tape changes speed and pitch together." : "Slice keeps drum attacks at their original pitch and spaces them to the new tempo. Large slowdowns can make the tails grainy.")
                        .foregroundStyle(Palette.secondary)
                    LabeledContent("Audio output") { Text(audio.outputName).foregroundStyle(Palette.secondary) }
                }
                Section("Loops") {
                    Text("Use a loop's A or B button to add it to that side, or drag the loop onto a stack. Both sides loop together; the crossfader blends between them. New loops start on the next bar without restarting the others.")
                    Text("Each clip has its own four part switches, filter and level. The master filter is in the bottom bar.")
                    Text("Edit pads excludes unwanted loops and saves your choices. Change songs without interrupting playback.")
                    Button("Restore all pads in this song") { audio.enableSong() }.accessibilityIdentifier("restorePads")
                }
                Section("MIDI pads") { Text("Notes 36–65 add loops 01–30 from the selected song to the quieter side, on any MIDI channel. Each added loop continues after the note is released.") }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDone") } }
        }
    }
}

struct TempoView: View {
    @ObservedObject var audio: AudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var taps: [Date] = []
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Follow MIDI clock", isOn: Binding(get: { audio.external }, set: audio.setExternal))
                    if audio.external { LabeledContent("Incoming tempo") { LiveIncomingTempo(playback: audio.playback) } }
                    else {
                        Stepper(value: Binding(get: { audio.manualBPM }, set: audio.setTempo), in: 30...300, step: 1) {
                            Text("\(audio.manualBPM, specifier: "%.1f") BPM").font(.title.monospacedDigit())
                        }.accessibilityIdentifier("tempoStepper")
                        Slider(value: Binding(get: { audio.manualBPM }, set: audio.setTempo), in: 30...300, step: 0.1).accessibilityLabel("Tempo")
                        Button("Tap tempo") {
                            let now = Date()
                            if let last=taps.last, now.timeIntervalSince(last)>2 { taps=[] }
                            taps.append(now); if taps.count>6 { taps.removeFirst() }
                            if taps.count>1 { audio.setTempo(60 * Double(taps.count-1) / now.timeIntervalSince(taps[0])) }
                        }.frame(maxWidth: .infinity, minHeight: 60).font(.title2)
                    }
                } footer: {
                    Text(audio.external ? "MIDI clock controls the tempo. Turn it off to set the tempo manually." : "Tempo changes glide into place while the loop stays on the beat.")
                        .foregroundStyle(Palette.secondary)
                }
            }
            .navigationTitle("Tempo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

private struct LiveClockStatus: View {
    @ObservedObject var playback: PlaybackMonitor
    var body: some View { Text(playback.state.clockLabel.capitalized).foregroundStyle(Palette.secondary) }
}

private struct LiveIncomingTempo: View {
    @ObservedObject var playback: PlaybackMonitor
    var body: some View { Text(String(format: "%.1f BPM", playback.state.bpm)) }
}
