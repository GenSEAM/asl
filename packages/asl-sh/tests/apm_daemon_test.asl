(module asl-sh/apm-daemon-test
  :d "Falsifiable test suite for APM Singleton Lock, Stream Framing, Supervisor, and 10s Watchdog."
  :x [run-tests]
  :i [(apm      :a apm)
      (watchdog :a wd)])

(df test-singleton-lock [] -> Bool
  :d "Verifies singleton lock acquisition, duplicate collision detection, and stale PID reclamation."
  (let [(v-acq (apm/resolve-lock "/tmp/test.lock" 100 0 false))
        (v-coll (apm/resolve-lock "/tmp/test.lock" 200 100 true))
        (v-stale (apm/resolve-lock "/tmp/test.lock" 300 999 false))
        (v-self (apm/resolve-lock "/tmp/test.lock" 100 100 true))]
    (assert (.-acquired v-acq) "Fresh lock must be acquired")
    (assert (= (.-status v-acq) ":acquired") "Status must be :acquired")
    (assert (= (.-event v-acq) ":lock-acquired") "Event must be :lock-acquired")
    (assert (not (.-acquired v-coll)) "Collision must refuse lock acquisition")
    (assert (= (.-status v-coll) ":collision") "Collision status must be :collision")
    (assert (= (.-event v-coll) ":lock-refused") "Collision event must be :lock-refused")
    (assert (.-acquired v-stale) "Stale lock must be reclaimed")
    (assert (= (.-status v-stale) ":stale") "Stale lock status must be :stale")
    (assert (= (.-event v-stale) ":lock-reclaimed") "Stale lock event must be :lock-reclaimed")
    (assert (.-acquired v-self) "Self lock re-entry must be permitted")
    true))

(df test-stream-framing-newline [] -> Bool
  :d "Verifies ASNL newline-delimited stream frame extraction with parenthesis balance tracking."
  (let [(b1 "(:ping)\n(:next)\n")
        (r1 (apm/parse-stream-frame b1))
        (f1 (fst r1))
        (rem1 (snd r1))]
    (assert (option-is-some? f1) "First frame must be extracted")
    (mt f1
      ((some frame)
       (assert (= (.-payload frame) "(:ping)") "Frame payload must be (:ping)")
       (assert (= (.-kind frame) "newline") "Frame kind must be newline")
       (assert (.-valid frame) "Frame must be valid")
       (assert (= rem1 "(:next)\n") "Remaining buffer must preserve subsequent frames")
       (let [(r2 (apm/parse-stream-frame rem1))
             (f2 (fst r2))
             (rem2 (snd r2))]
         (assert (option-is-some? f2) "Second frame must be extracted")
         (mt f2
           ((some frame2)
            (assert (= (.-payload frame2) "(:next)") "Second frame payload must be (:next)")
            (assert (= rem2 "") "Remaining buffer after second frame must be empty")
            true)
           ((none) false))))
      ((none) false))))

(df test-stream-framing-content-length [] -> Bool
  :d "Verifies Content-Length header parsing and payload chunk delineation without packet tearing."
  (let [(header "Content-Length: 14\n\n(:ping :seq 1)TRAILING")
        (parsed (apm/parse-stream-frame header))
        (f (fst parsed))
        (rem (snd parsed))]
    (assert (option-is-some? f) "Content-Length frame must be parsed")
    (mt f
      ((some frame)
       (assert (= (.-kind frame) "content-length") "Frame kind must be content-length")
       (assert (= (.-length frame) 14) "Extracted length must be 14")
       (assert (= (.-payload frame) "(:ping :seq 1)") "Payload must match chunk length")
       (assert (= rem "TRAILING") "Remaining buffer must preserve trailing data")
       true)
      ((none) false))))

(df test-supervisor-10s-watchdog [] -> Bool
  :d "Verifies that steps exceeding the 10s ceiling trigger worker recycling and :ERR_WATCHDOG_TIMEOUT."
  (let [(ok-verdict (wd/check-step-deadline 2500 10000))
        (timeout-verdict (wd/check-step-deadline 10001 10000))
        (sup-ok (apm/supervise-step 400 10000 ":ping"))
        (sup-timeout (apm/supervise-step 10500 10000 ":exec-slow"))]
    (assert (not (.-timed-out ok-verdict)) "Step under 10s must not time out")
    (assert (= (.-error-code ok-verdict) ":none") "Normal step must have :none error code")
    (assert (.-timed-out timeout-verdict) "Step over 10s must trigger watchdog timeout")
    (assert (= (.-error-code timeout-verdict) ":ERR_WATCHDOG_TIMEOUT") "Breached deadline must emit :ERR_WATCHDOG_TIMEOUT")
    (assert (= (.-event timeout-verdict) ":step-timeout-recycled") "Breached deadline must emit :step-timeout-recycled")
    (assert (= (.-status sup-ok) ":ok") "Supervisor status for fast step must be :ok")
    (assert (not (.-worker-recycled sup-ok)) "Supervisor must not recycle worker for fast step")
    (assert (= (.-status sup-timeout) ":recycled") "Supervisor status on 10s timeout must be :recycled")
    (assert (= (.-exit-code sup-timeout) 124) "Watchdog timeout exit code must be 124")
    (assert (= (.-error-code sup-timeout) ":ERR_WATCHDOG_TIMEOUT") "Supervisor error code must be :ERR_WATCHDOG_TIMEOUT")
    (assert (.-worker-recycled sup-timeout) "Worker must be marked as recycled")
    true))

(df test-introspection-table [] -> Bool
  :d "Verifies diagnostic daemon inspection table formatting with DAEMON ID header."
  (let [(e1 (apm/make-daemon-entry "751f1272" 14842 42 ":active" ":idle"))
        (tbl (apm/format-daemon-table (list e1)))]
    (assert (string-contains? tbl "DAEMON ID") "Table must contain DAEMON ID header")
    (assert (string-contains? tbl "751f1272") "Table must contain daemon ID")
    (assert (string-contains? tbl "14842") "Table must contain PID")
    (assert (string-contains? tbl ":active") "Table must contain status")
    true))

(df run-tests [] -> Bool
  :d "Runs all APM daemon, singleton lock, stream framing, and watchdog supervisor tests."
  (and (test-singleton-lock)
       (and (test-stream-framing-newline)
            (and (test-stream-framing-content-length)
                 (and (test-supervisor-10s-watchdog)
                      (test-introspection-table))))))
