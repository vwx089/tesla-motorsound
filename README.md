# Tesla Motorsound

Synthetischer Verbrennerklang für Tesla Model 3/Y. Der Sound wird in Echtzeit aus echten Fahrzeugdaten erzeugt (Gaspedal, Drehmoment, Geschwindigkeit, Fahrstufe). Die Daten kommen per CAN vom S3XY Commander, der sie im ScanMyTesla-/Panda-Modus über WLAN bereitstellt. Stand: Prototyp, November 2026.

## Aufbau

| Ordner | Inhalt |
|---|---|
| [`motorsound/`](motorsound/) | Die App (`index.html`, Sound-Engine im AudioWorklet, virtuelles Getriebe, CAN-Dekoder) und die Bridge (`bridge/`), die Panda-UDP vom Commander per Server-Sent Events an den Browser weiterreicht. Details, Signaltabelle und Protokoll: [motorsound/README.md](motorsound/README.md) |
| [`packaging/`](packaging/) | `build.sh` baut fertige Testerpakete für macOS und Windows mit mitgeliefertem Node.js. Dazu kommen die Launcher (Doppelklick-Startdateien, `LIESMICH.txt`) und die Demo-Aufnahme `demo-fahrt.log`. |

## Schnellstart

Ohne Auto, mit simuliertem Commander (Node 18+):

```bash
cd motorsound/bridge
node fake-commander.mjs                      # Terminal 1
node commander-bridge.mjs --host 127.0.0.1   # Terminal 2
```

Mit einer Aufnahme statt Simulator:

```bash
node motorsound/bridge/commander-bridge.mjs --replay packaging/demo-fahrt.log
```

Danach http://localhost:8787 öffnen, „Motor starten“ klicken und „Live (Bridge)“ wählen.

Live im Auto: In der S3XY-App die ScanMyTesla-Unterstützung einschalten, den Laptop ins WLAN `S3XY_OBD` einbuchen und `node motorsound/bridge/commander-bridge.mjs` starten. Optional mit `--stats` (zeigt die ankommenden CAN-IDs) oder `--record fahrt.log` (Mitschnitt).

## Testerpakete bauen

```bash
./packaging/build.sh
```

Das Skript lädt Node.js von nodejs.org, prüft die Prüfsummen und legt `dist/Motorsound-mac.zip` (Apple Silicon und Intel) sowie `dist/Motorsound-windows.zip` ab. Benutzt wird immer der aktuelle Stand aus `motorsound/`. Die Anleitung für Tester steht in [packaging/launcher/LIESMICH.txt](packaging/launcher/LIESMICH.txt).

## Nicht im Repo

`dist/` (fertige ZIPs mit Node-Binaries), `packaging/.cache/` (heruntergeladene Node-Archive) und eigene Fahrtaufnahmen (`*.log`). Aufnahmen enthalten private Fahrdaten. Einzige Ausnahme ist die gekürzte Demo-Aufnahme `packaging/demo-fahrt.log`.
