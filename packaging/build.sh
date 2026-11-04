#!/bin/bash
# Baut die Testerpakete: dist/Motorsound-mac.zip (Apple Silicon + Intel) und dist/Motorsound-windows.zip.
# Nimmt immer den aktuellen Stand aus ../motorsound. Braucht nur bash, curl, tar, unzip, zip (macOS hat alles).
#   ./build.sh            beide Pakete
#   NODE_VERSION=v24.22.2 ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
NODE_VERSION="${NODE_VERSION:-v24.22.2}"
SRC="${SRC:-../motorsound}"
OUT="${OUT:-../dist}"
CACHE="${CACHE:-.cache}"
mkdir -p "$CACHE" "$OUT"; OUT=$(cd "$OUT" && pwd)

fetch() { [ -f "$CACHE/$1" ] || curl -fL --retry 3 -o "$CACHE/$1" "https://nodejs.org/dist/$NODE_VERSION/$1"; }
fetch SHASUMS256.txt
for f in node-$NODE_VERSION-darwin-arm64.tar.gz node-$NODE_VERSION-darwin-x64.tar.gz node-$NODE_VERSION-win-x64.zip; do
  fetch "$f"
  want=$(grep " $f\$" "$CACHE/SHASUMS256.txt" | cut -d' ' -f1)
  got=$( (sha256sum "$CACHE/$f" 2>/dev/null || shasum -a 256 "$CACHE/$f") | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "Prüfsumme falsch: $f"; exit 1; }
done

app() { # $1 = Zielordner
  mkdir -p "$1/app/bridge"
  cp "$SRC/index.html" "$1/app/"
  cp "$SRC"/bridge/*.mjs "$1/app/bridge/"
  cp launcher/start.mjs demo-fahrt.log "$1/app/"
  cp launcher/LIESMICH.txt "$1/"
  chmod -R u+w,a+r "$1"
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---- macOS ----
M="$TMP/Motorsound-mac"; app "$M"; mkdir -p "$M/runtime"
for a in arm64 x64; do
  tar -xzf "$CACHE/node-$NODE_VERSION-darwin-$a.tar.gz" -C "$TMP" "node-$NODE_VERSION-darwin-$a/bin/node" "node-$NODE_VERSION-darwin-$a/LICENSE"
  mv "$TMP/node-$NODE_VERSION-darwin-$a/bin/node" "$M/runtime/node-$a"   # Original, von der Node.js Foundation signiert + notarisiert
  cp "$TMP/node-$NODE_VERSION-darwin-$a/LICENSE" "$M/runtime/NODE-LICENSE.txt"
done
cp launcher/*.command "$M/"
chmod +x "$M"/*.command "$M"/runtime/node-*
rm -f "$OUT/Motorsound-mac.zip"; (cd "$TMP" && zip -qry "$OUT/Motorsound-mac.zip" Motorsound-mac)

# ---- Windows ----
W="$TMP/Motorsound-windows"; app "$W"; mkdir -p "$W/runtime"
unzip -q -j "$CACHE/node-$NODE_VERSION-win-x64.zip" "node-$NODE_VERSION-win-x64/node.exe" "node-$NODE_VERSION-win-x64/LICENSE" -d "$W/runtime"
mv "$W/runtime/LICENSE" "$W/runtime/NODE-LICENSE.txt"
cp launcher/*.bat "$W/"
sed -i.bak 's/$/\r/' "$W/LIESMICH.txt" && rm -f "$W/LIESMICH.txt.bak"
rm -f "$OUT/Motorsound-windows.zip"; (cd "$TMP" && zip -qr "$OUT/Motorsound-windows.zip" Motorsound-windows)

ls -lh "$OUT"/Motorsound-*.zip
