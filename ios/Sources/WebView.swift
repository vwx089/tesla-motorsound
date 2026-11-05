import SwiftUI
import WebKit

/// Zeigt die bestehende Web-App (index.html), ausgeliefert vom eingebauten Server auf localhost.
/// localhost gilt als sicherer Kontext, dadurch läuft das AudioWorklet wie im Desktop-Browser.
struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // Web Audio läuft in WKWebView sonst als "ambient" und wird vom Stummschalter stummgeschaltet.
        // Zusätzlich jeden AudioContext nach dem Erzeugen fortsetzen.
        let audioFix = """
        (function(){try{if(navigator.audioSession)navigator.audioSession.type="playback";}catch(e){}
        var AC=window.AudioContext||window.webkitAudioContext;if(!AC)return;
        var W=function(o){var c=o?new AC(o):new AC();try{if(navigator.audioSession)navigator.audioSession.type="playback";c.resume();}catch(e){}return c;};
        W.prototype=AC.prototype;window.AudioContext=W;window.webkitAudioContext=W;})();
        """
        cfg.userContentController.addUserScript(WKUserScript(source: audioFix, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }   // Safari > Entwickler > iPhone
        #endif
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        init(url: URL) { self.url = url }
        // Falls der Server beim ersten Laden noch nicht lauscht: kurz warten, neu laden.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { webView.load(URLRequest(url: self.url)) }
        }
    }
}
