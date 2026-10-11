#!/bin/sh
# Stage-0 ASL host build: content-addressed host cache (plan EP unit hostOnce).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd -P)
OUT=${ASL_HOST_OUT:-$HERE/out}
mkdir -p "$OUT"
CC="${CC:-/usr/bin/cc}"
[ -x "$CC" ] || CC="cc"
AR="${AR:-/usr/bin/ar}"
[ -x "$AR" ] || AR="ar"
CLANG="${CLANG:-clang}"
FLAGS="-std=c11 -Wall -Wextra -Werror -D_DEFAULT_SOURCE"
[ "$(uname -s)" = "Darwin" ] && FLAGS="$FLAGS -D_DARWIN_C_SOURCE"
MODE="${1:-}"
case "$MODE" in
  --sanitize) HOST_NAME="asl-host-asan"; LIB_NAME="libaslhost-asan.a"; RT_NAME="libaslrt-asan.a"; TEST_RT_NAME="libaslrt-asan-test.a" ;;
  "")         HOST_NAME="asl-host";      LIB_NAME="libaslhost.a";      RT_NAME="libaslrt.a"; TEST_RT_NAME="libaslrt-test.a" ;;
  *) echo "usage: build.sh [--sanitize]" >&2; exit 2 ;;
esac

# libaslrt.a carries native runtime pieces; table objects are pulled through asl_rt_builtin_<table>. No member reaches
# the evaluator: hostVerbLink.c, the hostVerb bridge, left with hostVerb in NX4, and a program's IR defines aslCall.
# libaslhost.a (every source but main.c) is asl-host's evaluator, compiler and loader; asl-target-llvm/rtAbi emits libaslrt.a's rtAbi.o.
# libaslrt.a's collector is gcAsl.o, asl-target-llvm/gcRoute's module compiled by clang (plan unit GCASL-2);
# gc.c is in libaslhost.a alone, as asl-host's collector. prelude.c and zstd.c left RT_SRCS in PRELUDEASL-Z
# (every builtinArity/coreBuiltins name lowers natively or fails with ERR_LOWER_UNSUPPORTED). value.c and
# float.c left RT_SRCS in ABIVAL-5 (native code and libaslhost.a's C share one intern table and raise state). strFloor.c left
# RT_SRCS in RT-FLOOR and stays in libaslhost.a alone: asl-target-llvm/rtFloor emits gcFloorFail and gcFloorGuard as rtFloor.o.
PACKAGES="$HERE/../packages"
GC_ROUTE="$PACKAGES/asl-target-llvm/src/gcRoute.asl"
RT_ABI="$PACKAGES/asl-target-llvm/src/rtAbi.asl"
RT_FLOOR="$PACKAGES/asl-target-llvm/src/rtFloor.asl"

# (:m :why "ARCHIVE-KEY: archives carry no timestamps (GNU ar D, ZERO_AR_DATE on macOS), so equal members give equal bytes and every key that hashes an archive stays put across rebuilds")
ar_pack() {
  ZERO_AR_DATE=1 "$AR" rcsD "$@" 2>/dev/null || ZERO_AR_DATE=1 "$AR" rcs "$@"
}

archives() {
  dir=$1; objs=$2
  set --; for f in "$HERE"/src/*.c; do b=${f##*/}; case $b in main.c) ;; *) set -- "$@" "$objs/${b%.c}.o" ;; esac; done
  rm -f "$dir/$LIB_NAME" && ar_pack "$dir/$LIB_NAME" "$@"
  rm -f "$dir/$TEST_RT_NAME" && ar_pack "$dir/$TEST_RT_NAME" "$objs/gcHooks.o"
}

do_compile() {
  dest=$1
  if [ "$MODE" = "--sanitize" ]; then
    san="-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined"
    set --; for f in "$HERE"/src/*.c; do case $f in */main.c) ;; *) set -- "$@" "$f" ;; esac; done
    rm -rf "$dest/objAsan" && mkdir "$dest/objAsan"
    (cd "$dest/objAsan" && "$CC" $FLAGS $san -c "$@")
    archives "$dest" "$dest/objAsan" && rm -rf "$dest/objAsan"
    "$CC" $FLAGS $san -o "$dest/$HOST_NAME" "$HERE/src/main.c" "$dest/$LIB_NAME" -lm
  else
    set --; for f in "$HERE"/src/*.c; do case $f in */main.c) ;; *) set -- "$@" "$f" ;; esac; done
    rm -rf "$dest/obj" && mkdir "$dest/obj"
    (cd "$dest/obj" && "$CC" $FLAGS -O2 -c "$@")
    archives "$dest" "$dest/obj" && rm -rf "$dest/obj"
    "$CC" $FLAGS -O2 -o "$dest/$HOST_NAME" "$HERE/src/main.c" "$dest/$LIB_NAME" -lm
  fi
  cp "$HERE/../prelude/prelude.asl" "$dest/prelude.asl"
}

# (:m :why "RUNTIME-NOHOST: the three emitters run as native programs a native asl1 compiled (ASL_NATIVE_ASL1, else the committed seed linked against an earlier libaslrt.a: ASL_NATIVE_RT, the out dir's, the newest cached, else one built from the runtime seed); asl-host runs them only when none of these exists, said on stderr")
SEED_DIR="$HERE/../seed"
PRIOR_RT="$OUT/.libaslrt.prior.a"
[ -f "$OUT/libaslrt.a" ] && { ln -f "$OUT/libaslrt.a" "$PRIOR_RT" 2>/dev/null || cp -p "$OUT/libaslrt.a" "$PRIOR_RT"; }

prior_runtime() {
  if [ -n "${ASL_NATIVE_RT:-}" ] && [ -f "$ASL_NATIVE_RT" ]; then echo "$ASL_NATIVE_RT"; return 0; fi
  if [ -f "$PRIOR_RT" ]; then echo "$PRIOR_RT"; return 0; fi
  cached=$(ls -t "$CACHE_DIR"/*/gc/*/libaslrt.a 2>/dev/null | head -n 1)
  if [ -n "$cached" ]; then echo "$cached"; return 0; fi
  seed_runtime
}

seed_field() { printf '%s' "$1" | sed -E "s/.*:$2 \"([^\"]*)\".*/\1/"; }
seed_triple() { "$CLANG" -print-target-triple 2>/dev/null | sed -E 's/[0-9.]+$//'; }

# (:m :why "RUNTIME-SEED: on a fresh clone the runtime IR beside the asl1 seed (seed.asn :runtimeSeed rows, llSha256 checked) becomes a bootstrap libaslrt.a under the host cache; the native emitters then re-emit the runtime from the tree")
seed_runtime() {
  triple=$(seed_triple) || return 1
  rows=$(grep -F ":runtimeSeed :triple \"$triple\"" "$SEED_DIR/seed.asn" 2>/dev/null) || { echo "build.sh: no runtime seed for $triple" >&2; return 1; }
  dir="$CACHE_DIR/seed/rt-$(printf '%s\n' "$rows" | hash_stdin | cut -c1-16)"
  if [ -f "$dir/libaslrt.a" ]; then echo "$dir/libaslrt.a"; return 0; fi
  tmp="$CACHE_DIR/seed/.rt.$$"
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

# (:m :why "the seed asl1 is linked once per seed IR and runtime archive, under the host cache")
native_asl1() {
  rt=$1
  if [ -n "${ASL_NATIVE_ASL1:-}" ] && [ -x "$ASL_NATIVE_ASL1" ]; then echo "$ASL_NATIVE_ASL1"; return 0; fi
  triple=$(seed_triple) || return 1
  row=$(grep -F "(:seed :triple \"$triple\"" "$SEED_DIR/seed.asn" 2>/dev/null) || { echo "build.sh: no seed for $triple" >&2; return 1; }
  gz="$SEED_DIR/$triple/$(basename "$(seed_field "$row" file)")"; llSha=$(seed_field "$row" llSha256)
  bin="$CACHE_DIR/seed/$llSha-$(hash_stdin < "$rt" | cut -c1-16)/asl1"
  if [ -x "$bin" ]; then echo "$bin"; return 0; fi
  tmp="$CACHE_DIR/seed/.tmp.$$"
  rm -rf "$tmp" && mkdir -p "$tmp" || return 1
  if gzip -dc "$gz" > "$tmp/asl1.ll" && [ "$(hash_stdin < "$tmp/asl1.ll")" = "$llSha" ] \
     && "$CLANG" -O2 -Wno-override-module -x ir "$tmp/asl1.ll" -x none "$rt" -lm -o "$tmp/asl1" && mkdir -p "${bin%/*}" && mv -f "$tmp/asl1" "$bin"; then
    rm -rf "$tmp"; echo "$bin"
  else
    echo "build.sh: the seed $gz did not unpack to llSha256 $llSha or did not link" >&2; rm -rf "$tmp"; return 1
  fi
}

# (:m :why "sets EMIT_DIR to the compiled emitters, or leaves it empty for the host bootstrap")
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
  [ -n "$EMIT_DIR" ] || echo "build.sh: the runtime emitters run on asl-host to bootstrap: $why" >&2
}

emit() {
  m=$1; shift
  if [ -n "$EMIT_DIR" ]; then env -u ASL_PRELUDE "$EMIT_DIR/$m" "$@"; else env -u ASL_PRELUDE "$host/$HOST_NAME" run "$PACKAGES/asl-target-llvm/src/$m.asl" "$@"; fi
}

# (:m :why "uninstrumented IR: the stack scan reads past frames")
runtime() {
  host=$1; dest=$2
  emitters "$dest"
  emit gcRoute "$dest/gcAsl.ll" || { echo "build.sh: asl-target-llvm/gcRoute did not write the collector module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/gcAsl.ll" -o "$dest/gcAsl.o" || { echo "build.sh: $CLANG did not compile the collector module" >&2; return 1; }
  abiFlag=""; [ "$MODE" = "--sanitize" ] && abiFlag="asan"
  emit rtAbi "$dest/rtAbi.ll" $abiFlag || { echo "build.sh: asl-target-llvm/rtAbi did not write the runtime ABI module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/rtAbi.ll" -o "$dest/rtAbi.o" || { echo "build.sh: $CLANG did not compile the runtime ABI module" >&2; return 1; }
  emit rtFloor "$dest/rtFloor.ll" || { echo "build.sh: asl-target-llvm/rtFloor did not write the runtime floor module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/rtFloor.ll" -o "$dest/rtFloor.o" || { echo "build.sh: $CLANG did not compile the runtime floor module" >&2; return 1; }
  rm -rf "$dest/gcAsl.ll" "$dest/rtAbi.ll" "$dest/rtFloor.ll" "$dest/$RT_NAME" "$dest/$RT_NAME.tmp" "$dest/emit"
  ar_pack "$dest/$RT_NAME.tmp" "$dest/rtFloor.o" "$dest/rtAbi.o" "$dest/gcAsl.o" && mv -f "$dest/$RT_NAME.tmp" "$dest/$RT_NAME"
  rm -f "$dest/gcAsl.o" "$dest/rtAbi.o" "$dest/rtFloor.o"
}

# (:m :why "a tree without the ASL packages (asl/host and asl/prelude copied alone) or a host without clang gets no libaslrt.a, said on stderr; asl build then reports it missing")
runtime_possible() {
  if [ ! -f "$GC_ROUTE" ]; then echo "build.sh: no $RT_NAME: $GC_ROUTE is absent" >&2; return 1; fi
  if [ ! -f "$RT_ABI" ]; then echo "build.sh: no $RT_NAME: $RT_ABI is absent" >&2; return 1; fi
  if [ ! -f "$RT_FLOOR" ]; then echo "build.sh: no $RT_NAME: $RT_FLOOR is absent" >&2; return 1; fi
  if ! command -v "$CLANG" >/dev/null 2>&1; then echo "build.sh: no $RT_NAME: $CLANG not found; install clang or set CLANG" >&2; return 1; fi
  return 0
}

link_or_copy() {
  rm -f "$2"
  ln -f "$1" "$2" 2>/dev/null || cp -p "$1" "$2" 2>/dev/null || cp "$1" "$2"
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

KEY=$( (
  "$CC" --version 2>&1 | head -n 1
  uname -m
  echo "$MODE"
  for f in "$HERE/build.sh" "$HERE"/src/*; do
    [ -f "$f" ] || continue
    echo "${f##*/}"
    cat "$f"
  done
) | hash_stdin )

CACHE_DIR="${ASL_HOST_CACHE_DIR:-$HOME/.asl/run/hosts}"
if [ "${ASL_HOST_CACHE:-1}" = "0" ] || [ -z "$KEY" ] || ! mkdir -p "$CACHE_DIR" 2>/dev/null; then
  rm -f "$OUT/$HOST_NAME" "$OUT/$LIB_NAME" "$OUT/$RT_NAME" "$OUT/$TEST_RT_NAME"
  do_compile "$OUT"
  if runtime_possible; then runtime "$OUT" "$OUT"; fi
  rm -f "$PRIOR_RT"
  exit 0
fi

KEY_DIR="$CACHE_DIR/$KEY"
if ! { [ -x "$KEY_DIR/$HOST_NAME" ] && [ -f "$KEY_DIR/$LIB_NAME" ] && [ -f "$KEY_DIR/$TEST_RT_NAME" ]; }; then
  TMP_DIR="$CACHE_DIR/.tmp.$KEY.$$"
  mkdir -p "$TMP_DIR"
  trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
  do_compile "$TMP_DIR"

  mkdir -p "$KEY_DIR"
  mv -f "$TMP_DIR/$LIB_NAME" "$KEY_DIR/$LIB_NAME.tmp.$$"
  mv -f "$KEY_DIR/$LIB_NAME.tmp.$$" "$KEY_DIR/$LIB_NAME"
  mv -f "$TMP_DIR/$TEST_RT_NAME" "$KEY_DIR/$TEST_RT_NAME.tmp.$$"
  mv -f "$KEY_DIR/$TEST_RT_NAME.tmp.$$" "$KEY_DIR/$TEST_RT_NAME"
  mv -f "$TMP_DIR/$HOST_NAME" "$KEY_DIR/$HOST_NAME.tmp.$$"
  mv -f "$KEY_DIR/$HOST_NAME.tmp.$$" "$KEY_DIR/$HOST_NAME"
  rm -rf "$TMP_DIR"
  trap - EXIT INT TERM
fi

link_or_copy "$KEY_DIR/$HOST_NAME" "$OUT/$HOST_NAME"
link_or_copy "$KEY_DIR/$LIB_NAME" "$OUT/$LIB_NAME"
link_or_copy "$KEY_DIR/$TEST_RT_NAME" "$OUT/$TEST_RT_NAME"
touch "$OUT/$HOST_NAME" 2>/dev/null || true
cp "$HERE/../prelude/prelude.asl" "$OUT/prelude.asl"

# (:m :why "libaslrt.a is keyed again by clang and every source of the collector module, so an edit to the ASL collector or its emitter rebuilds it alone")
rm -f "$OUT/$RT_NAME"
runtime_possible || { rm -f "$PRIOR_RT"; exit 0; }
GC_KEY=$( (
  echo "$KEY"
  "$CLANG" --version 2>&1 | head -n 1
  for f in "$HERE/../prelude/prelude.asl" "$PACKAGES"/asl-ir/src/*.asl "$PACKAGES"/asl-target-llvm/src/*.asl; do
    echo "${f##*/}"
    cat "$f"
  done
) | hash_stdin )
GC_DIR="$KEY_DIR/gc/$GC_KEY"
if [ ! -f "$GC_DIR/$RT_NAME" ]; then
  GC_TMP="$KEY_DIR/gc/.tmp.$$"
  rm -rf "$GC_TMP" && mkdir -p "$GC_TMP"
  trap 'rm -rf "$GC_TMP"' EXIT INT TERM
  runtime "$OUT" "$GC_TMP"
  mkdir -p "$GC_DIR"
  mv -f "$GC_TMP/$RT_NAME" "$GC_DIR/$RT_NAME.tmp.$$"
  mv -f "$GC_DIR/$RT_NAME.tmp.$$" "$GC_DIR/$RT_NAME"
  rm -rf "$GC_TMP"
  trap - EXIT INT TERM
fi
link_or_copy "$GC_DIR/$RT_NAME" "$OUT/$RT_NAME"
rm -f "$PRIOR_RT"

# (:m :why "TOOLSHOST-THIN: a tree with no native CLI head gets one here, so a fresh clone runs no asl-host: the seed asl1 compiles asl-cli/nativeBuild (cached by its sources), which builds native.asl and writes the head with the keys bin/asl's fallback build uses; a tree that has a head is left to asl-cli/nativeCli")
native_cli() {
  [ -z "$MODE" ] && [ -f "$PACKAGES/asl-cli/src/nativeBuild.asl" ] || return 0
  asl1=$(native_asl1 "$OUT/$RT_NAME") || { echo "build.sh: no native CLI: no native asl1" >&2; return 0; }
  root=$(cd "$HERE/../.." && pwd -P)
  deps=$(cd "$root" && ASL_PRELUDE="$root/asl/prelude/prelude.asl" "$asl1" deps asl/packages/asl-cli/src/nativeBuild.asl) || { echo "build.sh: no native CLI: asl1 deps of asl-cli/nativeBuild failed" >&2; return 0; }
  key=$( { echo "$asl1"; for f in $deps "$root"/asl/prelude/prelude.asl "$root"/asl/prelude/native/*.asl; do case $f in (/*) ;; (*) f="$root/$f" ;; esac; echo "${f#"$root"/}"; cat "$f"; done; } | hash_stdin )
  dir="$CACHE_DIR/nativeBuild/$key"
  if [ ! -x "$dir/aslNativeBuild" ]; then
    tmp="$CACHE_DIR/nativeBuild/.tmp.$$"
    rm -rf "$tmp" && mkdir -p "$tmp" || return 0
    if (cd "$root" && ASL_PRELUDE="$root/asl/prelude/prelude.asl" "$asl1" build asl/packages/asl-cli/src/nativeBuild.asl -o "$tmp/nativeBuild.ll") >&2 \
       && "$CLANG" -O2 -Wno-override-module -x ir "$tmp/nativeBuild.ll" -x none "$OUT/$RT_NAME" -lm -o "$tmp/aslNativeBuild" && mkdir -p "$dir" && mv -f "$tmp/aslNativeBuild" "$dir/aslNativeBuild"; then
      rm -rf "$tmp"
    else
      rm -rf "$tmp"; echo "build.sh: no native CLI: the seed asl1 could not build asl-cli/nativeBuild" >&2; return 0
    fi
  fi
  link_or_copy "$dir/aslNativeBuild" "$OUT/aslNativeBuild"
  "$OUT/aslNativeBuild" "$root" --if-cold >&2 || echo "build.sh: the native CLI build failed; bin/asl falls back to asl-host" >&2
}
native_cli
