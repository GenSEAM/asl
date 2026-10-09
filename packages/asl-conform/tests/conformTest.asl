(module aslConform/tests/conformTest
  :x [testContractLoading testRuleLookup testProfileLookup testCompareOutput testInvertComparison testMutantTransformations testValidateRuleMutants runTests]
  :i [(aslConform/types :a ty)
      (aslConform/semantics :a sem)
      (aslConform/compare :a cmp)
      (aslConform/mutant :a mut)
      (aslConform/main :a conform)])

fn testContractLoading -> Bool
  (let [(contract (sem/loadTargetSemantics))]
    (do
      (assert (= contract.version 1) "contract version is 1")
      (assert (= (listLength (sem/getAllProfiles contract)) 4) "4 target profiles configured")
      (assert (= (listLength (sem/getAllRules contract)) 5) "5 semantics rules configured")
      (assert (= (listLength (sem/getTiers contract)) 3) "3 tiers configured")
      true))

fn testRuleLookup -> Bool
  (let [(contract (sem/loadTargetSemantics))
        (rDivOpt (sem/findRule contract "divModFloor"))
        (rBadOpt (sem/findRule contract "nonExistentRule"))]
    (do
      (assert (some? rDivOpt) "divModFloor rule found")
      (refute (none? rDivOpt) "divModFloor rule refutes none")
      (assert (none? rBadOpt) "nonExistentRule is none")
      (refute (some? rBadOpt) "nonExistentRule refutes some")
      (mt rDivOpt
        ((some r)
          (do
            (assert (= r.tier "A") "tier is A")
            (refute (!= r.tier "A") "tier refutes non-A")
            (assert (sem/ruleHasMutants? r) "rule has mutants")
            (refute (not (sem/ruleHasMutants? r)) "rule refutes lacking mutants")
            (assert (> (listLength (sem/getRuleCases r)) 0) "rule has test cases")
            true))
        ((none) false))))

fn testProfileLookup -> Bool
  (let [(contract (sem/loadTargetSemantics))
        (pC11Opt (sem/findProfile contract "c11"))
        (pWasmOpt (sem/findProfile contract "wasm"))]
    (do
      (assert (some? pC11Opt) "c11 profile found")
      (refute (none? pC11Opt) "c11 profile refutes none")
      (assert (some? pWasmOpt) "wasm profile found")
      (refute (none? pWasmOpt) "wasm profile refutes none")
      (mt pC11Opt
        ((some p)
          (do
            (assert (= p.id "c11") "id is c11")
            (refute (!= p.id "c11") "id refutes non-c11")
            (assert (= p.tier "A") "c11 tier is A")
            true))
        ((none) false))))

fn testCompareOutput -> Bool
  (do
    (assert (cmp/compareOutput "hello\n" 0 "hello" 0) "trimmed stdout matches")
    (assert (not (cmp/compareOutput "hello" 1 "hello" 0)) "differing exit code fails")
    (refute (cmp/compareOutput "hello" 1 "hello" 0) "differing exit code refutes match")
    (assert (not (cmp/compareOutput "hello" 0 "world" 0)) "differing stdout fails")
    (refute (cmp/compareOutput "hello" 0 "world" 0) "differing stdout refutes match")
    true)

fn testInvertComparison -> Bool
  (do
    (assert (cmp/invertComparison "hello" 1 "hello" 0) "inverted comparison succeeds on exit divergence")
    (assert (cmp/invertComparison "world" 0 "hello" 0) "inverted comparison succeeds on stdout divergence")
    (assert (not (cmp/invertComparison "same" 0 "same" 0)) "inverted comparison fails on identical output")
    (refute (cmp/invertComparison "same" 0 "same" 0) "inverted comparison refutes identical output")
    true)

fn testMutantTransformations -> Bool
  (let [(mDiv (ty/makeMutant "divModFloorOmitMutant" "asl-target-py" "omit floored mod" "case1"))
        (mShift (ty/makeMutant "shiftMaskOmitMutant" "asl-target-c" "omit shift mask" "case2"))
        (pyCode "res = a // b")
        (cCode "uint64_t val = x & 63;")
        (mutPy (mut/applyMutant mDiv pyCode))
        (mutC (mut/applyMutant mShift cCode))]
    (do
      (assert (= mutPy "res = a / b") "divModFloor replaces // with /")
      (refute (!= mutPy "res = a / b") "divModFloor refutes non-replacement")
      (assert (= mutC "uint64_t val = x & 255;") "shiftMask replaces 63 with 255")
      (refute (!= mutC "uint64_t val = x & 255;") "shiftMask refutes non-replacement")
      (assert (mut/verifyMutantKilled mDiv "res = 1" "res = 2") "mutant killed when output differs")
      (refute (not (mut/verifyMutantKilled mDiv "res = 1" "res = 2")) "mutant killed refutes false")
      (assert (not (mut/verifyMutantKilled mDiv "same" "same")) "mutant survives when output identical")
      (refute (mut/verifyMutantKilled mDiv "same" "same") "mutant survives refutes true")
      true))

fn testValidateRuleMutants -> Bool
  (let [(m (ty/makeMutant "divModFloorOmitMutant" "asl-target-py" "omit floored mod" "case1"))
        (armed (ty/makeRule "divModFloor" "A" "div" "floored division" ["case1"] [m]))
        (bare (ty/makeRule "shiftMask" "A" "shift" "masked shift" ["case2"] []))
        (allArmed (ty/makeContract 1 [] ["A"] [armed armed]))
        (oneBare (ty/makeContract 1 [] ["A"] [armed bare]))
        (allBare (ty/makeContract 1 [] ["A"] [bare bare]))]
    (do
      (assert (conform/validateRuleMutants allArmed) "every rule with mutants validates")
      (refute (conform/validateRuleMutants oneBare) "one rule without mutants fails validation")
      (refute (conform/validateRuleMutants allBare) "no rule with mutants fails validation")
      (assert (conform/validateRuleMutants (sem/loadTargetSemantics)) "shipped contract validates")
      true))

fn ! runTests -> Bool
  (do
    (assert (testContractLoading) "testContractLoading")
    (assert (testRuleLookup) "testRuleLookup")
    (assert (testProfileLookup) "testProfileLookup")
    (assert (testCompareOutput) "testCompareOutput")
    (assert (testInvertComparison) "testInvertComparison")
    (assert (testMutantTransformations) "testMutantTransformations")
    (assert (testValidateRuleMutants) "testValidateRuleMutants")
    true)
