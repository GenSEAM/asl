(module asl-sh/apmDaemonTest
  :d "Falsifiable test suite for APM Singleton Lock, Stream Framing, Supervisor, and 10s Watchdog."
  :x [runTests]
  :i [(apm      :a apm)
      (watchdog :a wd)])

(df testSingletonLock [] -> Bool
  :d "Verifies singleton lock acquisition, duplicate collision detection, and stale PID reclamation."
  (let [(vAcq (apm/resolveLock "/tmp/test.lock" 100 0 false))
        (vColl (apm/resolveLock "/tmp/test.lock" 200 100 true))
        (vStale (apm/resolveLock "/tmp/test.lock" 300 999 false))
        (vSelf (apm/resolveLock "/tmp/test.lock" 100 100 true))]
    (assert (.-acquired vAcq) "Fresh lock must be acquired")
    (assert (= (.-status vAcq) ":acquired") "Status must be :acquired")
    (assert (= (.-event vAcq) ":lock-acquired") "Event must be :lock-acquired")
    (refute (.-acquired vColl) "Collision must refuse lock acquisition")
    (assert (= (.-status vColl) ":collision") "Collision status must be :collision")
    (assert (= (.-event vColl) ":lock-refused") "Collision event must be :lock-refused")
    (assert (.-acquired vStale) "Stale lock must be reclaimed")
    (assert (= (.-status vStale) ":stale") "Stale lock status must be :stale")
    (assert (= (.-event vStale) ":lock-reclaimed") "Stale lock event must be :lock-reclaimed")
    (assert (.-acquired vSelf) "Self lock re-entry must be permitted")
    true))

(df testStreamFramingNewline [] -> Bool
  :d "Verifies ASNL newline-delimited stream frame extraction with parenthesis balance tracking."
  (let [(b1 "(:ping)\n(:next)\n")
        (r1 (apm/parseStreamFrame b1))
        (f1 (fst r1))
        (rem1 (snd r1))]
    (assert (is-some? f1) "First frame must be extracted")
    (mt f1
      ((some frame)
       (assert (= (.-payload frame) "(:ping)") "Frame payload must be (:ping)")
       (assert (= (.-kind frame) "newline") "Frame kind must be newline")
       (assert (.-valid frame) "Frame must be valid")
       (assert (= rem1 "(:next)\n") "Remaining buffer must preserve subsequent frames")
       (let [(r2 (apm/parseStreamFrame rem1))
             (f2 (fst r2))
             (rem2 (snd r2))]
         (assert (is-some? f2) "Second frame must be extracted")
         (mt f2
           ((some frame2)
            (assert (= (.-payload frame2) "(:next)") "Second frame payload must be (:next)")
            (assert (= rem2 "") "Remaining buffer after second frame must be empty")
            true)
           ((none) false))))
      ((none) false))))

(df testStreamFramingContentLength [] -> Bool
  :d "Verifies Content-Length header parsing and payload chunk delineation without packet tearing."
  (let [(header "Content-Length: 14\n\n(:ping :seq 1)TRAILING")
        (parsed (apm/parseStreamFrame header))
        (f (fst parsed))
        (rem (snd parsed))]
    (assert (is-some? f) "Content-Length frame must be parsed")
    (mt f
      ((some frame)
       (assert (= (.-kind frame) "content-length") "Frame kind must be content-length")
       (assert (= (.-length frame) 14) "Extracted length must be 14")
       (assert (= (.-payload frame) "(:ping :seq 1)") "Payload must match chunk length")
       (assert (= rem "TRAILING") "Remaining buffer must preserve trailing data")
       true)
      ((none) false))))

(df testSupervisor10sWatchdog [] -> Bool
  :d "Verifies that steps exceeding the 10s ceiling trigger worker recycling and :ERR_WATCHDOG_TIMEOUT."
  (let [(okVerdict (wd/checkStepDeadline 2500 10000))
        (timeoutVerdict (wd/checkStepDeadline 10001 10000))
        (supOk (apm/superviseStep 400 10000 ":ping"))
        (supTimeout (apm/superviseStep 10500 10000 ":exec-slow"))]
    (refute (.-timedOut okVerdict) "Step under 10s must not time out")
    (assert (= (.-errorCode okVerdict) ":none") "Normal step must have :none error code")
    (assert (.-timedOut timeoutVerdict) "Step over 10s must trigger watchdog timeout")
    (assert (= (.-errorCode timeoutVerdict) ":ERR_WATCHDOG_TIMEOUT") "Breached deadline must emit :ERR_WATCHDOG_TIMEOUT")
    (assert (= (.-event timeoutVerdict) ":step-timeout-recycled") "Breached deadline must emit :step-timeout-recycled")
    (assert (= (.-status supOk) ":ok") "Supervisor status for fast step must be :ok")
    (refute (.-workerRecycled supOk) "Supervisor must not recycle worker for fast step")
    (assert (= (.-status supTimeout) ":recycled") "Supervisor status on 10s timeout must be :recycled")
    (assert (= (.-exitCode supTimeout) 124) "Watchdog timeout exit code must be 124")
    (assert (= (.-errorCode supTimeout) ":ERR_WATCHDOG_TIMEOUT") "Supervisor error code must be :ERR_WATCHDOG_TIMEOUT")
    (assert (.-workerRecycled supTimeout) "Worker must be marked as recycled")
    true))

(df testIntrospectionTable [] -> Bool
  :d "Verifies diagnostic daemon inspection table formatting with DAEMON ID header."
  (let [(e1 (apm/makeDaemonEntry "751f1272" 14842 42 ":active" ":idle"))
        (tbl (apm/formatDaemonTable (list e1)))]
    (assert (string-contains? tbl "DAEMON ID") "Table must contain DAEMON ID header")
    (assert (string-contains? tbl "751f1272") "Table must contain daemon ID")
    (assert (string-contains? tbl "14842") "Table must contain PID")
    (assert (string-contains? tbl ":active") "Table must contain status")
    true))

(df testCountParenBalanceNegativeGuard [] -> Bool
  :d "Verifies that unmatched closing parentheses drive balance negative and prevent recovery."
  (let [(bInvalid (apm/countParenBalance ")("))
        (bValid (apm/countParenBalance "(:ok)"))
        (bExtraClose (apm/countParenBalance "())("))]
    (assert (< bInvalid 0) ")( must yield negative balance")
    (refute (apm/isBalancedFrame? ")(") ")( must not be considered balanced")
    (assert (= bValid 0) "(:ok) must have zero balance")
    (assert (apm/isBalancedFrame? "(:ok)") "(:ok) is balanced")
    (assert (< bExtraClose 0) "())( must yield negative balance")
    (refute (apm/isBalancedFrame? "())(") "())( is not balanced")
    true))

(df testStreamFramingMultiline [] -> Bool
  :d "Verifies ASNL stream framing accumulates multiline s-expressions without stalling."
  (let [(b1 "(:task\n  :name \"build\"\n  :timeout 5000)\n(:next)\n")
        (r1 (apm/parseStreamFrame b1))
        (f1 (fst r1))
        (rem1 (snd r1))]
    (assert (is-some? f1) "Multiline frame must be extracted")
    (mt f1
      ((some frame)
       (assert (= (.-payload frame) "(:task\n  :name \"build\"\n  :timeout 5000)") "Multiline payload matches")
       (assert (= (.-kind frame) "newline") "Frame kind is newline")
       (assert (.-valid frame) "Frame is valid")
       (assert (= rem1 "(:next)\n") "Remaining buffer preserved")
       (let [(r2 (apm/parseStreamFrame rem1))
             (f2 (fst r2))
             (rem2 (snd r2))]
         (assert (is-some? f2) "Next frame extracted")
         (mt f2
           ((some frame2)
            (assert (= (.-payload frame2) "(:next)") "Second frame payload is (:next)")
            (assert (= rem2 "") "Remaining buffer empty")
            true)
           ((none) false))))
      ((none) false))))

(df testOobDemuxerActiveRamBounded [] -> Bool
  :d "Verifies OobDemuxer bufferBytes tracks active RAM and is not monotonic across large stream throughput."
  (let [(d0 (apm/makeOobDemuxer "tmp/test-oob.spool" 67108864))
        (chunk "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n")
        (d300 (fold (fn [(demuxer apm/OobDemuxer) (_i Int64)] -> apm/OobDemuxer
                      (apm/oobDemuxChunk demuxer chunk))
                    d0
                    (range 0 300)))]
    (assert (= (.-totalBytes d300) 24300) "Total bytes reflects cumulative throughput (300 * 81)")
    (assert (<= (.-bufferBytes d300) 17000) "Active bufferBytes bounded by 200-line RAM ring buffer (<= 200 * 81)")
    (refute (.-isTerminated d300) "Demuxer is not terminated by cumulative throughput")
    true))

(df runTests [] -> Bool
  :d "Runs all APM daemon, singleton lock, stream framing, and watchdog supervisor tests."
  (let [(r1 (testSingletonLock))
        (r2 (testStreamFramingNewline))
        (r3 (testStreamFramingContentLength))
        (r4 (testSupervisor10sWatchdog))
        (r5 (testIntrospectionTable))
        (r6 (testCountParenBalanceNegativeGuard))
        (r7 (testStreamFramingMultiline))
        (r8 (testOobDemuxerActiveRamBounded))]
    (assert r1 "testSingletonLock failed")
    (assert r2 "testStreamFramingNewline failed")
    (assert r3 "testStreamFramingContentLength failed")
    (assert r4 "testSupervisor10sWatchdog failed")
    (assert r5 "testIntrospectionTable failed")
    (assert r6 "testCountParenBalanceNegativeGuard failed")
    (assert r7 "testStreamFramingMultiline failed")
    (assert r8 "testOobDemuxerActiveRamBounded failed")
    true))
