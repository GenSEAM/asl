(module aslAgent/ramTxn
  :x [RamBuffer RamVfs ThreePointReceipt makeRamVfs stageBufferEdit getBufferContent discardBuffer flushBufferAtomic! verifyThreePointGate!]
  :i [])

(schema RamBuffer
  (:f path Str)
  (:f content Str)
  (:f isDirty Bool))

(schema RamVfs
  (:f buffers (List RamBuffer)))

(schema ThreePointReceipt
  (:f receiptId Str)
  (:f isVerified Bool)
  (:f discardExit I64)
  (:f applyExit I64)
  (:f revertExit I64))

fn makeRamVfs -> RamVfs
  (RamVfs :buffers (list))

fn stageBufferEdit vfs: RamVfs path: Str newContent: Str -> RamVfs
  (let [(existing vfs.buffers)
        (filtered (filter (fn [(b RamBuffer)] -> Bool (!= b.path path)) existing))
        (newBuf (RamBuffer :path path :content newContent :isDirty true))]
    (RamVfs :buffers (cons newBuf filtered)))

fn getBufferContent vfs: RamVfs path: Str -> (Option Str)
  (let [(existing vfs.buffers)]
    (fold (fn [(found (Option Str)) (b RamBuffer)] -> (Option Str)
            (mt found
              ((some _) found)
              ((none) (if (= b.path path)
                        (some b.content)
                        (none)))))
          (none) existing))

fn discardBuffer vfs: RamVfs path: Str -> RamVfs
  (let [(existing vfs.buffers)
        (remaining (filter (fn [(b RamBuffer)] -> Bool (!= b.path path)) existing))]
    (RamVfs :buffers remaining))

fn flushBufferAtomic! vfs: RamVfs path: Str -> (Result Unit Str)
  (let [(contentOpt (getBufferContent vfs path))]
    (mt contentOpt
      ((none) (err (str "No buffered content found for path: " path)))
      ((some content)
        (let [(writeRes (fileWrite path content))]
          (mt writeRes
            ((err e) (err (str "Failed to flush RAM buffer: " e)))
            ((ok _) (ok ())))))))

fn verifyThreePointGate! discardCmd: Str applyCmd: Str revertCmd: Str -> (Result ThreePointReceipt Str)
  (let [(resDiscard (processRun discardCmd))
        (resApply (processRun applyCmd))
        (resRevert (processRun revertCmd))
        (dCode resDiscard.exitCode)
        (aCode resApply.exitCode)
        (rCode resRevert.exitCode)]
    (if (and (!= dCode 0) (and (= aCode 0) (!= rCode 0)))
      (ok (ThreePointReceipt :receiptId (str "rcpt-3point-" (stringFromInt64 aCode)) :isVerified true :discardExit dCode :applyExit aCode :revertExit rCode))
      (err (str "Three-point verification failed: gate(discard)=" (stringFromInt64 dCode) " gate(apply)=" (stringFromInt64 aCode) " gate(revert)=" (stringFromInt64 rCode)))))
