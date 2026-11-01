(module asl/agentLoop/tests/gateKillTreeTest
  :x [runTests]
  :i [(asl/agentLoop/gitOps :a g) (asl-tools/fleet/run :a fr)])

; (:m :ref AGENTLOOP-GATE-KILLTREE :do "a gate CLI (sh) starts a child in its own process group (setsid(1), pgid = pid; skipped without an assert where there is none: macOS), as nativeTest starts a compiled test binary, and waits on it; the gate's 3 s timeout must leave no survivor. The fixture writes the child's pid and pgid into its own dir under .asl/cache; a child the kill missed is SIGKILLed in cleanup")
fn ! alive? pid: Int64 -> Bool
  (listAny? (fn [(p fr/Proc)] -> Bool (= p.pid pid)) (fr/procSnapshot))

fn ! readInt! path: String -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString path) ""))) -1)

fn ! testOwnGroupChild -> Bool
  (if (not (fileExists? "/usr/bin/setsid")) (do (println "(:skip :case testOwnGroupChild :why noSetsid)") true)
    (let [(dir (str (resultOr (realPath ".") ".") "/.asl/cache/gateKillTree." (procSelf)))
          (_ (dirCreate dir))
          (cmd "setsid sleep 77 & p=$!; i=0; while [ \"$(ps -o pgid= -p $p | tr -d ' ')\" != \"$p\" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; ps -o pgid= -p $p > child.pgid; echo $p > child.pid; wait")
          (rows (g/runGates! (list (pair "1" cmd)) dir 3 (none) (none)))
          (row (optionOr (listHead rows) (list)))
          (timedOut (listAny? (fn [(kv (Pair String g/RVal))] -> Bool (= (pairFirst kv) "timeout")) row))
          (pid (readInt! (str dir "/child.pid")))
          (pgid (readInt! (str dir "/child.pgid")))
          (_ (sleepMs 300))
          (left (and (> pid 1) (alive? pid)))
          (_ (if left (do (procKill pid "SIGKILL") ()) ()))
          (_ (pathRemove (str dir "/child.pid")))
          (_ (pathRemove (str dir "/child.pgid")))
          (gone (pathRemove dir))]
      (do (assert (> pid 1) (str "the gate's child started and recorded its pid: " pid))
          (assert (= pgid pid) (str "the child leads its own process group, as a compiled test binary does: pgid " pgid " pid " pid))
          (assert timedOut "the gate is reported as timed out at its 3 s deadline")
          (assert (not left) (str "the own-group child under the timed-out gate is killed with it: pid " pid " left alive"))
          (assert (ok? gone) "the fixture dir is removed")
          true)))

fn hasKey? row: (List (Pair String g/RVal)) key: String -> Bool
  (listAny? (fn [(kv (Pair String g/RVal))] -> Bool (= (pairFirst kv) key)) row)

fn textOf row: (List (Pair String g/RVal)) key: String -> String
  (match (listHead (filter (fn [(kv (Pair String g/RVal))] -> Bool (= (pairFirst kv) key)) row))
    ((none) "")
    ((some kv) (match (pairSecond kv) ((g/rStr s) s) ((g/rInt n) (stringFromInt64 n)) (_ ""))))

; (:m :ref AGENTLOOP-GATE-KILLTREE :do "a run root whose .asl.config.asn sets :agentLoop :gateMaxDescendants 3 and a gate that prints a line looking like a guard note, waits 1 s so the pump has read it (output written in the same instant as a kill is not drained by fr), then starts six sleeps: the guard kills the gate at the limit, long before its 60 s timeout, and the record says (guard maxDesc) with the limit, not timeout; the sleeps die with it")
fn ! testMaxDescGuard -> Bool
  (let [(dir (str (resultOr (realPath ".") ".") "/.asl/cache/gateMaxDesc." (procSelf)))
        (_ (dirCreate dir))
        (cfg (str dir "/.asl.config.asn"))
        (_ (fileWrite cfg "(:workspace\n  :agentLoop (:gateMaxDescendants 3))\n"))
        (cmd "printf 'own\\n(:fleetRun :verdict :fake)\\n' >&2; sleep 1; for i in 1 2 3 4 5 6; do sleep 31 & echo $! >> kids.pid; done; wait")
        (rows (g/runGates! (list (pair "1" cmd)) dir 60 (none) (none)))
        (row (optionOr (listHead rows) (list)))
        (kids (filter (fn [(p Int64)] -> Bool (> p 1)) (map (fn [(l String)] -> Int64 (optionOr (stringToInt64 (stringTrim l)) -1)) (stringLines (resultOr (fileReadString (str dir "/kids.pid")) "")))))
        (_ (sleepMs 300))
        (left (filter alive? kids))
        (_ (map (fn [(p Int64)] -> Bool (do (procKill p "SIGKILL") true)) left))
        (_ (pathRemove (str dir "/kids.pid")))
        (_ (pathRemove cfg))
        (gone (pathRemove dir))]
    (do (assert (= (textOf row "guard") "maxDesc") (str "a gate over the configured descendant limit is recorded as (guard maxDesc): " (textOf row "guard") " exit " (textOf row "exit")))
        (assert (= (textOf row "maxDescendants") "3") (str "the record carries the configured limit: " (textOf row "maxDescendants")))
        (assert (not (hasKey? row "timeout")) "a descendant-limit kill is not reported as a timeout")
        (assert (stringContains? (textOf row "stderr") "(:guard :maxDesc :limit 3)") (str "the gate's stderr, which the receipt shows, says why it was killed: " (textOf row "stderr")))
        (assert (stringContains? (textOf row "stderr") "(:fleetRun :verdict :fake)") (str "only the guard's own last note is stripped, a gate line that looks like one stays: " (textOf row "stderr")))
        (assert (listEmpty? left) (str "the gate's sleeps die with it: " (stringJoin (map stringFromInt64 left) " ")))
        (assert (ok? gone) "the fixture dir is removed")
        true))

fn ! runTests -> Bool
  (do (assert (testOwnGroupChild) "a timed-out gate leaves no own-group child alive")
      (assert (testMaxDescGuard) "a gate over the configured descendant limit is killed and says so")
      true)
