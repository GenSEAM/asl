(module asl-checker/typeVarParamTest :x [runTests] :i [(asl-checker/check :a c) (asl-checker/types :a ty)])

; (:m :ref typeVarParamUnchecked :do "a signature type variable that the body pins to a concrete type (c: C passed to a function taking a record, x: T passed to stringLength) is a check error at the definition, because callers instantiate the variable freshly and would otherwise pass any value and fail at run time with ERR_TYPE; truly generic bodies, Any targets and the concrete signature stay clean")
fn ! checkSnippet! tag: String src: String -> (List ty/Diagnostic)
  (let [(path (str (optionOr (envGet "TMPDIR") "/tmp/") "typeVarParam_" tag "_" (stringFromInt64 (nowNs)) ".asl"))
        (_wrote (fileWrite path src))
        (ds (resultOr (c/checkFile! path (list ".")) (list)))
        (_cleaned (pathRemove path))]
    ds)

fn diagnosticsText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn pinError? ds: (List ty/Diagnostic) name: String shown: String -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code "ERR_TYPE_MISMATCH") (stringContains? d.message (str "type variable " name " of")) (stringContains? d.message shown))) ds)

fn hiddenModule body: String -> String
  (str "(module p/tv :x [passOn])\n\n(schema Hidden (:f n Int64))\n\nfn twiceOf h: Hidden -> Int64\n  (* 2 h.n)\n\n" body)

fn ! runTests -> Bool
  (let [(pin (checkSnippet! "pin" (hiddenModule "fn passOn c: C -> Int64\n  (twiceOf c)\n")))
        (prim (checkSnippet! "prim" "(module p/tv :x [len])\n\nfn len x: T -> Int64\n  (stringLength x)\n"))
        (ret (checkSnippet! "ret" "(module p/tv :x [zero])\n\nfn zero x: T -> T\n  \"none\"\n"))
        (fixed (checkSnippet! "fixed" (hiddenModule "fn passOn c: Hidden -> Int64\n  (twiceOf c)\n")))
        (same (checkSnippet! "same" "(module p/tv :x [same])\n\nfn same x: T -> T\n  x\n"))
        (generic (checkSnippet! "generic" "(module p/tv :x [firstOr])\n\nfn firstOr xs: (List T) d: T -> T\n  (optionOr (listHead xs) d)\n"))
        (merged (checkSnippet! "merged" "(module p/tv :x [second])\n\nfn second a: A b: B -> A\n  b\n"))
        (lamMerge (checkSnippet! "lamMerge" "(module p/tv :x [second])\n\nfn second a: A b: B -> A\n  ((fn [(x A)] -> A x) b)\n"))
        (letMerge (checkSnippet! "letMerge" "(module p/tv :x [second])\n\nfn second a: A b: B -> A\n  (let [(y A b)] y)\n"))
        (lamOwn (checkSnippet! "lamOwn" "(module p/tv :x [second])\n\nfn second a: A b: B -> B\n  ((fn [(x B)] -> B x) b)\n"))
        (letOwn (checkSnippet! "letOwn" "(module p/tv :x [second])\n\nfn second a: A b: B -> A\n  (let [(y A a)] y)\n"))
        (fakePrelude (checkSnippet! "fakePrelude" "(module prelude :x [divF])\n\nfn divF a: N b: N -> (Option N)\n  (if (= b 0.0) none (some (/ a b)))\n"))
        (lam (checkSnippet! "lam" "(module p/tv :x [keep])\n\nfn keep xs: (List T) -> (List T)\n  (filter (fn [(x T)] -> Bool true) xs)\n"))
        (num (checkSnippet! "num" "(module p/tv :x [divF])\n\nfn divF a: N b: N -> (Option N)\n  (if (= b 0.0) none (some (/ a b)))\n"))
        (any (checkSnippet! "any" "(module p/tv :x [show])\n\nfn pick f: Any -> Any\n  f\n\nfn show x: T -> Any\n  (pick x)\n"))]
    (do
      (assert (pinError? pin "C" "Hidden") (str "a type variable passed where a record is required is a check error naming the record: " (diagnosticsText pin)))
      (assert (= (listLength pin) 1) (str "the pin is reported once: " (diagnosticsText pin)))
      (assert (pinError? prim "T" "String") (str "a type variable passed to a String builtin is a check error: " (diagnosticsText prim)))
      (assert (pinError? ret "T" "String") (str "a type variable returned as a literal String is a check error: " (diagnosticsText ret)))
      (assert (listAny? (fn [(d ty/Diagnostic)] -> Bool (and (= d.code "ERR_TYPE_MISMATCH") (stringContains? d.message "type variables A and B of second"))) merged) (str "two signature variables used as one type are a check error: " (diagnosticsText merged)))
      (assert (pinError? num "N" "Float64") (str "a numeric variable pinned to Float64 outside prelude is a check error: " (diagnosticsText num)))
      (assert (pinError? lamMerge "B" "A") (str "a lambda annotated with another signature variable merges the two: " (diagnosticsText lamMerge)))
      (assert (pinError? letMerge "B" "A") (str "a let annotated with another signature variable merges the two: " (diagnosticsText letMerge)))
      (assert (listEmpty? lamOwn) (str "a lambda annotated with its own variable passes: " (diagnosticsText lamOwn)))
      (assert (listEmpty? letOwn) (str "a let annotated with its own variable passes: " (diagnosticsText letOwn)))
      (assert (pinError? fakePrelude "N" "Float64") (str "a user module named prelude is not exempt: " (diagnosticsText fakePrelude)))
      (assert (listEmpty? fixed) (str "the concrete signature passes: " (diagnosticsText fixed)))
      (assert (listEmpty? same) (str "an identity over T passes: " (diagnosticsText same)))
      (assert (listEmpty? generic) (str "a generic body that keeps T abstract passes: " (diagnosticsText generic)))
      (assert (listEmpty? lam) (str "a lambda annotated with the signature variable is not a pin: " (diagnosticsText lam)))
      (assert (listEmpty? any) (str "a type variable passed to Any is not flagged: " (diagnosticsText any)))
      true))
