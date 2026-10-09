(module asl/packages/asl-agent/tests/ramTxnTest
  :x [runTests]
  :i [(aslAgent/ramTxn :a txn)])

fn testBufferStagingAndDiscard -> Bool
  (let [(vfs0 (txn/makeRamVfs))
        (vfs1 (txn/stageBufferEdit vfs0 "test/file.asl" "(module test) (fn f -> Bool true)"))
        (stagedOpt (txn/getBufferContent vfs1 "test/file.asl"))
        (vfs2 (txn/discardBuffer vfs1 "test/file.asl"))
        (discardedOpt (txn/getBufferContent vfs2 "test/file.asl"))]
    (do
      (assert (some? stagedOpt) "staged buffer content exists")
      (assert (= (optionOr stagedOpt "") "(module test) (fn f -> Bool true)") "staged content matches")
      (refute (some? discardedOpt) "discarded buffer content is removed")
      true))

fn testThreePointGateVerification! -> Bool
  (let [(gateFailCmd "false")
        (gatePassCmd "true")
        (resFail (txn/verifyThreePointGate! gateFailCmd gatePassCmd gateFailCmd))
        (resPass (txn/verifyThreePointGate! gateFailCmd gatePassCmd gatePassCmd))]
    (do
      (assert (ok? resFail) "canonical 3-point check (FAIL, PASS, FAIL) succeeds")
      (refute (ok? resPass) "divergent revert state (FAIL, PASS, PASS) must fail verification")
      (mt resFail
        ((err _) (assert false "resFail must be ok"))
        ((ok receipt)
          (do
            (assert receipt.isVerified "receipt confirms verified status")
            (refute (stringEmpty? receipt.receiptId) "receipt has unique id")
            true)))
      true))

fn ! runTests -> Bool
  (and (testBufferStagingAndDiscard)
       (testThreePointGateVerification!))
