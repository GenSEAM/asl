(module asl-cli/tests/watchTest :x [runTests] :i [(asl-cli/watch :a w) (asl-compiler/salsa :a salsa)])

fn testWatchStep! -> Bool
  (let [(db (salsa/makeSalsaDatabase 10))
        (ws (w/watchInit db "test.asl"))
        (stepRes (w/watchStep! ws "test.asl" "Math:add" "(fn add [(a Int) (b Int)] -> Int (+ a b))"))
        (nextWs (pairFirst stepRes))
        (rcpt (pairSecond stepRes))]
    (assert (= rcpt.status "ok") "watchStep status is ok")
    (assert (= rcpt.mutatedSymbol "Math:add") "watchStep mutatedSymbol matches")
    (assert (>= rcpt.latencyMicros 0) "watchStep latency non-negative")
    (assert (= nextWs.activeEpoch (+ ws.activeEpoch 1)) "epoch increments on step")
    true)

fn testWatchLoop! -> Bool
  (let [(db (salsa/makeSalsaDatabase 10))
        (ws (w/watchInit db "test.asl"))
        (rcpt (w/watchLoop! ws 3))]
    (assert (= rcpt.status "ok") "watchLoop status is ok")
    (assert (= rcpt.mutatedSymbol "LoopComplete") "watchLoop completed")
    (assert (= rcpt.recomputedCount 3) "watchLoop 3 cycles recomputed")
    (assert (>= rcpt.latencyMicros 0) "watchLoop latency non-negative")
    true)

fn ! runTests -> Bool
  (and (testWatchStep!) (testWatchLoop!))
