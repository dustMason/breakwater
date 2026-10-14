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
                    LabeledContent("Status") { Text(audio.state.clockLabel.capitalized).foregroundStyle(Palette.secondary) }
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
                Section("Pads") {
                    Text("Tap a pad to launch it on the next bar. Hold one pad and touch more to build a cycle in that order; release to keep it cycling. Dragging across pads also builds a cycle. Each loop plays its full length until your next selection.")
                    Text("Edit pads excludes unwanted loops and saves your choices. Change songs without interrupting playback.")
                    Button("Restore all pads in this song") { audio.enableSong() }.accessibilityIdentifier("restorePads")
                }
                Section("MIDI pads") { Text("Notes 36–65 trigger pads 01–30 in the selected song, on any MIDI channel. Hold notes together to latch a cycle. A new touch or note gesture replaces the cycle.") }
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
                    if audio.external { LabeledContent("Incoming tempo", value: String(format: "%.1f BPM", audio.state.bpm)) }
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
                } footer: { Text("Tempo changes glide into place while the loop stays on the beat.").foregroundStyle(Palette.secondary) }
            }
            .navigationTitle("Tempo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
