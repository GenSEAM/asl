(module asl-lint/incongruityTest
  :d "Unit tests for monorepo incongruity scanner validating zero sigils, zero foreign files, and 1-to-2 token compliance (d41, d46, d48)."
  :x [testDetectLingeringSigils
      testDetectCrutches
      testDetectForeignFiles
      testTokenCompliance
      testMakeIncongruityReport
      testScanMonorepoIncongruities
      runTests]
  :i [(incongruity :a inc)])

(df testDetectLingeringSigils [] -> Bool
  :d "Verifies detection of prohibited @ and # sigils."
  (let [(cleanItems (list "valid-id" "norm-path" "phase-396" "c1" "d48"))
        (dirtyItems (list "valid-id" "@sigil-ref" "anchor" "#hashtag" "c2"))
        (cleanCount (inc/detectLingeringSigils cleanItems))
        (dirtyCount (inc/detectLingeringSigils dirtyItems))]
    (assert (= cleanCount 0) "Clean list must contain 0 sigils")
    (assert (= dirtyCount 2) "Dirty list must detect exactly 2 lingering sigils")
    (assert (> dirtyCount cleanCount) "Dirty count must exceed clean count")
    true))

(df testDetectCrutches [] -> Bool
  :d "Verifies detection of temporary crutches and scaffolding markers."
  (let [(cleanItems (list "pure implementation" "production code" "canonical standard"))
        (dirtyItems (list "TODO fix this" "temporary-scaffolding" "clean line" "STUB fallback" "mock object"))
        (cleanCount (inc/detectCrutches cleanItems))
        (dirtyCount (inc/detectCrutches dirtyItems))]
    (assert (= cleanCount 0) "Clean list must contain 0 crutches")
    (assert (= dirtyCount 4) "Dirty list must detect exactly 4 crutches")
    (assert (> dirtyCount 0) "Dirty crutch count must be strictly positive")
    true))

(df testDetectForeignFiles [] -> Bool
  :d "Verifies detection of non-ASL foreign files and forbidden memory markdown files."
  (let [(cleanPaths (list "asl/packages/asl-lint/src/incongruity.asl" "harness/paradigm.asn" ".asl/mem/tasks/phase_396.asn"))
        (dirtyPaths (list "scripts/test.py" "web/bundle.js" "asl/packages/test.rs" ".asl/mem/decisions/old.md" "asl/packages/clean.asl"))
        (cleanReport (inc/scanMonorepoIncongruities cleanPaths (list) (list)))
        (dirtyReport (inc/scanMonorepoIncongruities dirtyPaths (list) (list)))]
    (assert (= (.-foreignViolations cleanReport) 0) "Clean paths must have 0 foreign violations")
    (assert (= (.-foreignViolations dirtyReport) 4) "Dirty paths must detect exactly 4 foreign violations")
    (assert (.-passed cleanReport) "Clean file scan must pass")
    (assert (not (.-passed dirtyReport)) "Dirty file scan must fail")
    true))

(df testTokenCompliance [] -> Bool
  :d "Verifies 1-to-2 token basis compliance checking."
  (let [(cleanSyms (list "c1" "d46" "norm" "v/norm" "txt/len"))
        (dirtySyms (list "c1" "norm" "my-extremely-long-uncompacted-identifier-name" "another-super-verbose-non-compliant-symbol-name"))
        (cleanReport (inc/scanMonorepoIncongruities (list) cleanSyms (list)))
        (dirtyReport (inc/scanMonorepoIncongruities (list) dirtySyms (list)))]
    (assert (= (.-tokenViolations cleanReport) 0) "Clean symbols must have 0 token violations")
    (assert (= (.-tokenViolations dirtyReport) 2) "Dirty symbols must detect 2 token violations")
    (assert (.-passed cleanReport) "Clean symbol scan must pass")
    (assert (not (.-passed dirtyReport)) "Dirty symbol scan must fail")
    true))

(df testMakeIncongruityReport [] -> Bool
  :d "Verifies IncongruityReport construction and pass/fail evaluation."
  (let [(clean (inc/makeIncongruityReport 50 0 0 0 0))
        (dirtySigil (inc/makeIncongruityReport 50 1 0 0 0))
        (dirtyForeign (inc/makeIncongruityReport 50 0 1 0 0))
        (dirtyTokens (inc/makeIncongruityReport 50 0 0 1 0))
        (dirtyCrutch (inc/makeIncongruityReport 50 0 0 0 1))]
    (assert (.-passed clean) "Report with zero violations must pass")
    (assert (= (.-totalScanned clean) 50) "Total scanned must match")
    (assert (not (.-passed dirtySigil)) "Report with sigil violation must fail")
    (assert (not (.-passed dirtyForeign)) "Report with foreign violation must fail")
    (assert (not (.-passed dirtyTokens)) "Report with token violation must fail")
    (assert (not (.-passed dirtyCrutch)) "Report with crutch violation must fail")
    true))

(df testScanMonorepoIncongruities [] -> Bool
  :d "Verifies composite monorepo scan aggregating all 4 invariant categories."
  (let [(cleanPaths (list "asl/packages/asl-lint/src/incongruity.asl" "harness/paradigm.asn"))
        (cleanSyms (list "c1" "d46" "v/norm" "txt/len"))
        (cleanSnippets (list "clean code without scaffolding" "verified physical truth"))
        (cleanRep (inc/scanMonorepoIncongruities cleanPaths cleanSyms cleanSnippets))
        (dirtyPaths (list "tmp.py" ".asl/mem/notes.md"))
        (dirtySyms (list "@sigil-one" "#tag-two" "excessive-length-uncompacted-identifier-symbol"))
        (dirtySnippets (list "TODO remove later" "HACK work-around"))
        (dirtyRep (inc/scanMonorepoIncongruities dirtyPaths dirtySyms dirtySnippets))]
    (assert (.-passed cleanRep) "Clean composite scan must pass")
    (assert (= (.-totalScanned cleanRep) 8) "Clean composite scanned count must be 8")
    (assert (= (.-sigilViolations cleanRep) 0) "Clean sigil violations must be 0")
    (assert (= (.-foreignViolations cleanRep) 0) "Clean foreign violations must be 0")
    (assert (= (.-tokenViolations cleanRep) 0) "Clean token violations must be 0")
    (assert (= (.-crutchViolations cleanRep) 0) "Clean crutch violations must be 0")
    (assert (not (.-passed dirtyRep)) "Dirty composite scan must fail")
    (assert (= (.-foreignViolations dirtyRep) 2) "Dirty foreign violations must be 2")
    (assert (= (.-sigilViolations dirtyRep) 2) "Dirty sigil violations must be 2")
    (assert (= (.-tokenViolations dirtyRep) 1) "Dirty token violations must be 1")
    (assert (= (.-crutchViolations dirtyRep) 2) "Dirty crutch violations must be 2")
    true))

(df runTests [] -> Bool
  :d "Runs all incongruity scanner unit tests under strict falsification."
  (do
    (assert (testDetectLingeringSigils) "test-detect-lingering-sigils must pass")
    (assert (testDetectCrutches) "test-detect-crutches must pass")
    (assert (testDetectForeignFiles) "test-detect-foreign-files must pass")
    (assert (testTokenCompliance) "test-token-compliance must pass")
    (assert (testMakeIncongruityReport) "test-make-incongruity-report must pass")
    (assert (testScanMonorepoIncongruities) "test-scan-monorepo-incongruities must pass")
    true))

(runTests)
