import Foundation
import Network

/// Swift-Version von bridge/commander-bridge.mjs:
///  - holt CAN-Frames per Panda-UDP vom S3XY Commander (192.168.4.1:1338, Handshake "ehllo")
///  - oder spielt die mitgelieferte Aufnahme demo-fahrt.log ab
///  - liefert index.html und den SSE-Stream /stream auf http://localhost:8787 aus,
///    genau wie die Node-Bridge. Die Web-App bleibt dadurch unverändert.
final class Bridge: ObservableObject {
    static let host = "192.168.4.1"
    static let udpPort: UInt16 = 1338
    static let httpPort: UInt16 = 8787
    static let hello = "ehllo"
    static let wanted: Set<UInt32> = [0x257, 0x118, 0x108, 0x186, 0x132]

    @Published var status = "startet …"
    @Published var fps = 0
    @Published var demo = false { didSet { if demo != oldValue { let v = demo; q.async { self.restartSource(demo: v) } } } }

    private let q = DispatchQueue(label: "motorsound.bridge")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]
    private var pending: [String] = []
    private var frameCount = 0
    private var lastRx = Date.distantPast
    private var timers: [DispatchSourceTimer] = []
    private var sourceTimers: [DispatchSourceTimer] = []
    private var started = false
    private var useDemo = false

    // MARK: Start

    func start() {
        q.async {
            guard !self.started else { return }
            self.started = true
            self.startHTTP()
            self.timers.append(self.timer(every: 0.02) { self.flush() })
            self.timers.append(self.timer(every: 15) { self.broadcast(": ping\n\n") })
            self.timers.append(self.timer(every: 1) { self.tick() })
            self.restartSource(demo: false)
        }
    }

    private func timer(every s: Double, _ fn: @escaping () -> Void) -> DispatchSourceTimer {
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + s, repeating: s, leeway: .milliseconds(2))
        t.setEventHandler(handler: fn)
        t.resume()
        return t
    }

    private func setStatus(_ s: String) { DispatchQueue.main.async { self.status = s } }

    private func tick() {
        let n = frameCount; frameCount = 0
        DispatchQueue.main.async { self.fps = n }
        if useDemo { setStatus("Demo: \(n) Frames/s"); return }
        if Date().timeIntervalSince(lastRx) > 5 {
            // Diagnose für die Fehlersuche im Auto
            var msg = "Keine Daten · ehllo \(helloSent)× gesendet"
            if !helloErr.isEmpty { msg += " · Fehler: \(helloErr)" + (helloErr.contains("route") || helloErr.contains("permitted") ? " (Lokales Netzwerk erlaubt? WLAN S3XY_OBD?)" : "") }
            if rxPackets > 0 { msg += " · zuletzt von \(rxFrom)" }
            setStatus(msg)
        } else {
            setStatus("Commander \(rxFrom): \(n) Frames/s")
        }
    }

    // MARK: Datenquelle

    private func restartSource(demo: Bool) {
        sourceTimers.forEach { $0.cancel() }; sourceTimers = []
        stopUDP()
        useDemo = demo
        if useDemo { startReplay() } else { startUDP() }
    }

    private func onFrame(id: UInt32, bus: UInt32, data: Data) {
        frameCount += 1
        guard Self.wanted.contains(id) else { return }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        pending.append("[\(id),\(bus),\"\(hex)\"]")
    }

    // Panda-UDP: 16 Byte pro Frame (siehe commander-bridge.mjs)
    private func parsePanda(_ d: Data) {
        let b = [UInt8](d)
        var o = 0
        while o + 16 <= b.count {
            let h1 = UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24
            let h2 = UInt32(b[o+4]) | UInt32(b[o+5]) << 8 | UInt32(b[o+6]) << 16 | UInt32(b[o+7]) << 24
            let id = (h1 & 4) != 0 ? h1 >> 3 : h1 >> 21
            let len = Int(min(h2 & 0x0f, 8))
            let bus = (h2 >> 4) & 0xff
            onFrame(id: id, bus: bus, data: Data(b[(o+8)..<(o+8+len)]))
            o += 16
        }
    }

    // UDP wie in der Node-Bridge: unverbundener Socket, der Antworten von JEDEM Absender-Port annimmt
    // (NWConnection würde nur Pakete von genau 192.168.4.1:1338 durchlassen).
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var helloSent = 0, helloErr = "", rxPackets = 0, rxFrom = ""
    private var target = sockaddr_in()

    private func stopUDP() {
        if fd >= 0 { _ = sendRaw("bye") }
        readSource?.cancel(); readSource = nil
        fd = -1
    }

    @discardableResult
    private func sendRaw(_ text: String) -> Bool {
        guard fd >= 0 else { return false }
        let bytes = Array(text.utf8)
        var t = target
        let n = withUnsafePointer(to: &t) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if n < 0 { helloErr = String(cString: strerror(errno)); return false }
        helloErr = ""
        return true
    }

    private func startUDP() {
        helloSent = 0; helloErr = ""; rxPackets = 0; rxFrom = ""
        let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { setStatus("UDP-Socket: \(String(cString: strerror(errno)))"); return }
        // An das WLAN (en0) binden, damit iOS nicht übers Mobilnetz routet (S3XY_OBD hat kein Internet)
        var idx = if_nametoindex("en0")
        if idx != 0 { setsockopt(s, IPPROTO_IP, 25 /* IP_BOUND_IF */, &idx, socklen_t(MemoryLayout<UInt32>.size)) }
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = INADDR_ANY
        _ = withUnsafePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)

        target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = Self.udpPort.bigEndian
        inet_pton(AF_INET, Self.host, &target.sin_addr)
        fd = s

        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: q)
        var buf = [UInt8](repeating: 0, count: 65536)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            while true {
                var from = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(s, &buf, buf.count, 0, $0, &len) }
                }
                if n <= 0 { break }
                if self.rxPackets == 0 {
                    var a = from.sin_addr
                    var str = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &a, &str, socklen_t(INET_ADDRSTRLEN))
                    self.rxFrom = "\(String(cString: str)):\(UInt16(bigEndian: from.sin_port))"
                }
                self.rxPackets += 1
                self.lastRx = Date()
                self.parsePanda(Data(buf[0..<n]))
            }
        }
        src.setCancelHandler { close(s) }
        src.resume()
        readSource = src

        let hello = { [weak self] in
            guard let self else { return }
            if self.sendRaw(Self.hello) { self.helloSent += 1 }
        }
        hello()
        sourceTimers.append(timer(every: 3.5, hello))
        setStatus("Sende \"\(Self.hello)\" an \(Self.host):\(Self.udpPort) …")
    }

    private lazy var demoFrames: [(Double, UInt32, UInt32, Data)] = {
        guard let url = Bundle.main.url(forResource: "demo-fahrt", withExtension: "log"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [(Double, UInt32, UInt32, Data)] = []
        for line in text.split(separator: "\n") {
            let p = line.split(separator: " ")
            guard p.count >= 3, let t = Double(p[0]), let bus = UInt32(p[1]), let id = UInt32(p[2], radix: 16) else { continue }
            let hex = p.count > 3 ? Array(p[3].utf8) : []
            var bytes = [UInt8](); bytes.reserveCapacity(hex.count / 2)
            var i = 0
            while i + 1 < hex.count, let v = UInt8(String(decoding: hex[i...i+1], as: UTF8.self), radix: 16) { bytes.append(v); i += 2 }
            out.append((t, bus, id, Data(bytes)))
        }
        return out
    }()

    private func startReplay() {
        let frames = demoFrames
        guard let first = frames.first?.0 else { setStatus("Demo-Aufnahme fehlt"); return }
        var i = 0
        var start = Date()
        setStatus("Demo: \(frames.count) Frames")
        sourceTimers.append(timer(every: 0.005) { [weak self] in
            guard let self else { return }
            let t = Date().timeIntervalSince(start) * 1000
            while i < frames.count, frames[i].0 - first <= t {
                let f = frames[i]; i += 1
                self.onFrame(id: f.2, bus: f.1, data: f.3)
            }
            if i >= frames.count { i = 0; start = Date() }
        })
    }

    // MARK: HTTP + SSE

    private func startHTTP() {
        do {
            let l = try NWListener(using: .tcp, on: .init(rawValue: Self.httpPort)!)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] st in
                if case .failed(let e) = st { self?.setStatus("Server-Fehler: \(e.localizedDescription)") }
            }
            l.start(queue: q)
            listener = l
        } catch {
            setStatus("Server startet nicht: \(error.localizedDescription)")
        }
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: q)
        readRequest(c, buffer: Data())
    }

    private func readRequest(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
                let method = parts.first.map(String.init) ?? "GET"
                let path = parts.count > 1 ? String(parts[1].split(separator: "?").first ?? "/") : "/"
                self.handle(c, method: method, path: path)
            } else if done || err != nil || buf.count > 65536 {
                c.cancel()
            } else {
                self.readRequest(c, buffer: buf)
            }
        }
    }

    private let cors = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Private-Network: true\r\n"

    private func handle(_ c: NWConnection, method: String, path: String) {
        if method == "OPTIONS" {
            send(c, "HTTP/1.1 204 No Content\r\n\(cors)Access-Control-Allow-Headers: *\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", close: true)
        } else if path == "/stream" {
            send(c, "HTTP/1.1 200 OK\r\n\(cors)Content-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\nretry: 1000\n\n", close: false)
            let key = ObjectIdentifier(c)
            clients[key] = c
            c.stateUpdateHandler = { [weak self] st in
                switch st { case .failed, .cancelled: self?.clients[key] = nil; default: break }
            }
        } else if path == "/" || path == "/index.html" {
            let body = Data(page().utf8)
            var res = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            res.append(body)
            c.send(content: res, completion: .contentProcessed { _ in c.cancel() })
        } else {
            send(c, "HTTP/1.1 404 Not Found\r\n\(cors)Content-Length: 0\r\nConnection: close\r\n\r\n", close: true)
        }
    }

    private func send(_ c: NWConnection, _ s: String, close: Bool) {
        c.send(content: Data(s.utf8), completion: .contentProcessed { _ in if close { c.cancel() } })
    }

    private func page() -> String {
        let body = Bundle.main.url(forResource: "index", withExtension: "html")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "<p>index.html fehlt im App-Bundle</p>"
        return "<!doctype html><html lang=\"de\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\"></head><body>\(body)</body></html>"
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let msg = "data: [" + pending.joined(separator: ",") + "]\n\n"
        pending.removeAll(keepingCapacity: true)
        broadcast(msg)
    }

    private func broadcast(_ s: String) {
        guard !clients.isEmpty else { return }
        let d = Data(s.utf8)
        for (key, c) in clients {
            c.send(content: d, completion: .contentProcessed { [weak self] err in
                if err != nil { self?.q.async { self?.clients[key] = nil; c.cancel() } }
            })
        }
    }
}
