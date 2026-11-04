#!/usr/bin/env node
// Diagnose: probiert nacheinander verschiedene Arten, den Commander anzusprechen,
// und meldet, welche Daten liefert.   node probe.mjs   [--host 192.168.4.1]
import dgram from "node:dgram";

const i = process.argv.indexOf("--host");
const HOST = i > 0 ? process.argv[i + 1] : "192.168.4.1";
const PORT = 1338;

const variants = [
  { name: "hello, beliebiger lokaler Port", msg: "hello", local: 0 },
  { name: "hello, lokaler Port 1338", msg: "hello", local: 1338 },
  { name: "ehllo (Panda v2), beliebiger Port", msg: "ehllo", local: 0 },
  { name: "ehllo (Panda v2), lokaler Port 1338", msg: "ehllo", local: 1338 },
];

function tryVariant(v) {
  return new Promise((resolve) => {
    const s = dgram.createSocket({ type: "udp4", reuseAddr: true });
    let packets = 0, bytes = 0, from = "", err = "";
    s.on("message", (m, r) => { packets++; bytes += m.length; from = `${r.address}:${r.port}`; });
    let bound = false;
    s.on("error", (e) => { err = e.code || e.message; if (!bound) { try { s.close(); } catch {} resolve({ packets, bytes, from, err }); } });
    s.bind(v.local, () => {
      bound = true;
      const send = () => s.send(Buffer.from(v.msg), PORT, HOST, (e) => { if (e) err = e.code || e.message; });
      send(); const t = setInterval(send, 1000);
      setTimeout(() => {
        clearInterval(t);
        s.send(Buffer.from("bye"), PORT, HOST, () => { s.close(); resolve({ packets, bytes, from, err }); });
      }, 5000);
    });
  });
}

console.log(`Teste ${HOST}:${PORT}, je Variante 5 Sekunden …\n`);
let any = false;
for (const v of variants) {
  const r = await tryVariant(v);
  const ok = r.packets > 0;
  any ||= ok;
  console.log(`${ok ? "✅" : "❌"} ${v.name.padEnd(38)} ${r.packets} Pakete, ${r.bytes} Bytes${r.from ? " von " + r.from : ""}${r.err ? "  Fehler: " + r.err : ""}`);
  await new Promise((res) => setTimeout(res, 1500));
}
if (!any) console.log(`\nKeine Variante liefert Daten. Wenn oben "EHOSTUNREACH" oder "EPERM" steht: Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk → Terminal einschalten, Terminal neu starten. Und das Handy mit TesLax vorher aus dem WLAN nehmen.`);
