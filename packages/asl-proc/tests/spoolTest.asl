(module asl-proc/spoolTest :x [testRingBufferCapacity testDiskSpoolCircularCap testDiskSpoolAutoUnlink testTwoTierSpoolIntegration testTwoTierCloseSync! testRssCeilingGuard testDeadlockGuard testPortDetectionGuard testShLifecycleWiring! testRawByteFidelity! testUniqueSpoolPathsAndRelease! testDiskSpool50mbHardCap! runTests] :i [(spool :a spool) (deadline :a wd) (sh :a sh) (asl-proc/process :a proc) (asl-proc/coreProcess :a cp)])

fn testRingBufferCapacity -> Bool
  (let [(init (spool/makeRingBuffer 200)) (rb (fold (fn [(b spool/RingBuffer) (i Int64)] -> spool/RingBuffer (spool/ringPush b (str "line-" (stringFromInt64 i)))) init (range 0 250))) (firstLine (optionOr (listHead rb.lines) "")) (last3 (spool/ringTail rb 3)) (emptyTail (spool/ringTail rb 0)) (defRb (spool/makeRingBuffer 0))] (assert (= (spool/ringSize rb) 200) "Ring buffer size must be capped at 200") (assert (= rb.count 200) "Ring buffer count field must equal 200") (assert (= firstLine "line-50") "Oldest 50 lines must be evicted FIFO (first retained is line-50)") (assert (= (listLength last3) 3) "ring-tail 3 must return exactly 3 lines") (assert (= last3 (list "line-247" "line-248" "line-249")) "Tail lines must match last 3 pushed items") (assert (= (listLength emptyTail) 0) "ring-tail 0 must return empty list") (assert (= defRb.capacity 200) "Default capacity must be 200 when <= 0") true)

fn testDiskSpoolCircularCap -> Bool
  (let [(spool (spool/makeDiskSpool "tmp/test-spool.spool" 100)) (chunkA "012345678901234567890123456789012345678901234567890123456789") (chunkB "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+~<>?[]{}|/=") (s1 (spool/spoolWrite spool chunkA)) (s2 (spool/spoolWrite s1 chunkB)) (defSpool (spool/makeDiskSpool "tmp/default.spool" 0))] (assert (= s1.currentBytes 60) "First write must store exactly 60 bytes") (refute s1.truncated "A write that fits under the cap must not be flagged truncated") (assert (= s2.currentBytes 100) "Second write must be capped at 100 bytes") (assert s2.truncated "A write that drops the head of the content must be flagged truncated") (assert (<= (stringLength s2.content) 100) "Spool content length must not exceed 100 bytes") (assert (stringEndsWith? s2.content chunkB) "Recent chunk bytes must be preserved at tail") (assert (= defSpool.maxBytes 10485760) "Default max-bytes must be 10MB (10485760)") (refute defSpool.truncated "A fresh spool must not be flagged truncated") true)

fn ! testDiskSpoolAutoUnlink -> Bool
  (let [(spool (spool/makeDiskSpool "tmp/unlink-test.spool" 1024))]
    (do
      (refute (spool/spoolIsUnlinked? spool) "Fresh spool must not be unlinked")
      (let [(spoolW (spool/spoolWrite spool "ephemeral-payload")) (unlinkRes (spool/spoolUnlink! spoolW))]
        (do
          (assert (ok? unlinkRes) "spool-unlink! must succeed even when no backing file was ever synced to disk")
          (assert (mt unlinkRes ((ok unlinked) (and (spool/spoolIsUnlinked? unlinked) (and (= unlinked.currentBytes 0) (= unlinked.content "")))) ((err _) false)) "Unlinked spool must be flagged unlinked with cleared bytes and content")
          true))))

fn testTwoTierSpoolIntegration -> Bool
  (let [(tt (spool/makeTwoTierSpool "tmp/two-tier-test.spool" 5 1024)) (pushed (fold (fn [(s spool/TwoTierSpool) (i Int64)] -> spool/TwoTierSpool (spool/twoTierPush s (str "msg-" (stringFromInt64 i)))) tt (range 0 10))) (closed (spool/twoTierClose pushed))] (assert (= (spool/ringSize pushed.ring) 5) "Ring buffer retains last 5 lines") (assert (= (spool/ringTail pushed.ring 2) (list "msg-8" "msg-9")) "Ring tail matches last 2 messages") (assert (> pushed.disk.currentBytes 0) "Disk spool captured non-zero bytes") (assert (spool/spoolIsUnlinked? closed.disk) "Disk spool must be unlinked on close") (assert (= (spool/ringSize closed.ring) 5) "Ring buffer persists after disk unlink for tail inspection") (assert (= (spool/ringTail closed.ring 1) (list "msg-9")) "Tail inspection returns latest line after close") true)

fn testRssCeilingGuard -> Bool
  (let [(vNormal (wd/checkRssCeiling 256 512)) (vBreach (wd/checkRssCeiling 600 512)) (vExact (wd/checkRssCeiling 512 512)) (vDef (wd/checkRssCeiling 600 0))] (refute vNormal.exceeded "RSS 256MB under 512MB ceiling must not exceed") (assert (= vNormal.signal "NONE") "Signal must be NONE for normal usage") (assert (= vNormal.event ":ok") "Event must be :ok for normal usage") (assert vBreach.exceeded "RSS 600MB over 512MB ceiling must exceed") (assert (= vBreach.signal "SIGKILL") "Signal must be SIGKILL on breach") (assert (= vBreach.event ":oom-killed") "Event must be :oom-killed on breach") (refute vExact.exceeded "Exact threshold 512MB must not exceed") (assert vDef.exceeded "RSS 600MB exceeds default 512MB ceiling") (assert (= vDef.ceilingMb 512) "Default ceiling must be 512MB") true)

fn testDeadlockGuard -> Bool
  (let [(vOk (wd/detectDeadlock 5000 10000)) (vDead (wd/detectDeadlock 10000 10000)) (vDef (wd/detectDeadlock 15000 0))] (refute vOk.deadlocked "5000ms idle under 10000ms is not deadlocked") (assert (= vOk.event ":ok") "Event must be :ok") (assert vDead.deadlocked "10000ms idle matches ceiling and is deadlocked") (assert (= vDead.event ":deadlock-detected") "Event must be :deadlock-detected") (assert vDef.deadlocked "15000ms idle exceeds default 10000ms ceiling") (assert (= vDef.ceilingMs 10000) "Default ceiling must be 10000ms") true)

fn testPortDetectionGuard -> Bool
  (let [(vDirect (wd/detectBoundPort ":port-bound 3000")) (vListen (wd/detectBoundPort "Server listening on port 8080")) (vHost (wd/detectBoundPort "Ready at http://localhost:5173/")) (vIp1 (wd/detectBoundPort "Serving HTTP on 127.0.0.1:8000 ...")) (vIp0 (wd/detectBoundPort "Bound to 0.0.0.0:4000")) (vNone (wd/detectBoundPort "Compiling main.rs: 42 modules processed"))] (assert vDirect.detected "Port 3000 must be detected from :port-bound") (assert (= vDirect.port 3000) "Port number must be 3000") (assert (= vDirect.event ":port-bound") "Event must be :port-bound") (assert vListen.detected "Listening on port 8080 must be detected") (assert (= vListen.port 8080) "Port number must be 8080") (assert vHost.detected "localhost:5173 must be detected") (assert (= vHost.port 5173) "Port number must be 5173") (assert vIp1.detected "127.0.0.1:8000 must be detected") (assert (= vIp1.port 8000) "Port number must be 8000") (assert vIp0.detected "0.0.0.0:4000 must be detected") (assert (= vIp0.port 4000) "Port number must be 4000") (refute vNone.detected "Non-server output must not detect a port") (assert (= vNone.port 0) "Port must be 0 for non-server line") (assert (= vNone.event ":none") "Event must be :none for non-server line") true)

fn ! testTwoTierCloseSync! -> Bool
  (let [(tmpDir (str (optionOr (envGet "TMPDIR") "/tmp") "/asl-proc-twotier-" (stringFromInt64 (monotonicNs)))) (path (str tmpDir "/nested/two-tier-sync-test.spool")) (tt (spool/makeTwoTierSpool path 5 1024)) (pushed (fold (fn [(s spool/TwoTierSpool) (i Int64)] -> spool/TwoTierSpool (spool/twoTierPush s (str "msg-" (stringFromInt64 i)))) tt (range 0 3))) (closeRes (spool/twoTierCloseSync! pushed))]
    (do
      (assert (ok? closeRes) "two-tier-close-sync! must succeed")
      (let [(closed (resultOr closeRes pushed)) (readRes (fileRead path))]
        (do
          (refute (spool/spoolIsUnlinked? closed.disk) "Disk spool must remain linked (file present on disk) right after sync-close")
          (assert (ok? readRes) "fileRead of the synced two-tier spool must succeed while it is still linked")
          (assert (mt readRes ((ok diskData) (and (stringContains? diskData "msg-0") (stringContains? diskData "msg-2"))) ((err _) false)) "Synced disk file must contain the pushed messages")
          (let [(unlinkRes (spool/spoolUnlink! closed.disk))]
            (do
              (assert (ok? unlinkRes) "spool-unlink! must succeed")
              (refute (ok? (fileRead path)) "fileRead must fail once the spool has actually been removed from disk")
              (let [(_ (pathRemove tmpDir))] true)))))))

fn ! testShLifecycleWiring! -> Bool
  (let [(expectedPrefix (str (optionOr (envGet "TMPDIR") "/tmp") "/asl-proc/asl-proc-echo-")) (res (sh/runCmd! "echo" (list "hi")))]
    (do
      (assert (ok? res) "run-cmd! execution must succeed")
      (assert (mt res ((ok receipt) (and (= receipt.exitCode 0) (and (stringStartsWith? receipt.spoolPath expectedPrefix) (and (stringEndsWith? receipt.spoolPath ".spool") (< (proc/receiptTokens receipt) 80))))) ((err _) false)) "ProcessReceipt must have exit-code 0, an absolute spool path under TMPDIR/asl-proc, and stay under 80 tokens")
      (let [(spoolPath (mt res ((ok receipt) receipt.spoolPath) ((err _) ""))) (readRes (fileRead spoolPath))]
        (do
          (assert (ok? readRes) "fileRead of the documented spoolPath must succeed")
          (assert (mt readRes ((ok content) (= content "hi\n")) ((err _) false)) "Spool file at the documented spoolPath must hold the command's exact raw output byte-for-byte")
          (let [(releaseRes (mt res ((ok receipt) (sh/releaseReceipt! receipt)) ((err _) (err "no receipt"))))]
            (do
              (assert (ok? releaseRes) "release-receipt! must succeed")
              (refute (ok? (fileRead spoolPath)) "fileRead must fail once the receipt's spool path has been released")
              true))))))

fn ! testRawByteFidelity! -> Bool
  (let [(res (sh/runCmd! "sh" (list "-c" "printf '%s' no-trailing-newline")))]
    (do
      (assert (ok? res) "run-cmd! of a command with no trailing newline must still succeed")
      (let [(spoolPath (mt res ((ok receipt) receipt.spoolPath) ((err _) ""))) (readRes (fileRead spoolPath))]
        (do
          (assert (ok? readRes) "fileRead of the no-trailing-newline command's spool path must succeed")
          (assert (mt readRes ((ok content) (= content "no-trailing-newline")) ((err _) false)) "Spool content must be the exact raw bytes with no newline normalization added")
          (let [(_ (mt res ((ok receipt) (sh/releaseReceipt! receipt)) ((err _) (err "no receipt"))))] true)))))

fn ! testUniqueSpoolPathsAndRelease! -> Bool
  (let [(labels (map (fn [(i Int64)] -> String (str "spool-fidelity-" (stringFromInt64 i))) (range 0 100))) (receiptResults (map (fn [(label String)] -> (Result cp/ProcessReceipt cp/ProcessError) (sh/runCmd! "echo" (list label))) labels))]
    (do
      (assert (listAll? (fn [(r (Result cp/ProcessReceipt cp/ProcessError))] -> Bool (ok? r)) receiptResults) "all 100 runCmd! calls must succeed")
      (let [(receipts (map (fn [(r (Result cp/ProcessReceipt cp/ProcessError))] -> cp/ProcessReceipt (resultOr r (proc/makeProcessReceipt -1 0 0 "" ""))) receiptResults)) (paths (map (fn [(rc cp/ProcessReceipt)] -> String rc.spoolPath) receipts)) (distinctCount (listLength (fold (fn [(acc (List String)) (p String)] -> (List String) (if (listContains? acc p) acc (listAppend acc (list p)))) (list) paths)))]
        (do
          (assert (= distinctCount 100) "100 runCmd! calls must produce 100 distinct spool paths, not a handful reused across calls")
          (let [(pairs (zip receipts labels))]
            (assert (listAll? (fn [(pr (Pair cp/ProcessReceipt String))] -> Bool (let [(rc (pairFirst pr)) (label (pairSecond pr))] (mt (fileRead rc.spoolPath) ((ok content) (stringContains? content label)) ((err _) false)))) pairs) "every receipt's spool file must contain that call's own output, not another run's"))
          (assert (listAll? (fn [(rc cp/ProcessReceipt)] -> Bool (ok? (sh/releaseReceipt! rc))) receipts) "release must succeed for every receipt")
          (refute (listAny? (fn [(p String)] -> Bool (ok? (fileRead p))) paths) "no spool files must remain readable after every receipt has been released")
          true))))

fn ! testDiskSpool50mbHardCap! -> Bool
  (let [(tmpDir (str (optionOr (envGet "TMPDIR") "/tmp") "/asl-proc-spool-" (stringFromInt64 (monotonicNs)))) (_ (dirCreate tmpDir)) (path (str tmpDir "/asl-proc-test-50mb.spool")) (spool0 (spool/makeDiskSpool path 10485760)) (chunk1mb (stringRepeat "0123456789ABCDEF" 65536)) (lastChunk (str (stringRepeat "0123456789ABCDEF" 65535) "FINAL_BYTES_50MB")) (spool49 (fold (fn [(s spool/DiskSpool) (_i Int64)] -> spool/DiskSpool (spool/spoolWrite s chunk1mb)) spool0 (range 0 49))) (spool50 (spool/spoolWrite spool49 lastChunk)) (syncRes (spool/spoolSync! spool50))]
    (do
      (assert (= spool50.currentBytes 10485760) "Spool current-bytes must be exactly 10MB (10485760)")
      (assert (<= (stringLength spool50.content) 10485760) "Spool content length in RAM must be <= 10485760")
      (assert (stringEndsWith? spool50.content "FINAL_BYTES_50MB") "Tail of spool content must match the final bytes of 50MB stream")
      (assert spool50.truncated "A 50MB stream into a 10MB cap must be flagged truncated")
      (assert (ok? syncRes) "spool-sync! must succeed")
      (mt syncRes
        ((err _) false)
        ((ok synced)
          (let [(readRes (fileRead path))]
            (do
              (assert (ok? readRes) "fileRead of synced spool must succeed")
              (assert (mt readRes ((ok diskData) (and (<= (stringLength diskData) 10485760) (and (= (stringLength diskData) 10485760) (stringEndsWith? diskData "FINAL_BYTES_50MB")))) ((err _) false)) "Synced disk file size must be exactly 10485760 bytes and preserve trailing stream bytes")
              (let [(unlinkRes (spool/spoolUnlink! synced))]
                (do
                  (assert (ok? unlinkRes) "spool-unlink! must succeed")
                  (assert (mt unlinkRes ((ok unlinked) (spool/spoolIsUnlinked? unlinked)) ((err _) false)) "Spool must be unlinked after test")
                  (let [(_ (pathRemove tmpDir))] true)))))))))

fn ! runTests -> Bool
  (and (testRingBufferCapacity) (and (testDiskSpoolCircularCap) (and (testDiskSpoolAutoUnlink) (and (testTwoTierSpoolIntegration) (and (testTwoTierCloseSync!) (and (testRssCeilingGuard) (and (testDeadlockGuard) (and (testPortDetectionGuard) (and (testShLifecycleWiring!) (and (testRawByteFidelity!) (and (testUniqueSpoolPathsAndRelease!) (testDiskSpool50mbHardCap!))))))))))))
