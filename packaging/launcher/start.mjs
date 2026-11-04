// Startet die Commander-Bridge mit dem mitgelieferten Node und öffnet danach den Browser.
//   start.mjs            live vom S3XY Commander
//   start.mjs --demo     Aufnahme abspielen (ohne Auto)
import { spawn } from "node:child_process";
import path from "node:path";
import net from "node:net";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const demo = args.includes("--demo");
const rest = args.filter((a) => a !== "--demo");
const portArg = rest.indexOf("--http");
const port = portArg >= 0 ? +rest[portArg + 1] : 8787;
const url = `http://localhost:${port}`;

console.log("==============================================");
console.log("  Motorsound " + (demo ? "(Demo mit Aufnahme)" : "(live vom S3XY Commander)"));
console.log("  Browser: " + url);
console.log("  Beenden: dieses Fenster schließen oder Strg+C");
console.log("==============================================\n");

// Läuft schon eine Bridge? Dann nur den Browser öffnen.
const probe = net.connect(port, "127.0.0.1");
probe.on("connect", () => { probe.end(); console.log("Bridge läuft bereits, öffne nur den Browser."); openBrowser(); setTimeout(() => process.exit(0), 1500); });
probe.on("error", async () => {
  process.argv = [process.argv[0], "commander-bridge.mjs", ...(demo ? ["--replay", path.join(here, "demo-fahrt.log")] : []), ...rest];
  await import(pathToFileURL(path.join(here, "bridge", "commander-bridge.mjs")).href);
  setTimeout(openBrowser, 800);
});

function openBrowser() {
  if (process.env.MOTORSOUND_NO_BROWSER) return;
  const [cmd, a] = process.platform === "darwin" ? ["open", [url]]
    : process.platform === "win32" ? ["cmd", ["/c", "start", "", url]]
    : ["xdg-open", [url]];
  try { spawn(cmd, a, { stdio: "ignore", detached: true }).unref(); } catch { console.log("Bitte im Browser öffnen: " + url); }
}
