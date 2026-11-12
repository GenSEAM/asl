(module asl-forms/tests/writeRejectAllErrorsTest
  :x [runTests]
  :i [(asl-forms/gate :a g)])

fn badSource -> String
  "(module probe :x [missingFn present] :i [])\n\nfn present -> Int64\n  (+ 1 \"x\")\n\nfn other -> Int64\n  (nope 1)\n"

fn ! runTests -> Bool
  (let [(base (resultOr (realPath ".") "."))
        (root (str base "/writeRejectAllErrorsTest-" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (file (str root "/probe.asl"))
        (text (badSource))
        (made (ok? (dirCreate root)))
        (r (if made (g/checkOnce! root file "probe.asl" text) (pair "skipped" "")))
        (status (pairFirst r))
        (msg (pairSecond r))
        (removed (pathRemove root))]
    (do
      (assert made (str "create the scratch module " file))
      (assert (ok? removed) (str "remove the scratch module " root))
      (assert (= status "error") (str "checkOnce! rejects the module: " status " " msg))
      (assert (stringContains? msg "ERR_UNDEFINED_EXPORT") (str "the result names the undefined export: " msg))
      (assert (stringContains? msg "ERR_UNKNOWN_SYMBOL") (str "the result names the unknown symbol: " msg))
      (assert (stringContains? msg "ERR_TYPE") (str "the result names the type error: " msg))
      true))
