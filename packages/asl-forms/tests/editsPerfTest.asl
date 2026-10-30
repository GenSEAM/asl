(module asl-forms/tests/editsPerfTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/vfs :a v) (asl-forms/edit :a e) (asl-forms/ops :a ops)])


fn lineAt i: Int64 -> String
  (cond ((= (mod i 7) 0) "\n") ((= (mod i 11) 0) "}\n") (else (str "value " (stringFromInt64 (mod (* i 7919) 100003)) " at " (stringFromInt64 i) "\n")))

fn changed i: Int64 -> String
  (if (= (mod i 97) 5) (str "changed " (stringFromInt64 i) "\n") (lineAt i))

fn ms! t0: Int64 -> Int64
  (/ (- (monotonicNs) t0) 1000000)

fn unrouted -> e/Checkers
  (e/Checkers :aslCheck (fn [(p String) (after String) (before (Option String))] -> e/SyntaxResult (e/SyntaxResult :status "error" :message "unrouted" :before "error" :host ""))
              :foreignCheck (fn [(p String) (c String)] -> e/SyntaxResult (e/SyntaxResult :status "error" :message "unrouted" :before "" :host "")))

fn ! runTests -> Bool
  (let [(a (map lineAt (range 0 4000)))
        (b (filter (fn [(l String)] -> Bool (not (stringStartsWith? l "value 1"))) (map changed (range 0 4000))))
        (t0 (monotonicNs))
        (d (e/unifiedDiff! a b "x" "y" 2))
        (small (ms! t0))]
    (println (str "(:editsPerf :diff4000Ms " (stringFromInt64 small) " :diffLines " (stringFromInt64 (listLength d)) ")"))
    (assert (> (listLength d) 100) "the 4000-line diff has hunks")
    (assert (< small 2000) "a 4000-line unified diff takes under 2 s")
    (let [(ws (str (resultOr (realPath "/tmp") "/tmp") "/aslFormsEditsPerf"))
          (big (k/concatAll (map lineAt (range 0 52000))))
          (vs (do (resultOr (pathRemove ws) ()) (resultOr (dirCreate (str ws "/.asl/vfs")) ()) (resultOr (fileWrite (str ws "/big.txt") big) ()) (v/vfsAt ws (str ws "/.asl/vfs") "")))
          (t1 (monotonicNs))
          (ed (e/editStep! vs (unrouted) (list) 1 (mapSet (mapSet (mapSet (mapEmpty) "file" "big.txt") "old" (lineAt 26000)) "new" "edited\n") (list)))
          (df (e/diffStep! vs 2 (mapSet (mapEmpty) "file" "big.txt") (list)))
          (bigMs (ms! t1))]
      (resultOr (pathRemove ws) ())
      (println (str "(:editsPerf :edit52kMs " (stringFromInt64 bigMs) ")"))
      (assert (= ed.errCount 0) "the 52k-line edit stages")
      (assert (stringContains? (optionOr (listHead df.lines) "") ":hunkLines 9 :patch \"--- disk/big.txt\\n+++ staged/big.txt\\n@@ -25999,5 +25999,5 @@") "the 52k-line diff shows the one changed line")
      (assert (< bigMs 60000) "the 52k-line edit plus diff finishes within 60 s")
      true))
