(module asl-sh/apm
  :d "APM Daemon, Supervisor, Singleton Advisory Lock, and Multi-Client Stream Framing."
  :x [LockVerdict
      StreamFrame
      SupervisorVerdict
      DaemonEntry
      OobDemuxer
      makeLockVerdict
      resolveLock
      makeStreamFrame
      countParenBalance
      isBalancedFrame?
      extractContentLength
      parseStreamFrame
      makeSupervisorVerdict
      superviseStep
      makeDaemonEntry
      formatDaemonTable
      makeOobDemuxer
      oobDemuxChunk
      oobDemuxFinish]
  :i [(watchdog     :a wd)
      (spool        :a spool)
      (asl-sh/coreProcess :a proc)])

(dfs LockVerdict
  (:f acquired Bool "True if singleton advisory lock was successfully acquired")
  (:f lockPath String "File system path of the advisory lock")
  (:f holderPid Int64 "Process ID of the lock holder (0 if acquired or stale)")
  (:f status String "Lock resolution status: :acquired, :collision, or :stale")
  (:f event String "Audit event emitted: :lock-acquired, :lock-refused, or :lock-reclaimed"))

(df makeLockVerdict [(acquired Bool) (lockPath String) (holderPid Int64) (status String) (event String)] -> LockVerdict
  :d "Constructs a LockVerdict."
  (LockVerdict :acquired acquired :lockPath lockPath :holderPid holderPid :status status :event event))

(df resolveLock [(lockPath String) (currentPid Int64) (holderPid Int64) (holderAlive Bool)] -> LockVerdict
  :d "Resolves singleton advisory lock acquisition; refuses duplicate spawn on active collision and reclaims on stale PID."
  (if (or (= holderPid 0) (= holderPid currentPid))
      (makeLockVerdict true lockPath currentPid ":acquired" ":lock-acquired")
      (if holderAlive
          (makeLockVerdict false lockPath holderPid ":collision" ":lock-refused")
          (makeLockVerdict true lockPath currentPid ":stale" ":lock-reclaimed"))))

(dfs StreamFrame
  (:f kind String "Framing protocol kind: newline or content-length")
  (:f payload String "Extracted expression or batch payload")
  (:f length Int64 "Length in bytes of payload")
  (:f valid Bool "True if frame was cleanly delineated without packet tearing"))

(df makeStreamFrame [(kind String) (payload String) (length Int64) (valid Bool)] -> StreamFrame
  :d "Constructs a StreamFrame."
  (StreamFrame :kind kind :payload payload :length length :valid valid))

(df countParenBalance [(text String)] -> Int64
  :d "Computes net parenthesis balance (+1 for '(', -1 for ')'), ignoring characters inside double quotes."
  (let [(chars (string-chars text))
        (st (fold (fn [(acc (Pair Int64 (Pair Bool Bool))) (c String)] -> (Pair Int64 (Pair Bool Bool))
                    (let [(depth (fst acc))
                          (inStr (fst (snd acc)))
                          (esc (snd (snd acc)))]
                      (if esc
                          (pair depth (pair inStr false))
                          (if (= c "\\")
                              (if inStr
                                  (pair depth (pair inStr true))
                                  (pair depth (pair inStr false)))
                              (if (= c "\"")
                                  (pair depth (pair (not inStr) false))
                                  (if inStr
                                      acc
                                      (if (= c "(")
                                          (pair (+ depth 1) (pair inStr false))
                                          (if (= c ")")
                                              (pair (- depth 1) (pair inStr false))
                                              acc))))))))
                  (pair 0 (pair false false))
                  chars))]
    (fst st)))

(df isBalancedFrame? [(text String)] -> Bool
  :d "Returns true if text is non-empty and has zero net parenthesis balance."
  (let [(clean (string-trim text))]
    (if (string-empty? clean)
        false
        (= (countParenBalance clean) 0))))

(df extractContentLength [(header String)] -> (Option Int64)
  :d "Parses Content-Length integer value from header prefix."
  (let [(lower (string-lower header))]
    (if (string-starts-with? lower "content-length:")
        (let [(after (option-or (string-slice header 15 (string-length header)) ""))
              (clean (string-trim after))]
          (string-to-int64 clean))
        (none))))

(df parseStreamFrame [(buffer String)] -> (Pair (Option StreamFrame) String)
  :d "Delineates stream frame using Content-Length headers or newline-delimited ASNL s-expressions."
  (let [(trimmed (string-trim-left buffer))]
    (if (string-starts-with? (string-lower trimmed) "content-length:")
        (let [(hdrEnd (string-index-of trimmed "\n\n"))
              (hdrDelim (if (is-some? hdrEnd) hdrEnd (string-index-of trimmed "\r\n\r\n")))]
          (mt hdrDelim
            ((some idx)
             (let [(hdrLen (if (string-contains? trimmed "\r\n\r\n") (+ idx 4) (+ idx 2)))
                   (hdrPart (option-or (string-slice trimmed 0 idx) ""))
                   (valOpt (extractContentLength hdrPart))]
               (mt valOpt
                 ((some cl)
                  (let [(bodyStart hdrLen)
                        (totalNeed (+ bodyStart cl))
                        (bufLen (int32-to-int64 (string-length trimmed)))]
                    (if (>= bufLen totalNeed)
                        (let [(payload (option-or (string-slice trimmed bodyStart totalNeed) ""))
                              (rem (option-or (string-slice trimmed totalNeed bufLen) ""))
                              (frame (makeStreamFrame "content-length" payload cl true))]
                          (pair (some frame) rem))
                        (pair (none) buffer))))
                 ((none) (pair (none) buffer)))))
            ((none) (pair (none) buffer))))
        (let [(nlIdx (string-index-of buffer "\n"))]
          (mt nlIdx
            ((some i)
             (let [(candidate (option-or (string-slice buffer 0 i) ""))
                   (rem (option-or (string-slice buffer (+ i 1) (string-length buffer)) ""))]
               (if (= (countParenBalance candidate) 0)
                   (let [(payload (string-trim candidate))]
                     (if (string-empty? payload)
                         (pair (none) rem)
                         (let [(frame (makeStreamFrame "newline" payload (int32-to-int64 (string-length payload)) true))]
                           (pair (some frame) rem))))
                   (pair (none) buffer))))
            ((none) (pair (none) buffer)))))))

(dfs SupervisorVerdict
  (:f status String "Execution status: :ok or :recycled")
  (:f exitCode Int64 "Resulting code: 0 on success, 124 on watchdog timeout")
  (:f errorCode String "Error symbol: :OK or :ERR_WATCHDOG_TIMEOUT")
  (:f workerRecycled Bool "True if hanging execution worker was recycled without socket teardown")
  (:f summary String "Execution summary or timeout verdict"))

(df makeSupervisorVerdict [(status String) (exitCode Int64) (errorCode String) (workerRecycled Bool) (summary String)] -> SupervisorVerdict
  :d "Constructs a SupervisorVerdict."
  (SupervisorVerdict :status status :exitCode exitCode :errorCode errorCode :workerRecycled workerRecycled :summary summary))

(df superviseStep [(elapsedMs Int64) (deadlineMs Int64) (opName String)] -> SupervisorVerdict
  :d "Supervises an execution worker step with a 10s ceiling; on deadline expiry recycles worker and emits :ERR_WATCHDOG_TIMEOUT."
  (let [(ceiling (if (<= deadlineMs 0) 10000 deadlineMs))
        (verdict (wd/checkStepDeadline elapsedMs ceiling))]
    (if (.-timedOut verdict)
        (makeSupervisorVerdict ":recycled" 124 ":ERR_WATCHDOG_TIMEOUT" true (str "Watchdog deadline exceeded (10s) on step: " opName))
        (makeSupervisorVerdict ":ok" 0 ":OK" false (str "Step completed within deadline: " opName)))))

(dfs DaemonEntry
  (:f daemonId String "Short hash identifier of daemon")
  (:f pid Int64 "Process ID of the daemon host")
  (:f rssMb Int64 "Memory usage in megabytes")
  (:f status String "Daemon operational status: :active, :idle, :hung")
  (:f activeOp String "Currently running batch step or :idle"))

(df makeDaemonEntry [(daemonId String) (pid Int64) (rssMb Int64) (status String) (activeOp String)] -> DaemonEntry
  :d "Constructs a DaemonEntry."
  (DaemonEntry :daemonId daemonId :pid pid :rssMb rssMb :status status :activeOp activeOp))

(df formatDaemonTable [(entries (List DaemonEntry))] -> String
  :d "Renders introspection process table for active daemons with DAEMON ID header."
  (let [(header "DAEMON ID  PID     STATUS   RSS(MB)  ACTIVE OP\n---------  ------  -------  -------  ---------")
        (rows (map (fn [(e DaemonEntry)] -> String
                     (str (.-daemonId e) "  "
                          (string-from-int64 (.-pid e)) "  "
                          (.-status e) "  "
                          (string-from-int64 (.-rssMb e)) "MB  "
                          (.-activeOp e)))
                   entries))]
    (string-join (list-append (list header) rows) "\n")))

(dfs OobDemuxer
  (:f maxBufferBytes Int64 "Hard memory buffer ceiling in bytes (default 64MB: 67108864)")
  (:f bufferBytes Int64 "Current active in-flight buffer size in bytes")
  (:f totalBytes Int64 "Cumulative byte count processed across stream")
  (:f spool spool/TwoTierSpool "Integrated two-tier spool (RAM ring + circular disk)")
  (:f isTerminated Bool "True if stream was terminated due to memory/stream boundary breach")
  (:f terminationReason String "Reason for stream termination: :none, :buffer-overflow, or :sigkill"))

(df makeOobDemuxer [(spoolPath String) (maxBufferBytes Int64)] -> OobDemuxer
  :d "Constructs an OobDemuxer with bounded memory buffer ceiling and two-tier spool."
  (let [(limit (if (<= maxBufferBytes 0) 67108864 maxBufferBytes))
        (tt (spool/makeTwoTierSpool spoolPath 200 10485760))]
    (OobDemuxer
      :maxBufferBytes limit
      :bufferBytes 0
      :totalBytes 0
      :spool tt
      :isTerminated false
      :terminationReason ":none")))

(df oobDemuxChunk [(demuxer OobDemuxer) (chunk String)] -> OobDemuxer
  :d "Streams a chunk into the two-tier spool while bounding active buffer memory strictly under max-buffer-bytes."
  (let [(chunkLen (int32-to-int64 (string-length chunk)))
        (newTotal (+ (.-totalBytes demuxer) chunkLen))
        (maxBuf (.-maxBufferBytes demuxer))]
    (if (.-isTerminated demuxer)
        (OobDemuxer
          :maxBufferBytes maxBuf
          :bufferBytes (.-bufferBytes demuxer)
          :totalBytes newTotal
          :spool (.-spool demuxer)
          :isTerminated true
          :terminationReason (.-terminationReason demuxer))
        (let [(newBuf (+ (.-bufferBytes demuxer) chunkLen))]
          (if (> newBuf maxBuf)
              (OobDemuxer
                :maxBufferBytes maxBuf
                :bufferBytes (.-bufferBytes demuxer)
                :totalBytes newTotal
                :spool (.-spool demuxer)
                :isTerminated true
                :terminationReason ":buffer-overflow")
              (let [(updatedSpool (spool/twoTierPush (.-spool demuxer) chunk))]
                (OobDemuxer
                  :maxBufferBytes maxBuf
                  :bufferBytes newBuf
                  :totalBytes newTotal
                  :spool updatedSpool
                  :isTerminated false
                  :terminationReason ":none")))))))

(df oobDemuxFinish [(demuxer OobDemuxer) (exitCode Int64) (durationMs Int64)] -> proc/ProcessReceipt
  :d "Finalizes two-tier spool and returns a compact ProcessReceipt (<80 tokens)."
  (let [(closedSpool (spool/twoTierClose (.-spool demuxer)))
        (spoolPath (.-path (.-disk closedSpool)))
        (finalExit (if (.-isTerminated demuxer) 137 exitCode))
        (finalSummary (if (.-isTerminated demuxer)
                           "OOB stream terminated: memory bound < 64MB exceeded"
                           (if (= exitCode 0)
                               "Command succeeded"
                               (str "Process failed with exit code " (string-from-int64 exitCode)))))]
    (proc/makeProcessReceipt finalExit durationMs 32 spoolPath finalSummary)))
