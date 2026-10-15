#!/bin/sh
# Builds aslang.dev into web/dist: every page prerendered by web/tools/build.asl on the stage-0 host,
# and site.wasm compiled from web/site through asl-target-llvm (needs llc and wasm-ld, LLVM 18+).
set -eu
WEB=$(cd "$(dirname "$0")" && pwd -P)
ROOT=$(cd "$WEB/.." && pwd -P)
# The site needs asl-host alone: host/build.sh installs it before it builds the native runtime,
# which has no seed on some triples (x86_64 Linux), so its exit status is not this script's.
if [ ! -x "$ROOT/host/out/asl-host" ]; then
  CC="${CC:-$(command -v clang || echo cc)}" sh "$ROOT/host/build.sh" || true
  [ -x "$ROOT/host/out/asl-host" ] || { echo "web/build.sh: host/build.sh did not produce host/out/asl-host" >&2; exit 1; }
fi
# asl-ir and the build tool address the tree as asl/..., the layout of the monorepo checkout;
# a checkout under another name (a CI clone into repo/) is reached through a link named asl.
if [ "$(basename "$ROOT")" = "asl" ]; then
  PARENT=$(dirname "$ROOT")
else
  PARENT=$(mktemp -d)
  trap 'rm -rf "$PARENT"' EXIT
  ln -s "$ROOT" "$PARENT/asl"
fi
cd "$PARENT"
"$ROOT/host/out/asl-host" run asl/web/tools/build.asl
