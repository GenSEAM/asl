(module asl-forms/tests/evalTimeoutTest :x [runTests] :i [(asl-forms/evalOp :a ev)])

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (tmp (str root "/evalTimeoutTest-" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (cache (str tmp "/cache"))
        (created (dirCreate cache))]
    (mt created
      ((err e) (do (assert false (str "create the cold native cache " cache ": " e)) false))
      ((ok _)
        (let [(kw (mapSet (mapSet (mapEmpty) "nativeTestCache" cache) "timeoutMs" "1000"))
              (t0 (monotonicNs))
              (result (ev/evalStep! root 1 kw (list "1")))
              (elapsedMs (/ (- (monotonicNs) t0) 1000000))
              (cached (resultOr (dirList cache) (list)))
              (removed (pathRemove tmp))]
          (do
            (assert (and (= (pairSecond result) 0) (stringContains? (pairFirst result) ":value \"1\""))
                    (str "a cold native eval succeeds under a 1000 ms evaluation timeout: " (pairFirst result) " :exit " (stringFromInt64 (pairSecond result))))
            (assert (not (listEmpty? cached)) "the eval was built cold into the configured native cache")
            (assert (> elapsedMs 1000) (str "the cold build took longer than the evaluation timeout and was not charged to it: " (stringFromInt64 elapsedMs) " ms"))
            (assert (ok? removed) (str "remove " tmp))
            true)))))
