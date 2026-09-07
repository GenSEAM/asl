(module asl-sh/watchdog
  :d "APM Resource Watchdogs: RSS memory ceilings, stdin idle deadlock detection, and network port binding guards."
  :x [RssVerdict
      DeadlockVerdict
      PortVerdict
      make-rss-verdict
      check-rss-ceiling
      make-deadlock-verdict
      detect-deadlock
      make-port-verdict
      detect-bound-port
      parse-port-number])

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
  (:f event String "Audit event emitted: :deadlock-detected or :ok"))

(df make-deadlock-verdict [(deadlocked Bool) (idle-ms Int64) (ceiling-ms Int64) (event String)] -> DeadlockVerdict
  :d "Constructs a DeadlockVerdict."
  (DeadlockVerdict :deadlocked deadlocked :idle-ms idle-ms :ceiling-ms ceiling-ms :event event))

(df detect-deadlock [(idle-ms Int64) (ceiling-ms Int64)] -> DeadlockVerdict
  :d "Checks idle duration on blocking stdin pipe against ceiling (default 10,000ms)."
  (let [(cap (if (<= ceiling-ms 0) 10000 ceiling-ms))]
    (if (>= idle-ms cap)
        (make-deadlock-verdict true idle-ms cap ":deadlock-detected")
        (make-deadlock-verdict false idle-ms cap ":ok"))))

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
