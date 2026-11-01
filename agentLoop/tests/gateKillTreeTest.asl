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

fn ! runTests -> Bool
  (do (assert (testOwnGroupChild) "a timed-out gate leaves no own-group child alive")
      true)
