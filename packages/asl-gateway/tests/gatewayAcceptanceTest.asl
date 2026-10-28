(module asl-gateway/tests/gatewayAcceptanceTest
  :x [runTests RunTests testGatewayRateLimiting testGatewayThinkingQuarantine testDualPolarityRefutations]
  :i [(aslGateway/gateway :a gw)])

fn testGatewayRateLimiting -> Bool
  (let [(cfg0 (gw/makeGatewayConfig 120 2 "http://127.0.0.1:9000" false))
        (chk1 (gw/rateLimitCheck cfg0 1))
        (cfg1 (pairFirst chk1))
        (allowed1 (pairSecond chk1))
        (chk2 (gw/rateLimitCheck cfg1 1))
        (cfg2 (pairFirst chk2))
        (allowed2 (pairSecond chk2))
        (chk3 (gw/rateLimitCheck cfg2 1))
        (allowed3 (pairSecond chk3))]
    (assert allowed1 "request 1 allowed within burst limit")
    (refute (not allowed1) "request 1 refutes rejection")
    (assert allowed2 "request 2 allowed within burst limit")
    (refute (not allowed2) "request 2 refutes rejection")
    (assert (not allowed3) "request 3 rejected when burst capacity exhausted")
    (refute allowed3 "request 3 refutes allowed"))
  true

fn testGatewayThinkingQuarantine -> Bool
  (let [(cfg (gw/makeGatewayConfig 60 5 "http://127.0.0.1:9000" false))
        (rawPayload "<think>private agent reasoning scratchpad</think>(:task :id 42)")
        (dispatchRes (gw/dispatchGatewayRequest cfg "/mesh/agent" rawPayload "key"))
        (resp (pairSecond dispatchRes))]
    (assert (= resp.status 200) "dispatch succeeds with 200")
    (refute (!= resp.status 200) "status refutes non-200")
    (assert (= resp.quarantinedThink "private agent reasoning scratchpad") "thinking scratchpad is isolated")
    (refute (!= resp.quarantinedThink "private agent reasoning scratchpad") "quarantine refutes mismatch")
    (assert (not (stringContains? resp.body "<think>")) "clean body has no think open tag")
    (assert (not (stringContains? resp.body "</think>")) "clean body has no think close tag")
    (assert (stringContains? resp.body "(:task :id 42)") "clean payload retained in dispatch"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(cfgAuth (gw/makeGatewayConfig 60 5 "http://127.0.0.1:9000" true))
        (unauthRes (gw/dispatchGatewayRequest cfgAuth "/mesh/agent" "payload" ""))
        (resp (pairSecond unauthRes))]
    (assert (= resp.status 401) "missing API key with required auth returns 401")
    (refute (!= resp.status 401) "unauthorized refutes 200"))
  true

fn runTests -> Bool
  (do
    (assert (testGatewayRateLimiting) "testGatewayRateLimiting passed")
    (assert (testGatewayThinkingQuarantine) "testGatewayThinkingQuarantine passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
