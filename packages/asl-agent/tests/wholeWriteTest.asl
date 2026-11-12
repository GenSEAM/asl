(module aslAgent/tests/wholeWriteTest
  :x [runTests]
  :i [(aslAgent/exec :a ex)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)])

fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn intField rec: (List (Pair String ex/Val)) k: String -> Int64
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vInt n) n) (_ -1)))
    ((none) -1))

fn writeOp file: String content: String -> (List (Pair String c/KvVal))
  (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr "write"))
    (pair "file" (c/kvStr file)) (pair "content" (c/kvStr content)))

fn editOp file: String old: String new: String -> (List (Pair String c/KvVal))
  (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr "edit"))
    (pair "file" (c/kvStr file)) (pair "old" (c/kvStr old)) (pair "new" (c/kvStr new)))

fn fill n: Int64 -> String
  (stringJoin (map (fn [i] "a") (range 0 n)) "")

fn freshRoot -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        root (str base "/wholeWriteTest-" (stringFromInt64 (nowNs)))]
    (if (ok? (dirCreate root)) root root))

fn runTests -> Bool
  (let [root (freshRoot)
        big (str root "/big.txt")
        small (str root "/small.txt")
        bigOk (ok? (fileWrite big (fill 5000)))
        smallOk (ok? (fileWrite small (fill 100)))
        env (ex/makeExecEnv root root "auto" (list "**") false "HEAD" (list)
              (list (pair "read" "local") (pair "write" "local") (pair "edit" "local"))
              "" (list) 20000 60 (none) "wholeWriteTest" (none))
        idf (fn [] "id1")
        snap (fn [s] false)
        onKeep (fn [a b n] true)
        run (fn [f d] (t/aslRun 0 "" ""))
        outBig (ex/execOp! (writeOp "big.txt" "replacement") env (r/newProcs) idf snap onKeep run)
        recBig outBig.rec
        outSmall (ex/execOp! (writeOp "small.txt" "replacement") env (r/newProcs) idf snap onKeep run)
        recSmall outSmall.rec
        outNew (ex/execOp! (writeOp "new.txt" "fresh") env (r/newProcs) idf snap onKeep run)
        recNew outNew.rec
        outEdit (ex/execOp! (editOp "big.txt" "a" "b") env (r/newProcs) idf snap onKeep run)
        recEdit outEdit.rec
        hint (strField recBig "hint")]
    (do
      (assert bigOk "the 5000-byte fixture is written")
      (assert smallOk "the 100-byte fixture is written")
      (assert (= (resultOr (fileSize big) -1) 5000) "the big fixture is 5000 bytes on disk")
      (assert (= (resultOr (fileSize small) -1) 100) "the small fixture is 100 bytes on disk")
      (assert (= (strField recBig "status") "rejected") "a whole write of an existing 5000-byte file is rejected")
      (assert (= (strField recBig "error") "ERR_WRITE_WHOLE_FILE") "the big-file refusal is ERR_WRITE_WHOLE_FILE")
      (assert (= (strField recBig "file") "big.txt") "the refusal names the target file")
      (assert (= (intField recBig "bytes") 5000) "the refusal carries the existing size in :bytes")
      (assert (stringContains? hint ":edit") "the hint offers (:edit)")
      (assert (stringContains? hint ":old ... :new ...") "the hint shows the edit shape")
      (assert (stringContains? hint ":read") "the hint offers (:read) first")
      (assert (= (strField recSmall "status") "ok") "a whole write of an existing 100-byte file passes")
      (assert (!= (strField recSmall "error") "ERR_WRITE_WHOLE_FILE") "the small-file write is not refused as a whole write")
      (assert (= (strField recNew "status") "ok") "a whole write of a new file passes")
      (assert (= (strField recEdit "status") "ok") "an edit of the 5000-byte file passes")
      (assert (ok? (pathRemove root)) "the temp dir is removed")
      true))
