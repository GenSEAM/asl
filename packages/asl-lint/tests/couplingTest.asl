(module asl-lint/coupling-test :x [main] :i [(asl-lint/coupling :a c)])

fn testInstability -> Bool
  (do
    (assert (= (c/calculateInstability 0 0) 0.0) "0 fanIn and 0 fanOut must have 0.0 instability")
    (assert (<= (c/calculateInstability 20 0) 0.01) "pure foundation package must have near 0.0 instability")
    (assert (c/isInstabilityAcceptable 0.0 true) "0.0 instability is acceptable for foundation")
    (assert (c/isInstabilityAcceptable 0.1 true) "0.1 instability is acceptable for foundation")
    (assert (not (c/isInstabilityAcceptable 0.5 true)) "0.5 instability is rejected for foundation")
    (assert (c/isInstabilityAcceptable 0.5 false) "0.5 instability is acceptable for non-foundation")
    true)

fn testCohesion -> Bool
  (do
    (assert (= (c/calculateCohesion 0 1) 1.0) "single module package must have 1.0 cohesion")
    (assert (= (c/calculateCohesion 1 1) 1.0) "single module package edge must have 1.0 cohesion")
    (assert (> (c/calculateCohesion 2 3) 0.0) "multi module package with edges must have positive cohesion")
    true)

fn testFictionsAndCycles -> Bool
  (do
    (assert (= (c/detectCycles false) 0) "clean DAG must have 0 cycles")
    (assert (= (c/detectCycles true) 1) "detected cycle must count 1")
    (assert (= (c/checkModuleFictions 0 0 0) 0) "clean packages must have 0 fictions")
    (assert (= (c/checkModuleFictions 1 2 3) 6) "fictions must sum cleanly")
    true)

fn testCouplingSummaryAndFormat -> Bool
  (let [(okSummary (c/analyzeCoupling 45 320 0 0))
        (failSummary (c/analyzeCoupling 45 320 1 2))
        (formatted (c/formatCouplingAsn okSummary))]
    (do
      (assert (= okSummary.status "ok") "clean audit must have ok status")
      (assert (= okSummary.cyclesCount 0) "clean audit must have 0 cycles")
      (assert (= okSummary.totalFictions 0) "clean audit must have 0 fictions")
      (assert (= failSummary.status "failed") "audit with cycles/fictions must fail")
      (assert (> (stringLength formatted) 20) "formatted ASN must have valid length")
      true))

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (and (testInstability) (and (testCohesion) (and (testFictionsAndCycles) (testCouplingSummaryAndFormat))))
    (let [(u (println "asl-lint coupling unit tests passed cleanly"))]
      (ok ()))
    (let [(u (eprintln "asl-lint coupling unit test failure"))]
      (err (other))))
