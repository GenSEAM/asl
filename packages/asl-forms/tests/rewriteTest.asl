(module asl-forms/tests/rewriteTest
  :x [runTests]
  :i [(asl-forms/rewrite :a rw)])

fn testAslSingleNodeRewrites -> Bool
  (let [(src1 "fn test x: Option -> Bool\n  (some? x)\n")
        (expected1 "fn test x: Option -> Bool\n  (some? x)\n")
        (res1 (rw/rewrite src1 "(some? $X)" "(some? $X)" "asl"))
        (src2 "fn addZero a: Int64 -> Int64\n  (+ (* a 2) 0)\n")
        (expected2 "fn addZero a: Int64 -> Int64\n  (* a 2)\n")
        (res2 (rw/rewrite src2 "(+ $A 0)" "$A" "asl"))
        (src3 "fn swapArgs a: Int64 b: Int64 -> Pair\n  (pair b a)\n")
        (res3 (rw/rewrite src3 "(pair $A $B)" "(pair $B $A)" "asl"))
        (expected3 "fn swapArgs a: Int64 b: Int64 -> Pair\n  (pair a b)\n")]
    (do
      (assert (= res1 expected1) "asl some? to some? rewrite must match expected")
      (assert (= res2 expected2) "asl (+ $A 0) to $A rewrite must match expected")
      (assert (= res3 expected3) "asl (pair $A $B) to (pair $B $A) rewrite must match expected")
      true))

fn testAslSequenceRewrites -> Bool
  (let [(src "(module foo/bar\n  :x [a b]\n  :i [])\n")
        (expected "(module foo/bar\n  :x [a b]\n  :i [])\n")
        (res (rw/rewrite src "(module $NAME :d $DOC $$$REST)" "(module $NAME\n  $$$REST)" "asl"))]
    (do
      (assert (= res expected) "asl module sequence rewrite must drop :d and keep rest")
      true))

fn testAsnRewrites -> Bool
  (let [(src "(:v :n 1 :status \"pending\" :note \"first\")\n(:v :n 2 :status \"pending\" :note \"second\")\n")
        (expected "(:v :n 1 :status \"done\" :note \"first\")\n(:v :n 2 :status \"done\" :note \"second\")\n")
        (res (rw/rewrite src "(:v :n $N :status \"pending\" $$$REST)" "(:v :n $N :status \"done\" $$$REST)" "asn"))
        (src2 "(:item :name \"foo\" :val 42)")
        (expected2 "(:entry :key \"foo\" :val 42)")
        (res2 (rw/rewrite src2 "(:item :name $N :val $V)" "(:entry :key $N :val $V)" "asn"))]
    (do
      (assert (= res expected) "asn status pending to done rewrite must match expected")
      (assert (= res2 expected2) "asn item to entry rewrite must match expected")
      true))

fn testJsRewrites -> Bool
  (let [(src "function test(x) {\n  console.log(x);\n  return x + 1;\n}\n")
        (expected "function test(x) {\n  logger.info(x);\n  return x + 1;\n}\n")
        (res (rw/rewrite src "console.log($ARG);" "logger.info($ARG);" "js"))
        (srcCall "foo(1, 2, 3);\n")
        (expectedCall "bar(1, 2, 3);\n")
        (resCall (rw/rewrite srcCall "foo($$$ARGS)" "bar($$$ARGS)" "js"))
        (srcStmts "function test() {\n  let a = 1;\n  let b = 2;\n}\n")
        (expectedStmts "function run() {\n  let a = 1;\n  let b = 2;\n}\n")
        (resStmts (rw/rewrite srcStmts "function test() { $$$BODY }" "function run() {\n  $$$BODY\n}" "js"))
        (srcWs "const   x   =   10  ;\n")
        (expectedWs "let x = 10;\n")
        (resWs (rw/rewrite srcWs "const $A = $B;" "let $A = $B;" "js"))
        (srcNl "function add(\n  a,\n  b\n) {\n  return a + b;\n}\n")
        (expectedNl "function sum(a, b) { return a + b; }\n")
        (resNl (rw/rewrite srcNl "function add(a, b) { return a + b; }" "function sum(a, b) { return a + b; }" "js"))]
    (do
      (assert (= res expected) "js console.log to logger.info rewrite must match expected")
      (assert (= resCall expectedCall) "js call arguments sequence rewrite must match expected")
      (assert (= resStmts expectedStmts) "js statement list sequence rewrite must match expected")
      (assert (= resWs expectedWs) "js whitespace-insensitive rewrite must match expected")
      (assert (= resNl expectedNl) "js newline whitespace-insensitive rewrite must match expected")
      true))

fn testTsRewrites -> Bool
  (let [(src "const id: any = 123;\n")
        (expected "const id: unknown = 123;\n")
        (res (rw/rewrite src "const $NAME: any = $VAL;" "const $NAME: unknown = $VAL;" "ts"))
        (src2 "type ItemId = string;\n")
        (expected2 "type ItemId = Promise<string>;\n")
        (res2 (rw/rewrite src2 "type $A = $B;" "type $A = Promise<$B>;" "ts"))
        (srcTsCall "dispatch(action, true, 42);\n")
        (expectedTsCall "trigger(action, true, 42);\n")
        (resTsCall (rw/rewrite srcTsCall "dispatch($$$ARGS)" "trigger($$$ARGS)" "ts"))
        (srcTsStmts "function compute(x: number): number {\n  const res = x * 2;\n  return res;\n}\n")
        (expectedTsStmts "function execute(x: number): number {\n  const res = x * 2;\n  return res;\n}\n")
        (resTsStmts (rw/rewrite srcTsStmts "function compute(x: number): number { $$$BODY }" "function execute(x: number): number {\n  $$$BODY\n}" "ts"))
        (srcTsWs "let    total  :   number    =   100   ;\n")
        (expectedTsWs "const total: number = 100;\n")
        (resTsWs (rw/rewrite srcTsWs "let $NAME: number = $VAL;" "const $NAME: number = $VAL;" "ts"))
        (srcTsNl "type Handler =\n  (\n    event: string\n  ) => void;\n")
        (expectedTsNl "type Listener = (event: string) => void;\n")
        (resTsNl (rw/rewrite srcTsNl "type Handler = (event: string) => void;" "type Listener = (event: string) => void;" "ts"))]
    (do
      (assert (= res expected) "ts any to unknown rewrite must match expected")
      (assert (= res2 expected2) "ts type wrap with Promise rewrite must match expected")
      (assert (= resTsCall expectedTsCall) "ts call arguments sequence rewrite must match expected")
      (assert (= resTsStmts expectedTsStmts) "ts statement list sequence rewrite must match expected")
      (assert (= resTsWs expectedTsWs) "ts whitespace-insensitive rewrite must match expected")
      (assert (= resTsNl expectedTsNl) "ts newline whitespace-insensitive rewrite must match expected")
      true))

fn testCssRewrites -> Bool
  (let [(src ".btn {\n  color: red;\n  margin: 10px;\n}\n")
        (expected ".btn {\n  color: var(--primary);\n  margin: 10px;\n}\n")
        (res (rw/rewrite src "color: $C;" "color: var(--primary);" "css"))
        (src2 ".old-panel {\n  padding: 5px;\n}\n")
        (expected2 ".new-panel {\n  padding: 5px;\n}\n")
        (res2 (rw/rewrite src2 ".old-panel { $$$DECLS }" ".new-panel {\n  $$$DECLS\n}" "css"))]
    (do
      (assert (= res expected) "css color property rewrite must match expected")
      (assert (= res2 expected2) "css class selector rewrite must match expected")
      true))

fn testIndentTrimmingCases -> Bool
  (let [(src0 "(wrap a)")
        (res0 (rw/rewrite src0 "(wrap $A $$$REST)" "(wrap $A\n$$$REST)" "asl"))
        (src4 "    (wrap a)")
        (res4 (rw/rewrite src4 "(wrap $A $$$REST)" "(wrap $A\n    $$$REST)" "asl"))
        (src6 "      (wrap a)")
        (res6 (rw/rewrite src6 "(wrap $A $$$REST)" "(wrap $A\n      $$$REST)" "asl"))]
    (do
      (assert (= res0 "(wrap a)") "indent trimming at 0 spaces must match expected")
      (assert (= res4 "    (wrap a)") "indent trimming at 4 spaces must match expected")
      (assert (= res6 "      (wrap a)") "indent trimming at 6 spaces must match expected")
      true))

fn testErrorPaths -> Bool
  (let [(badAslSrc "(item 1 2)\n(unclosed (")
        (badAslPat "(item $A $B (unclosed")
        (badJsSrc "const = ;")
        (badJsPat "function ( { @@@ {")
        (badTsSrc "type = ;")
        (badTsPat "interface { bad")
        (validSrc "(item 1 2)\n")
        (seqMismatchSrc "(call myFunc 1 2 3 start)")
        (seqMismatchPat "(call $FN $$$ARGS finish)")
        (seqInconsistentSrc "(pair (list 1 2) (list 3 4))")
        (seqInconsistentPat "(pair (list $$$A) (list $$$A))")
        (jsSeqMismatchSrc "process(1, 2, 3, otherHandler);")
        (jsSeqMismatchPat "process($$$ARGS, finalHandler);")
        (tsSeqMismatchSrc "dispatch(1, 2, 3);")
        (tsSeqMismatchPat "dispatch($$$ARGS, 999);")]
    (do
      (assert (listEmpty? (rw/findMatches badAslSrc "(item $A $B)" "asl")) "unparseable ASL source must yield no matches")
      (assert (= (rw/rewrite badAslSrc "(item $A $B)" "(new $A $B)" "asl") badAslSrc) "unparseable ASL source rewrite returns unchanged")
      (assert (listEmpty? (rw/findMatches validSrc badAslPat "asl")) "unparseable ASL pattern must yield no matches")
      (assert (= (rw/rewrite validSrc badAslPat "(new $A $B)" "asl") validSrc) "unparseable ASL pattern rewrite returns unchanged")
      (assert (listEmpty? (rw/findMatches badJsSrc "const $A = $B;" "js")) "unparseable JS source must yield no matches")
      (assert (= (rw/rewrite badJsSrc "const $A = $B;" "let $A = $B;" "js") badJsSrc) "unparseable JS source rewrite returns unchanged")
      (assert (listEmpty? (rw/findMatches "const x = 1;" badJsPat "js")) "unparseable JS pattern must yield no matches")
      (assert (listEmpty? (rw/findMatches badTsSrc "type $A = $B;" "ts")) "unparseable TS source must yield no matches")
      (assert (= (rw/rewrite badTsSrc "type $A = $B;" "type $A = Promise<$B>;" "ts") badTsSrc) "unparseable TS source rewrite returns unchanged")
      (assert (listEmpty? (rw/findMatches "type X = string;" badTsPat "ts")) "unparseable TS pattern must yield no matches")
      (assert (listEmpty? (rw/findMatches seqMismatchSrc seqMismatchPat "asl")) "mismatched sequence remainder must yield no matches")
      (assert (= (rw/rewrite seqMismatchSrc seqMismatchPat "(call $FN $$$ARGS done)" "asl") seqMismatchSrc) "mismatched sequence rewrite returns unchanged")
      (assert (listEmpty? (rw/findMatches seqInconsistentSrc seqInconsistentPat "asl")) "inconsistent sequence variable must yield no matches")
      (assert (= (rw/rewrite seqInconsistentSrc seqInconsistentPat "(pair $$$A)" "asl") seqInconsistentSrc) "inconsistent sequence rewrite returns unchanged")
      (assert (listEmpty? (rw/findMatches jsSeqMismatchSrc jsSeqMismatchPat "js")) "mismatched JS sequence must yield no matches")
      (assert (= (rw/rewrite jsSeqMismatchSrc jsSeqMismatchPat "run($$$ARGS);" "js") jsSeqMismatchSrc) "mismatched JS sequence rewrite returns unchanged")
      (assert (listEmpty? (rw/findMatches tsSeqMismatchSrc tsSeqMismatchPat "ts")) "mismatched TS sequence must yield no matches")
      (assert (= (rw/rewrite tsSeqMismatchSrc tsSeqMismatchPat "send($$$ARGS);" "ts") tsSeqMismatchSrc) "mismatched TS sequence rewrite returns unchanged")
      true))

fn ! runTests -> Bool
  (and (testAslSingleNodeRewrites)
  (and (testAslSequenceRewrites)
  (and (testAsnRewrites)
  (and (testJsRewrites)
  (and (testTsRewrites)
  (and (testCssRewrites)
  (and (testIndentTrimmingCases)
       (testErrorPaths))))))))
