(module asl/packages/asl-mesh/tests/synthesisTest :x [runTests] :i [(asl-mesh/synthesis :a synth)])

fn testSynthesisConsensus -> Bool
  (let [(f1 {:id "1" :confidence 0.9 :status "verified"}) (f2 {:id "2" :confidence 0.2 :status "verified"}) (f3 {:id "3" :confidence 0.8 :status "verified"}) (filtered (synth/consensusFilter (list f1 f2) 0.8)) (atThreshold (synth/consensusFilter (list f2 f3) 0.8)) (receipt (synth/synthesizeDefects (list "pkg1") (list f1)))] (assert (= (listLength filtered) 1) "Only threshold-qualified finding retained") (refute (= (listLength filtered) 2) "Below-threshold finding is dropped") (assert (= (optionOr (listHead filtered) mapEmpty).id "1") "Retained finding is the above-threshold one") (assert (= (map (fn [finding] finding.id) atThreshold) (list "3")) "Finding exactly at the threshold is retained") (assert (= receipt.agreementRate 1.0) "1.0 agreement") (refute (= receipt.agreementRate 0.0) "Not 0.0 agreement") true)

fn testSynthesisTriangulate -> Bool
  (let [(l1 (list {:id "1"})) (l2 (list {:id "2"})) (l3 (list {:id "3"})) (all (synth/triangulateFindings l1 l2 l3))] (assert (= (listLength all) 3) "Combined length is 3") (refute (= (listLength all) 0) "Not empty") true)

fn runTests -> Bool
  (let [(r1 (testSynthesisConsensus)) (r2 (testSynthesisTriangulate))] (assert (and r1 r2) "All synthesis tests pass") true)
