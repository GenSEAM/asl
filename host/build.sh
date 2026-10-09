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
# float.c left RT_SRCS in ABIVAL-5 (native code and libaslhost.a's C share one intern table and raise state).
RT_SRCS="strFloor.c"
PACKAGES="$HERE/../packages"
GC_ROUTE="$PACKAGES/asl-target-llvm/src/gcRoute.asl"
RT_ABI="$PACKAGES/asl-target-llvm/src/rtAbi.asl"

# (:m :why "rtc.a holds libaslrt.a's C members for the cache; runtime appends the collector, and only libaslrt.a is ever linked")
archives() {
  dir=$1; objs=$2
  set --; for f in "$HERE"/src/*.c; do b=${f##*/}; case $b in main.c) ;; *) set -- "$@" "$objs/${b%.c}.o" ;; esac; done
  rm -f "$dir/$LIB_NAME" && "$AR" rcs "$dir/$LIB_NAME" "$@"
  set --; for b in $RT_SRCS; do set -- "$@" "$objs/${b%.c}.o"; done
  rm -f "$dir/rtc.a" && "$AR" rcs "$dir/rtc.a" "$@"
  rm -f "$dir/$TEST_RT_NAME" && "$AR" rcs "$dir/$TEST_RT_NAME" "$objs/gcHooks.o"
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

# (:m :why "uninstrumented IR: the stack scan reads past frames")
runtime() {
  host=$1; rtc=$2; dest=$3
  env -u ASL_PRELUDE "$host/$HOST_NAME" run "$GC_ROUTE" "$dest/gcAsl.ll" || { echo "build.sh: asl-target-llvm/gcRoute did not write the collector module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/gcAsl.ll" -o "$dest/gcAsl.o" || { echo "build.sh: $CLANG did not compile the collector module" >&2; return 1; }
  abiFlag=""; [ "$MODE" = "--sanitize" ] && abiFlag="asan"
  env -u ASL_PRELUDE "$host/$HOST_NAME" run "$RT_ABI" "$dest/rtAbi.ll" $abiFlag || { echo "build.sh: asl-target-llvm/rtAbi did not write the runtime ABI module" >&2; return 1; }
  "$CLANG" -O2 -Wno-override-module -c -x ir "$dest/rtAbi.ll" -o "$dest/rtAbi.o" || { echo "build.sh: $CLANG did not compile the runtime ABI module" >&2; return 1; }
  rm -f "$dest/gcAsl.ll" "$dest/rtAbi.ll" "$dest/$RT_NAME"
  cp "$rtc" "$dest/$RT_NAME.tmp" && "$AR" rs "$dest/$RT_NAME.tmp" "$dest/rtAbi.o" "$dest/gcAsl.o" && mv -f "$dest/$RT_NAME.tmp" "$dest/$RT_NAME"
  rm -f "$dest/gcAsl.o" "$dest/rtAbi.o"
}

# (:m :why "a tree without the ASL packages (asl/host and asl/prelude copied alone) or a host without clang gets no libaslrt.a, said on stderr; asl build then reports it missing")
runtime_possible() {
  if [ ! -f "$GC_ROUTE" ]; then echo "build.sh: no $RT_NAME: $GC_ROUTE is absent" >&2; return 1; fi
  if [ ! -f "$RT_ABI" ]; then echo "build.sh: no $RT_NAME: $RT_ABI is absent" >&2; return 1; fi
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
  if runtime_possible; then runtime "$OUT" "$OUT/rtc.a" "$OUT"; fi
  rm -f "$OUT/rtc.a"
  exit 0
fi

KEY_DIR="$CACHE_DIR/$KEY"
if ! { [ -x "$KEY_DIR/$HOST_NAME" ] && [ -f "$KEY_DIR/$LIB_NAME" ] && [ -f "$KEY_DIR/rtc.a" ] && [ -f "$KEY_DIR/$TEST_RT_NAME" ]; }; then
  TMP_DIR="$CACHE_DIR/.tmp.$KEY.$$"
  mkdir -p "$TMP_DIR"
  trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
  do_compile "$TMP_DIR"

  mkdir -p "$KEY_DIR"
  mv -f "$TMP_DIR/$LIB_NAME" "$KEY_DIR/$LIB_NAME.tmp.$$"
  mv -f "$KEY_DIR/$LIB_NAME.tmp.$$" "$KEY_DIR/$LIB_NAME"
  mv -f "$TMP_DIR/rtc.a" "$KEY_DIR/rtc.a.tmp.$$"
  mv -f "$KEY_DIR/rtc.a.tmp.$$" "$KEY_DIR/rtc.a"
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
runtime_possible || exit 0
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
  runtime "$OUT" "$KEY_DIR/rtc.a" "$GC_TMP"
  mkdir -p "$GC_DIR"
  mv -f "$GC_TMP/$RT_NAME" "$GC_DIR/$RT_NAME.tmp.$$"
  mv -f "$GC_DIR/$RT_NAME.tmp.$$" "$GC_DIR/$RT_NAME"
  rm -rf "$GC_TMP"
  trap - EXIT INT TERM
fi
link_or_copy "$GC_DIR/$RT_NAME" "$OUT/$RT_NAME"
