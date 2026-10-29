(module asl-parser/tests/printHostValidKillTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref STRAY-CHK-PRINT :do "a print-host-valid shard is killed as soon as one of its printed copies exists, so the kill lands between create and remove; every descendant and its group are stopped first, then SIGKILLed, since the native test binary runs in a group of its own and killing the shell job group alone left it writing. A second shard is started and killed the same way; the copies the first left must be gone by then. The script is bounded by the guard's timeout and reaps the shard tree on every exit")
fn ! work -> String
  (str "/tmp/aslChkPrintKill." (stringFromInt64 (procSelf)))

fn shard -> String
  "asl/packages/asl-parser/tests/printHostValidShard4Test.asl"

fn ! script marker: String -> String
  (str "tree() { for c in $(pgrep -P $1); do echo $c; (tree $c); done; }; "
       "reap() { [ -n \"$p\" ] || return 0; ps=\"$(tree $p) $p\"; for x in $ps; do kill -STOP $x 2>/dev/null; done; for x in $ps; do kill -9 -$x 2>/dev/null; kill -9 $x 2>/dev/null; done; p=; }; "
       "strays() { find asl tests tools -name '.asl_chk_print_*' -newer '" marker "' 2>/dev/null | sort; }; "
       "round() { set -m; env -u ASL_ROOT -u ASL_PRELUDE ./bin/asl test " (shard) " >/dev/null 2>&1 & p=$!; set +m; i=0; seen=; "
       "while [ $i -lt 6000 ] && kill -0 $p 2>/dev/null; do i=$((i+1)); seen=$(strays | grep -v -x -F \"$1\" | head -1); [ -n \"$seen\" ] && break; sleep 0.1; done; reap; sleep 1; }; "
       "trap reap EXIT; touch '" marker "'; sleep 1; "
       "round ''; first=$(strays); echo \"seen1=$seen\"; echo \"first=$(echo $first)\"; "
       "round \"$first\"; echo \"seen2=$seen\"; "
       "kept=; for f in $first; do [ -e \"$f\" ] && kept=\"$kept $f\"; done; echo \"kept=$kept\"; "
       "echo \"left=$(strays | tr '\\n' ' ')\"")

fn ! fieldOf out: String key: String -> String
  (match (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l (str key "="))) (stringLines out)))
    ((some l) (stringTrim (optionOr (stringSlice l (+ (stringLength key) 1) (stringLength l)) "")))
    ((none) "<absent>"))

fn present? v: String -> Bool
  (not (or (stringEmpty? v) (= v "<absent>")))

fn ! runTests -> Bool
  (let [(dir (work))
        (made (dirCreate dir))
        (marker (str dir "/marker"))
        (out (fr/runGuarded (list "/bin/sh" "-c" (script marker)) "." (fr/childEnv (list)) (fr/limits 1500 64)))
        (first (fieldOf out.stdout "first"))
        (kept (fieldOf out.stdout "kept"))
        (left (fieldOf out.stdout "left"))
        (_ (map (fn [(p String)] -> Bool (ok? (pathRemove p))) (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit left " "))))
        (removed (pathRemove dir))]
    (do (assert (ok? made) "work dir created")
        (assert (= out.exitCode 0) (str "the kill script ran to its end: exit " (stringFromInt64 out.exitCode) " " out.stderr))
        (assert (present? (fieldOf out.stdout "seen1")) (str "the first shard was killed mid-check: " out.stdout))
        (assert (present? first) (str "and left its printed copy in the tree, as a kill must: " out.stdout))
        (assert (present? (fieldOf out.stdout "seen2")) (str "the second shard was killed mid-check too: " out.stdout))
        (assert (not (present? kept)) (str "a shard starting after a killed one removes the copies the killed one left: " kept))
        (assert (ok? removed) "work dir removed")
        true))
