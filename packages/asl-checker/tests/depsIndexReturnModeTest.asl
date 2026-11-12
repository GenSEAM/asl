(module asl-checker/depsIndexReturnModeTest :x [runTests] :i [(asl-checker/resolve :a r) (asl-checker/foreign :a ff) (asl-parser/ast :a a) (asl-parser/reader :a rd)])

; (:m :ref LLVM-FOR-ENTRY-TESTS :do "loadModuleDepsIx! hands back the module index its walk built, so a second load resolves against it; withReturnMode appends the return mode of a four-item foreign body: result for a Result return, value otherwise, and leaves any other body alone")
fn summaryName deps: (Map String r/ModuleSummary) key: String -> String
  (match (mapGet deps key) ((some s) s.name) ((none) ""))

fn namesOf res: (Result (Map String r/ModuleSummary) String) -> String
  (match res ((err e) (str "err " e)) ((ok deps) (str (summaryName deps "asl-checker/types") "|" (summaryName deps "unify"))))

fn ! testLoadModuleDepsIx -> Bool
  (let [(roots (list "asl/packages/asl-checker/tests"))
        (first (r/loadModuleDepsIx! roots (list "asl-checker/types" "unify") (r/emptyModIndex)))
        (ix (pairSecond first))
        (again (r/loadModuleDepsIx! roots (list "asl-checker/types" "unify") ix))
        (missing (r/loadModuleDepsIx! roots (list "noSuchModuleDepsIndexZz") (r/emptyModIndex)))]
    (do
      (assert (= (namesOf (pairFirst first)) "asl-checker/types|asl-checker/unify") (str "both imports resolve: " (namesOf (pairFirst first))))
      (assert (> (listLength ix.mods) 0) "the index the walk built is handed back, not the empty one passed in")
      (assert (!= ix.root "") "the handed-back index names the root it walked")
      (assert (= (namesOf (pairFirst again)) (namesOf (pairFirst first))) "a load against the handed-back index resolves the same modules")
      (assert (= (listLength (pairSecond again).mods) (listLength ix.mods)) "a load against a built index keeps it")
      (assert (= (pairFirst missing) (err "notFound")) "an unknown import is notFound")
      true))

fn defunOf src: String -> (Option a/DefunNode)
  (match (a/parse (str "(module t/f :x [f])\n\n" src))
    ((err _) (none))
    ((ok forms) (match (listGet forms 1) ((some (a/topDefun d)) (some d)) (_ (none)))))

fn modeOf src: String -> String
  (match (defunOf src)
    ((none) "noDefun")
    ((some d) (stringJoin (map rd/renderSexpr (ff/withReturnMode d).body) " ")))

fn ! testWithReturnMode -> Bool
  (do
    (assert (= (modeOf "fn f x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")\n") "(foreign \"m\" \"cbrt\" \"f64 -> f64\" \"value\")") (str "a plain return gets value: " (modeOf "fn f x: Float64 -> Float64\n  (foreign \"m\" \"cbrt\" \"f64 -> f64\")\n")))
    (assert (= (modeOf "fn f x: Int64 -> (Result Int64 String)\n  (foreign \"c\" \"abs\" \"i64 -> i64\")\n") "(foreign \"c\" \"abs\" \"i64 -> i64\" \"result\")") (str "a Result return gets result: " (modeOf "fn f x: Int64 -> (Result Int64 String)\n  (foreign \"c\" \"abs\" \"i64 -> i64\")\n")))
    (assert (= (modeOf "fn f x: Int64 -> Int64\n  (foreign \"c\" \"abs\" \"i64 -> i64\" \"value\")\n") "(foreign \"c\" \"abs\" \"i64 -> i64\" \"value\")") "a body that already names its mode is left alone")
    (assert (= (modeOf "fn f x: Int64 -> Int64\n  (+ x 1)\n") "(+ x 1)") "a body that is not a foreign call is left alone")
    (assert (= (modeOf "fn f x: Int64 -> Int64\n  (foreign \"c\" \"abs\" \"i64 -> i64\")\n  x\n") "(foreign \"c\" \"abs\" \"i64 -> i64\") x") "a foreign call that is not the whole body is left alone")
    true)

fn ! runTests -> Bool
  (do
    (assert (testLoadModuleDepsIx) "testLoadModuleDepsIx")
    (assert (testWithReturnMode) "testWithReturnMode")
    true)
