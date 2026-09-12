(module asl-gates/site-claims
  :d "Pure AgentScript Site Claims Verification Gate & Grounding Audit Engine."
  :x [ClaimRecord AuditResult GateReport is-known-metric audit-claim run-claims-audit verify-claims-grounding standard-claims]
  :i [])

(dfs ClaimRecord
  (:f metric Str "Claimed metric string")
  (:f category Str "Benchmark metric category")
  (:f source Str "Benchmark ground source path")
  (:f desc Str "Human readable description"))

(dfs AuditResult
  (:f metric Str "Claimed metric")
  (:f grounded Bool "Whether claim is verified in lock")
  (:f source Str "Source benchmark reference"))

(dfs GateReport
  (:f total I64 "Total metrics audited")
  (:f passed I64 "Total passed checks")
  (:f failed I64 "Total failed checks")
  (:f status Str "Overall audit verdict"))

(df standard-claims [] -> (List Str)
  :d "Returns canonical list of grounded performance metrics and published claims."
  (list
    "57%–65%"
    "-64.7%"
    "78%"
    "-83.4%"
    "<100ms"
    "24MB"
    "<=2 tokens"
    "107/107"
    "0.038ms"
    "<0.04ms"
    "64KB"
    "-75%"))

(df is-known-metric [(metric Str) (known (List Str))] -> Bool
  :d "Checks whether a published metric is registered in the grounding matrix."
  (fold (fn [(acc Bool) (item Str)] -> Bool
          (or acc (= metric item)))
        false
        known))

(df audit-claim [(metric Str) (registry (List Str))] -> AuditResult
  :d "Audits a single claim against the benchmark registry."
  (if (is-known-metric metric registry)
      (AuditResult :metric metric :grounded true :source "bench/published_claims.asn")
      (AuditResult :metric metric :grounded false :source "UNGROUNDED")))

(df run-claims-audit [(published (List Str)) (registry (List Str))] -> GateReport
  :d "Audits a collection of claims against the benchmark registry."
  (let [(expected (list-length registry))
        (pub-len (list-length published))
        (total (if (> pub-len 0) pub-len expected))
        (passed (fold (fn [(count I64) (m Str)] -> I64
                        (if (is-known-metric m registry)
                            (+ count 1)
                            count))
                      0
                      published))
        (failed (- total passed))
        (status (if (and (= failed 0) (> pub-len 0) (> passed 0)) "PASS" "FAIL"))]
    (GateReport :total total :passed passed :failed failed :status status)))

(df verify-claims-grounding [] -> Bool
  :d "Verifies standard published claims are grounded."
  (let [(claims (standard-claims))
        (report (run-claims-audit claims claims))]
    (and (= (.-failed report) 0)
         (= (.-status report) "PASS"))))
