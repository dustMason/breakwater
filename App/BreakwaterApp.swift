import SwiftUI

@main
struct BreakwaterApp: App {
    @StateObject private var audio = AudioModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            GridView(audio: audio)
                .tint(Palette.accent)
                .onChange(of: audio.state.playing) { _, playing in
                    UIApplication.shared.isIdleTimerDisabled = playing
                }
                .onChange(of: scenePhase) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active && audio.state.playing
                }
        }
    }
}
