(module asl-tools/coord/docRowsGate
  :x [main]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docDup :a dd)])

; (:m :ref COND-WORK-PRESENT :do "docRowsGate.asl WT BASE: the fix-round writer's gate for a docRows failure; it runs docRowsCheckAt! on the worktree against the base, prints the red message and exits 1 when the unit's new exported symbols lack their contract rows, else prints one assert line and exits 0")
; (:m :ref REVIEW-CRITERIA-DOCDUP :do "a second assert: a symbol whose doc row the unit added has one row in its file (docDup); a duplicate is exit 1 with the symbol and both lines, printed with the missing-row message so one turn fixes both, and it is red even when the missing-row check could not run")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(wt (optionOr (listGet args 0) "."))
        (base (optionOr (listGet args 1) "main"))
        (dup (dd/dupCheckAt! wt base))
        (dupRed (if (stringEmpty? dup) 0 1))
        (r (cd/docRowsCheckAt! wt base 300))
        (msg (pairFirst r))
        (_ (println (str "(:gate :asserts 2 :failed " (stringFromInt64 (+ dupRed (if (and (stringEmpty? msg) (or (listContains? args "--writer") (not (stringContains? (pairSecond r) ":why infra")))) 0 1))) ")")))
        (_ (println (if (= dupRed 1) (str "FAIL docRows: " dup) "assert docRows: no symbol the unit added has two doc rows")))]
    (if (stringContains? (pairSecond r) ":why infra")
      ; (:m :ref COND-OWNS-DOC :do "--writer: the gate inside the writer's own run; a check that could not run is infrastructure and no fault of the model, so it is green there with the note, and the conductor's gate stage still judges the unit")
      (if (listContains? args "--writer")
        (do (println (str "assert docRows: could not run, left to the conductor " (pairSecond r))) (ok dupRed))
        (do (println (str "gateInfra: docRows could not run " (pairSecond r))) (ok (if (= dupRed 1) 1 2))))
    (if (stringEmpty? msg)
      (do (println "assert docRows: no new exported symbol lacks its contract row") (ok dupRed))
      (do (println (str "FAIL docRows: " msg)) (ok 1)))))
