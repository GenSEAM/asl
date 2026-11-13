(module asl-checker/variantCallTest :x [runTests] :i [(asl-checker/check :a c) (asl-checker/types :a ty)])

; (:m :ref checkMissesVariantCall :do "a call whose head is a form evaluating to a non-function (a duplicated ((ok x) ...) match clause, a vector head) is a check error, not a run-time ERR_TYPE cannot call a Variant; Any heads and function-returning heads stay legal")
fn ! checkSnippet! tag: String src: String -> (List ty/Diagnostic)
  (let [(path (str (optionOr (envGet "TMPDIR") "/tmp/") "variantCall_" tag "_" (stringFromInt64 (nowNs)) ".asl"))
        (_wrote (fileWrite path src))
        (ds (resultOr (c/checkFile! path (list ".")) (list)))
        (_cleaned (pathRemove path))]
    ds)

fn diagnosticsText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn callError? ds: (List ty/Diagnostic) -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code "ERR_TYPE_MISMATCH") (stringContains? d.message "cannot call"))) ds)

fn ! runTests -> Bool
  (let [(dup (checkSnippet! "dup" "(module p/vc :x [f])\n\nfn f r: (Result Float64 String) -> Float64\n  (match r ((err e) 0.0) ((ok x) ((ok x) (+ x 1.0))))\n"))
        (vec (checkSnippet! "vec" "(module p/vc :x [f])\n\nfn f x: Int64 -> Int64\n  ([x] 1)\n"))
        (hof (checkSnippet! "hof" "(module p/vc :x [f])\n\nfn adder n: Int64 -> (fn [Int64] -> Int64)\n  (fn [(m Int64)] -> Int64 (+ n m))\n\nfn f -> Int64\n  ((adder 1) 2)\n"))
        (any (checkSnippet! "any" "(module p/vc :x [f])\n\nfn pick f: Any -> Any\n  f\n\nfn f g: Any -> Int64\n  ((pick g) 1)\n"))
        (ok (checkSnippet! "ok" "(module p/vc :x [f])\n\nfn f r: (Result Float64 String) -> Float64\n  (match r ((err e) 0.0) ((ok x) (+ x 1.0)))\n"))]
    (do
      (assert (callError? dup) (str "a match clause body that calls a pattern is a check error: " (diagnosticsText dup)))
      (assert (callError? vec) (str "a vector in call position is a check error: " (diagnosticsText vec)))
      (assert (listEmpty? hof) (str "a call whose head returns a function is legal: " (diagnosticsText hof)))
      (assert (listEmpty? any) (str "a head of type Any is not flagged: " (diagnosticsText any)))
      (assert (listEmpty? ok) (str "the corrected clause passes: " (diagnosticsText ok)))
      true))
