(module asl-sh/watchdog
  :d "APM Resource Watchdogs: RSS memory ceilings, stdin idle deadlock detection, and network port binding guards."
  :x [RssVerdict
      DeadlockVerdict
      PortVerdict
      StepDeadlineVerdict
      makeRssVerdict
      checkRssCeiling
      makeDeadlockVerdict
      detectDeadlock
      detectDeadlockEscalation
      makePortVerdict
      detectBoundPort
      parsePortNumber
      makeStepDeadlineVerdict
      checkStepDeadline])

(dfs RssVerdict
  (:f exceeded Bool "True if memory usage exceeded configured ceiling")
  (:f rssMb Int64 "Actual peak resident set size in megabytes")
  (:f ceilingMb Int64 "Configured memory limit ceiling in megabytes")
  (:f signal String "Signal dispatched: SIGKILL on breach, NONE otherwise")
  (:f event String "Audit event emitted: :oom-killed or :ok"))

(df makeRssVerdict [(exceeded Bool) (rssMb Int64) (ceilingMb Int64) (signal String) (event String)] -> RssVerdict
  :d "Constructs an RssVerdict."
  (RssVerdict :exceeded exceeded :rssMb rssMb :ceilingMb ceilingMb :signal signal :event event))

(df checkRssCeiling [(currentRssMb Int64) (ceilingMb Int64)] -> RssVerdict
  :d "Checks current RSS against memory ceiling; triggers SIGKILL and :oom-killed if breached."
  (let [(limit (if (<= ceilingMb 0) 512 ceilingMb))]
    (if (> currentRssMb limit)
        (makeRssVerdict true currentRssMb limit "SIGKILL" ":oom-killed")
        (makeRssVerdict false currentRssMb limit "NONE" ":ok"))))

(dfs DeadlockVerdict
  (:f deadlocked Bool "True if stdin pipe has been idle at or beyond deadline")
  (:f idleMs Int64 "Duration stdin pipe has been idle in milliseconds")
  (:f ceilingMs Int64 "Configured idle deadlock ceiling in milliseconds (default 10000)")
  (:f event String "Audit event emitted: :deadlock-detected, :deadlock-sigterm, :deadlock-sigkill, or :ok")
  (:f signal String "Signal dispatched: NONE, SIGTERM, or SIGKILL")
  (:f exitCode Int64 "Synthetic exit status code: 0, 143, or 137")
  (:f killCeilingMs Int64 "Configured SIGKILL ceiling in milliseconds (default 12000)"))

(df makeDeadlockVerdict [(deadlocked Bool) (idleMs Int64) (ceilingMs Int64) (event String)] -> DeadlockVerdict
  :d "Constructs a DeadlockVerdict."
  (DeadlockVerdict
    :deadlocked deadlocked
    :idleMs idleMs
    :ceilingMs ceilingMs
    :event event
    :signal (if deadlocked "SIGTERM" "NONE")
    :exitCode (if deadlocked 143 0)
    :killCeilingMs 12000))

(df detectDeadlock [(idleMs Int64) (ceilingMs Int64)] -> DeadlockVerdict
  :d "Checks idle duration on blocking stdin pipe against ceiling (default 10,000ms)."
  (let [(cap (if (<= ceilingMs 0) 10000 ceilingMs))]
    (if (>= idleMs cap)
        (makeDeadlockVerdict true idleMs cap ":deadlock-detected")
        (makeDeadlockVerdict false idleMs cap ":ok"))))

(df detectDeadlockEscalation [(idleMs Int64) (termMs Int64) (killMs Int64)] -> DeadlockVerdict
  :d "Enforces two-stage stdin deadlock escalation: SIGTERM at term-ms (default 10s), SIGKILL at kill-ms (default 12s)."
  (let [(tCap (if (<= termMs 0) 10000 termMs))
        (kCap (if (<= killMs 0) 12000 killMs))]
    (cond
      ((>= idleMs kCap)
       (DeadlockVerdict
         :deadlocked true
         :idleMs idleMs
         :ceilingMs tCap
         :event ":deadlock-sigkill"
         :signal "SIGKILL"
         :exitCode 137
         :killCeilingMs kCap))
      ((>= idleMs tCap)
       (DeadlockVerdict
         :deadlocked true
         :idleMs idleMs
         :ceilingMs tCap
         :event ":deadlock-sigterm"
         :signal "SIGTERM"
         :exitCode 143
         :killCeilingMs kCap))
      (:else
       (DeadlockVerdict
         :deadlocked false
         :idleMs idleMs
         :ceilingMs tCap
         :event ":ok"
         :signal "NONE"
         :exitCode 0
         :killCeilingMs kCap)))))

(dfs StepDeadlineVerdict
  (:f timedOut Bool "True if step execution duration exceeded watchdog deadline")
  (:f elapsedMs Int64 "Actual elapsed duration of step in milliseconds")
  (:f ceilingMs Int64 "Configured step deadline ceiling in milliseconds (default 10000)")
  (:f errorCode String "Error code emitted: :ERR_WATCHDOG_TIMEOUT or :none")
  (:f event String "Audit event emitted: :step-timeout-recycled or :ok"))

(df makeStepDeadlineVerdict [(timedOut Bool) (elapsedMs Int64) (ceilingMs Int64) (errorCode String) (event String)] -> StepDeadlineVerdict
  :d "Constructs a StepDeadlineVerdict."
  (StepDeadlineVerdict :timedOut timedOut :elapsedMs elapsedMs :ceilingMs ceilingMs :errorCode errorCode :event event))

(df checkStepDeadline [(elapsedMs Int64) (ceilingMs Int64)] -> StepDeadlineVerdict
  :d "Enforces a 10s deadline ceiling per batch execution step, returning :ERR_WATCHDOG_TIMEOUT when breached."
  (let [(cap (if (<= ceilingMs 0) 10000 ceilingMs))]
    (if (>= elapsedMs cap)
        (makeStepDeadlineVerdict true elapsedMs cap ":ERR_WATCHDOG_TIMEOUT" ":step-timeout-recycled")
        (makeStepDeadlineVerdict false elapsedMs cap ":none" ":ok"))))

(dfs PortVerdict
  (:f detected Bool "True if a listening network port was discovered")
  (:f port Int64 "Identified TCP/UDP port number (0 if none)")
  (:f event String "Audit event emitted: :port-bound or :none"))

(df makePortVerdict [(detected Bool) (port Int64) (event String)] -> PortVerdict
  :d "Constructs a PortVerdict."
  (PortVerdict :detected detected :port port :event event))

(df parsePortNumber [(text String)] -> (Option Int64)
  :d "Extracts a valid numeric TCP port (1-65535) from a text token, stripping trailing non-numeric characters."
  (let [(clean (string-trim text))
        (chars (string-chars clean))
        (digits (fold (fn [(acc (Pair (List String) Bool)) (c String)] -> (Pair (List String) Bool)
                        (if (snd acc)
                            acc
                            (if (or (= c "0")
                                    (or (= c "1")
                                        (or (= c "2")
                                            (or (= c "3")
                                                (or (= c "4")
                                                    (or (= c "5")
                                                        (or (= c "6")
                                                            (or (= c "7")
                                                                (or (= c "8")
                                                                    (= c "9"))))))))))
                                (pair (list-append (fst acc) (list c)) false)
                                (pair (fst acc) true))))
                      (pair (list) false)
                      chars))
        (digitStr (string-join (fst digits) ""))]
    (if (string-empty? digitStr)
        (none)
        (mt (string-to-int64 digitStr)
          ((some p)
           (if (and (> p 0) (<= p 65535))
               (some p)
               (none)))
          ((none) (none))))))

(df detectBoundPort [(line String)] -> PortVerdict
  :d "Inspects log line for bound port notifications e.g. :port-bound 3000, listening on port 8080, localhost:5173, 127.0.0.1:8000, 0.0.0.0:4000."
  (let [(lower (string-lower line))]
    (cond
      ((string-contains? lower ":port-bound ")
       (let [(idx (string-index-of lower ":port-bound "))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 12) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parsePortNumber token)
                ((some p) (makePortVerdict true p ":port-bound"))
                ((none) (makePortVerdict false 0 ":none")))))
           ((none) (makePortVerdict false 0 ":none")))))
      ((string-contains? lower "listening on port ")
       (let [(idx (string-index-of lower "listening on port "))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 18) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parsePortNumber token)
                ((some p) (makePortVerdict true p ":port-bound"))
                ((none) (makePortVerdict false 0 ":none")))))
           ((none) (makePortVerdict false 0 ":none")))))
      ((string-contains? lower "localhost:")
       (let [(idx (string-index-of lower "localhost:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 10) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parsePortNumber token)
                ((some p) (makePortVerdict true p ":port-bound"))
                ((none) (makePortVerdict false 0 ":none")))))
           ((none) (makePortVerdict false 0 ":none")))))
      ((string-contains? lower "127.0.0.1:")
       (let [(idx (string-index-of lower "127.0.0.1:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 10) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parsePortNumber token)
                ((some p) (makePortVerdict true p ":port-bound"))
                ((none) (makePortVerdict false 0 ":none")))))
           ((none) (makePortVerdict false 0 ":none")))))
      ((string-contains? lower "0.0.0.0:")
       (let [(idx (string-index-of lower "0.0.0.0:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 8) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parsePortNumber token)
                ((some p) (makePortVerdict true p ":port-bound"))
                ((none) (makePortVerdict false 0 ":none")))))
           ((none) (makePortVerdict false 0 ":none")))))
      ((string-contains? lower "[::1]:")
       (let [(idx (string-index-of lower "[::1]:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 6) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parsePortNumber token)
                ((some p) (makePortVerdict true p ":port-bound"))
                ((none) (makePortVerdict false 0 ":none")))))
           ((none) (makePortVerdict false 0 ":none")))))
      ((string-contains? lower "[::]:")
       (let [(idx (string-index-of lower "[::]:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 5) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parsePortNumber token)
                ((some p) (makePortVerdict true p ":port-bound"))
                ((none) (makePortVerdict false 0 ":none")))))
           ((none) (makePortVerdict false 0 ":none")))))
      (:else
       (makePortVerdict false 0 ":none")))))
