#!/bin/bash
cd "$(dirname "$0")" || exit 1
case "$(uname -m)" in arm64) NODE=runtime/node-arm64 ;; *) NODE=runtime/node-x64 ;; esac
"$NODE" app/start.mjs --demo "$@"
echo; read -n 1 -s -r -p "Bridge beendet. Taste drücken zum Schließen."
