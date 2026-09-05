(module asl-gates/tests/site-claims-test
  :d "Unit tests for pure AgentScript Site Claims Verification Gate."
  :x [test-known-claims test-unknown-claim test-claims-audit test-full-grounding run-tests]
  :i [(site-claims :a sc)])

(df test-known-claims [] -> Bool
  :d "Verifies grounded claims pass lookup."
  (let [(registry (sc/standard-claims))]
    (and (sc/is-known-metric "57%–65%" registry)
         (and (sc/is-known-metric "<100ms" registry)
              (sc/is-known-metric "24MB" registry)))))

(df test-unknown-claim [] -> Bool
  :d "Verifies ungrounded claims are rejected."
  (let [(registry (sc/standard-claims))]
    (not (sc/is-known-metric "99.999% fake" registry))))

(df test-claims-audit [] -> Bool
  :d "Verifies run-claims-audit computes accurate report totals."
  (let [(registry (sc/standard-claims))
        (sample (list "57%–65%" "fake-claim"))
        (report (sc/run-claims-audit sample registry))]
    (and (= (.-total report) 2)
         (and (= (.-passed report) 1)
              (and (= (.-failed report) 1)
                   (= (.-status report) "FAIL"))))))

(df test-full-grounding [] -> Bool
  :d "Verifies standard claims matrix is fully grounded."
  (sc/verify-claims-grounding))

(df run-tests [] -> Bool
  :d "Runs all site claims tests."
  (and (test-known-claims)
       (and (test-unknown-claim)
            (and (test-claims-audit)
                 (test-full-grounding)))))
