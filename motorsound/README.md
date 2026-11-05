# Verbrenner-Klang für Tesla

Synthetischer Verbrennermotor-Sound aus echten Fahrzeugdaten (Gaspedal, Drehmoment, Geschwindigkeit, Fahrstufe) statt aus GPS. Stand: Prototyp, 4. November 2026.

## Kernbefund: Der Commander ist gar nicht so proprietär

Der S3XY Commander (Enhance Auto) hat einen eingebauten **ScanMyTesla-/Panda-Modus**. Laut Enhance-Auto-Anleitung „ScanMyTesla and other apps“:

- In der S3XY-App die **ScanMyTesla-Unterstützung aktivieren**.
- Der Commander macht dann ein WLAN **`S3XY_OBD`** auf (Passwort laut Anleitung `12345678`).
- Er ist unter **`192.168.4.1`** erreichbar, TesLax nutzt **UDP-Port 1338** im Modus „Panda“.
- Nur **ein** Gerät gleichzeitig verbinden, VPN aus.

„Panda“ ist das offene Protokoll von comma.ai, das auch der CANServer nutzt. Es ist in SavvyCAN (`connections/canserver.cpp`) nachvollziehbar implementiert:

- Client schickt `ehllo` (Panda v2; der S3XY Commander reagiert nicht auf das ältere `hello`, getestet am 4.11.2026) per UDP an Port 1338, wiederholt alle ~3,5 s als Heartbeat, `bye` zum Abmelden.
- Der Server antwortet mit Datagrammen aus 16-Byte-Blöcken, ein Block pro CAN-Frame:
  - Byte 0–3 (Little Endian): Bits 31..21 = 11-Bit-CAN-ID
  - Byte 4–7 (Little Endian): Bits 3..0 = Länge, Bits ab 4 = Bus-Nummer
  - Byte 8–15: Nutzdaten

Die App bekommt also **rohe Tesla-CAN-Frames**, nicht nur fertige OBD-Werte. Die Bedeutung der Frames ist durch die Community-DBC gut dokumentiert ([joshwardell/model3dbc](https://github.com/joshwardell/model3dbc), auch in [commaai/opendbc](https://github.com/commaai/opendbc)).

Noch offen und nur im Auto prüfbar: welche IDs der Commander tatsächlich weiterreicht (alle oder gefiltert), ob er an den Absender-Port oder fest an 1338 zurücksendet, und die Update-Raten.

## Die verwendeten Signale (Model 3/Y, Vehicle-Bus)

| CAN-ID | Signal | Bits | Skalierung | Wofür |
|---|---|---|---|---|
| 0x257 | DI_vehicleSpeed | 12\|12 | ×0,08 − 40 km/h | Drehzahl über virtuelles Getriebe |
| 0x118 | DI_accelPedalPos | 32\|8 | ×0,4 % | Motorlast, sofortige Reaktion |
| 0x118 | DI_gear | 21\|3 | 1=P 2=R 3=N 4=D | Leerlauf, freies Hochdrehen |
| 0x118 | DI_brakePedalState | 19\|2 | 0/1 | |
| 0x108 | DIR_torqueActual | 27\|13 signed | ×2 Nm | Last, Rekuperation → Schubknallen |
| 0x186 | DIF_torqueActual | 27\|13 signed | ×2 Nm | Frontmotor (Dual Motor) |

Alle Intel/Little-Endian. Das Gaspedal ist der wichtigste Vorteil gegenüber GPS: Der Klang reagiert, bevor das Auto überhaupt beschleunigt.

## Was im Ordner liegt

- `index.html`: die App. Sound-Engine, virtuelles Getriebe, Tesla-CAN-Dekoder, Drehzahlmesser. Drei Datenquellen: Simulation (Gas/Bremse per Knopf oder Tastatur), Live über die Bridge, Abspielen einer Aufnahme.
- `bridge/commander-bridge.mjs`: kleines Node-Programm ohne Abhängigkeiten. Spricht Panda-UDP mit dem Commander, reicht die Frames per Server-Sent Events an den Browser und kann alles mitschneiden. Nötig, weil ein Browser kein UDP kann.
- `bridge/fake-commander.mjs`: simulierter Commander zum Testen ohne Auto.

### Wie der Sound entsteht

Keine Samples, alles wird in Echtzeit im AudioWorklet erzeugt:

1. Jeder Zylinder zündet zu seinem Zeitpunkt im 720°-Arbeitsspiel und erzeugt einen Druckpuls. Stärke und Rauschanteil hängen von der Last ab.
2. Die Pulse laufen je Zylinderbank durch ein simuliertes Abgasrohr (Verzögerungsleitung mit Rückkopplung). Beim Crossplane-V8 feuern die Bänke ungleichmäßig, daraus entsteht das typische Blubbern. Beim Boxer machen das die ungleich langen Krümmer.
3. Ein lastabhängiger Tiefpass als Schalldämpfer, Ansaugrauschen bei offener Drossel, leichte Sättigung.
4. Schubbetrieb nach Gaswegnehmen (stärker bei Rekuperation) erzeugt Knallen und Knistern, Hochschalten kurze Zündunterbrechung, Begrenzer an der Abregeldrehzahl.

Motoren: V8 Crossplane, V10 Biturbo (RS6 C6), Boxer-Sechszylinder 4.0 Sauger mit 7-Gang-PDK (911 GT3 RS 992), V8 Flatplane, Reihensechser, Boxer-Vierzylinder, V10. Getriebe: 7 Gänge, Schaltpunkte abhängig von Pedalstellung und Modus (Komfort, Sport, Rennstrecke), Kickdown, Wandlerschlupf beim Anfahren.

## Ausprobieren

**Ohne Auto, nur Browser:** veröffentlichte Seite öffnen, „Motor starten“, dann Gas halten oder „Demofahrt“.

**Mit simuliertem Commander (Laptop, Node 18+):**

```
cd bridge
node fake-commander.mjs                    # Terminal 1
node commander-bridge.mjs --host 127.0.0.1 # Terminal 2
```

Dann http://localhost:8787 öffnen, „Live (Bridge)“, „Verbinden“.

## Erste Messung im Auto (der wichtigste nächste Schritt)

Mit einem Laptop (oder Android-Handy mit Termux und Node):

1. In der S3XY-App die ScanMyTesla-Unterstützung einschalten.
2. Laptop mit WLAN `S3XY_OBD` verbinden. ScanMyTesla/TesLax auf dem Handy vorher trennen, nur ein Gerät gleichzeitig.
3. `node commander-bridge.mjs --stats --record fahrt1.log`
4. Im Terminal erscheint alle 5 s, welche CAN-IDs ankommen. Wichtig sind 257, 118, 108 (und 186 bei Dual Motor).
5. Eine kurze Runde fahren: Stand mit Gas in P, normal anfahren, einmal kräftig beschleunigen, Gas weg und rekuperieren.
6. `fahrt1.log` in den Projektordner legen. Die App spielt sie unter „Aufnahme“ ab, und ich kann die Signale damit prüfen und das Getriebe abstimmen.

Falls keine Daten kommen: `--local-port 1338` probieren (manche Panda-Server senden fest an Port 1338 zurück), und prüfen, ob die S3XY-App dabei getrennt sein muss.

## Ins Auto bringen (später)

Eine veröffentlichte Webseite darf keine Verbindung zu lokalen Adressen aufbauen, und ein Browser kann kein UDP. Live braucht deshalb immer ein Gerät, das gleichzeitig im Commander-WLAN hängt und die Daten weiterreicht. Mögliche Wege, in der Reihenfolge, wie ich sie angehen würde:

1. **Handy-App** (Android zuerst): verbindet sich mit `S3XY_OBD`, erzeugt den Sound selbst und spielt ihn über Bluetooth ins Auto. Einfachster Weg zu niedriger Latenz.
2. **ESP32 als Bridge**: hängt im Commander-WLAN und gleichzeitig im Handy-Hotspot, den auch der Tesla nutzt, und stellt den Stream für den Tesla-Browser bereit.
3. **Tesla-Browser direkt**: nur, wenn der Tesla selbst ins `S3XY_OBD`-WLAN darf und die Seite lokal geladen wird. Unsicher, muss getestet werden.

## Quellen

- Enhance Auto, ScanMyTesla and other apps: https://www.enhauto.com/blogs/all/scanmytesla-and-other-apps
- SavvyCAN, CANserver/Panda-UDP-Client: https://github.com/collin80/SavvyCAN/blob/master/connections/canserver.cpp
- Model 3/Y DBC: https://github.com/joshwardell/model3dbc
- comma.ai opendbc (tesla_model3_party.dbc): https://github.com/commaai/opendbc
