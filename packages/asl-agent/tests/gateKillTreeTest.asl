(module aslAgent/tests/gateKillTreeTest
  :x [runTests]
  :i [(aslAgent/gitOps :a g) (asl-tools/fleet/run :a fr)])

; (:m :ref AGENTLOOP-GATE-KILLTREE :do "a gate CLI (sh) starts a child in its own process group (setsid(1), pgid = pid; skipped without an assert where there is none: macOS), as nativeTest starts a compiled test binary, and waits on it; the gate's 3 s timeout must leave no survivor. The fixture writes the child's pid and pgid into its own dir under .asl/cache; a child the kill missed is SIGKILLed in cleanup")
; (:m :ref NODE-AGENT-BASE-REDS :do "the gate runs in an OS sandbox with its own pid namespace on Linux (bwrap --unshare-pid), so the pid its shell records is the namespace's own (3 there), and a lookup of that number in the host's process table finds a kernel thread: the test read a live pid 3 for a child that was dead. The child now proves it is alive by its own heartbeat file, which no pid namespace changes: it counts into child.beat every 0.1 s for at most 60 s (self-bounded, no cleanup by pid), and the test asks whether the count still moves after the gate returned")
fn ! readInt! path: String -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString path) ""))) -1)

; (:m :ref NODE-AGENT-BASE-REDS :do "only where setsid(1) exists (Linux): under the macOS sandbox profile the perl setsid and ps the fixture needs do not run, so the case is skipped there as before")
fn ! ownGroup -> String
  (if (fileExists? "/usr/bin/setsid") "setsid" "")

fn ! testOwnGroupChild -> Bool
  (if (stringEmpty? (ownGroup)) (do (println "(:skip :case testOwnGroupChild :why noSetsid)") true)
    (let [(dir (str (resultOr (realPath ".") ".") "/.asl/cache/gateKillTree." (procSelf)))
          (_ (dirCreate dir))
          (cmd (str (ownGroup) " sh -c 'i=0; while [ $i -lt 600 ]; do i=$((i+1)); echo $i > child.beat; sleep 0.1; done' & p=$!; i=0; while [ \"$(ps -o pgid= -p $p | tr -d ' ')\" != \"$p\" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; ps -o pgid= -p $p > child.pgid; echo $p > child.pid; wait"))
          (rows (g/runGates! (list (pair "1" cmd)) dir 3 (none) (none)))
          (row (optionOr (listHead rows) (list)))
          (timedOut (listAny? (fn [(kv (Pair String g/RVal))] -> Bool (= (pairFirst kv) "timeout")) row))
          (pid (readInt! (str dir "/child.pid")))
          (pgid (readInt! (str dir "/child.pgid")))
          (_ (sleepMs 300))
          (beat1 (readInt! (str dir "/child.beat")))
          (_ (sleepMs 600))
          (beat2 (readInt! (str dir "/child.beat")))
          (left (!= beat1 beat2))
          (_ (pathRemove (str dir "/child.pid")))
          (_ (pathRemove (str dir "/child.pgid")))
          (_ (pathRemove (str dir "/child.beat")))
          (gone (pathRemove dir))]
      (do (assert (> pid 1) (str "the gate's child started and recorded its pid: " pid))
          (assert (= pgid pid) (str "the child leads its own process group, as a compiled test binary does: pgid " pgid " pid " pid))
          (assert timedOut "the gate is reported as timed out at its 3 s deadline")
          (assert (> beat1 0) (str "the child had started its heartbeat: " beat1))
          (assert (not left) (str "the own-group child under the timed-out gate is killed with it: its heartbeat moved from " beat1 " to " beat2 " after the gate returned"))
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
        (cmd "printf 'own\\n(:fleetRun :verdict :fake)\\n' >&2; sleep 1; for i in 1 2 3 4 5 6; do sh -c 'j=0; while [ $j -lt 310 ]; do j=$((j+1)); echo $j > kid$0.beat; sleep 0.1; done' $i & done; wait")
        (rows (g/runGates! (list (pair "1" cmd)) dir 60 (none) (none)))
        (row (optionOr (listHead rows) (list)))
        (kids (list "1" "2" "3" "4" "5" "6"))
        (_ (sleepMs 300))
        (beats1 (map (fn [(k String)] -> Int64 (readInt! (str dir "/kid" k ".beat"))) kids))
        (_ (sleepMs 600))
        (beats2 (map (fn [(k String)] -> Int64 (readInt! (str dir "/kid" k ".beat"))) kids))
        (moved (if (= (stringJoin (map stringFromInt64 beats1) ",") (stringJoin (map stringFromInt64 beats2) ",")) 0 1))
        (_ (map (fn [(k String)] -> Bool (ok? (pathRemove (str dir "/kid" k ".beat")))) kids))
        (_ (pathRemove cfg))
        (gone (pathRemove dir))]
    (do (assert (= (textOf row "guard") "maxDesc") (str "a gate over the configured descendant limit is recorded as (guard maxDesc): " (textOf row "guard") " exit " (textOf row "exit")))
        (assert (= (textOf row "maxDescendants") "3") (str "the record carries the configured limit: " (textOf row "maxDescendants")))
        (assert (not (hasKey? row "timeout")) "a descendant-limit kill is not reported as a timeout")
        (assert (stringContains? (textOf row "stderr") "(:guard :maxDesc :limit 3)") (str "the gate's stderr, which the receipt shows, says why it was killed: " (textOf row "stderr")))
        (assert (stringContains? (textOf row "stderr") "(:fleetRun :verdict :fake)") (str "only the guard's own last note is stripped, a gate line that looks like one stays: " (textOf row "stderr")))
        (assert (listAny? (fn [(b Int64)] -> Bool (> b 0)) beats1) (str "some child had started its heartbeat before the kill: " (stringJoin (map stringFromInt64 beats1) " ")))
        (assert (= moved 0) (str "the gate's children die with it, none of their heartbeats moves after the gate returned: " (stringJoin (map stringFromInt64 beats1) " ") " then " (stringJoin (map stringFromInt64 beats2) " ")))
        (assert (ok? gone) "the fixture dir is removed")
        true))

; (:m :ref AGENTLOOP-GATE-KILLTREE-FIX :do "a gate that prints a line looking like a guard verdict and exits 0 by itself is not a timeout: its exit code is kept, no guard field is set and its stderr is kept whole (grader memsweep's probe)")
fn ! testOwnVerdictLine -> Bool
  (let [(rows (g/runGates! (list (pair "1" "printf 'x\\n(:fleetRun :verdict :timeout)\\n(:fleetRun :verdict :runaway)\\n' >&2; exit 0")) "." 60 (none) (none)))
        (row (optionOr (listHead rows) (list)))]
    (do (assert (not (hasKey? row "timeout")) (str "a gate that exits 0 and prints a guard-looking line is not a timeout: exit " (textOf row "exit")))
        (assert (= (textOf row "exit") "0") (str "its exit code is kept: " (textOf row "exit")))
        (assert (not (hasKey? row "guard")) (str "no guard verdict is recorded: " (textOf row "guard")))
        (assert (stringEndsWith? (textOf row "stderr") "(:fleetRun :verdict :timeout)\n(:fleetRun :verdict :runaway)\n") (str "its stderr is kept whole: " (textOf row "stderr")))
        true))

fn ! runTests -> Bool
  (do (assert (testOwnGroupChild) "a timed-out gate leaves no own-group child alive")
      (assert (testMaxDescGuard) "a gate over the configured descendant limit is killed and says so")
      (assert (testOwnVerdictLine) "a gate's own verdict-looking line is not a guard verdict")
      true)
