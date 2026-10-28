(module asl-runtime/tests/runtimeOptimizationAcceptanceTest
  :x [runTests]
  :i [(asl-runtime/collections :a col)
      (asl-parser/reader :a rd)
      (asl-compiler/optFold :a opt)])

fn testStringSlice -> Bool
  (let [(s "hello world")
        (sl1 (optionOr (stringSlice s 0 5) ""))
        (sl2 (optionOr (stringSlice s 6 11) ""))
        (sl3 (optionOr (stringSlice s 0 11) ""))
        (slEmpty (stringSlice s 15 20))]
    (do (assert (= sl1 "hello") "slice 0..5 matches hello")
        (assert (= sl2 "world") "slice 6..11 matches world")
        (assert (= sl3 "hello world") "slice 0..11 matches full string")
        (assert (none? slEmpty) "out of bounds slice returns none")
        true))

; (:m :ref MAINFIX10 :do "stringReplace s \"\" new is not a no-op: prelude.asl's stringReplace traps unconditionally on an empty search string (same convention as stringSplit's empty separator), by design, same as charCode on an empty string -- ERR_MATCH_NONEXHAUSTIVE in prelude.preludeTrap, not a value this test can compare. The real contract (it traps, with that exact message) is already covered by tests/acceptance/r1Prelude/preludeBehaviourTest.asl's loud! probes; drop the wrong assumption here rather than duplicate that coverage")
fn testStringReplaceAndJoin -> Bool
  (let [(s "foo bar foo baz foo")
        (replaced (stringReplace s "foo" "qux"))
        (repNone (stringReplace "hello" "xyz" "abc"))]
    (do (assert (= replaced "qux bar qux baz qux") "multi-match stringReplace matches")
        (assert (= repNone "hello") "no-match stringReplace leaves string unchanged")
        true))

fn testSexprStructuralEquality -> Bool
  (let [(a1 (rd/makeAtom "foo"))
        (a2 (rd/makeAtom "foo"))
        (a3 (rd/makeAtom "bar"))
        (l1 (rd/makeList (list a1 a3)))
        (l2 (rd/makeList (list a2 a3)))
        (l3 (rd/makeList (list a1 a1)))
        (v1 (rd/makeVect (list a1 a3)))
        (v2 (rd/makeVect (list a2 a3)))]
    (do (assert (opt/sexprEquals? a1 a2) "identical atoms are structurally equal")
        (refute (opt/sexprEquals? a1 a3) "different atoms are not structurally equal")
        (assert (opt/sexprEquals? l1 l2) "lists with equal elements are structurally equal")
        (refute (opt/sexprEquals? l1 l3) "lists with different elements are not equal")
        (assert (opt/sexprEquals? v1 v2) "vectors with equal elements are structurally equal")
        (refute (opt/sexprEquals? l1 v1) "list and vector are not structurally equal")
        true))

fn testPureMapCollections -> Bool
  (let [(m0 (col/makeMap))
        (m1 (col/mapPut m0 "alpha" "100"))
        (m2 (col/mapPut m1 "beta" "200"))
        (m3 (col/mapPut m2 "alpha" "150"))
        (vAlpha (optionOr (col/mapGet m3 "alpha") ""))
        (vBeta (optionOr (col/mapGet m3 "beta") ""))
        (m4 (col/mapRemove m3 "beta"))]
    (do (assert (= (col/mapSize m2) 2) "mapSize after 2 puts is 2")
        (assert (= (col/mapSize m3) 2) "mapSize after update is 2")
        (assert (= vAlpha "150") "mapGet returns updated value")
        (assert (= vBeta "200") "mapGet returns retained key value")
        (assert (= (col/mapSize m4) 1) "mapSize after remove is 1")
        (refute (col/mapContains? m4 "beta") "mapContains? returns false after removal")
        true))

fn testStringChars -> Bool
  (let [(chars (stringChars "hello"))]
    (do (assert (= (listLength chars) 5) "stringChars length is 5")
        (assert (= (optionOr (listGet chars 0) "") "h") "char 0 is h")
        (assert (= (optionOr (listGet chars 4) "") "o") "char 4 is o")
        true))

fn testDceBlockConstantFold -> Bool
  (let [(ast (rd/makeList (list (rd/makeAtom "if") (rd/makeAtom "true") (rd/makeAtom "10") (rd/makeAtom "20"))))
        (optimized (opt/dceBlock ast))]
    (do (assert (opt/sexprEquals? optimized (rd/makeAtom "10")) "dceBlock eliminates false branch on constant true")
        true))

; (:m :ref MAINFIX10 :do "testL1ResidentRuntimeC! asserted a prebuilt /tmp/runtime_test binary compiled against engine/asl_runtime.h; git log --follow back to this file's first commit (1ebce7c6d) shows that path and header never existed in this tree and no build step anywhere ever produced them. asl-gates/src/gateRunner.asl's own gate 4 (Zero-Foreign File & Zero-C Policy) asserts the opposite: test ! -f engine/asl_runtime.h must hold, matching the ASL-first floor (C only for memory, syscalls, 3 string prims). The sub-test checked for a legacy C artifact the project's own policy forbids from existing; drop the dead check rather than build a forbidden file or loosen its assertions")
fn ! runTests -> Bool
  (let [(r1 (testStringSlice))
        (r2 (testStringReplaceAndJoin))
        (r3 (testSexprStructuralEquality))
        (r4 (testPureMapCollections))
        (r5 (testStringChars))
        (r6 (testDceBlockConstantFold))]
    (and r1 r2 r3 r4 r5 r6))
