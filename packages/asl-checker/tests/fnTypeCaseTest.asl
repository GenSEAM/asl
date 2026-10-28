(module asl-checker/tests/fnTypeCaseTest :x [runTests] :i [(types :a ty) (ast :a a) (resolve :a r) (check :a chk)])

fn ! diagsOf src: String -> (List ty/Diagnostic)
  (match (a/parse src)
    ((err _) (list (ty/Diagnostic :path "test.asl" :line 0 :col 0 :code "parse" :message "parse" :msg "parse")))
    ((ok forms) (chk/checkModule forms (mapEmpty) "test.asl")))

fn hasCode diags: (List ty/Diagnostic) wantCode: String -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool (or acc (= d.code wantCode))) false diags)

fn rule10 src: String -> Bool
  (match (a/parse src)
    ((err _) false)
    ((ok forms) (hasCode (r/resolveModule (r/collectSummary forms "test.asl") forms (mapEmpty)) "rule-10")))

fn withParam paramType: String -> String
  (str "(module t/a :x [g])\n\nfn g cb: " paramType " -> Int64\n  (cb)\n")

fn runTests -> Bool
  (do
    (refute (rule10 (withParam "(fn [] -> Int64)")) "lowercase fn type with no parameters is a known type")
    (refute (rule10 (withParam "(Fn [] -> Int64)")) "Fn is the grammar's spelling of fn (genFnType) and is a known type")
    (refute (rule10 (withParam "(Fn [] Int64)")) "Fn with no parameters and no arrow reads like fn")
    (refute (rule10 "(module t/a :x [g])\n\nfn g cb: (Fn [Int64 String] -> (List Int64)) -> Int64\n  (listLength (cb 1 \"a\"))\n") "Fn with parameters is a known type")
    (assert (rule10 (withParam "(Gn [] -> Int64)")) "an unrelated type head is still rule-10")
    (assert (listEmpty? (diagsOf "(module t/a :x [g])\n\nfn g cb: (Fn Int64 -> (List Int64)) -> Int64\n  (listLength (cb 1))\n")) "bare-param Fn type: cb takes one Int64 and returns a List, so calling it checks clean")
    (assert (listEmpty? (diagsOf "(module t/a :x [g])\n\nfn g cb: (Fn Int64 String -> Int64) -> Int64\n  (cb 1 \"a\")\n")) "bare-param Fn type with two params checks clean")
    (assert (listEmpty? (diagsOf "(module t/a :x [g])\n\nfn g cb: (Fn Int64 String (List Int64)) -> Int64\n  (listLength (cb 1 \"a\"))\n")) "arrowless Fn type: the last type is the return, so cb takes two params and returns a List")
    true)
