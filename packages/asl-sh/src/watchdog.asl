(module asl-sh/watchdog
  :d "APM Resource Watchdogs: RSS memory ceilings, stdin idle deadlock detection, and network port binding guards."
  :x [RssVerdict
      DeadlockVerdict
      PortVerdict
      StepDeadlineVerdict
      make-rss-verdict
      check-rss-ceiling
      make-deadlock-verdict
      detect-deadlock
      detect-deadlock-escalation
      make-port-verdict
      detect-bound-port
      parse-port-number
      make-step-deadline-verdict
      check-step-deadline])

(dfs RssVerdict
  (:f exceeded Bool "True if memory usage exceeded configured ceiling")
  (:f rss-mb Int64 "Actual peak resident set size in megabytes")
  (:f ceiling-mb Int64 "Configured memory limit ceiling in megabytes")
  (:f signal String "Signal dispatched: SIGKILL on breach, NONE otherwise")
  (:f event String "Audit event emitted: :oom-killed or :ok"))

(df make-rss-verdict [(exceeded Bool) (rss-mb Int64) (ceiling-mb Int64) (signal String) (event String)] -> RssVerdict
  :d "Constructs an RssVerdict."
  (RssVerdict :exceeded exceeded :rss-mb rss-mb :ceiling-mb ceiling-mb :signal signal :event event))

(df check-rss-ceiling [(current-rss-mb Int64) (ceiling-mb Int64)] -> RssVerdict
  :d "Checks current RSS against memory ceiling; triggers SIGKILL and :oom-killed if breached."
  (let [(limit (if (<= ceiling-mb 0) 512 ceiling-mb))]
    (if (> current-rss-mb limit)
        (make-rss-verdict true current-rss-mb limit "SIGKILL" ":oom-killed")
        (make-rss-verdict false current-rss-mb limit "NONE" ":ok"))))

(dfs DeadlockVerdict
  (:f deadlocked Bool "True if stdin pipe has been idle at or beyond deadline")
  (:f idle-ms Int64 "Duration stdin pipe has been idle in milliseconds")
  (:f ceiling-ms Int64 "Configured idle deadlock ceiling in milliseconds (default 10000)")
  (:f event String "Audit event emitted: :deadlock-detected, :deadlock-sigterm, :deadlock-sigkill, or :ok")
  (:f signal String "Signal dispatched: NONE, SIGTERM, or SIGKILL")
  (:f exit-code Int64 "Synthetic exit status code: 0, 143, or 137")
  (:f kill-ceiling-ms Int64 "Configured SIGKILL ceiling in milliseconds (default 12000)"))

(df make-deadlock-verdict [(deadlocked Bool) (idle-ms Int64) (ceiling-ms Int64) (event String)] -> DeadlockVerdict
  :d "Constructs a DeadlockVerdict."
  (DeadlockVerdict
    :deadlocked deadlocked
    :idle-ms idle-ms
    :ceiling-ms ceiling-ms
    :event event
    :signal (if deadlocked "SIGTERM" "NONE")
    :exit-code (if deadlocked 143 0)
    :kill-ceiling-ms 12000))

(df detect-deadlock [(idle-ms Int64) (ceiling-ms Int64)] -> DeadlockVerdict
  :d "Checks idle duration on blocking stdin pipe against ceiling (default 10,000ms)."
  (let [(cap (if (<= ceiling-ms 0) 10000 ceiling-ms))]
    (if (>= idle-ms cap)
        (make-deadlock-verdict true idle-ms cap ":deadlock-detected")
        (make-deadlock-verdict false idle-ms cap ":ok"))))

(df detect-deadlock-escalation [(idle-ms Int64) (term-ms Int64) (kill-ms Int64)] -> DeadlockVerdict
  :d "Enforces two-stage stdin deadlock escalation: SIGTERM at term-ms (default 10s), SIGKILL at kill-ms (default 12s)."
  (let [(t-cap (if (<= term-ms 0) 10000 term-ms))
        (k-cap (if (<= kill-ms 0) 12000 kill-ms))]
    (cond
      ((>= idle-ms k-cap)
       (DeadlockVerdict
         :deadlocked true
         :idle-ms idle-ms
         :ceiling-ms t-cap
         :event ":deadlock-sigkill"
         :signal "SIGKILL"
         :exit-code 137
         :kill-ceiling-ms k-cap))
      ((>= idle-ms t-cap)
       (DeadlockVerdict
         :deadlocked true
         :idle-ms idle-ms
         :ceiling-ms t-cap
         :event ":deadlock-sigterm"
         :signal "SIGTERM"
         :exit-code 143
         :kill-ceiling-ms k-cap))
      (:else
       (DeadlockVerdict
         :deadlocked false
         :idle-ms idle-ms
         :ceiling-ms t-cap
         :event ":ok"
         :signal "NONE"
         :exit-code 0
         :kill-ceiling-ms k-cap)))))

(dfs StepDeadlineVerdict
  (:f timed-out Bool "True if step execution duration exceeded watchdog deadline")
  (:f elapsed-ms Int64 "Actual elapsed duration of step in milliseconds")
  (:f ceiling-ms Int64 "Configured step deadline ceiling in milliseconds (default 10000)")
  (:f error-code String "Error code emitted: :ERR_WATCHDOG_TIMEOUT or :none")
  (:f event String "Audit event emitted: :step-timeout-recycled or :ok"))

(df make-step-deadline-verdict [(timed-out Bool) (elapsed-ms Int64) (ceiling-ms Int64) (error-code String) (event String)] -> StepDeadlineVerdict
  :d "Constructs a StepDeadlineVerdict."
  (StepDeadlineVerdict :timed-out timed-out :elapsed-ms elapsed-ms :ceiling-ms ceiling-ms :error-code error-code :event event))

(df check-step-deadline [(elapsed-ms Int64) (ceiling-ms Int64)] -> StepDeadlineVerdict
  :d "Enforces a 10s deadline ceiling per batch execution step, returning :ERR_WATCHDOG_TIMEOUT when breached."
  (let [(cap (if (<= ceiling-ms 0) 10000 ceiling-ms))]
    (if (>= elapsed-ms cap)
        (make-step-deadline-verdict true elapsed-ms cap ":ERR_WATCHDOG_TIMEOUT" ":step-timeout-recycled")
        (make-step-deadline-verdict false elapsed-ms cap ":none" ":ok"))))

(dfs PortVerdict
  (:f detected Bool "True if a listening network port was discovered")
  (:f port Int64 "Identified TCP/UDP port number (0 if none)")
  (:f event String "Audit event emitted: :port-bound or :none"))

(df make-port-verdict [(detected Bool) (port Int64) (event String)] -> PortVerdict
  :d "Constructs a PortVerdict."
  (PortVerdict :detected detected :port port :event event))

(df parse-port-number [(text String)] -> (Option Int64)
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
        (digit-str (string-join (fst digits) ""))]
    (if (string-empty? digit-str)
        (none)
        (mt (string-to-int64 digit-str)
          ((some p)
           (if (and (> p 0) (<= p 65535))
               (some p)
               (none)))
          ((none) (none))))))

(df detect-bound-port [(line String)] -> PortVerdict
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
              (mt (parse-port-number token)
                ((some p) (make-port-verdict true p ":port-bound"))
                ((none) (make-port-verdict false 0 ":none")))))
           ((none) (make-port-verdict false 0 ":none")))))
      ((string-contains? lower "listening on port ")
       (let [(idx (string-index-of lower "listening on port "))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 18) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parse-port-number token)
                ((some p) (make-port-verdict true p ":port-bound"))
                ((none) (make-port-verdict false 0 ":none")))))
           ((none) (make-port-verdict false 0 ":none")))))
      ((string-contains? lower "localhost:")
       (let [(idx (string-index-of lower "localhost:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 10) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parse-port-number token)
                ((some p) (make-port-verdict true p ":port-bound"))
                ((none) (make-port-verdict false 0 ":none")))))
           ((none) (make-port-verdict false 0 ":none")))))
      ((string-contains? lower "127.0.0.1:")
       (let [(idx (string-index-of lower "127.0.0.1:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 10) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parse-port-number token)
                ((some p) (make-port-verdict true p ":port-bound"))
                ((none) (make-port-verdict false 0 ":none")))))
           ((none) (make-port-verdict false 0 ":none")))))
      ((string-contains? lower "0.0.0.0:")
       (let [(idx (string-index-of lower "0.0.0.0:"))]
         (mt idx
           ((some i)
            (let [(after (option-or (string-slice lower (+ i 8) (string-length lower)) ""))
                  (parts (string-split (string-trim after) " "))
                  (token (option-or (list-head parts) ""))]
              (mt (parse-port-number token)
                ((some p) (make-port-verdict true p ":port-bound"))
                ((none) (make-port-verdict false 0 ":none")))))
           ((none) (make-port-verdict false 0 ":none")))))
      (:else
       (make-port-verdict false 0 ":none")))))
