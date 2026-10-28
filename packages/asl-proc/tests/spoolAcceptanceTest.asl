(module asl-proc/tests/spoolAcceptanceTest
  :x [runTests RunTests testSpoolAuditPreservation testDiskSpoolCircularCap testRingBufferFIFO testStderrDemuxingAndPreservation testDualPolarityRefutations]
  :i [(asl-proc/spool :a spool) (asl-proc/process :a proc) (asl-proc :a sh) (asl-proc/apm :a apm) (asl-proc/coreProcess :a cp)])

fn receiptOk? result: (Result cp/ProcessReceipt E) -> Bool
  (match result ((ok _) true) ((err _) false))

fn receiptValue result: (Result cp/ProcessReceipt E) -> cp/ProcessReceipt
  (match result ((ok receipt) receipt) ((err _) (cp/ProcessReceipt :exitCode -1 :durationMs 0 :peakRssMb 0 :spoolPath "" :summary "")))

fn diskSpoolOk? result: (Result spool/DiskSpool String) -> Bool
  (match result ((ok _) true) ((err _) false))

fn diskSpoolValue result: (Result spool/DiskSpool String) -> spool/DiskSpool
  (match result ((ok disk) disk) ((err _) (spool/DiskSpool :path "" :maxBytes 0 :currentBytes 0 :content "" :isUnlinked false :truncated false)))

fn testSpoolAuditPreservation -> Bool
  (let [(spoolPath "tmp/audit_test_55602.spool")
        (tt (spool/makeTwoTierSpool spoolPath 5 2048))
        (p1 (spool/twoTierPush tt "audit-transaction-init: step 1"))
        (p2 (spool/twoTierPush p1 "audit-transaction-payload: step 2"))
        (closed (spool/twoTierClose p2))
        (closedDisk closed.disk)
        (closedBytes closedDisk.currentBytes)
        (closedContent closedDisk.content)]
    (assert (> closedBytes 0) "closed spool preserves non-zero byte count")
    (refute (= closedBytes 0) "closed spool must not clear byte count to zero")
    (assert (stringContains? closedContent "audit-transaction-init") "closed spool content preserves initial transaction")
    (assert (stringContains? closedContent "audit-transaction-payload") "closed spool content preserves second transaction")
    (refute (stringEmpty? closedContent) "closed spool content must not be emptied on close")
    (assert (spool/spoolIsUnlinked? closedDisk) "closed spool is flagged as unlinked for descriptor lifecycle")
    (refute (not (spool/spoolIsUnlinked? closedDisk)) "closed spool must acknowledge unlinked state")
    (assert (= (spool/ringSize closed.ring) 2) "ring buffer retains 2 pushed lines after close")
    (refute (!= (spool/ringSize closed.ring) 2) "ring buffer count must remain stable")
    true)

fn testDiskSpoolCircularCap -> Bool
  (let [(cap 128)
        (spool (spool/makeDiskSpool "tmp/circular_55602.spool" cap))
        (chunkA "FIRST_STREAM_PREFIX_0123456789_ALPHA_BETA_GAMMA_DELTA_EPSILON_ZETA_ETA_THETA_IOTA_KAPPA_LAMBDA_MU_NU_XI_OMICRON_PI_RHO_SIGMA_TAU")
        (chunkB "LATEST_STREAM_SUFFIX_9876543210_OMEGA_PSI_CHI_PHI_UPSILON")
        (s1 (spool/spoolWrite spool chunkA))
        (s2 (spool/spoolWrite s1 chunkB))
        (finalBytes s2.currentBytes)
        (finalContent s2.content)]
    (assert (<= finalBytes cap) "spool byte count bounded by cap")
    (assert (= finalBytes cap) "spool fills to exactly cap on overflow")
    (refute (> finalBytes cap) "spool must never breach circular capacity")
    (assert (stringEndsWith? finalContent chunkB) "tail of circular spool preserves latest bytes")
    (refute (stringStartsWith? finalContent "FIRST_STREAM_PREFIX") "head of circular spool is evicted on overflow")
    true)

fn testRingBufferFIFO -> Bool
  (let [(rb0 (spool/makeRingBuffer 4))
        (rb1 (spool/ringPush rb0 "item-0"))
        (rb2 (spool/ringPush rb1 "item-1"))
        (rb3 (spool/ringPush rb2 "item-2"))
        (rb4 (spool/ringPush rb3 "item-3"))
        (rb5 (spool/ringPush rb4 "item-4"))
        (rb6 (spool/ringPush rb5 "item-5"))
        (tail2 (spool/ringTail rb6 2))
        (tailAll (spool/ringTail rb6 10))
        (firstRetained (optionOr (listHead rb6.lines) ""))]
    (assert (= (spool/ringSize rb6) 4) "ring buffer count is capped at 4")
    (refute (> (spool/ringSize rb6) 4) "ring buffer count must not exceed capacity")
    (assert (= firstRetained "item-2") "oldest items evicted FIFO, first retained is item-2")
    (refute (= firstRetained "item-0") "item-0 must have been evicted")
    (refute (= firstRetained "item-1") "item-1 must have been evicted")
    (assert (= (listLength tail2) 2) "tail 2 returns 2 items")
    (assert (= tail2 (list "item-4" "item-5")) "tail 2 matches latest pushed items")
    (assert (= (listLength tailAll) 4) "tail 10 returns all 4 retained items")
    true)

fn ! testStderrDemuxingAndPreservation -> Bool
  (let [(cmd (proc/cmd "sh" (list "-c" "echo out_marker_55602; echo err_marker_55602 >&2")))
        (receiptRes (sh/execReceipt! cmd))]
    (assert (receiptOk? receiptRes) "execReceipt! executes command cleanly")
    (refute (not (receiptOk? receiptRes)) "execReceipt! must not fail on standard command")
    (let [(rcpt (receiptValue receiptRes))]
      (assert (= rcpt.exitCode 0) "process exit code is 0")
      (refute (!= rcpt.exitCode 0) "process exit code must not be non-zero")
      (assert (stringContains? rcpt.spoolPath "/asl-proc/asl-proc-sh-") "spool path uses the OS temp directory and process-specific prefix")
      (assert (stringEndsWith? rcpt.spoolPath ".spool") "spool path has .spool extension")
      (refute (stringEmpty? rcpt.summary) "receipt summary must be non-empty"))
    (let [(demuxer (apm/makeOobDemuxer "tmp/demux_test.spool" 32768))
          (d1 (apm/oobDemuxChunk demuxer "stdout stream line\n"))
          (d2 (apm/oobDemuxChunk d1 "stderr stream diagnostic\n"))
          (finishRes (apm/oobDemuxFinish d2 0 15))]
      (assert (receiptOk? finishRes) "demuxer finish executes cleanly")
      (refute (not (receiptOk? finishRes)) "demuxer finish must not fail")
      (let [(finishRcpt (receiptValue finishRes))]
        (assert (= finishRcpt.exitCode 0) "demuxer finish exit code is 0")
        (refute (!= finishRcpt.exitCode 0) "demuxer finish exit code must be 0")
        (assert (stringEndsWith? finishRcpt.spoolPath ".spool") "demuxer finish produces valid spool path")
        (refute (stringEmpty? finishRcpt.spoolPath) "demuxer spool path must not be empty")))
    true)

fn ! testDualPolarityRefutations -> Bool
  (let [(freshDisk (spool/makeDiskSpool "tmp/fresh_test.spool" 512))
        (unlinkRes (spool/spoolUnlink! freshDisk))
        (failCmd (proc/cmd "nonexistent_sh_subcommand_xyz_789" (list)))
        (failReceipt (sh/execReceipt! failCmd))]
    (refute (spool/spoolIsUnlinked? freshDisk) "freshly created disk spool must not be unlinked")
    (assert (not (spool/spoolIsUnlinked? freshDisk)) "fresh disk spool isUnlinked flag is false")
    (assert (diskSpoolOk? unlinkRes) "spool-unlink! on a never-synced path must still succeed")
    (let [(unlinkedDisk (diskSpoolValue unlinkRes))]
      (assert (spool/spoolIsUnlinked? unlinkedDisk) "explicitly unlinked spool is flagged unlinked")
      (refute (not (spool/spoolIsUnlinked? unlinkedDisk)) "unlinked spool must refute false for isUnlinked"))
    (assert (not (receiptOk? failReceipt)) "nonexistent binary in execReceipt! must return err")
    (refute (receiptOk? failReceipt) "nonexistent binary must not return ok receipt")
    true)

fn ! RunTests -> Bool
  (do
    (assert (testSpoolAuditPreservation) "testSpoolAuditPreservation must pass")
    (assert (testDiskSpoolCircularCap) "testDiskSpoolCircularCap must pass")
    (assert (testRingBufferFIFO) "testRingBufferFIFO must pass")
    (assert (testStderrDemuxingAndPreservation) "testStderrDemuxingAndPreservation must pass")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass")
    true)

fn ! runTests -> Bool
  (RunTests)
