(module aslAgent/tests/retryTemplateTest
  :x [runTests]
  :i [(aslAgent/txn :a t)])

; (:m :ref LEON-WHOLE-FILE-WRITE :do "a rejected edit or flush must not tell the writer to resend a large file whole: retryTemplate gives write only under 4096 bytes or a new file, edit otherwise; largeFileHint says one edit per fn")

fn ! runTests -> Bool
  (let [big (t/retryTemplate "native.asl" 30000)
        small (t/retryTemplate "small.asl" 200)
        fresh (t/retryTemplate "new.asl" 0)
        hint (t/largeFileHint)]
    (do
      (assert (stringContains? big ":op \"edit\"") "a large file gets an edit template")
      (assert (not (stringContains? big ":content :raw")) "a large file is not resent whole")
      (assert (stringContains? small ":content :raw") "a small file gets a write template")
      (assert (stringContains? fresh ":content :raw") "a new file gets a write template")
      (assert (stringContains? hint "edit") "the hint says edit")
      true))
