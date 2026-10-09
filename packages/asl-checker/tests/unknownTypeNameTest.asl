(module asl-checker/unknownTypeNameTest :x [runTests RunTests] :i [(types :a ty) (check :a c)])

fn checkHasCode diags: (List ty/Diagnostic) wantCode: String -> Bool
  (fold (fn [(acc Bool) (d ty/Diagnostic)] -> Bool (or acc (= d.code wantCode))) false diags)

fn sourceDiags src: String -> (List ty/Diagnostic)
  (c/checkSource src (mapEmpty) "unknownTypeNameTest.asl")

fn testUnknownTypeNameInLambdaParam -> Bool
  (let [(ds (sourceDiags "(module m :x [foo]) (fn foo [] -> Int64 (let [(g (fn [(x (Fn A B))] -> Int64 1))] (g 1)))"))]
    (checkHasCode ds "rule-10"))

fn testUnknownTypeNameInLambdaReturn -> Bool
  (let [(ds (sourceDiags "(module m :x [foo]) (fn foo [] -> Int64 (let [(g (fn [(x Int64)] -> Bogus x))] 1))"))]
    (checkHasCode ds "rule-10"))

fn testTypevarNotFlaggedAsUnknown -> Bool
  (let [(ds (sourceDiags "(module m :x [foo]) (fn foo [] -> Int64 (let [(g (fn [(x T)] -> T x))] (g 1)))"))]
    (not (checkHasCode ds "rule-10")))

fn testKnownParamTypeNotFlagged -> Bool
  (let [(ds (sourceDiags "(module m :x [foo]) (fn foo [] -> Int64 (let [(g (fn [(x (List Int64))] -> Int64 1))] (g (list 1))))"))]
    (not (checkHasCode ds "rule-10")))

fn runTests -> Bool
  (do
    (assert (testUnknownTypeNameInLambdaParam) "unknown type constructor in lambda param is rule-10")
    (assert (testUnknownTypeNameInLambdaReturn) "unknown type constructor in lambda return is rule-10")
    (assert (testTypevarNotFlaggedAsUnknown) "a bare single-letter typevar in a lambda is not rule-10")
    (assert (testKnownParamTypeNotFlagged) "a known parameterized type in a lambda is not rule-10")
    true)

fn RunTests -> Bool
  (runTests)
