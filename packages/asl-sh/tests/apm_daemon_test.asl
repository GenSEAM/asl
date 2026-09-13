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

(df runTests [] -> Bool
  :d "Runs all APM daemon, singleton lock, stream framing, and watchdog supervisor tests."
  (and (testSingletonLock)
       (and (testStreamFramingNewline)
            (and (testStreamFramingContentLength)
                 (and (testSupervisor10sWatchdog)
                      (testIntrospectionTable))))))
