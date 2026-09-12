#!/usr/bin/env bash
set -eo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/../.." && pwd)"
SRC="${1:-$DIR/engine.js}"
if [ ! -f "$SRC" ]; then
  SRC="/tmp/engine.js"
fi
DEST="$DIR/engine_js.h"

if [ ! -f "$SRC" ]; then
  echo "Error: source file '$SRC' not found" >&2
  exit 1
fi

TMP_GEN=$(mktemp /tmp/engine_combined.XXXXXX.js)
trap 'rm -f "$TMP_GEN"' EXIT

{
  echo "const __EMBEDDED_ASL_FILES__ = ["
  (cd "$ROOT_DIR" && find . -name "*.asl" -not -path "*/.*" -not -path "*/node_modules/*" -type f | sed 's|^\./||' | sort) | while read -r f; do
    echo "  \"$f\","
  done
  echo "];"
  cat "$SRC"
} > "$TMP_GEN"

{
  echo "const unsigned char engine_js[] = {"
  (cat "$TMP_GEN"; printf '\0') | xxd -i
  echo "};"
} > "$DEST"

echo "Generated $(wc -c < "$DEST" | tr -d ' ') bytes to $DEST from $SRC"
