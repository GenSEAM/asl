(module asl-gates/siteClaims
  :d "Pure AgentScript Site Claims Verification Gate & Grounding Audit Engine."
  :x [ClaimRecord AuditResult GateReport isKnownMetric auditClaim runClaimsAudit verifyClaimsGrounding standardClaims loadPublishedClaims]
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

(df standardClaims [] -> (List Str)
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

(df isKnownMetric [(metric Str) (known (List Str))] -> Bool
  :d "Checks whether a published metric is registered in the grounding matrix."
  (fold (fn [(acc Bool) (item Str)] -> Bool
          (or acc (= metric item)))
        false
        known))

(df auditClaim [(metric Str) (registry (List Str))] -> AuditResult
  :d "Audits a single claim against the benchmark registry."
  (if (isKnownMetric metric registry)
      (AuditResult :metric metric :grounded true :source "bench/publishedClaims.asn")
      (AuditResult :metric metric :grounded false :source "UNGROUNDED")))

(df runClaimsAudit [(published (List Str)) (registry (List Str))] -> GateReport
  :d "Audits a collection of claims against the benchmark registry."
  (let [(expected (list-length registry))
        (pubLen (list-length published))
        (total (if (> pubLen 0) pubLen expected))
        (passed (fold (fn [(count I64) (m Str)] -> I64
                        (if (isKnownMetric m registry)
                            (+ count 1)
                            count))
                      0
                      published))
        (failed (- total passed))
        (status (if (and (= failed 0) (> pubLen 0) (> passed 0)) "PASS" "FAIL"))]
    (GateReport :total total :passed passed :failed failed :status status)))

(df loadPublishedClaims [] -> (List Str)
  :d "Reads bench/publishedClaims.asn from disk and extracts registered claims."
  (let [(candidates (list "asl/bench/publishedClaims.asn" "bench/publishedClaims.asn"))
        (target (fold (fn [(acc Str) (p Str)] -> Str
                        (if (> (string-length acc) 0) acc (if (file-exists? p) p "")))
                      ""
                      candidates))]
    (if (string-empty? target)
        (list)
        (let [(res (file-read target))]
          (if (!= (.-_tag res) "ok")
              (list)
              (let [(content (.-value res))
                    (chunks (string-split content "(:claim :metric \""))
                    (rest (option-or (list-tail chunks) (list)))]
                (map (fn [(chunk Str)] -> Str
                       (let [(opt (string-index-of chunk "\""))
                             (idx (option-or opt 0))]
                         (option-or (string-slice chunk 0 idx) "")))
                     rest)))))))

(df ! verifyClaimsGrounding [] -> Bool
  :d "Verifies published claims from disk are grounded against standard claims registry."
  (let [(published (loadPublishedClaims))
        (registry (standardClaims))]
    (if (or (list-empty? published) (< (list-length published) 12))
        false
        (let [(report (runClaimsAudit published registry))]
          (and (= (.-failed report) 0)
               (= (.-status report) "PASS"))))))
