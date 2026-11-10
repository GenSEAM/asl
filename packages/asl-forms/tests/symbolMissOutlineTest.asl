(module asl-forms/tests/symbolMissOutlineTest
  :x [runTests]
  :i [(asl-forms/ops :a ops) (asl-forms/kernel :a k)])

fn testMissOutline! -> Bool
  (let [(tmp (str (optionOr (envGet "TMPDIR") "/tmp/") "aslSymbolMissOutline_" (stringFromInt64 (mod (nowNs) 1000000))))
        (made (dirCreate tmp))
        (root (resultOr (realPath tmp) tmp))
        (file (k/joinPath tmp "sample.asl"))
        (content "(module temp/sample :x [alpha beta])\n\nfn alpha -> Int64\n  1\n\nfn beta x: Int64 -> Int64\n  (+ x 1)\n")
        (written (fileWrite file content))
        (miss (ops/runStep! root 1 "(:read :file \"sample.asl\" :symbol \"gamma\")"))
        (missLine (optionOr (listHead miss.lines) ""))
        (hit (ops/runStep! root 2 "(:read :file \"sample.asl\" :symbol \"alpha\")"))
        (hitLine (optionOr (listHead hit.lines) ""))
        (removed (pathRemove file))
        (cleaned (pathRemove tmp))]
    (do
      (assert (ok? made) "temp directory created")
      (assert (ok? written) "temp asl file written")
      (assert (= miss.errCount 1) "unknown symbol is rejected")
      (assert (stringContains? missLine ":ERR_SYMBOL_NOT_FOUND") missLine)
      (assert (stringContains? missLine " :outline [") "miss carries an outline list")
      (assert (stringContains? missLine " :nearest [") "miss still carries nearest names")
      (assert (stringContains? missLine "\"alpha 3-4\"") "outline lists alpha with its line range")
      (assert (stringContains? missLine "\"beta 6-7\"") "outline lists beta with its line range")
      (assert (= hit.errCount 0) "known symbol read succeeds")
      (assert (stringContains? hitLine ":status \"ok\"") "read of alpha has ok status")
      (assert (stringContains? hitLine "fn alpha") "read of alpha returns its body")
      (assert (ok? removed) "temp asl file removed")
      (assert (ok? cleaned) "temp directory removed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testMissOutline!) "testMissOutline")
    true)
