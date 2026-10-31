#!/bin/sh
# Runtime-only build (HL-DELETE, 2026-10-13): no host interpreter is built or run. This script builds libaslrt.a,
# the archive the native CLI links (gcAsl.o from asl-target-llvm/gcRoute, rtAbi.o from rtAbi, rtFloor.o from
# rtFloor, every one ASL emitted to LLVM IR by a native asl1 and compiled by clang; zero hand-written C), then
# bootstraps the native CLI head so bin/asl never needs a host to serve a command.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd -P)
OUT=${ASL_HOST_OUT:-$HERE/out}
mkdir -p "$OUT"

# (:m :ref COLDSTART-WAIT-LIVE-HOLDER :why "--cold CACHE [WINDOW]: one cold-start build per node at a time, by the lock dir CACHE/build.lockd holding the holder's pid, out dir, ps start time and watcher pid. A waiter waits while the holder is alive (the pid runs, is no zombie and still has the recorded start time, so a reused pid after a SIGKILL reads as gone) and makes progress: CPU time of its tree grows, or files get newer under its out dir, the CACHE/tmp.PID dirs of its descendants or the build pool CACHE/../jobserver/build (a token wait); a gone holder is taken over at once; the waiter gives up only after WINDOW seconds with no progress (default .asl.config.asn :nativeCli :coldStallS, else 1800, the old fixed cap). The holder runs a --cold-watch child that stops the holder's tree and the holder itself (exit 75, lock released) after the same window without progress, so no waiter waits on a hung build. A fixed deadline used to fail every agent queued behind a slow but healthy cold build. --cold-probe takes the lock and exits; --cold-hold takes it and idles under the watcher")
cold_window() {
  awk 'match($0, /:coldStallS[ \t]+[0-9]+/) { s = substr($0, RSTART, RLENGTH); sub(/:coldStallS[ \t]+/, "", s); print s; exit }' "$HERE/../../.asl.config.asn" 2>/dev/null || true
}
cold_start() { ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//' || true; }
cold_alive() {
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null || true)" in *Z*) return 1 ;; esac
  [ -z "$2" ] || [ "$(cold_start "$1")" = "$2" ]
}
cold_descendants() {
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v r="$1" -v skip="${2:-0}" '{ p[$1] = $2 } END { for (x in p) { y = x; n = 0; while ((y in p) && y != r && y != skip && n < 64) { y = p[y]; n++ } if (y == r && x != r) print x } }'
}
cold_cpu() {
  ps -A -o pid= -o ppid= -o time= 2>/dev/null | awk -v r="$1" -v skip="${2:-0}" '
    function secs(t,  d, a, n, i, s) { d = 0; if (index(t, "-")) { split(t, a, "-"); d = a[1]; t = a[2] } n = split(t, a, ":"); s = 0; for (i = 1; i <= n; i++) s = s * 60 + a[i]; return d * 86400 + s }
    { p[$1] = $2; c[$1] = $3 }
    END { s = 0; for (x in p) { y = x; n = 0; while ((y in p) && y != r && y != skip && n < 64) { y = p[y]; n++ } if (y == r) s += secs(c[x]) } printf "%d\n", s * 100 }'
}
cold_files() {
  for d in "$2" "$3/../jobserver/build"; do
    [ -n "$(find "$d" -newer "$4" -print 2>/dev/null | head -n 1)" ] && return 0
  done
  for d in $(cold_descendants "$1" "$5"); do
    [ -d "$3/tmp.$d" ] && [ -n "$(find "$3/tmp.$d" -newer "$4" -print 2>/dev/null | head -n 1)" ] && return 0
  done
  return 1
}
cold_lock() {
  L=$1/build.lockd; win=$2; mkdir -p "$1"
  mark="$1/.coldWait.$$"; : > "$mark"; seen=$(date +%s); last=""; cpu0=""
  while ! mkdir "$L" 2>/dev/null; do
    pid=$(sed -n 1p "$L/holder" 2>/dev/null || true); dir=$(sed -n 2p "$L/holder" 2>/dev/null || true)
    st=$(sed -n 3p "$L/holder" 2>/dev/null || true); wp=$(sed -n 4p "$L/holder" 2>/dev/null || true)
    if [ -n "$pid" ] && ! cold_alive "$pid" "$st"; then
      [ "$(sed -n 1p "$L/holder" 2>/dev/null || true)" = "$pid" ] && rm -rf "$L"
      continue
    fi
    [ "$pid" = "$last" ] || { last=$pid; seen=$(date +%s); cpu0=""; }
    if [ -n "$pid" ]; then
      cpu=$(cold_cpu "$pid" "${wp:-0}")
      if { [ -n "$cpu0" ] && [ "$cpu" -gt "$cpu0" ]; } || cold_files "$pid" "${dir:-$L}" "$1" "$mark" "${wp:-0}"; then seen=$(date +%s); : > "$mark"; fi
      cpu0=$cpu
    fi
    if [ $(( $(date +%s) - seen )) -ge "$win" ]; then
      if [ -z "$pid" ]; then rm -rf "$L"; continue; fi
      rm -f "$mark"; echo "build.sh: the cold-start build lock holder $pid made no progress for ${win}s; giving up" >&2 || true; return 1
    fi
    sleep 1
  done
  rm -f "$mark"
  COLD_L=$L
  printf '%s\n%s\n%s\n' "$$" "$OUT" "$(cold_start $$)" > "$L/holder"
  sh "$0" --cold-watch "$$" "$1" "$win" "$OUT" &
  COLD_W=$!
  echo "$COLD_W" >> "$L/holder"
  trap 'cold_release' EXIT
  trap 'cold_release; exit 130' INT
  trap 'cold_release; exit 75' TERM
}
cold_release() {
  [ -z "${COLD_W:-}" ] || kill "$COLD_W" 2>/dev/null || true
  [ -z "${COLD_L:-}" ] || rm -rf "$COLD_L"
}
cold_watch() {
  h=$1; mark="$2/build.lockd/.self"; : > "$mark" 2>/dev/null || true; seen=$(date +%s); cpu0=""
  while kill -0 "$h" 2>/dev/null; do
    cpu=$(cold_cpu "$h" "$$")
    if { [ -n "$cpu0" ] && [ "$cpu" -gt "$cpu0" ]; } || cold_files "$h" "$4" "$2" "$mark" "$$"; then seen=$(date +%s); : > "$mark" 2>/dev/null || true; fi
    cpu0=$cpu
    if [ $(( $(date +%s) - seen )) -ge "$3" ]; then
      echo "build.sh: the cold-start build $h made no progress for ${3}s; stopping it" >&2 || true
      kids=$(cold_descendants "$h" "$$")
      kill -TERM "$h" 2>/dev/null || true
      for d in $kids; do kill -TERM "$d" 2>/dev/null || true; done
      break
    fi
    sleep 1
  done
  rm -f "$mark" 2>/dev/null || true
}
case "${1:-}" in
  --cold-watch) trap "" PIPE; cold_watch "$2" "$3" "$4" "$5"; exit 0 ;;
  --cold|--cold-probe|--cold-hold)
    w=${3:-$(cold_window)}; case "$w" in ''|*[!0-9]*) w=1800 ;; esac
    cold_lock "${2:?build.sh $1 needs the cache dir}" "$w" || exit 1
    case "$1" in
      --cold-probe) trap "" PIPE; echo "(:coldLock :got $$)" || true; exit 0 ;;
      --cold-hold) trap "" PIPE; echo "(:coldLock :holding $$)" || true; sleep 600 & wait $! || true; exit 0 ;;
    esac
    shift; shift; [ $# -gt 0 ] && shift ;;
esac
# (:m :why "VPSLIN-2: with CLANG unset the first of clang, clang-19 .. clang-15 on PATH is used (a distro that ships only clang-18 has no bare clang); an explicit CLANG is never second-guessed")
if [ -z "${CLANG:-}" ]; then
  CLANG=clang
  for c in clang clang-19 clang-18 clang-17 clang-16 clang-15; do
    if command -v "$c" >/dev/null 2>&1; then CLANG=$c; break; fi
  done
fi
export CLANG
RT_NAME="libaslrt.a"
PACKAGES="$HERE/../packages"
GC_ROUTE="$PACKAGES/asl-target-llvm/src/gcRoute.asl"
RT_ABI="$PACKAGES/asl-target-llvm/src/rtAbi.asl"
RT_FLOOR="$PACKAGES/asl-target-llvm/src/rtFloor.asl"

# (:m :why "ARCHIVE-KEY: archives carry no timestamps (GNU ar D, ZERO_AR_DATE on macOS), so equal members give equal bytes and every key that hashes an archive stays put across rebuilds")
ar_pack() {
  ZERO_AR_DATE=1 "${AR:-ar}" rcsD "$@" 2>/dev/null || ZERO_AR_DATE=1 "${AR:-ar}" rcs "$@"
}

# (:m :why "RUNTIME-NOHOST: the three emitters run as native programs a native asl1 compiled (ASL_NATIVE_ASL1, else the committed seed linked against an earlier libaslrt.a: ASL_NATIVE_RT, the out dir's, the newest cached, else one built from the runtime seed); there is no host to fall back to")
SEED_DIR="$HERE/../seed"
PRIOR_RT="$OUT/.libaslrt.prior.a"
[ -f "$OUT/$RT_NAME" ] && cp -p "$OUT/$RT_NAME" "$PRIOR_RT"

CACHE_DIR="${ASL_HOST_CACHE_DIR:-$HOME/.asl/run/hosts}"
CACHE_OK=1
mkdir -p "$CACHE_DIR" 2>/dev/null || CACHE_OK=0

prior_runtime() {
  if [ -n "${ASL_NATIVE_RT:-}" ] && [ -f "$ASL_NATIVE_RT" ]; then echo "$ASL_NATIVE_RT"; return 0; fi
  if [ -f "$PRIOR_RT" ]; then echo "$PRIOR_RT"; return 0; fi
  if [ "$CACHE_OK" = "1" ]; then
    cached=$(ls -t "$CACHE_DIR"/rt/*/libaslrt.a 2>/dev/null | head -n 1)
    [ -n "$cached" ] && { echo "$cached"; return 0; }
  fi
  seed_runtime
}

seed_field() { printf '%s' "$1" | sed -E "s/.*:$2 \"([^\"]*)\".*/\1/"; }
# (:m :why "RV1: the seed dir follows uname -sm, the machine the seed runs on, so a Linux clang printing aarch64-linux-gnu or x86_64-pc-linux-gnu still finds asl/seed/aarch64-unknown-linux-gnu; another host falls back to clang's triple without its OS version")
seed_triple() {
  case "$(uname -sm 2>/dev/null)" in
    "Darwin arm64") echo arm64-apple-darwin ;;
    "Linux aarch64"|"Linux arm64") echo aarch64-unknown-linux-gnu ;;
    "Linux x86_64") echo x86_64-unknown-linux-gnu ;;
    *) "$CLANG" -print-target-triple 2>/dev/null | sed -E 's/[0-9.]+$//' ;;
  esac
}

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  fi
}

SEED_CACHE_DIR="$CACHE_DIR/seed"

# (:m :why "RUNTIME-SEED: on a fresh clone the runtime IR beside the asl1 seed (seed.asn :runtimeSeed rows, llSha256 checked) becomes a bootstrap libaslrt.a; the native emitters then re-emit the runtime from the tree")
seed_runtime() {
  triple=$(seed_triple) || return 1
  rows=$(grep -F ":runtimeSeed :triple \"$triple\"" "$SEED_DIR/seed.asn" 2>/dev/null) || { echo "build.sh: no runtime seed for $triple" >&2; return 1; }
  dir="$SEED_CACHE_DIR/rt-$(printf '%s\n' "$rows" | hash_stdin | cut -c1-16)"
  if [ -f "$dir/libaslrt.a" ]; then echo "$dir/libaslrt.a"; return 0; fi
  tmp="$SEED_CACHE_DIR/.rt.$$"
  rm -rf "$tmp" && mkdir -p "$tmp" || return 1
  for m in gcAsl rtAbi rtFloor; do
    row=$(printf '%s\n' "$rows" | grep -F ":module \"$m\"") || { echo "build.sh: the runtime seed for $triple lacks $m" >&2; rm -rf "$tmp"; return 1; }
    llSha=$(seed_field "$row" llSha256)
    if ! { gzip -dc "$SEED_DIR/$triple/$m.ll.gz" > "$tmp/$m.ll" && [ "$(hash_stdin < "$tmp/$m.ll")" = "$llSha" ] \
           && "$CLANG" -O2 -Wno-override-module -c -x ir "$tmp/$m.ll" -o "$tmp/$m.o"; }; then
      echo "build.sh: the runtime seed $m.ll.gz did not unpack to llSha256 $llSha or did not compile" >&2; rm -rf "$tmp"; return 1
    fi
  done
  if ar_pack "$tmp/libaslrt.a" "$tmp/rtFloor.o" "$tmp/rtAbi.o" "$tmp/gcAsl.o" && mkdir -p "$dir" && mv -f "$tmp/libaslrt.a" "$dir/libaslrt.a"; then
    rm -rf "$tmp"; echo "$dir/libaslrt.a"
  else
    rm -rf "$tmp"; return 1
  fi
}

# (:m :why "the seed asl1 is linked once per seed IR and runtime archive, under the cache")
native_asl1() {
  rt=$1
  if [ -n "${ASL_NATIVE_ASL1:-}" ] && [ -x "$ASL_NATIVE_ASL1" ]; then echo "$ASL_NATIVE_ASL1"; return 0; fi
  triple=$(seed_triple) || return 1
  row=$(grep -F "(:seed :triple \"$triple\"" "$SEED_DIR/seed.asn" 2>/dev/null) || { echo "build.sh: no seed for $triple" >&2; return 1; }
  gz="$SEED_DIR/$triple/$(basename "$(seed_field "$row" file)")"; llSha=$(seed_field "$row" llSha256)
  bin="$SEED_CACHE_DIR/$llSha-$(hash_stdin < "$rt" | cut -c1-16)/asl1"
  if [ -x "$bin" ]; then echo "$bin"; return 0; fi
  tmp="$SEED_CACHE_DIR/.tmp.$$"
  rm -rf "$tmp" && mkdir -p "$tmp" || return 1
  if gzip -dc "$gz" > "$tmp/asl1.ll" && [ "$(hash_stdin < "$tmp/asl1.ll")" = "$llSha" ] \
     && "$CLANG" -O2 -Wno-override-module -x ir "$tmp/asl1.ll" -x none "$rt" -lm -o "$tmp/asl1" && mkdir -p "${bin%/*}" && mv -f "$tmp/asl1" "$bin"; then
    rm -rf "$tmp"; echo "$bin"
  else
    echo "build.sh: the seed $gz did not unpack to llSha256 $llSha or did not link" >&2; rm -rf "$tmp"; return 1
  fi
}

# (:m :why "sets EMIT_DIR to the compiled emitters; there is no host bootstrap left to fall back to")
emitters() {
  dest=$1; EMIT_DIR=""; why=""
  rt=$(prior_runtime)
  if [ -z "$rt" ]; then why="no earlier libaslrt.a to link a native asl1 against"
  elif ! asl1=$(native_asl1 "$rt"); then why="no native asl1"
  else
    mkdir -p "$dest/emit"
    for m in gcRoute rtAbi rtFloor; do
      if ! (cd "$HERE/../.." && ASL_PRELUDE="$HERE/../prelude/prelude.asl" "$asl1" build "$PACKAGES/asl-target-llvm/src/$m.asl" -o "$dest/emit/$m.ll") >&2 \
         || ! "$CLANG" -O0 -Wno-override-module -x ir "$dest/emit/$m.ll" -x none "$rt" -lm -o "$dest/emit/$m"; then
        why="the native asl1 could not build asl-target-llvm/$m"; break
      fi
    done
    [ -n "$why" ] || EMIT_DIR="$dest/emit"
  fi
  [ -n "$EMIT_DIR" ] || echo "build.sh: no runtime emitters: $why" >&2
}

emit() {
  m=$1; shift
  [ -n "$EMIT_DIR" ] || return 1
  env -u ASL_PRELUDE "$EMIT_DIR/$m" "$@"
}

# (:m :why "uninstrumented IR: the stack scan reads past frames")
runtime() {
  dest=$1
  emitters "$dest"
  [ -n "$EMIT_DIR" ] || return 1
  emit gcRoute "$dest/gcAsl.ll" || { echo "build.sh: asl-target-llvm/gcRoute did not write the collector module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/gcAsl.ll" -o "$dest/gcAsl.o" || { echo "build.sh: $CLANG did not compile the collector module" >&2; return 1; }
  emit rtAbi "$dest/rtAbi.ll" || { echo "build.sh: asl-target-llvm/rtAbi did not write the runtime ABI module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/rtAbi.ll" -o "$dest/rtAbi.o" || { echo "build.sh: $CLANG did not compile the runtime ABI module" >&2; return 1; }
  emit rtFloor "$dest/rtFloor.ll" || { echo "build.sh: asl-target-llvm/rtFloor did not write the runtime floor module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/rtFloor.ll" -o "$dest/rtFloor.o" || { echo "build.sh: $CLANG did not compile the runtime floor module" >&2; return 1; }
  rm -rf "$dest/gcAsl.ll" "$dest/rtAbi.ll" "$dest/rtFloor.ll" "$dest/$RT_NAME.tmp" "$dest/emit"
  ar_pack "$dest/$RT_NAME.tmp" "$dest/rtFloor.o" "$dest/rtAbi.o" "$dest/gcAsl.o" && mv -f "$dest/$RT_NAME.tmp" "$dest/$RT_NAME"
  rm -f "$dest/gcAsl.o" "$dest/rtAbi.o" "$dest/rtFloor.o"
}

# (:m :why "a tree without the ASL packages (asl/host and asl/prelude copied alone) or a host without clang gets no libaslrt.a, said on stderr; asl build then reports it missing")
runtime_possible() {
  if [ ! -f "$GC_ROUTE" ]; then echo "build.sh: no $RT_NAME: $GC_ROUTE is absent" >&2; return 1; fi
  if [ ! -f "$RT_ABI" ]; then echo "build.sh: no $RT_NAME: $RT_ABI is absent" >&2; return 1; fi
  if [ ! -f "$RT_FLOOR" ]; then echo "build.sh: no $RT_NAME: $RT_FLOOR is absent" >&2; return 1; fi
  return 0
}

# (:m :why "HOSTLINK-CLOBBER: never hardlink a cache entry into $OUT - every tree keyed the same way would then share one inode, so a write through any one of them corrupts the cache and every other tree's copy. Install as an independent copy instead: cp -p to a temp name beside the destination, then mv it into place, so the install is atomic and $OUT always gets a fresh inode. The cache file itself is chmod a-w right after it is written (see cacheReadonly below), so a write attempted through the cache path fails loudly instead of silently clobbering")
install_copy() {
  tmp="$2.tmp.$$"
  rm -f "$tmp"
  cp -p "$1" "$tmp" 2>/dev/null || cp "$1" "$tmp"
  chmod u+w "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$2"
}

# (:m :why "HOSTLINK-CLOBBER: strips write permission from a freshly written cache entry so any future write attempted through the cache path itself fails with EACCES instead of silently mutating bytes every tree's install_copy already read")
cacheReadonly() {
  for f in "$@"; do chmod a-w "$f" 2>/dev/null || true; done
}

# (:m :why "REBUILD-NODESTROY: a tree that already has a working $RT_NAME must never lose it just because a later rebuild attempt (stale toolchain, scratch-cache probe, transient compiler failure) fails partway; $RT_NAME is deleted up front only when the tree is genuinely incomplete (runtime_possible false), everywhere else the existing file is left alone unless a rebuild actually produces a replacement to atomically install over it")
RT_OK=1
if ! command -v "$CLANG" >/dev/null 2>&1; then
  echo "build.sh: no $RT_NAME: $CLANG not found; install clang (clang-15 .. clang-19 are probed) or set CLANG; an installed $RT_NAME is kept" >&2
  exit 1
fi
if runtime_possible; then
  if [ "$CACHE_OK" = "1" ] && [ "${ASL_HOST_CACHE:-1}" != "0" ]; then
    GC_KEY=$( (
      "$CLANG" --version 2>&1 | head -n 1
      for f in "$HERE/../prelude/prelude.asl" "$PACKAGES"/asl-ir/src/*.asl "$PACKAGES"/asl-target-llvm/src/*.asl; do
        echo "${f##*/}"
        cat "$f"
      done
    ) | hash_stdin )
    GC_DIR="$CACHE_DIR/rt/$GC_KEY"
    if [ ! -f "$GC_DIR/$RT_NAME" ]; then
      GC_TMP="$CACHE_DIR/rt/.tmp.$$"
      rm -rf "$GC_TMP" && mkdir -p "$GC_TMP"
      trap 'rm -rf "$GC_TMP"; cold_release' EXIT
      trap 'rm -rf "$GC_TMP"; cold_release; exit 130' INT
      trap 'rm -rf "$GC_TMP"; cold_release; exit 75' TERM
      if runtime "$GC_TMP"; then
        mkdir -p "$GC_DIR"
        mv -f "$GC_TMP/$RT_NAME" "$GC_DIR/$RT_NAME.tmp.$$"
        mv -f "$GC_DIR/$RT_NAME.tmp.$$" "$GC_DIR/$RT_NAME"
        cacheReadonly "$GC_DIR/$RT_NAME"
      else
        RT_OK=0
      fi
      rm -rf "$GC_TMP"
      trap 'cold_release' EXIT
      trap 'cold_release; exit 130' INT
      trap 'cold_release; exit 75' TERM
    fi
    [ "$RT_OK" = "1" ] && install_copy "$GC_DIR/$RT_NAME" "$OUT/$RT_NAME"
  else
    runtime "$OUT" || RT_OK=0
  fi
  if [ "$RT_OK" != "1" ]; then
    echo "build.sh: runtime rebuild failed, keeping the existing $RT_NAME if one was already installed" >&2
  fi
else
  rm -f "$OUT/$RT_NAME"
fi
rm -f "$PRIOR_RT"
# (:m :why "NATIVECACHE: out/prelude.asl is a toolchain root of the native fingerprint and the ASL_PRELUDE of running suites; an unchanged copy keeps its bytes and stamp, and a changed one lands by rename, so a neighbour rebuilding the host never shows a reader a truncated file or a new stamp")
cmp -s "$HERE/../prelude/prelude.asl" "$OUT/prelude.asl" || install_copy "$HERE/../prelude/prelude.asl" "$OUT/prelude.asl"

# (:m :why "TOOLSHOST-THIN: a tree with no native CLI head gets one here, so a fresh clone runs no host at all: the seed asl1 compiles asl-cli/nativeBuild (cached by its sources), which builds native.asl and writes the head with the keys bin/asl's fallback build uses; a tree that has a head is left to asl-cli/nativeCli")
native_cli() {
  [ -f "$PACKAGES/asl-cli/src/nativeBuild.asl" ] || return 0
  asl1=$(native_asl1 "$OUT/$RT_NAME") || { echo "build.sh: no native CLI: no native asl1" >&2; return 1; }
  root=$(cd "$HERE/../.." && pwd -P)
  clang_version=$("$CLANG" --version | head -n 1)
  deps=$(cd "$root" && ASL_PRELUDE="$root/asl/prelude/prelude.asl" "$asl1" deps asl/packages/asl-cli/src/nativeBuild.asl) || { echo "build.sh: no native CLI: asl1 deps of asl-cli/nativeBuild failed" >&2; return 1; }
  # (:m :why "STAMP-ENTRY: asl1 deps omits the entry file")
  deps=$(printf '%s\n%s\n' asl/packages/asl-cli/src/nativeBuild.asl "$deps")
  key=$( { echo "$asl1"; echo "$clang_version"; for f in $deps "$root"/asl/prelude/prelude.asl "$root"/asl/prelude/native/*.asl; do case $f in (/*) ;; (*) f="$root/$f" ;; esac; echo "${f#"$root"/}"; cat "$f"; done; } | hash_stdin )
  dir="$CACHE_DIR/nativeBuild/$key"
  if [ ! -x "$dir/aslNativeBuild" ]; then
    tmp="$CACHE_DIR/nativeBuild/.tmp.$$"
    rm -rf "$tmp" && mkdir -p "$tmp" || return 1
    if (cd "$root" && ASL_PRELUDE="$root/asl/prelude/prelude.asl" "$asl1" build asl/packages/asl-cli/src/nativeBuild.asl -o "$tmp/nativeBuild.ll") >&2 \
       && "$CLANG" -O2 -Wno-override-module -x ir "$tmp/nativeBuild.ll" -x none "$OUT/$RT_NAME" -lm -o "$tmp/aslNativeBuild" && mkdir -p "$dir" && mv -f "$tmp/aslNativeBuild" "$dir/aslNativeBuild"; then
      rm -rf "$tmp"
      cacheReadonly "$dir/aslNativeBuild"
    else
      rm -rf "$tmp"; echo "build.sh: no native CLI: the seed asl1 could not build asl-cli/nativeBuild" >&2; return 1
    fi
  fi
  install_copy "$dir/aslNativeBuild" "$OUT/aslNativeBuild" || { echo "build.sh: no native CLI: aslNativeBuild did not install" >&2; return 1; }
  stamp="$OUT/aslNativeBuild-fresh"
  # (:m :why "STAMP-SHADOW: the source snapshot sits in .src behind the symlink src (nativeCli fresh? reads dir/src/p); the module index (asl-checker/resolve walkEntry!) skips dot names and symlinks, so the copies never make an undeclared import such as asl-parser/indentParser ambiguous")
  rm -rf "$stamp" && mkdir -p "$stamp/.src" && ln -s .src "$stamp/src" || { echo "build.sh: no native CLI: the source stamp dir was not made" >&2; return 1; }
  printf '%s\n' "$deps" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in /*) rel=${f#"$root"/} ;; *) rel=$f; f="$root/$f" ;; esac
    mkdir -p "$stamp/.src/$(dirname "$rel")" && cp "$f" "$stamp/.src/$rel" || exit 1
    printf '%s\n' "$rel"
  done > "$stamp/deps" || { echo "build.sh: no native CLI: the source stamp was not copied" >&2; return 1; }
  printf '%s\n' "$clang_version" > "$stamp/clang-version" && cp "$OUT/aslNativeBuild" "$stamp/bin" && chmod +x "$stamp/bin" || { echo "build.sh: no native CLI: the stamp binary was not copied" >&2; return 1; }
  # (:m :why "BUILD-DETACHED-ESCAPE: the caller (bin/asl) is the build owner, so a killed caller ends the build and its clang parts instead of leaving them under init")
  "$OUT/aslNativeBuild" "$root" --if-cold --lock-owner "$PPID" >&2 || { echo "build.sh: the native CLI build failed" >&2; return 1; }
}
# (:m :why "HOSTBUILD-EXIT-MASK: every failed step makes the script exit 1 and names the step last on stderr; native_cli runs in an || list, where set -e does not apply, so each of its steps checks its own status and returns 1")
CLI_OK=1
native_cli || CLI_OK=0
[ "$RT_OK" = "1" ] || echo "build.sh: failed step: runtime $RT_NAME" >&2
[ "$CLI_OK" = "1" ] || echo "build.sh: failed step: native CLI" >&2
[ "$RT_OK" = "1" ] && [ "$CLI_OK" = "1" ] || exit 1
