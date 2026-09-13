(module asl-sh/spoolTest
  :d "Falsifiable test suite for APM Two-Tier Spooling and Resource Guards."
  :x [testRingBufferCapacity
      testDiskSpoolCircularCap
      testDiskSpoolAutoUnlink
      testTwoTierSpoolIntegration
      testWatchdogRssCeiling
      testWatchdogDeadlock
      testWatchdogPortDetection
      testShLifecycleWiring
      testDiskSpool50mbHardCap
      runTests]
  :i [(spool        :a spool)
      (watchdog     :a wd)
      (sh           :a sh)
      (asl-sh/process :a proc)])

(df testRingBufferCapacity [] -> Bool
  :d "Verifies that RAM RingBuffer evicts oldest lines FIFO when 200 capacity is exceeded."
  (let [(init (spool/makeRingBuffer 200))
        (rb (fold (fn [(b spool/RingBuffer) (i Int64)] -> spool/RingBuffer
                    (spool/ringPush b (str "line-" (string-from-int64 i))))
                  init
                  (range 0 250)))
        (firstLine (option-or (list-head (.-lines rb)) ""))
        (last3 (spool/ringTail rb 3))
        (emptyTail (spool/ringTail rb 0))
        (defRb (spool/makeRingBuffer 0))]
    (assert (= (spool/ringSize rb) 200) "Ring buffer size must be capped at 200")
    (assert (= (.-count rb) 200) "Ring buffer count field must equal 200")
    (assert (= firstLine "line-50") "Oldest 50 lines must be evicted FIFO (first retained is line-50)")
    (assert (= (list-length last3) 3) "ring-tail 3 must return exactly 3 lines")
    (assert (= last3 (list "line-247" "line-248" "line-249")) "Tail lines must match last 3 pushed items")
    (assert (= (list-length emptyTail) 0) "ring-tail 0 must return empty list")
    (assert (= (.-capacity defRb) 200) "Default capacity must be 200 when <= 0")
    true))

(df testDiskSpoolCircularCap [] -> Bool
  :d "Verifies circular FIFO byte truncation on DiskSpool when cap is exceeded."
  (let [(spool (spool/makeDiskSpool "/tmp/test-spool.spool" 100))
        (chunkA "012345678901234567890123456789012345678901234567890123456789")
        (chunkB "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+~<>?[]{}|/=")
        (s1 (spool/spoolWrite spool chunkA))
        (s2 (spool/spoolWrite s1 chunkB))
        (defSpool (spool/makeDiskSpool "/tmp/default.spool" 0))]
    (assert (= (.-currentBytes s1) 60) "First write must store exactly 60 bytes")
    (assert (= (.-currentBytes s2) 100) "Second write must be capped at 100 bytes")
    (assert (<= (int32-to-int64 (string-length (.-content s2))) 100) "Spool content length must not exceed 100 bytes")
    (assert (string-ends-with? (.-content s2) chunkB) "Recent chunk bytes must be preserved at tail")
    (assert (= (.-maxBytes defSpool) 10485760) "Default max-bytes must be 10MB (10485760)")
    true))

(df testDiskSpoolAutoUnlink [] -> Bool
  :d "Verifies auto-unlink transition and storage zeroing upon spool reclamation."
  (let [(spool (spool/makeDiskSpool "/tmp/unlink-test.spool" 1024))]
    (refute (spool/spoolIsUnlinked? spool) "Fresh spool must not be unlinked")
    (let [(spoolW (spool/spoolWrite spool "ephemeral-payload"))
          (unlinked (spool/spoolUnlink spoolW))]
      (assert (spool/spoolIsUnlinked? unlinked) "Spool must be marked as unlinked")
      (assert (= (.-currentBytes unlinked) 0) "Unlinked spool must have 0 current bytes")
      (assert (= (.-content unlinked) "") "Unlinked spool content must be cleared")
      true)))

(df testTwoTierSpoolIntegration [] -> Bool
  :d "Verifies coordinated RAM ring buffer and disk spool dual writes and close lifecycle."
  (let [(tt (spool/makeTwoTierSpool "/tmp/two-tier-test.spool" 5 1024))
        (pushed (fold (fn [(s spool/TwoTierSpool) (i Int64)] -> spool/TwoTierSpool
                        (spool/twoTierPush s (str "msg-" (string-from-int64 i))))
                      tt
                      (range 0 10)))
        (closed (spool/twoTierClose pushed))]
    (assert (= (spool/ringSize (.-ring pushed)) 5) "Ring buffer retains last 5 lines")
    (assert (= (spool/ringTail (.-ring pushed) 2) (list "msg-8" "msg-9")) "Ring tail matches last 2 messages")
    (assert (> (.-currentBytes (.-disk pushed)) 0) "Disk spool captured non-zero bytes")
    (assert (spool/spoolIsUnlinked? (.-disk closed)) "Disk spool must be unlinked on close")
    (assert (= (spool/ringSize (.-ring closed)) 5) "Ring buffer persists after disk unlink for tail inspection")
    (assert (= (spool/ringTail (.-ring closed) 1) (list "msg-9")) "Tail inspection returns latest line after close")
    true))

(df testWatchdogRssCeiling [] -> Bool
  :d "Verifies RSS memory ceiling watchdog verdicts, SIGKILL dispatches, and :oom-killed events."
  (let [(vNormal (wd/checkRssCeiling 256 512))
        (vBreach (wd/checkRssCeiling 600 512))
        (vExact  (wd/checkRssCeiling 512 512))
        (vDef    (wd/checkRssCeiling 600 0))]
    (refute (.-exceeded vNormal) "RSS 256MB under 512MB ceiling must not exceed")
    (assert (= (.-signal vNormal) "NONE") "Signal must be NONE for normal usage")
    (assert (= (.-event vNormal) ":ok") "Event must be :ok for normal usage")
    (assert (.-exceeded vBreach) "RSS 600MB over 512MB ceiling must exceed")
    (assert (= (.-signal vBreach) "SIGKILL") "Signal must be SIGKILL on breach")
    (assert (= (.-event vBreach) ":oom-killed") "Event must be :oom-killed on breach")
    (refute (.-exceeded vExact) "Exact threshold 512MB must not exceed")
    (assert (.-exceeded vDef) "RSS 600MB exceeds default 512MB ceiling")
    (assert (= (.-ceilingMb vDef) 512) "Default ceiling must be 512MB")
    true))

(df testWatchdogDeadlock [] -> Bool
  :d "Verifies deadlock detector on idle stdin pipes against 10s ceiling."
  (let [(vOk   (wd/detectDeadlock 5000 10000))
        (vDead (wd/detectDeadlock 10000 10000))
        (vDef  (wd/detectDeadlock 15000 0))]
    (refute (.-deadlocked vOk) "5000ms idle under 10000ms is not deadlocked")
    (assert (= (.-event vOk) ":ok") "Event must be :ok")
    (assert (.-deadlocked vDead) "10000ms idle matches ceiling and is deadlocked")
    (assert (= (.-event vDead) ":deadlock-detected") "Event must be :deadlock-detected")
    (assert (.-deadlocked vDef) "15000ms idle exceeds default 10000ms ceiling")
    (assert (= (.-ceilingMs vDef) 10000) "Default ceiling must be 10000ms")
    true))

(df testWatchdogPortDetection [] -> Bool
  :d "Verifies automated bound network port detection across log formats."
  (let [(vDirect (wd/detectBoundPort ":port-bound 3000"))
        (vListen (wd/detectBoundPort "Server listening on port 8080"))
        (vHost   (wd/detectBoundPort "Ready at http://localhost:5173/"))
        (vIp1    (wd/detectBoundPort "Serving HTTP on 127.0.0.1:8000 ..."))
        (vIp0    (wd/detectBoundPort "Bound to 0.0.0.0:4000"))
        (vNone   (wd/detectBoundPort "Compiling main.rs: 42 modules processed"))]
    (assert (.-detected vDirect) "Port 3000 must be detected from :port-bound")
    (assert (= (.-port vDirect) 3000) "Port number must be 3000")
    (assert (= (.-event vDirect) ":port-bound") "Event must be :port-bound")
    (assert (.-detected vListen) "Listening on port 8080 must be detected")
    (assert (= (.-port vListen) 8080) "Port number must be 8080")
    (assert (.-detected vHost) "localhost:5173 must be detected")
    (assert (= (.-port vHost) 5173) "Port number must be 5173")
    (assert (.-detected vIp1) "127.0.0.1:8000 must be detected")
    (assert (= (.-port vIp1) 8000) "Port number must be 8000")
    (assert (.-detected vIp0) "0.0.0.0:4000 must be detected")
    (assert (= (.-port vIp0) 4000) "Port number must be 4000")
    (refute (.-detected vNone) "Non-server output must not detect a port")
    (assert (= (.-port vNone) 0) "Port must be 0 for non-server line")
    (assert (= (.-event vNone) ":none") "Event must be :none for non-server line")
    true))

(df testShLifecycleWiring [] -> Bool
  :d "Verifies command execution lifecycle with two-tier spooling and watchdog guards."
  (let [(res (sh/runCmd! "echo" (list "test-spool-output")))]
    (mt res
      ((ok receipt)
       (assert (= (.-exitCode receipt) 0) "ProcessReceipt exit-code must be 0")
       (assert (string-starts-with? (.-spoolPath receipt) "/tmp/asl-proc-") "Spool path must start with /tmp/asl-proc-")
       (assert (string-ends-with? (.-spoolPath receipt) ".spool") "Spool path must end with .spool")
       (assert (< (proc/receiptTokens receipt) 80) "Receipt tokens must be < 80")
       true)
      ((err _)
       (assert false "run-cmd! execution must succeed")
       false))))

(df testDiskSpool50mbHardCap [] -> Bool
  :d "Verifies that streaming 50MB of data enforces the 10MB hard cap in RAM and on disk."
  (let [(path "/tmp/asl-proc-test-50mb.spool")
        (spool0 (spool/makeDiskSpool path 10485760))
        (chunk1mb (string-repeat "0123456789ABCDEF" 65536))
        (lastChunk (str (string-repeat "0123456789ABCDEF" 65535) "FINAL_BYTES_50MB"))
        (spool49 (fold (fn [(s spool/DiskSpool) (_i Int64)] -> spool/DiskSpool
                          (spool/spoolWrite s chunk1mb))
                        spool0
                        (range 0 49)))
        (spool50 (spool/spoolWrite spool49 lastChunk))
        (syncRes (spool/spoolSync! spool50))]
    (assert (= (.-currentBytes spool50) 10485760) "Spool current-bytes must be exactly 10MB (10485760)")
    (assert (<= (int32-to-int64 (string-length (.-content spool50))) 10485760) "Spool content length in RAM must be <= 10485760")
    (assert (string-ends-with? (.-content spool50) "FINAL_BYTES_50MB") "Tail of spool content must match the final bytes of 50MB stream")
    (mt syncRes
      ((ok synced)
       (let [(readRes (file-read path))]
         (mt readRes
           ((ok diskData)
            (let [(diskLen (int32-to-int64 (string-length diskData)))]
              (assert (<= diskLen 10485760) "Synced disk file size read via file-read must be <= 10485760 bytes")
              (assert (= diskLen 10485760) "Synced disk file size must be exactly 10485760 bytes")
              (assert (string-ends-with? diskData "FINAL_BYTES_50MB") "Disk content must preserve trailing stream bytes")
              (let [(unlinked (spool/spoolUnlink synced))]
                (assert (spool/spoolIsUnlinked? unlinked) "Spool must be unlinked after test")
                true)))
           ((err _)
            (assert false "file-read of synced spool must succeed")
            false))))
      ((err _)
       (assert false "spool-sync! must succeed")
       false))))

(df runTests [] -> Bool
  :d "Executes all test suites for two-tier spooling and resource watchdogs."
  (and (testRingBufferCapacity)
       (and (testDiskSpoolCircularCap)
            (and (testDiskSpoolAutoUnlink)
                 (and (testTwoTierSpoolIntegration)
                      (and (testWatchdogRssCeiling)
                           (and (testWatchdogDeadlock)
                                (and (testWatchdogPortDetection)
                                     (and (testShLifecycleWiring)
                                          (testDiskSpool50mbHardCap))))))))))
