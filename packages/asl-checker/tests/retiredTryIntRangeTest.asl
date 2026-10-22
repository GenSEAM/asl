(module asl-checker/tests/retiredTryIntRangeTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/check :a c) (asl-checker/types :a ty)])

fn diagsOf src: String -> (List ty/Diagnostic)
  (match (a/parseForTypeCheck src)
    ((ok forms) (c/checkModuleSource forms (mapEmpty) "probe.asl" src))
    ((err _) (list)))

fn codesOf src: String -> (List String)
  (map (fn [(d ty/Diagnostic)] -> String d.code) (diagsOf src))

fn messagesOf src: String -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) (diagsOf src)) "; ")

fn tryInResult -> String
  "(module probe :x [f] :i [])\nfn g -> (Result Int64 String)\n  (ok 1)\nfn f -> (Result Int64 String)\n  (ok (try (g)))\n"

fn tryInLambda -> String
  "(module probe :x [f] :i [])\nfn g s: String -> (Result Int64 String)\n  (ok 1)\nfn f xs: (List String) -> (Result (List Int64) String)\n  (ok (map (fn [(x String)] -> Int64 (try (g x))) xs))\n"

fn int32Over -> String
  "(module probe :x [f] :i [])\nfn f n: Int32 -> Int32\n  (+ n 2147483648)\n"

fn int32Fits -> String
  "(module probe :x [f] :i [])\nfn f n: Int32 -> Int32\n  (+ n 2147483647)\n"

fn constantCases -> (List String)
  (list "(module probe :x [f] :i [])\nfn f -> Bool\n  (do (assert true \"t\") true)\n"
        "(module probe :x [f] :i [])\nfn f -> Bool\n  (do (assert (= 1 1) \"one\") true)\n"
        "(module probe :x [f] :i [])\nfn f -> Bool\n  (let [(k 3)] (do (refute (> k 4) \"k\") true))\n"
        "(module probe :x [f] :i [])\nfn f -> Bool\n  (do (refute false \"never\") true)\n")

fn computedCases -> (List String)
  (list "(module probe :x [f] :i [])\nfn f n: Int64 -> Bool\n  (do (assert (= n 1) \"n\") true)\n"
        "(module probe :x [f] :i [])\nfn f -> Bool\n  (do (assert false \"marker\") true)\n"
        "(module probe :x [f] :i [])\nfn f -> Bool\n  (do (assert (= (listLength (list 1)) 1) \"computed\") true)\n"
        "(module probe :x [f] :i [])\n; (:m :tags (hostSubject))\nfn f -> Bool\n  (do (assert (= (+ 1 2) 3) \"reader subject\") true)\n")

fn unmarkedSpawn -> String
  "(module probe :x [touch] :i [])\nfn touch -> Int64\n  (processRun \"true\").exitCode\n"

fn markedSpawn -> String
  "(module probe :x [touch] :i [])\nfn ! touch -> Int64\n  (processRun \"true\").exitCode\n"

fn ! runTests -> Bool
  (do
    (refute (listContains? (codesOf (unmarkedSpawn)) "ERR_EFFECT_UNMARKED") (str "EFFECT-INFER: processRun (host effect flag) in a fn without ! infers clean outside a :pure package: " (messagesOf (unmarkedSpawn))))
    (refute (listContains? (codesOf (markedSpawn)) "ERR_EFFECT_UNMARKED") (str "fn ! may spawn: " (messagesOf (markedSpawn))))
    (assert (listAll? (fn [(src String)] -> Bool (listContains? (codesOf src) "ERR_CONSTANT_ASSERT")) (constantCases)) (str "a constant assert or refute condition is ERR_CONSTANT_ASSERT (D152): " (stringJoin (map messagesOf (constantCases)) " | ")))
    (refute (listAny? (fn [(src String)] -> Bool (listContains? (codesOf src) "ERR_CONSTANT_ASSERT")) (computedCases)) (str "computed conditions, failure markers and hostSubject fns pass: " (stringJoin (map messagesOf (computedCases)) " | ")))
    (assert (listContains? (codesOf (tryInResult)) "ERR_UNKNOWN_SYMBOL") (str "try is retired even where it would propagate a Result: " (messagesOf (tryInResult))))
    (assert (stringContains? (messagesOf (tryInResult)) "unbound symbol: try") (str "the diagnostic names try: " (messagesOf (tryInResult))))
    (assert (listContains? (codesOf (tryInLambda)) "ERR_UNKNOWN_SYMBOL") (str "try inside a lambda is the same unknown symbol: " (messagesOf (tryInLambda))))
    (refute (listContains? (codesOf (tryInLambda)) "rule-5") (str "no rule-5 code leaks out: " (messagesOf (tryInLambda))))
    (assert (listContains? (codesOf (int32Over)) "ERR_INT_RANGE") (str "a literal past Int32 is ERR_INT_RANGE: " (messagesOf (int32Over))))
    (refute (listContains? (codesOf (int32Over)) "literal-range") (str "the internal literal-range code is mapped: " (messagesOf (int32Over))))
    (assert (listEmpty? (diagsOf (int32Fits))) (str "Int32 max fits: " (messagesOf (int32Fits))))
    true)
