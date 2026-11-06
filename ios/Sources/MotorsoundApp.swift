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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Quelle", selection: $bridge.demo) {
                    Text("Live").tag(false)
                    Text("Demo").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Circle().fill(bridge.fps > 0 ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(bridge.status).font(.caption).foregroundStyle(.secondary).lineLimit(3).minimumScaleFactor(0.8)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.black)
            WebView(url: URL(string: "http://localhost:\(Bridge.httpPort)/")!)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onChange(of: phase) { _, p in if p == .active { bridge.wake() } }
        .onAppear {
            bridge.start()
            UIApplication.shared.isIdleTimerDisabled = true   // Display bleibt an, solange die App vorne ist
        }
    }
}
