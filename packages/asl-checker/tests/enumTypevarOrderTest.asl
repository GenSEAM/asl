(module asl-checker/tests/enumTypevarOrderTest
  :x [runTests]
  :i [(asl-parser/ast :a a) (asl-checker/check :a chk) (asl-checker/types :a ty)])

; (:m :ref CHECK-PRELUDE-ZSTD :do "regression for 40 false ERR_TYPE_MISMATCH positions the native checker raised over asl/prelude/prelude.asl's zstd Huffman/FSE decoder, none of which asl-host reported: EnumSummary/SchemaSummary.typevars was always the parser's placeholder empty list, unlike FunSummary which falls back to ty/collectTvars; and ty/collectTvars itself built its result by consing onto an accumulator, reversing first-occurrence order. For a 2-typevar local enum case like (pair first: A second: B), the reversal swapped the constructed return type to (Pair B A), so a case called twice in one nested expression (as zstdAslFseRead and friends do, pattern-matching and constructing nested (Pair (Pair ...) ...) values from the prelude's own locally defined enum Pair) instantiated the wrong slot and the checker reported a false mismatch")

fn nestedPairSrc -> String
  (str
    "(module m :x [] :i [])\n"
    "\n"
    "enum Pair\n"
    "  (pair first: A second: B)\n"
    "\n"
    "fn f x: Int64 -> (Pair (Pair Int64 Int64) Int64)\n"
    "  (pair (pair x x) x)\n")

fn checkDiags src: String -> (List ty/Diagnostic)
  (match (a/parseForChecker src)
    ((err pe) (list (ty/Diagnostic :code "parse" :message pe.msg :msg pe.msg :line pe.line :col pe.col :path "m.asl")))
    ((ok forms) (chk/checkModule forms (mapEmpty) "m.asl")))

fn diagSummary ds: (List ty/Diagnostic) -> String
  (fold (fn [(acc String) (d ty/Diagnostic)] -> String (str acc " " d.code ":" d.message)) "" ds)

fn testNestedGenericCaseConstructorChecksClean -> Bool
  (let [(ds (checkDiags (nestedPairSrc)))]
    (do
      (assert (listEmpty? ds) (str "a locally defined 2-typevar enum case, called twice in one nested expression, must not produce a false type mismatch:" (diagSummary ds)))
      true))

fn testCollectTvarsPreservesDeclarationOrder -> Bool
  (do
    (assert (= (ty/collectTvars (list "A" "B") "") (list "A" "B")) "collectTvars keeps first-occurrence order for two params, not reversed")
    (assert (= (ty/collectTvars (list "K" "V") "(PreludeTree K V)") (list "K" "V")) "collectTvars does not duplicate a typevar already seen in params when it recurs in ret")
    (assert (= (ty/collectTvars (list) "(Result T E)") (list "T" "E")) "collectTvars reads a composite ret string left to right")
    true)

fn ! runTests -> Bool
  (do
    (assert (testCollectTvarsPreservesDeclarationOrder) "testCollectTvarsPreservesDeclarationOrder")
    (assert (testNestedGenericCaseConstructorChecksClean) "testNestedGenericCaseConstructorChecksClean")
    true)
