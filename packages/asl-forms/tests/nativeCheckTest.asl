(module asl-forms/tests/nativeCheckTest :x [runTests] :i [(asl-forms/ops :a ops)])

fn joined o: ops/StepOutcome -> String
  (stringJoin o.lines "\n")

fn ! step! root: String form: String -> ops/StepOutcome
  (ops/runStep! root 1 form)

fn goodSource -> String
  "(module good :x [f])\n\nfn f -> Int64\n  1\n"

fn badSource -> String
  "(module bad :x [f])\n\nfn f -> Int64\n  (+ 1 undefinedThing)\n"

fn ! checks! root: String -> (List (Pair Bool String))
  (let [(good (step! root "(:check :file \"good.asl\")"))
        (bad (step! root "(:check :file \"bad.asl\")"))
        (unbound (step! root "(:edit :file \"good.asl\" :old \"  1\" :new \"  (+ 1 undefinedThing)\")"))
        (afterUnbound (step! root "(:check :file \"good.asl\")"))
        (bound (step! root "(:edit :file \"good.asl\" :old \"  1\" :new \"  2\")"))
        (staged (step! root "(:check :file \"good.asl\")"))
        (discarded (step! root "(:discard)"))]
    (list
      (pair (= good.errCount 0) (str "(:check) passes a well-typed file natively: " (joined good)))
      (pair (stringContains? (joined good) ":valid true") (str "(:check) on a good file reports :valid true: " (joined good)))
      (pair (stringContains? (joined good) ":checker \"asl-checker\"") (str "(:check) names the native checker: " (joined good)))
      (pair (= bad.errCount 1) (str "(:check) rejects a file with an unbound symbol: " (joined bad)))
      (pair (stringContains? (joined bad) "ERR_CHECK_FAILED") (str "(:check) on a bad file is ERR_CHECK_FAILED: " (joined bad)))
      (pair (stringContains? (joined bad) "ERR_UNKNOWN_SYMBOL") (str "(:check) on a bad file carries the checker's ERR_UNKNOWN_SYMBOL: " (joined bad)))
      (pair (not (stringContains? (joined bad) "ERR_HOST_ABSENT")) "(:check) never needs the stage-0 host")
      (pair (= unbound.errCount 1) (str "(:edit) adding an unbound symbol is rejected: " (joined unbound)))
      (pair (stringContains? (joined unbound) "ERR_UNKNOWN_SYMBOL") (str "the edit rejection carries ERR_UNKNOWN_SYMBOL: " (joined unbound)))
      (pair (not (stringContains? (joined unbound) ":staged true")) "a rejected edit stages nothing")
      (pair (stringContains? (joined afterUnbound) ":source :disk") (str "after the rejected edit the file is still read from disk: " (joined afterUnbound)))
      (pair (= bound.errCount 0) (str "(:edit) keeping the file well-typed is staged: " (joined bound)))
      (pair (stringContains? (joined bound) ":syntax :ok :checker \"asl-checker\"") (str "the staged edit was checked natively: " (joined bound)))
      (pair (stringContains? (joined staged) ":source :staged :valid true") (str "(:check) validates the staged content: " (joined staged)))
      (pair (= discarded.errCount 0) (str "(:discard) drops the staged edit: " (joined discarded)))))

fn ! runTests -> Bool
  (let [(base (resultOr (realPath ".") "."))
        (root (str base "/nativeCheckTest-" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (made (and (ok? (dirCreate (str root "/.asl")))
                   (and (ok? (fileWrite (str root "/good.asl") (goodSource)))
                        (ok? (fileWrite (str root "/bad.asl") (badSource))))))
        (results (if made (checks! root) (list)))
        (removed (pathRemove root))]
    (do
      (assert made (str "create the scratch workspace " root))
      (assert (ok? removed) (str "remove the scratch workspace " root))
      (assert (= (listLength results) 15) "all fifteen claims were evaluated")
      (listAll? (fn [(r (Pair Bool String))] -> Bool (do (assert (pairFirst r) (pairSecond r)) true)) results)))
