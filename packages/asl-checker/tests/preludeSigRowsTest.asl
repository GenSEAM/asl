(module asl-checker/preludeSigRowsTest
  :x [runTests]
  :i [(check :a c) (types :a ty)])

; (:m :ref CHKFIX :do "listFind listCount listFlatMap mapGetOr stringSliceUtf8 were added to prelude.asl (PRELUDE-PASSES) with no matching row in types.asl#builtinSigFallback, so lookupSysBuiltinSig fell through genericSig to (none) for every call and a wrong-typed argument was never rejected; this pins both that a correct call type-checks clean and that a wrong-typed call now reports ERR_TYPE_MISMATCH")

fn checkerProbe src: String -> (List ty/Diagnostic)
  (c/checkSource src (mapEmpty) "preludeSigRowsProbe.asl")

fn diagnosticText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn codesOf ds: (List ty/Diagnostic) -> (List String)
  (map (fn [(d ty/Diagnostic)] -> String d.code) ds)

; (:m :ref CHKFIX :do "checkSource/checkModule return the checker's internal short codes (type, rule-6, ...); check.asl#hostCheckCode maps both to the display code ERR_TYPE_MISMATCH for the CLI/host-parity surface, but that mapper is not exported, so this test asserts on the internal codes directly")
fn hasTypeMismatch? ds: (List ty/Diagnostic) -> Bool
  (listAny? (fn [(code String)] -> Bool (or (= code "type") (= code "rule-6"))) (codesOf ds))

fn okListFindSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> (Option Int64)"
    "  (listFind (fn [(x Int64)] -> Bool (> x 1)) (list 1 2 3))") "\n")

fn badListFindSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> (Option Int64)"
    "  (listFind \"not a predicate\" (list 1 2 3))") "\n")

fn okListCountSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> Int64"
    "  (listCount (fn [(x Int64)] -> Bool (> x 1)) (list 1 2 3))") "\n")

fn badListCountSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> Int64"
    "  (listCount (list 1 2 3) (fn [(x Int64)] -> Bool (> x 1)))") "\n")

fn okListFlatMapSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> (List Int64)"
    "  (listFlatMap (fn [(x Int64)] -> (List Int64) (list x x)) (list 1 2 3))") "\n")

fn badListFlatMapSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> (List Int64)"
    "  (listFlatMap (fn [(x Int64)] -> Int64 x) (list 1 2 3))") "\n")

fn okMapGetOrSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> Int64"
    "  (mapGetOr (mapEmpty) \"k\" 0)") "\n")

fn badMapGetOrSource -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> Int64"
    "  (mapGetOr (list 1 2 3) \"k\" 0)") "\n")

fn okStringSliceUtf8Source -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> (Option String)"
    "  (stringSliceUtf8 \"hello\" 0 2)") "\n")

fn badStringSliceUtf8Source -> String
  (stringJoin (list
    "(module probe :x [go] :i [])"
    ""
    "fn go -> (Option String)"
    "  (stringSliceUtf8 \"hello\" \"oops\" 2)") "\n")

fn ! runTests -> Bool
  (let [(okFind (checkerProbe (okListFindSource)))
        (badFind (checkerProbe (badListFindSource)))
        (okCount (checkerProbe (okListCountSource)))
        (badCount (checkerProbe (badListCountSource)))
        (okFlat (checkerProbe (okListFlatMapSource)))
        (badFlat (checkerProbe (badListFlatMapSource)))
        (okGetOr (checkerProbe (okMapGetOrSource)))
        (badGetOr (checkerProbe (badMapGetOrSource)))
        (okSlice (checkerProbe (okStringSliceUtf8Source)))
        (badSlice (checkerProbe (badStringSliceUtf8Source)))]
    (do
      (assert (listEmpty? okFind) (str "listFind: correctly-typed call checks clean: " (diagnosticText okFind)))
      (assert (hasTypeMismatch? badFind) (str "listFind: wrong-typed predicate must be rejected: " (diagnosticText badFind)))
      (assert (listEmpty? okCount) (str "listCount: correctly-typed call checks clean: " (diagnosticText okCount)))
      (assert (hasTypeMismatch? badCount) (str "listCount: swapped args must be rejected: " (diagnosticText badCount)))
      (assert (listEmpty? okFlat) (str "listFlatMap: correctly-typed call checks clean: " (diagnosticText okFlat)))
      (assert (hasTypeMismatch? badFlat) (str "listFlatMap: non-List-returning fn must be rejected: " (diagnosticText badFlat)))
      (assert (listEmpty? okGetOr) (str "mapGetOr: correctly-typed call checks clean: " (diagnosticText okGetOr)))
      (assert (hasTypeMismatch? badGetOr) (str "mapGetOr: a List where a Map is expected must be rejected: " (diagnosticText badGetOr)))
      (assert (listEmpty? okSlice) (str "stringSliceUtf8: correctly-typed call checks clean: " (diagnosticText okSlice)))
      (assert (hasTypeMismatch? badSlice) (str "stringSliceUtf8: a String where Int64 is expected must be rejected: " (diagnosticText badSlice)))
      true))
