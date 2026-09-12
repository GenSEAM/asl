(module asl-sh/spool-test
  :d "Falsifiable test suite for APM Two-Tier Spooling and Resource Guards."
  :x [test-ring-buffer-capacity
      test-disk-spool-circular-cap
      test-disk-spool-auto-unlink
      test-two-tier-spool-integration
      test-watchdog-rss-ceiling
      test-watchdog-deadlock
      test-watchdog-port-detection
      test-sh-lifecycle-wiring
      test-disk-spool-50mb-hard-cap
      run-tests]
  :i [(spool        :a spool)
      (watchdog     :a wd)
      (sh           :a sh)
      (asl-sh/process :a proc)])

(df test-ring-buffer-capacity [] -> Bool
  :d "Verifies that RAM RingBuffer evicts oldest lines FIFO when 200 capacity is exceeded."
  (let [(init (spool/make-ring-buffer 200))
        (rb (fold (fn [(b spool/RingBuffer) (i Int64)] -> spool/RingBuffer
                    (spool/ring-push b (str "line-" (string-from-int64 i))))
                  init
                  (range 0 250)))
        (first-line (option-or (list-head (.-lines rb)) ""))
        (last-3 (spool/ring-tail rb 3))
        (empty-tail (spool/ring-tail rb 0))
        (def-rb (spool/make-ring-buffer 0))]
    (assert (= (spool/ring-size rb) 200) "Ring buffer size must be capped at 200")
    (assert (= (.-count rb) 200) "Ring buffer count field must equal 200")
    (assert (= first-line "line-50") "Oldest 50 lines must be evicted FIFO (first retained is line-50)")
    (assert (= (list-length last-3) 3) "ring-tail 3 must return exactly 3 lines")
    (assert (= last-3 (list "line-247" "line-248" "line-249")) "Tail lines must match last 3 pushed items")
    (assert (= (list-length empty-tail) 0) "ring-tail 0 must return empty list")
    (assert (= (.-capacity def-rb) 200) "Default capacity must be 200 when <= 0")
    true))

(df test-disk-spool-circular-cap [] -> Bool
  :d "Verifies circular FIFO byte truncation on DiskSpool when cap is exceeded."
  (let [(spool (spool/make-disk-spool "/tmp/test-spool.spool" 100))
        (chunk-a "012345678901234567890123456789012345678901234567890123456789")
        (chunk-b "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+~<>?[]{}|/=")
        (s1 (spool/spool-write spool chunk-a))
        (s2 (spool/spool-write s1 chunk-b))
        (def-spool (spool/make-disk-spool "/tmp/default.spool" 0))]
    (assert (= (.-current-bytes s1) 60) "First write must store exactly 60 bytes")
    (assert (= (.-current-bytes s2) 100) "Second write must be capped at 100 bytes")
    (assert (<= (int32-to-int64 (string-length (.-content s2))) 100) "Spool content length must not exceed 100 bytes")
    (assert (string-ends-with? (.-content s2) chunk-b) "Recent chunk bytes must be preserved at tail")
    (assert (= (.-max-bytes def-spool) 10485760) "Default max-bytes must be 10MB (10485760)")
    true))

(df test-disk-spool-auto-unlink [] -> Bool
  :d "Verifies auto-unlink transition and storage zeroing upon spool reclamation."
  (let [(spool (spool/make-disk-spool "/tmp/unlink-test.spool" 1024))]
    (assert (not (spool/spool-is-unlinked? spool)) "Fresh spool must not be unlinked")
    (let [(spool-w (spool/spool-write spool "ephemeral-payload"))
          (unlinked (spool/spool-unlink spool-w))]
      (assert (spool/spool-is-unlinked? unlinked) "Spool must be marked as unlinked")
      (assert (= (.-current-bytes unlinked) 0) "Unlinked spool must have 0 current bytes")
      (assert (= (.-content unlinked) "") "Unlinked spool content must be cleared")
      true)))

(df test-two-tier-spool-integration [] -> Bool
  :d "Verifies coordinated RAM ring buffer and disk spool dual writes and close lifecycle."
  (let [(tt (spool/make-two-tier-spool "/tmp/two-tier-test.spool" 5 1024))
        (pushed (fold (fn [(s spool/TwoTierSpool) (i Int64)] -> spool/TwoTierSpool
                        (spool/two-tier-push s (str "msg-" (string-from-int64 i))))
                      tt
                      (range 0 10)))
        (closed (spool/two-tier-close pushed))]
    (assert (= (spool/ring-size (.-ring pushed)) 5) "Ring buffer retains last 5 lines")
    (assert (= (spool/ring-tail (.-ring pushed) 2) (list "msg-8" "msg-9")) "Ring tail matches last 2 messages")
    (assert (> (.-current-bytes (.-disk pushed)) 0) "Disk spool captured non-zero bytes")
    (assert (spool/spool-is-unlinked? (.-disk closed)) "Disk spool must be unlinked on close")
    (assert (= (spool/ring-size (.-ring closed)) 5) "Ring buffer persists after disk unlink for tail inspection")
    (assert (= (spool/ring-tail (.-ring closed) 1) (list "msg-9")) "Tail inspection returns latest line after close")
    true))

(df test-watchdog-rss-ceiling [] -> Bool
  :d "Verifies RSS memory ceiling watchdog verdicts, SIGKILL dispatches, and :oom-killed events."
  (let [(v-normal (wd/check-rss-ceiling 256 512))
        (v-breach (wd/check-rss-ceiling 600 512))
        (v-exact  (wd/check-rss-ceiling 512 512))
        (v-def    (wd/check-rss-ceiling 600 0))]
    (assert (not (.-exceeded v-normal)) "RSS 256MB under 512MB ceiling must not exceed")
    (assert (= (.-signal v-normal) "NONE") "Signal must be NONE for normal usage")
    (assert (= (.-event v-normal) ":ok") "Event must be :ok for normal usage")
    (assert (.-exceeded v-breach) "RSS 600MB over 512MB ceiling must exceed")
    (assert (= (.-signal v-breach) "SIGKILL") "Signal must be SIGKILL on breach")
    (assert (= (.-event v-breach) ":oom-killed") "Event must be :oom-killed on breach")
    (assert (not (.-exceeded v-exact)) "Exact threshold 512MB must not exceed")
    (assert (.-exceeded v-def) "RSS 600MB exceeds default 512MB ceiling")
    (assert (= (.-ceiling-mb v-def) 512) "Default ceiling must be 512MB")
    true))

(df test-watchdog-deadlock [] -> Bool
  :d "Verifies deadlock detector on idle stdin pipes against 10s ceiling."
  (let [(v-ok   (wd/detect-deadlock 5000 10000))
        (v-dead (wd/detect-deadlock 10000 10000))
        (v-def  (wd/detect-deadlock 15000 0))]
    (assert (not (.-deadlocked v-ok)) "5000ms idle under 10000ms is not deadlocked")
    (assert (= (.-event v-ok) ":ok") "Event must be :ok")
    (assert (.-deadlocked v-dead) "10000ms idle matches ceiling and is deadlocked")
    (assert (= (.-event v-dead) ":deadlock-detected") "Event must be :deadlock-detected")
    (assert (.-deadlocked v-def) "15000ms idle exceeds default 10000ms ceiling")
    (assert (= (.-ceiling-ms v-def) 10000) "Default ceiling must be 10000ms")
    true))

(df test-watchdog-port-detection [] -> Bool
  :d "Verifies automated bound network port detection across log formats."
  (let [(v-direct (wd/detect-bound-port ":port-bound 3000"))
        (v-listen (wd/detect-bound-port "Server listening on port 8080"))
        (v-host   (wd/detect-bound-port "Ready at http://localhost:5173/"))
        (v-ip1    (wd/detect-bound-port "Serving HTTP on 127.0.0.1:8000 ..."))
        (v-ip0    (wd/detect-bound-port "Bound to 0.0.0.0:4000"))
        (v-none   (wd/detect-bound-port "Compiling main.rs: 42 modules processed"))]
    (assert (.-detected v-direct) "Port 3000 must be detected from :port-bound")
    (assert (= (.-port v-direct) 3000) "Port number must be 3000")
    (assert (= (.-event v-direct) ":port-bound") "Event must be :port-bound")
    (assert (.-detected v-listen) "Listening on port 8080 must be detected")
    (assert (= (.-port v-listen) 8080) "Port number must be 8080")
    (assert (.-detected v-host) "localhost:5173 must be detected")
    (assert (= (.-port v-host) 5173) "Port number must be 5173")
    (assert (.-detected v-ip1) "127.0.0.1:8000 must be detected")
    (assert (= (.-port v-ip1) 8000) "Port number must be 8000")
    (assert (.-detected v-ip0) "0.0.0.0:4000 must be detected")
    (assert (= (.-port v-ip0) 4000) "Port number must be 4000")
    (assert (not (.-detected v-none)) "Non-server output must not detect a port")
    (assert (= (.-port v-none) 0) "Port must be 0 for non-server line")
    (assert (= (.-event v-none) ":none") "Event must be :none for non-server line")
    true))

(df test-sh-lifecycle-wiring [] -> Bool
  :d "Verifies command execution lifecycle with two-tier spooling and watchdog guards."
  (let [(res (sh/run-cmd! "echo" (list "test-spool-output")))]
    (mt res
      ((ok receipt)
       (assert (= (.-exit-code receipt) 0) "ProcessReceipt exit-code must be 0")
       (assert (string-starts-with? (.-spool-path receipt) "/tmp/asl-proc-") "Spool path must start with /tmp/asl-proc-")
       (assert (string-ends-with? (.-spool-path receipt) ".spool") "Spool path must end with .spool")
       (assert (< (proc/receipt-tokens receipt) 80) "Receipt tokens must be < 80")
       true)
      ((err _)
       (assert false "run-cmd! execution must succeed")
       false))))

(df test-disk-spool-50mb-hard-cap [] -> Bool
  :d "Verifies that streaming 50MB of data enforces the 10MB hard cap in RAM and on disk."
  (let [(path "/tmp/asl-proc-test-50mb.spool")
        (spool0 (spool/make-disk-spool path 10485760))
        (chunk-1mb (string-repeat "0123456789ABCDEF" 65536))
        (last-chunk (str (string-repeat "0123456789ABCDEF" 65535) "FINAL_BYTES_50MB"))
        (spool-49 (fold (fn [(s spool/DiskSpool) (_i Int64)] -> spool/DiskSpool
                          (spool/spool-write s chunk-1mb))
                        spool0
                        (range 0 49)))
        (spool-50 (spool/spool-write spool-49 last-chunk))
        (sync-res (spool/spool-sync! spool-50))]
    (assert (= (.-current-bytes spool-50) 10485760) "Spool current-bytes must be exactly 10MB (10485760)")
    (assert (<= (int32-to-int64 (string-length (.-content spool-50))) 10485760) "Spool content length in RAM must be <= 10485760")
    (assert (string-ends-with? (.-content spool-50) "FINAL_BYTES_50MB") "Tail of spool content must match the final bytes of 50MB stream")
    (mt sync-res
      ((ok synced)
       (let [(read-res (file-read path))]
         (mt read-res
           ((ok disk-data)
            (let [(disk-len (int32-to-int64 (string-length disk-data)))]
              (assert (<= disk-len 10485760) "Synced disk file size read via file-read must be <= 10485760 bytes")
              (assert (= disk-len 10485760) "Synced disk file size must be exactly 10485760 bytes")
              (assert (string-ends-with? disk-data "FINAL_BYTES_50MB") "Disk content must preserve trailing stream bytes")
              (let [(unlinked (spool/spool-unlink synced))]
                (assert (spool/spool-is-unlinked? unlinked) "Spool must be unlinked after test")
                true)))
           ((err _)
            (assert false "file-read of synced spool must succeed")
            false))))
      ((err _)
       (assert false "spool-sync! must succeed")
       false))))

(df run-tests [] -> Bool
  :d "Executes all test suites for two-tier spooling and resource watchdogs."
  (and (test-ring-buffer-capacity)
       (and (test-disk-spool-circular-cap)
            (and (test-disk-spool-auto-unlink)
                 (and (test-two-tier-spool-integration)
                      (and (test-watchdog-rss-ceiling)
                           (and (test-watchdog-deadlock)
                                (and (test-watchdog-port-detection)
                                     (and (test-sh-lifecycle-wiring)
                                          (test-disk-spool-50mb-hard-cap))))))))))
