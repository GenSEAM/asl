(module asl-sh/apm
  :d "APM Daemon, Supervisor, Singleton Advisory Lock, and Multi-Client Stream Framing."
  :x [LockVerdict
      StreamFrame
      SupervisorVerdict
      DaemonEntry
      make-lock-verdict
      resolve-lock
      make-stream-frame
      count-paren-balance
      is-balanced-frame?
      extract-content-length
      parse-stream-frame
      make-supervisor-verdict
      supervise-step
      make-daemon-entry
      format-daemon-table]
  :i [(watchdog :a wd)])

(dfs LockVerdict
  (:f acquired Bool "True if singleton advisory lock was successfully acquired")
  (:f lock-path String "File system path of the advisory lock")
  (:f holder-pid Int64 "Process ID of the lock holder (0 if acquired or stale)")
  (:f status String "Lock resolution status: :acquired, :collision, or :stale")
  (:f event String "Audit event emitted: :lock-acquired, :lock-refused, or :lock-reclaimed"))

(df make-lock-verdict [(acquired Bool) (lock-path String) (holder-pid Int64) (status String) (event String)] -> LockVerdict
  :d "Constructs a LockVerdict."
  (LockVerdict :acquired acquired :lock-path lock-path :holder-pid holder-pid :status status :event event))

(df resolve-lock [(lock-path String) (current-pid Int64) (holder-pid Int64) (holder-alive Bool)] -> LockVerdict
  :d "Resolves singleton advisory lock acquisition; refuses duplicate spawn on active collision and reclaims on stale PID."
  (if (or (= holder-pid 0) (= holder-pid current-pid))
      (make-lock-verdict true lock-path current-pid ":acquired" ":lock-acquired")
      (if holder-alive
          (make-lock-verdict false lock-path holder-pid ":collision" ":lock-refused")
          (make-lock-verdict true lock-path current-pid ":stale" ":lock-reclaimed"))))

(dfs StreamFrame
  (:f kind String "Framing protocol kind: newline or content-length")
  (:f payload String "Extracted expression or batch payload")
  (:f length Int64 "Length in bytes of payload")
  (:f valid Bool "True if frame was cleanly delineated without packet tearing"))

(df make-stream-frame [(kind String) (payload String) (length Int64) (valid Bool)] -> StreamFrame
  :d "Constructs a StreamFrame."
  (StreamFrame :kind kind :payload payload :length length :valid valid))

(df count-paren-balance [(text String)] -> Int64
  :d "Computes net parenthesis balance (+1 for '(', -1 for ')'), ignoring characters inside double quotes."
  (let [(chars (string-chars text))
        (st (fold (fn [(acc (Pair Int64 (Pair Bool Bool))) (c String)] -> (Pair Int64 (Pair Bool Bool))
                    (let [(depth (fst acc))
                          (in-str (fst (snd acc)))
                          (esc (snd (snd acc)))]
                      (if esc
                          (pair depth (pair in-str false))
                          (if (= c "\\")
                              (if in-str
                                  (pair depth (pair in-str true))
                                  (pair depth (pair in-str false)))
                              (if (= c "\"")
                                  (pair depth (pair (not in-str) false))
                                  (if in-str
                                      acc
                                      (if (= c "(")
                                          (pair (+ depth 1) (pair in-str false))
                                          (if (= c ")")
                                              (pair (- depth 1) (pair in-str false))
                                              acc))))))))
                  (pair 0 (pair false false))
                  chars))]
    (fst st)))

(df is-balanced-frame? [(text String)] -> Bool
  :d "Returns true if text is non-empty and has zero net parenthesis balance."
  (let [(clean (string-trim text))]
    (if (string-empty? clean)
        false
        (= (count-paren-balance clean) 0))))

(df extract-content-length [(header String)] -> (Option Int64)
  :d "Parses Content-Length integer value from header prefix."
  (let [(lower (string-lower header))]
    (if (string-starts-with? lower "content-length:")
        (let [(after (option-or (string-slice header 15 (string-length header)) ""))
              (clean (string-trim after))]
          (string-to-int64 clean))
        (none))))

(df parse-stream-frame [(buffer String)] -> (Pair (Option StreamFrame) String)
  :d "Delineates stream frame using Content-Length headers or newline-delimited ASNL s-expressions."
  (let [(trimmed (string-trim-left buffer))]
    (if (string-starts-with? (string-lower trimmed) "content-length:")
        (let [(hdr-end (string-index-of trimmed "\n\n"))
              (hdr-delim (if (option-is-some? hdr-end) hdr-end (string-index-of trimmed "\r\n\r\n")))]
          (mt hdr-delim
            ((some idx)
             (let [(hdr-len (if (string-contains? trimmed "\r\n\r\n") (+ idx 4) (+ idx 2)))
                   (hdr-part (option-or (string-slice trimmed 0 idx) ""))
                   (val-opt (extract-content-length hdr-part))]
               (mt val-opt
                 ((some cl)
                  (let [(body-start hdr-len)
                        (total-need (+ body-start cl))
                        (buf-len (int32-to-int64 (string-length trimmed)))]
                    (if (>= buf-len total-need)
                        (let [(payload (option-or (string-slice trimmed body-start total-need) ""))
                              (rem (option-or (string-slice trimmed total-need buf-len) ""))
                              (frame (make-stream-frame "content-length" payload cl true))]
                          (pair (some frame) rem))
                        (pair (none) buffer))))
                 ((none) (pair (none) buffer)))))
            ((none) (pair (none) buffer))))
        (let [(nl-idx (string-index-of buffer "\n"))]
          (mt nl-idx
            ((some i)
             (let [(candidate (option-or (string-slice buffer 0 i) ""))
                   (rem (option-or (string-slice buffer (+ i 1) (string-length buffer)) ""))]
               (if (= (count-paren-balance candidate) 0)
                   (let [(payload (string-trim candidate))]
                     (if (string-empty? payload)
                         (pair (none) rem)
                         (let [(frame (make-stream-frame "newline" payload (int32-to-int64 (string-length payload)) true))]
                           (pair (some frame) rem))))
                   (pair (none) buffer))))
            ((none) (pair (none) buffer)))))))

(dfs SupervisorVerdict
  (:f status String "Execution status: :ok or :recycled")
  (:f exit-code Int64 "Resulting code: 0 on success, 124 on watchdog timeout")
  (:f error-code String "Error symbol: :OK or :ERR_WATCHDOG_TIMEOUT")
  (:f worker-recycled Bool "True if hanging execution worker was recycled without socket teardown")
  (:f summary String "Execution summary or timeout verdict"))

(df make-supervisor-verdict [(status String) (exit-code Int64) (error-code String) (worker-recycled Bool) (summary String)] -> SupervisorVerdict
  :d "Constructs a SupervisorVerdict."
  (SupervisorVerdict :status status :exit-code exit-code :error-code error-code :worker-recycled worker-recycled :summary summary))

(df supervise-step [(elapsed-ms Int64) (deadline-ms Int64) (op-name String)] -> SupervisorVerdict
  :d "Supervises an execution worker step with a 10s ceiling; on deadline expiry recycles worker and emits :ERR_WATCHDOG_TIMEOUT."
  (let [(ceiling (if (<= deadline-ms 0) 10000 deadline-ms))
        (verdict (wd/check-step-deadline elapsed-ms ceiling))]
    (if (.-timed-out verdict)
        (make-supervisor-verdict ":recycled" 124 ":ERR_WATCHDOG_TIMEOUT" true (str "Watchdog deadline exceeded (10s) on step: " op-name))
        (make-supervisor-verdict ":ok" 0 ":OK" false (str "Step completed within deadline: " op-name)))))

(dfs DaemonEntry
  (:f daemon-id String "Short hash identifier of daemon")
  (:f pid Int64 "Process ID of the daemon host")
  (:f rss-mb Int64 "Memory usage in megabytes")
  (:f status String "Daemon operational status: :active, :idle, :hung")
  (:f active-op String "Currently running batch step or :idle"))

(df make-daemon-entry [(daemon-id String) (pid Int64) (rss-mb Int64) (status String) (active-op String)] -> DaemonEntry
  :d "Constructs a DaemonEntry."
  (DaemonEntry :daemon-id daemon-id :pid pid :rss-mb rss-mb :status status :active-op active-op))

(df format-daemon-table [(entries (List DaemonEntry))] -> String
  :d "Renders introspection process table for active daemons with DAEMON ID header."
  (let [(header "DAEMON ID  PID     STATUS   RSS(MB)  ACTIVE OP\n---------  ------  -------  -------  ---------")
        (rows (map (fn [(e DaemonEntry)] -> String
                     (str (.-daemon-id e) "  "
                          (string-from-int64 (.-pid e)) "  "
                          (.-status e) "  "
                          (string-from-int64 (.-rss-mb e)) "MB  "
                          (.-active-op e)))
                   entries))]
    (string-join (list-append (list header) rows) "\n")))
