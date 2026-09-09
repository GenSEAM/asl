(module asl-lint/incongruity-test
  :d "Unit tests for monorepo incongruity scanner validating zero sigils, zero foreign files, and 1-to-2 token compliance (d41, d46, d48)."
  :x [test-detect-lingering-sigils
      test-detect-crutches
      test-detect-foreign-files
      test-token-compliance
      test-make-incongruity-report
      test-scan-monorepo-incongruities
      run-tests]
  :i [(incongruity :a inc)])

(df test-detect-lingering-sigils [] -> Bool
  :d "Verifies detection of prohibited @ and # sigils."
  (let [(clean-items (list "valid-id" "norm-path" "phase-396" "c1" "d48"))
        (dirty-items (list "valid-id" "@sigil-ref" "anchor" "#hashtag" "c2"))
        (clean-count (inc/detect-lingering-sigils clean-items))
        (dirty-count (inc/detect-lingering-sigils dirty-items))]
    (assert (= clean-count 0) "Clean list must contain 0 sigils")
    (assert (= dirty-count 2) "Dirty list must detect exactly 2 lingering sigils")
    (assert (> dirty-count clean-count) "Dirty count must exceed clean count")
    true))

(df test-detect-crutches [] -> Bool
  :d "Verifies detection of temporary crutches and scaffolding markers."
  (let [(clean-items (list "pure implementation" "production code" "canonical standard"))
        (dirty-items (list "TODO fix this" "temporary-scaffolding" "clean line" "STUB fallback" "mock object"))
        (clean-count (inc/detect-crutches clean-items))
        (dirty-count (inc/detect-crutches dirty-items))]
    (assert (= clean-count 0) "Clean list must contain 0 crutches")
    (assert (= dirty-count 4) "Dirty list must detect exactly 4 crutches")
    (assert (> dirty-count 0) "Dirty crutch count must be strictly positive")
    true))

(df test-detect-foreign-files [] -> Bool
  :d "Verifies detection of non-ASL foreign files and forbidden memory markdown files."
  (let [(clean-paths (list "asl/packages/asl-lint/src/incongruity.asl" "harness/paradigm.asn" ".asl/mem/tasks/phase_396.asn"))
        (dirty-paths (list "scripts/test.py" "web/bundle.js" "asl/packages/test.rs" ".asl/mem/decisions/old.md" "asl/packages/clean.asl"))
        (clean-report (inc/scan-monorepo-incongruities clean-paths (list) (list)))
        (dirty-report (inc/scan-monorepo-incongruities dirty-paths (list) (list)))]
    (assert (= (.-foreign-violations clean-report) 0) "Clean paths must have 0 foreign violations")
    (assert (= (.-foreign-violations dirty-report) 4) "Dirty paths must detect exactly 4 foreign violations")
    (assert (.-passed clean-report) "Clean file scan must pass")
    (assert (not (.-passed dirty-report)) "Dirty file scan must fail")
    true))

(df test-token-compliance [] -> Bool
  :d "Verifies 1-to-2 token basis compliance checking."
  (let [(clean-syms (list "c1" "d46" "norm" "v/norm" "txt/len"))
        (dirty-syms (list "c1" "norm" "my-extremely-long-uncompacted-identifier-name" "another-super-verbose-non-compliant-symbol-name"))
        (clean-report (inc/scan-monorepo-incongruities (list) clean-syms (list)))
        (dirty-report (inc/scan-monorepo-incongruities (list) dirty-syms (list)))]
    (assert (= (.-token-violations clean-report) 0) "Clean symbols must have 0 token violations")
    (assert (= (.-token-violations dirty-report) 2) "Dirty symbols must detect 2 token violations")
    (assert (.-passed clean-report) "Clean symbol scan must pass")
    (assert (not (.-passed dirty-report)) "Dirty symbol scan must fail")
    true))

(df test-make-incongruity-report [] -> Bool
  :d "Verifies IncongruityReport construction and pass/fail evaluation."
  (let [(clean (inc/make-incongruity-report 50 0 0 0 0))
        (dirty-sigil (inc/make-incongruity-report 50 1 0 0 0))
        (dirty-foreign (inc/make-incongruity-report 50 0 1 0 0))
        (dirty-tokens (inc/make-incongruity-report 50 0 0 1 0))
        (dirty-crutch (inc/make-incongruity-report 50 0 0 0 1))]
    (assert (.-passed clean) "Report with zero violations must pass")
    (assert (= (.-total-scanned clean) 50) "Total scanned must match")
    (assert (not (.-passed dirty-sigil)) "Report with sigil violation must fail")
    (assert (not (.-passed dirty-foreign)) "Report with foreign violation must fail")
    (assert (not (.-passed dirty-tokens)) "Report with token violation must fail")
    (assert (not (.-passed dirty-crutch)) "Report with crutch violation must fail")
    true))

(df test-scan-monorepo-incongruities [] -> Bool
  :d "Verifies composite monorepo scan aggregating all 4 invariant categories."
  (let [(clean-paths (list "asl/packages/asl-lint/src/incongruity.asl" "harness/paradigm.asn"))
        (clean-syms (list "c1" "d46" "v/norm" "txt/len"))
        (clean-snippets (list "clean code without scaffolding" "verified physical truth"))
        (clean-rep (inc/scan-monorepo-incongruities clean-paths clean-syms clean-snippets))
        (dirty-paths (list "tmp.py" ".asl/mem/notes.md"))
        (dirty-syms (list "@sigil-one" "#tag-two" "excessive-length-uncompacted-identifier-symbol"))
        (dirty-snippets (list "TODO remove later" "HACK work-around"))
        (dirty-rep (inc/scan-monorepo-incongruities dirty-paths dirty-syms dirty-snippets))]
    (assert (.-passed clean-rep) "Clean composite scan must pass")
    (assert (= (.-total-scanned clean-rep) 8) "Clean composite scanned count must be 8")
    (assert (= (.-sigil-violations clean-rep) 0) "Clean sigil violations must be 0")
    (assert (= (.-foreign-violations clean-rep) 0) "Clean foreign violations must be 0")
    (assert (= (.-token-violations clean-rep) 0) "Clean token violations must be 0")
    (assert (= (.-crutch-violations clean-rep) 0) "Clean crutch violations must be 0")
    (assert (not (.-passed dirty-rep)) "Dirty composite scan must fail")
    (assert (= (.-foreign-violations dirty-rep) 2) "Dirty foreign violations must be 2")
    (assert (= (.-sigil-violations dirty-rep) 2) "Dirty sigil violations must be 2")
    (assert (= (.-token-violations dirty-rep) 1) "Dirty token violations must be 1")
    (assert (= (.-crutch-violations dirty-rep) 2) "Dirty crutch violations must be 2")
    true))

(df run-tests [] -> Bool
  :d "Runs all incongruity scanner unit tests under strict falsification."
  (do
    (assert (test-detect-lingering-sigils) "test-detect-lingering-sigils must pass")
    (assert (test-detect-crutches) "test-detect-crutches must pass")
    (assert (test-detect-foreign-files) "test-detect-foreign-files must pass")
    (assert (test-token-compliance) "test-token-compliance must pass")
    (assert (test-make-incongruity-report) "test-make-incongruity-report must pass")
    (assert (test-scan-monorepo-incongruities) "test-scan-monorepo-incongruities must pass")
    true))

(run-tests)
