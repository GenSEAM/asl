(module aslHarness/engineGatewayTestProxy :x [testAirgapAssertions runTests] :i [(engineGateway :a eg)])

fn testAirgapAssertions -> Bool
  (let [(resT0 (eg/queryGateway "sym" "tier-0-ast" 1 true)) (resAir (eg/queryGateway "ext" "tier-2-web" 1 true))] (assert (= (listLength resT0) 1) "tier-0 single result") (assert (= (optionOr (listHead resAir) (eg/EngineResult :tier "" :source "" :score 0.0 :title "" :snippet "")).source "airgap-policy") "airgap policy intercepted") true)

fn runTests -> Bool
  (testAirgapAssertions)
