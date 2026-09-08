(module asl-gates/tests/gate-runner-test
  :d "Falsifiable verification and test suite for pure ASL gate runner and extensionless audit."
  :x [test-all-gates-pass
      test-gate-fail-fast
      test-extensionless-audit
      test-dead-code-audit
      test-summary-formatting
      run-tests]
  :i [(gate-runner :a gr)
      (shebang-audit :a sa)
      (gates :a g)])

(df test-all-gates-pass [] -> Bool
  :d "Asserts all 7 gates passing verdict aggregation and clean report."
  (let [(summary (gr/run-all-gates 34 673 12 0 212 3223 29))]
    (assert (.-all-clean summary) "All 7 gates clean must report all-clean true")
    (assert (= (.-total-gates summary) 7) "Total gates count must equal 7")
    (assert (= (.-passed-gates summary) 7) "Passed gates count must equal 7")
    (assert (= (list-length (.-verdicts summary)) 7) "Verdicts list length must equal 7")
    (let [(s7 (gr/run-all-seven-gates 10 100 15 0 50 1500 20))]
      (assert (.-all-clean s7) "run-all-seven-gates must pass when all criteria met")
      (assert (= (.-passed-gates s7) 7) "run-all-seven-gates passed gates must be 7"))
    true))

(df test-gate-fail-fast [] -> Bool
  :d "Asserts fail-fast rejection for each individual gate failure mode."
  (let [(s-no-manifests (gr/run-all-gates 0 673 12 0 212 3223 29))
        (s-no-asl (gr/run-all-gates 34 0 12 0 212 3223 29))
        (s-few-claims (gr/run-all-gates 34 673 5 0 212 3223 29))
        (s-foreign-files (gr/run-all-gates 34 673 12 3 212 3223 29))
        (s-no-tests (gr/run-all-gates 34 673 12 0 0 3223 29))
        (s-few-grammar (gr/run-all-gates 34 673 12 0 212 500 29))
        (s-few-skills (gr/run-all-gates 34 673 12 0 212 3223 4))]
    (assert (not (.-all-clean s-no-manifests)) "0 manifests must fail gate 1")
    (assert (= (.-passed-gates s-no-manifests) 6) "0 manifests must leave 6 passed gates")
    (assert (not (.-all-clean s-no-asl)) "0 ASL files must fail gate 2")
    (assert (= (.-passed-gates s-no-asl) 6) "0 ASL files must leave 6 passed gates")
    (assert (not (.-all-clean s-few-claims)) "<12 claims must fail gate 3")
    (assert (not (.-all-clean s-foreign-files)) "Foreign files > 0 must fail gate 4")
    (assert (not (.-all-clean s-no-tests)) "0 tests must fail gate 5")
    (assert (not (.-all-clean s-few-grammar)) "<= 1000 grammar symbols must fail gate 6")
    (assert (not (.-all-clean s-few-skills)) "<10 skills must fail gate 7")
    true))

(df test-extensionless-audit [] -> Bool
  :d "Asserts extensionless binary blob detection and approved forwarder filtering."
  (let [(approved (list "asl" "agent" "gsa" "lens"))
        (elf-header "\u007fELF\u0002\u0001\u0001\u0000")
        (pe-header "MZ\u0090\u0000\u0003\u0000")
        (sh-header "#!/usr/bin/env bash\nexec asl \"$@\"")
        (asl-sh-header "#!/usr/bin/env asl\n(println 1)")
        (bad-sh-header "#!/usr/bin/python3\nimport os")]
    (assert (sa/is-binary-blob elf-header) "ELF header must be detected as binary blob")
    (assert (sa/is-binary-blob pe-header) "PE MZ header must be detected as binary blob")
    (assert (not (sa/is-binary-blob sh-header)) "Bash script must not be detected as binary blob")
    (assert (sa/audit-shebang sh-header) "Approved bash shebang must pass audit")
    (assert (sa/audit-shebang asl-sh-header) "Approved asl shebang must pass audit")
    (assert (not (sa/audit-shebang bad-sh-header)) "Python shebang must fail audit")
    (assert (sa/is-approved-forwarder "asl" approved) "asl must be approved forwarder")
    (assert (sa/is-approved-forwarder "agent" approved) "agent must be approved forwarder")
    (assert (not (sa/is-approved-forwarder "claude-standalone" approved)) "claude-standalone must be rejected")
    (assert (not (sa/is-approved-forwarder "eddie" approved)) "eddie must be rejected")
    (let [(unapproved (gr/audit-extensionless-binaries (list "asl" "rogue" "bin/eddie") approved))]
      (assert (= (list-length unapproved) 2) "Two unapproved binaries must be flagged")
      (assert (list-contains? unapproved "rogue") "rogue binary must be in unapproved list")
      (assert (list-contains? unapproved "bin/eddie") "eddie must be in unapproved list"))
    true))

(df test-dead-code-audit [] -> Bool
  :d "Asserts detection of dead code and orphan symbol exports."
  (let [(exports (list "live-fn" "orphan-fn" "unused-helper"))
        (callers (list "live-fn" "other-fn"))
        (orphans (gr/audit-dead-code exports callers))]
    (assert (= (list-length orphans) 2) "Two orphan functions must be detected")
    (assert (list-contains? orphans "orphan-fn") "orphan-fn must be detected")
    (assert (list-contains? orphans "unused-helper") "unused-helper must be detected")
    (assert (not (list-contains? orphans "live-fn")) "live-fn must not be in orphan list")
    true))

(df test-summary-formatting [] -> Bool
  :d "Asserts formatting of clean and failed gate summaries."
  (let [(s-clean (gr/run-all-gates 34 673 12 0 212 3223 29))
        (s-fail (gr/run-all-gates 0 0 0 1 0 0 0))
        (rep-clean (gr/format-gate-summary s-clean))
        (rep-fail (gr/format-gate-summary s-fail))]
    (assert (string-contains? rep-clean "ALL VERIFICATION GATES PASSED CLEANLY") "Clean report must contain success header")
    (assert (string-contains? rep-fail "GATES FAILED") "Failed report must contain failure header")
    (assert (> (string-length rep-clean) 100) "Report length must be substantial")
    true))

(df run-tests [] -> Bool
  :d "Master test runner executing all gate runner assertion suites."
  (and (test-all-gates-pass)
       (and (test-gate-fail-fast)
            (and (test-extensionless-audit)
                 (and (test-dead-code-audit)
                      (test-summary-formatting))))))
