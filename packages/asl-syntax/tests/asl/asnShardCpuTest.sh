#!/bin/sh
set -u

ulimit -t 240

host=${ASL_HOST:-asl/host/out/asl-host}
asserts=0
failed=0

# (:m :why "each call is one real gate assertion")
check() {
  asserts=$((asserts + 1))
  if [ "$1" -ne 0 ]; then
    failed=$((failed + 1))
    echo "FAIL $2"
  fi
}

run_shard() {
  out=$("$host" test "$1" 2>&1)
  code=$?
  n=$(printf '%s\n' "$out" | sed -n 's/^.*: \([0-9][0-9]*\) assertion(s) executed (\([0-9][0-9]*\) passed)$/\1 \2/p' | tail -1)
  check "$code" "$1 exits 0 within the CPU cap (exit $code)"
  set -- "$1" $n
  if [ $# -eq 3 ] && [ "$2" -gt 0 ] && [ "$2" -eq "$3" ]; then ok=0; else ok=1; fi
  check "$ok" "$1 reports a positive assertion count, all passed"
}

run_shard asl/packages/asl-syntax/tests/asl/asnShard1Test.asl
run_shard asl/packages/asl-syntax/tests/asl/asnShard2Test.asl
printf '(:gate :name asnShardCpu :asserts %s :failed %s)\n' "$asserts" "$failed"
test "$failed" -eq 0
