import SwiftUI

@main
struct BreakwaterApp: App {
    @StateObject private var audio = AudioModel()
    var body: some Scene {
        WindowGroup {
            GridView(audio: audio)
                .tint(Palette.accent)
                .background(IdleTimerObserver(playback: audio.playback))
        }
    }
}

private struct IdleTimerObserver: View {
    @ObservedObject var playback: PlaybackMonitor
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: playback.state.playing) { _, playing in
                UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && playing
            }
            .onChange(of: scenePhase) { _, phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active && playback.state.playing
            }
    }
}
