#!/usr/bin/env bash
set -eo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$DIR/engine.js}"
if [ ! -f "$SRC" ]; then
  SRC="/tmp/engine.js"
fi
DEST="$DIR/engine_js.h"

if [ ! -f "$SRC" ]; then
  echo "Error: source file '$SRC' not found" >&2
  exit 1
fi

{
  echo "const unsigned char engine_js[] = {"
  (cat "$SRC"; printf '\0') | xxd -i
  echo "};"
} > "$DEST"

echo "Generated $(wc -c < "$DEST" | tr -d ' ') bytes to $DEST from $SRC"
