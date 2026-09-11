#!/usr/bin/env bash
set -eo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
ASL_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ASL_BIN="$ASL_DIR/bin/asl"

if [ ! -x "$ASL_BIN" ]; then
  if [ -x "$ASL_DIR/../bin/asl" ]; then
    ASL_BIN="$ASL_DIR/../bin/asl"
  elif [ -x "$ASL_DIR/../asl/bin/asl" ]; then
    ASL_BIN="$ASL_DIR/../asl/bin/asl"
  else
    echo "Error: sovereign asl binary not found at $ASL_BIN" >&2
    exit 1
  fi
fi

exec "$ASL_BIN" "$@"
