(module asl-forms/tests/editNearTest
  :x [runTests]
  :i [(asl-forms/edit :a e)])

; (:m :ref LEON-OP-HINTS :do "REJECT-HINTS: a refused ASL edit names the module exports and up to 3 closest names with signatures on NOT_EXPORTED, UNKNOWN_SYMBOL and UNDEFINED_EXPORT; the whole refusal stays short")

fn checkerSaying msg: String -> e/Checkers
  (e/Checkers
    :aslCheck (fn [(path String) (content String) (before (Option String))] -> e/SyntaxResult (e/SyntaxResult :status "error" :message msg :before "" :host ""))
    :foreignCheck (fn [(path String) (content String)] -> e/SyntaxResult (e/SyntaxResult :status "ok" :message "" :before "" :host "")))

fn ! refusal! msg: String text: String -> e/Verdict
  (e/validateStaged! (checkerSaying msg) "asl/packages/asl-forms/tests/editNearTmp.asl" (none) text false)

fn ! runTests -> Bool
  (let [(src "(module editNearTmp :x [f])\n\nfn f xs: (List Int64) -> Int64\n  (listHead xs)\n")
        (notExp (refusal! "t.asl:4:4: ERR_NOT_EXPORTED ERR_NOT_EXPORTED: hintForr is not exported by asl-checker/hints" src))
        (unk (refusal! "t.asl:4:4: unbound symbol: listSun; nothing in scope" src))
        (undef (refusal! "t.asl:1:1: ERR_UNDEFINED_EXPORT: g is exported but not defined in this module" "(module editNearTmp :x [f g])\n\nfn f n: Int64 -> Int64\n  (+ n 1)\n\nfn gg n: Int64 -> Int64\n  n\n"))
        (other (refusal! "t.asl:4:4: ERR_ARITY: wrong count" src))
        (big (refusal! "t.asl:4:4: ERR_NOT_EXPORTED ERR_NOT_EXPORTED: loadModuleDepsAliasedd is not exported by asl-checker/resolve" src))
        (bigAt (optionOr (stringIndexOf big.message "(:near") 0))]
    (do (assert (= notExp.code ":ERR_CHECK_FAILED") "a refused check keeps its code")
        (assert (stringContains? notExp.message "(:near :in asl-checker/hints :exports") (str "NOT_EXPORTED names the module and its exports: " notExp.message))
        (assert (stringContains? notExp.message ":closest (hintFor ") (str "NOT_EXPORTED :near carries the right name hintFor with its signature: " notExp.message))
        (assert (stringContains? unk.message ":closest (listSum ") (str "UNKNOWN_SYMBOL :near carries listSum with its signature: " unk.message))
        (assert (stringContains? undef.message "(gg n: Int64 -> Int64)") (str "UNDEFINED_EXPORT :near carries the defined gg with its signature: " undef.message))
        (assert (not (stringContains? other.message "(:near")) (str "a code without candidates adds no near: " other.message))
        (assert (< (stringLength notExp.message) 700) (str "the NOT_EXPORTED refusal stays under 700 characters, got " (stringFromInt64 (stringLength notExp.message))))
        (assert (< (stringLength unk.message) 700) (str "the UNKNOWN_SYMBOL refusal stays under 700 characters, got " (stringFromInt64 (stringLength unk.message))))
        (assert (> bigAt 0) "the big module refusal carries a near tail")
        (assert (<= (- (stringLength big.message) bigAt) 400) (str "a module with many long signatures still gets a near tail of at most 400 characters, got " (stringFromInt64 (- (stringLength big.message) bigAt))))
        true))