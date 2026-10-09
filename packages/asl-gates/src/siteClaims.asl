(module asl-gates/siteClaims :x [ClaimRecord AuditResult GateReport isKnownMetric auditClaim runClaimsAudit verifyClaimsGrounding standardClaims loadPublishedClaims! loadPublishedClaimsAt! claimsGrounding! claimsGroundingAt!] :i [])

(schema ClaimRecord (:f metric Str) (:f category Str) (:f source Str) (:f desc Str))

(schema AuditResult (:f metric Str) (:f grounded Bool) (:f source Str))

(schema GateReport (:f total I64) (:f passed I64) (:f failed I64) (:f status Str))

fn standardClaims -> (List Str)
  (list "57%-65%" "-64.7%" "1.90%" "1.68%" "<100ms" "24MB" "<=2 tokens" "107/107" "0.038ms" "<0.04ms" "64KB" "-75%")

fn isKnownMetric metric: Str known: (List Str) -> Bool
  (fold (fn [(acc Bool) (item Str)] -> Bool (or acc (= metric item))) false known)

fn auditClaim metric: Str registry: (List Str) -> AuditResult
  (if (isKnownMetric metric registry) (AuditResult :metric metric :grounded true :source "bench/publishedClaims.asn") (AuditResult :metric metric :grounded false :source "UNGROUNDED"))

fn runClaimsAudit published: (List Str) registry: (List Str) -> GateReport
  (let [(expected (listLength registry)) (pubLen (listLength published)) (total (if (> pubLen 0) pubLen expected)) (passed (fold (fn [(count I64) (m Str)] -> I64 (if (isKnownMetric m registry) (+ count 1) count)) 0 published)) (failed (- total passed)) (status (if (and (= failed 0) (> pubLen 0) (> passed 0)) "PASS" "FAIL"))] (GateReport :total total :passed passed :failed failed :status status))

fn publishedClaimsCandidates -> (List Str)
  (list "asl/bench/publishedClaims.asn" "bench/publishedClaims.asn")

fn ! loadPublishedClaimsAt! candidates: (List Str) -> (Result (List Str) Str)
  (mt (listHead (filter (fn [(p Str)] -> Bool (fileExists? p)) candidates))
    ((none) (err (str "No published claims file at " (stringJoin candidates " or "))))
    ((some target)
      (mt (fileRead target)
        ((err e) (err (str "Failed to read published claims " target ": " e)))
        ((ok content)
          (fold (fn [(acc (Result (List Str) Str)) (chunk Str)] -> (Result (List Str) Str)
                  (mt acc
                    ((err e) (err e))
                    ((ok metrics)
                      (mt (stringIndexOf chunk "\"")
                        ((none) (err (str target ": claim " (stringFromInt64 (+ (listLength metrics) 1)) " has an unterminated :metric string")))
                        ((some idx) (mt (stringSlice chunk 0 idx) ((some m) (ok (listAppend metrics (list m)))) ((none) (err (str target ": claim " (stringFromInt64 (+ (listLength metrics) 1)) " :metric slice 0.." (stringFromInt64 idx) " is out of bounds")))))))))
                (ok (list))
                (optionOr (listTail (stringSplit content "(:claim :metric \"")) (list)))))))

fn ! loadPublishedClaims! -> (Result (List Str) Str)
  (loadPublishedClaimsAt! (publishedClaimsCandidates))

fn ! claimsGroundingAt! candidates: (List Str) -> (Result I64 Str)
  (mt (loadPublishedClaimsAt! candidates)
    ((err e) (err e))
    ((ok published)
      (let [(registry (standardClaims)) (ungrounded (filter (fn [(m Str)] -> Bool (not (isKnownMetric m registry))) published))]
        (cond
          ((< (listLength published) 12) (err (str "Only " (stringFromInt64 (listLength published)) " published claims; at least 12 are required")))
          ((not (listEmpty? ungrounded)) (err (str "Ungrounded published claims: " (stringJoin ungrounded ", "))))
          (else (ok (listLength published)))))))

fn ! claimsGrounding! -> (Result I64 Str)
  (claimsGroundingAt! (publishedClaimsCandidates))

fn ! verifyClaimsGrounding -> Bool
  (ok? (claimsGrounding!))
