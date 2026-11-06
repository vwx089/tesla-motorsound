import SwiftUI
import AVFoundation

@main
struct MotorsoundApp: App {
    init() {
        // Ton auch bei Stummschalter und im Hintergrund, mischt sich nicht mit anderer Musik.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var bridge = Bridge()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        WebView(url: URL(string: "http://localhost:\(Bridge.httpPort)/")!)
            .ignoresSafeArea()
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onChange(of: phase) { _, p in if p == .active { bridge.wake() } }
        .onAppear {
            bridge.start()
            UIApplication.shared.isIdleTimerDisabled = true   // Display bleibt an, solange die App vorne ist
        }
    }
}
