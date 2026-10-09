(module asl-mesh/tests/walTest
  :x [RunTests! runTests testWalInitialization testWalAppendAndReplay! testWalTruncateSuffix! testWalChecksumAndVerification!]
  :i [(asl-mesh/wal :a wal)])

fn testWalInitialization -> Bool
  (let [(w (wal/walInit "/tmp/test.wal"))]
    (assert (= w.lastAppendedIndex 0) "initial lastAppendedIndex is 0")
    (refute (!= w.lastAppendedIndex 0) "initial lastAppendedIndex refutes non-zero")
    (assert (listEmpty? w.records) "initial records list is empty")
    true)

fn testWalAppendAndReplay! -> Bool
  (let [(w0 (wal/walInit "/tmp/test.wal"))
        (w1 (wal/walAppendEntry! w0 1 "op-1"))
        (w2 (wal/walAppendEntry! w1 1 "op-2"))
        (replayed (wal/walReplayFromIndex w2 1))]
    (assert (= w2.lastAppendedIndex 2) "lastAppendedIndex is 2 after two appends")
    (assert (= (listLength replayed) 2) "replayed entries has length 2")
    true)

fn testWalTruncateSuffix! -> Bool
  (let [(w0 (wal/walInit "/tmp/test.wal"))
        (w1 (wal/walAppendEntry! w0 1 "op-1"))
        (w2 (wal/walAppendEntry! w1 1 "op-2"))
        (w3 (wal/walAppendEntry! w2 2 "op-3"))
        (wTrunc (wal/walTruncateSuffix! w3 1))]
    (assert (= wTrunc.lastAppendedIndex 1) "lastAppendedIndex is 1 after truncating to 1")
    (assert (= (listLength (wal/walReplayFromIndex wTrunc 1)) 1) "replayed count is 1 after truncation")
    true)

fn testWalChecksumAndVerification! -> Bool
  (let [(w0 (wal/walInit "/tmp/test.wal"))
        (w1 (wal/walAppendEntry! w0 1 "cluster:reconfigure"))
        (records w1.records)
        (rec (optionOr (listHead records) (wal/WalRecord :index 0 :term 0 :command "" :checksum 0)))
        (chkExpected (wal/computeWalChecksum 1 1 "cluster:reconfigure"))
        (tamperedRec (wal/WalRecord :index 1 :term 1 :command "cluster:corrupted" :checksum rec.checksum))]
    (assert (= rec.checksum chkExpected) "appended record has genuine matching FNV-1a checksum")
    (assert (wal/walVerifyRecord rec) "walVerifyRecord approves valid record")
    (refute (wal/walVerifyRecord tamperedRec) "walVerifyRecord refutes tampered payload")
    (refute (= (wal/computeWalChecksum 1 1 "cluster:reconfigure") (wal/computeWalChecksum 1 1 "other")) "distinct commands have distinct checksums")
    true)

fn RunTests! -> Bool
  (and
    (testWalInitialization)
    (and
      (testWalAppendAndReplay!)
      (and
        (testWalTruncateSuffix!)
        (testWalChecksumAndVerification!))))

fn ! runTests -> Bool
  (RunTests!)
