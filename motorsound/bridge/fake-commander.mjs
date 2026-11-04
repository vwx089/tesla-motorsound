#!/usr/bin/env node
// Simulierter S3XY Commander zum Testen ohne Auto: spricht Panda-UDP auf Port 1338,
// beantwortet "hello" und sendet eine Testfahrt als Tesla-CAN-Frames (50 Hz).
//
//   Terminal 1: node fake-commander.mjs
//   Terminal 2: node commander-bridge.mjs --host 127.0.0.1
import dgram from "node:dgram";

const PORT = +(process.argv[process.argv.indexOf("--port") + 1] || 0) || 1338;
const sock = dgram.createSocket("udp4");
const subs = new Map(); // "ip:port" -> letzter hello-Zeitpunkt

function putSig(b, start, len, signed, scale, offset, value) {
  let raw = Math.round((value - offset) / scale); if (signed && raw < 0) raw += 2 ** len;
  for (let i = 0; i < len; i++) { const bit = start + i; if (Math.floor(raw / 2 ** i) % 2) b[bit >> 3] |= 1 << (bit & 7); }
}
function frame(id, bus, data) {
  const f = Buffer.alloc(16);
  f.writeUInt32LE((id << 21) >>> 0, 0);
  f.writeUInt32LE((bus << 4) | data.length, 4);
  data.copy(f, 8);
  return f;
}

let v = 0, t = 0;
const pedalAt = (t) => { t %= 30; return t < 2 ? 0 : t < 9 ? 1 : t < 12 ? 0 : t < 18 ? 0.3 : t < 21 ? 0.9 : 0; };
setInterval(() => {
  t += 0.02;
  const pedal = pedalAt(t);
  const F = pedal * Math.min(11000, 340000 / Math.max(v, 1));
  const regen = pedal < 0.05 && v > 0.5 ? Math.min(4500, 60000 / Math.max(v, 3)) : 0;
  const brake = t % 30 > 24 ? 6000 : 0;
  v = Math.max(0, v + (F - regen - brake - 0.6 * v * v - 180) / 2000 * 0.02);
  const tq = (F - regen) * 0.35;
  const d257 = Buffer.alloc(8); putSig(d257, 12, 12, false, 0.08, -40, v * 3.6);
  const d118 = Buffer.alloc(8); putSig(d118, 32, 8, false, 0.4, 0, pedal * 100); putSig(d118, 21, 3, false, 1, 0, 4);
  const d108 = Buffer.alloc(8); putSig(d108, 27, 13, true, 2, 0, tq * 0.6);
  const d186 = Buffer.alloc(8); putSig(d186, 27, 13, true, 2, 0, tq * 0.4);
  const d132 = Buffer.alloc(8); putSig(d132, 0, 16, false, 0.01, 0, 360); putSig(d132, 16, 16, true, -0.1, 0, (F - regen) * v / 360);
  const noise = Buffer.from([1, 2, 3, 4, 5, 6, 7, 8]);
  const pkt = Buffer.concat([frame(0x257, 0, d257), frame(0x118, 0, d118), frame(0x108, 0, d108), frame(0x186, 0, d186), frame(0x132, 0, d132), frame(0x3e2, 0, noise)]);
  const now = Date.now();
  for (const [k, last] of subs) {
    if (now - last > 10000) { subs.delete(k); console.log("Timeout", k); continue; }
    const [ip, port] = k.split(":"); sock.send(pkt, +port, ip);
  }
}, 20);

sock.on("message", (msg, r) => {
  const k = r.address + ":" + r.port, s = msg.toString();
  if (s === "hello" || s === "ehllo") { if (!subs.has(k)) console.log("hello von", k); subs.set(k, Date.now()); }
  if (s === "bye") { subs.delete(k); console.log("bye von", k); }
});
sock.bind(PORT, () => console.log(`Fake-Commander auf UDP ${PORT}`));
