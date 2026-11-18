(module asl-tools/coord/docRowsGate
  :x [main]
  :i [(asl-tools/coord/conductor :a cd)])

; (:m :ref COND-WORK-PRESENT :do "docRowsGate.asl WT BASE: the fix-round writer's gate for a docRows failure; it runs docRowsCheckAt! on the worktree against the base, prints the red message and exits 1 when the unit's new exported symbols lack their contract rows, else prints one assert line and exits 0")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(wt (optionOr (listGet args 0) "."))
        (base (optionOr (listGet args 1) "main"))
        (r (cd/docRowsCheckAt! wt base 300))
        (msg (pairFirst r))]
    (if (stringContains? (pairSecond r) ":why infra")
      (do (println "(:gate :asserts 1 :failed 1)") (println (str "gateInfra: docRows could not run " (pairSecond r))) (ok 2))
    (if (stringEmpty? msg)
      (do (println "(:gate :asserts 1 :failed 0)") (println "assert docRows: no new exported symbol lacks its contract row") (ok 0))
      (do (println "(:gate :asserts 1 :failed 1)") (println (str "FAIL docRows: " msg)) (ok 1)))))
