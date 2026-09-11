#!/usr/bin/env bash
set -eo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-/tmp/engine.js}"
DEST="$DIR/engine_js.h"

if [ ! -f "$SRC" ]; then
  echo "Error: source file '$SRC' not found" >&2
  exit 1
fi

python3 -c "
import sys
with open('$SRC', 'rb') as f:
    data = f.read()
data = data + b'\x00'
lines = ['const unsigned char engine_js[] = {']
for i in range(0, len(data), 16):
    chunk = data[i:i+16]
    lines.append(' '.join(f'0x{b:02x},' for b in chunk))
lines[-1] = lines[-1].rstrip(',')
lines.append('};')
output = '\n'.join(lines) + '\n'
with open('$DEST', 'w') as f:
    f.write(output)
print(f'Generated {len(output)} bytes to $DEST from $SRC')
"
