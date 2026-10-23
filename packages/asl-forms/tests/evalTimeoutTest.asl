(module asl-forms/tests/evalTimeoutTest :x [runTests] :i [(asl-forms/evalOp :a ev)])

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (tmp (str root "/evalTimeoutTest-" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (cache (str tmp "/cache"))
        (created (dirCreate cache))]
    (match created
      ((err e) (do (assert false (str "create the cold native cache " cache ": " e)) false))
      ((ok _)
        (let [(okKw (mapSet (mapSet (mapEmpty) "nativeTestCache" cache) "timeoutMs" "2000"))
              (trapKw (mapSet (mapSet (mapSet (mapEmpty) "nativeTestCache" cache) "timeoutMs" "1000") "code" "(do (sleepMs 30000) \"late\")"))
              (t00 (monotonicNs))
              (result (ev/evalStep! root 1 okKw (list "1")))
              (elapsedMs (/ (- (monotonicNs) t00) 1000000))
              (cached (resultOr (dirList cache) (list)))
              (trap (ev/evalStep! root 2 trapKw (list)))
              (removed (pathRemove tmp))]
          (do
            (assert (and (= (pairSecond result) 0) (stringContains? (pairFirst result) ":value \"1\""))
                    (str "a cold native eval of a trivial form succeeds under a 2000 ms timeout: " (pairFirst result) " :exit " (stringFromInt64 (pairSecond result))))
            (assert (not (listEmpty? cached)) "the eval was built cold into the configured native cache")
            (assert (> elapsedMs 2000) (str "the cold build (about 3.4 s measured, run about 80 ms) outlasted the 2000 ms timeout and was not charged to it: " (stringFromInt64 elapsedMs) " ms"))
            (assert (stringContains? (pairFirst trap) ":error :ERR_TIMEOUT :timeoutMs 1000")
                    (str "an over-budget eval ends in ERR_TIMEOUT with the configured budget: " (pairFirst trap)))
            (assert (not (stringContains? (pairFirst trap) "late")) "the over-budget eval was cut off before it printed")
            (assert (ok? removed) (str "remove " tmp))
            true)))))
