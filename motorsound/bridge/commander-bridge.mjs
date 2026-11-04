#!/usr/bin/env node
// Commander-Bridge: holt CAN-Frames vom S3XY Commander (Panda-UDP-Protokoll, wie ScanMyTesla/TesLax)
// und reicht sie per Server-Sent Events an die Browser-App weiter. Keine Abhängigkeiten, Node 18+.
//
//   node commander-bridge.mjs                       live vom Commander (192.168.4.1:1338)
//   node commander-bridge.mjs --record fahrt.log    zusätzlich alles mitschneiden
//   node commander-bridge.mjs --stats               zeigt, welche CAN-IDs ankommen
//   node commander-bridge.mjs --replay fahrt.log    Aufnahme statt Auto abspielen
//
// Danach im Browser http://localhost:8787 öffnen und „Live (Bridge)“ wählen.

import dgram from "node:dgram";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf("--" + name); return i < 0 ? def : (args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : true); };
const HOST = opt("host", "192.168.4.1");
const PORT = +opt("port", 1338);
const HELLO = String(opt("hello", "ehllo"));      // S3XY Commander antwortet nur auf "ehllo" (Panda v2), getestet 4.11.2026
const LOCAL_PORT = +opt("local-port", 0);       // 0 = beliebig. Falls der Commander nur an 1338 zurücksendet: --local-port 1338
const HTTP_PORT = +opt("http", 8787);
const RECORD = opt("record", null);
const REPLAY = opt("replay", null);
const STATS = !!opt("stats", false);
const ALL = !!opt("all", false);                // alle IDs an den Browser, sonst nur die Motorsound-Signale
const WANTED = new Set([0x257, 0x118, 0x108, 0x186, 0x132]);

const here = path.dirname(fileURLToPath(import.meta.url));
const recStream = RECORD ? fs.createWriteStream(RECORD, { flags: "a" }) : null;
const t0 = Date.now();
const counts = new Map();
let pending = [];
const clients = new Set();

function onFrame(id, bus, data) {
  const key = bus + ":" + id.toString(16);
  counts.set(key, (counts.get(key) || 0) + 1);
  const hex = data.toString("hex");
  if (recStream) recStream.write(`${Date.now() - t0} ${bus} ${id.toString(16)} ${hex}\n`);
  if (ALL || WANTED.has(id)) pending.push([id, bus, hex]);
}

// ---------- Panda-UDP: 16 Byte pro Frame ----------
// Byte 0-3 (LE): bit 31..21 = 11-Bit-ID (bit 2 gesetzt = erweiterte 29-Bit-ID in bit 31..3)
// Byte 4-7 (LE): bit 3..0 = Länge, bit 11..4 = Bus (CANServer meldet Bus 15 für eigene Daten)
// Byte 8-15: Nutzdaten
export function parsePanda(buf, cb) {
  for (let o = 0; o + 16 <= buf.length; o += 16) {
    const h1 = buf.readUInt32LE(o), h2 = buf.readUInt32LE(o + 4);
    const ext = (h1 & 4) !== 0;
    const id = ext ? h1 >>> 3 : h1 >>> 21;
    const len = h2 & 0x0f, bus = (h2 >>> 4) & 0xff;
    cb(id, bus, buf.subarray(o + 8, o + 8 + Math.min(len, 8)));
  }
}

function startUdp() {
  const sock = dgram.createSocket("udp4");
  let rx = 0, lastRx = 0;
  sock.on("message", (msg, r) => { if (!rx) console.log(`Erste Daten von ${r.address}:${r.port} (${msg.length} Bytes)`); rx++; lastRx = Date.now(); parsePanda(msg, onFrame); });
  sock.on("error", (e) => console.error("UDP-Fehler:", e.message));
  const hello = () => sock.send(Buffer.from(HELLO), PORT, HOST, (e) => e && console.error("hello fehlgeschlagen:", e.message));
  sock.bind(LOCAL_PORT, () => {
    console.log(`UDP: lokal Port ${sock.address().port}, sende "${HELLO}" an ${HOST}:${PORT} alle 3,5 s`);
    hello();
    setInterval(hello, 3500);
    setInterval(() => { if (!lastRx || Date.now() - lastRx > 5000) console.log(`… keine Daten von ${HOST}:${PORT}. Im WLAN S3XY_OBD? ScanMyTesla-Unterstützung in der S3XY-App aktiviert?`); }, 5000);
  });
  const bye = () => { sock.send(Buffer.from("bye"), PORT, HOST, () => process.exit(0)); setTimeout(() => process.exit(0), 300); };
  process.on("SIGINT", bye); process.on("SIGTERM", bye);
}

function startReplay(file) {
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/).filter(Boolean);
  const frames = [];
  for (const l of lines) {
    let m = l.match(/^\s*(\d+(?:\.\d+)?)\s+(\d+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]*)/);
    if (m) { frames.push([+m[1], +m[2], parseInt(m[3], 16), Buffer.from(m[4], "hex")]); continue; }
    m = l.match(/^\s*\((\d+(?:\.\d+)?)\)\s+\S+\s+([0-9a-fA-F]+)#([0-9a-fA-F]*)/);
    if (m) frames.push([+m[1] * 1000, 0, parseInt(m[2], 16), Buffer.from(m[3], "hex")]);
  }
  if (!frames.length) { console.error("Keine Frames in", file); process.exit(1); }
  const first = frames[0][0];
  console.log(`Replay: ${frames.length} Frames aus ${file}, läuft in Schleife`);
  let i = 0, start = Date.now();
  setInterval(() => {
    const t = Date.now() - start;
    while (i < frames.length && frames[i][0] - first <= t) { const f = frames[i++]; onFrame(f[2], f[1], f[3]); }
    if (i >= frames.length) { i = 0; start = Date.now(); }
  }, 5);
}

// ---------- HTTP: App ausliefern + SSE-Stream ----------
function serveApp(res) {
  const file = path.join(here, "..", "index.html");
  fs.readFile(file, "utf8", (err, body) => {
    if (err) { res.writeHead(404); res.end("index.html nicht gefunden neben dem bridge-Ordner"); return; }
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(`<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>${body}</body></html>`);
  });
}
const server = http.createServer((req, res) => {
  const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Private-Network": "true" };
  if (req.method === "OPTIONS") { res.writeHead(204, { ...cors, "Access-Control-Allow-Headers": "*" }); res.end(); return; }
  const url = new URL(req.url, "http://x");
  if (url.pathname === "/stream") {
    res.writeHead(200, { ...cors, "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
    res.write("retry: 1000\n\n");
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }
  if (url.pathname === "/" || url.pathname === "/index.html") return serveApp(res);
  res.writeHead(404, cors); res.end();
});
setInterval(() => {
  if (!pending.length) return;
  const msg = "data: " + JSON.stringify(pending) + "\n\n";
  pending = [];
  for (const c of clients) c.write(msg);
}, 20);
setInterval(() => { for (const c of clients) c.write(": ping\n\n"); }, 15000);

if (STATS) setInterval(() => {
  const rows = [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 40);
  console.log(`\nCAN-IDs der letzten 5 s (bus:id → Frames):`);
  console.log(rows.map(([k, n]) => `${k.padEnd(8)} ${String(n).padStart(5)}`).join("\n") || "(nichts)");
  counts.clear();
}, 5000);

server.listen(HTTP_PORT, () => console.log(`App: http://localhost:${HTTP_PORT}   Stream: http://localhost:${HTTP_PORT}/stream`));
if (REPLAY) startReplay(REPLAY); else startUdp();
if (RECORD) console.log("Aufnahme läuft nach", RECORD);
