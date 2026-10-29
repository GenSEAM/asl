(module asl-checker/tests/hintsTest
  :x [runTests]
  :i [(asl-checker/hints :a hn) (asl-checker/types :a ty)])

; (:m :do "STATICHINT gap 1, pure table: each diagnostic class gets exactly one short hint, an unknown class gets none, the context hints (nearest name, exporting module) come from the caller")

fn diag code: String msg: String -> ty/Diagnostic
  (ty/Diagnostic :code code :message msg :msg msg :line 1 :col 1 :path "m.asl")

fn hintOf code: String msg: String near: (List String) owners: (List String) -> String
  (optionOr (hn/hintFor (diag code msg) near owners) "")

fn runTests -> Bool
  (let [(opt (hintOf "ERR_TYPE_MISMATCH" "return of f: expected Int64, found (Option Int64)" (list) (list)))
        (res (hintOf "ERR_TYPE_MISMATCH" "argument to +: expected a number, found (Result Int64 String)" (list) (list)))
        (plain (hintOf "ERR_TYPE_MISMATCH" "return of f: expected Int64, found String" (list) (list)))
        (arity (hintOf "ERR_ARITY" "g takes 1 argument(s), given 2" (list) (list)))
        (tarity (hintOf "type-arity" "List in f takes 1 type argument(s), given 2" (list) (list)))
        (unexp (hintOf "rule-9" "ERR_NOT_EXPORTED: foo is not exported by a/b" (list) (list)))
        (imp (hintOf "ERR_UNKNOWN_SYMBOL" "unbound symbol: headerExports" (list "headerFoo") (list "asl-checker/hints")))
        (many (hintOf "ERR_UNKNOWN_SYMBOL" "unbound symbol: zork" (list) (list "a/x" "b/x")))
        (nearest (hintOf "ERR_UNKNOWN_SYMBOL" "unbound symbol: listSun" (list "listSum") (list)))
        (bare (hintOf "ERR_UNKNOWN_SYMBOL" "unbound symbol: qqqq" (list) (list)))
        (other (hintOf "ERR_EFFECT_UNMARKED" "f reaches effectful println" (list) (list)))]
    (do (assert (stringContains? opt "optionOr") (str "Option hint, got " opt))
        (assert (stringContains? res "resultOr") (str "Result hint, got " res))
        (assert (stringEmpty? plain) (str "a plain mismatch gets no hint, got " plain))
        (assert (stringContains? arity "declared parameter count") (str "arity hint, got " arity))
        (assert (stringContains? tarity "type arguments") (str "type-arity hint, got " tarity))
        (assert (stringContains? unexp ":x") (str "unexported hint, got " unexp))
        (assert (and (stringContains? imp "(asl-checker/hints :a hints)") (stringContains? imp "hints/headerExports")) (str "import hint names module and alias, got " imp))
        (assert (stringContains? many "a/x b/x") (str "two owners listed, got " many))
        (assert (= nearest "nearest known name: listSum") (str "nearest-name hint, got " nearest))
        (assert (stringEmpty? bare) (str "no owner and no near name: no hint, got " bare))
        (assert (stringEmpty? other) (str "a class outside the table: no hint, got " other))
        (assert (= (hn/headerExports "(module m :x [a b\n  c])") (list "a" "b" "c")) "headerExports reads a multi-line :x")
        true))
