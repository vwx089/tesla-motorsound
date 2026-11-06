# Motorsound für iPhone

SwiftUI-Hülle um die Web-App `../motorsound/index.html`. Die App enthält eine Swift-Version der Bridge
(`Sources/Bridge.swift`): Panda-UDP zum S3XY Commander plus HTTP/SSE-Server auf `http://localhost:8787`.
Die Web-App läuft unverändert in einem WKWebView und verbindet sich mit „Live (Bridge)“ wie gewohnt.

## Installieren mit SideStore (ohne Mac)

GitHub baut die App bei jeder Änderung an `ios/` oder `motorsound/index.html` auf `main` automatisch
(`.github/workflows/ios.yml`) und veröffentlicht sie als Release. In SideStore unter „Sources“ diese Quelle hinzufügen:

    https://github.com/vwx089/tesla-motorsound/releases/latest/download/source.json

Dann Motorsound installieren. Updates erscheinen in SideStore, sobald ein neuer Build durch ist.
Hinweis: Mit kostenlosem Apple-Account zählen SideStore selbst und jede installierte App zum Limit von 3 Apps.

## Selbst bauen (Mac mit Xcode)

    cd ios
    xcodegen generate
    open Motorsound.xcodeproj      # iPhone wählen, ▶︎

`index.html` wird bei jedem Build frisch aus `../motorsound/` ins App-Bundle kopiert.

## Benutzen

1. iPhone ins WLAN `S3XY_OBD` (Passwort 12345678). Die Meldung „Kein Internet“ ignorieren; Mobilfunk läuft weiter.
2. App öffnen, oben „Live“ (oder „Demo“ ohne Auto), beim ersten Start „Lokales Netzwerk“ erlauben.
3. In der Web-App „Motor starten“. Sobald der Commander Daten liefert, wechselt die App von selbst auf „Live (Bridge)“.
   Wer von Hand „Simulation“ wählt, bleibt dort, bis der Commander einmal weg war und wiederkommt.

Die Statuszeile oben zeigt im Live-Modus, wie oft „ehllo“ gesendet wurde, Sendefehler und den Absender der Daten.
