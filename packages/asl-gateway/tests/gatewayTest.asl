(module aslGateway/tests/gatewayTest
  :x [runTests RunTests testGatewayConfigInitialization testRateLimitEnforcement testThinkingQuarantine testDispatchAuthAndMeshForwarding testDualPolarityRefutations]
  :i [(gateway :a gw)])

fn testGatewayConfigInitialization -> Bool
  (let [(cfg (gw/makeGatewayConfig 100 5 "http://127.0.0.1:9000/mesh" true))]
    (assert (= cfg.maxRequestsPerMinute 100) "maxRequestsPerMinute is 100")
    (refute (!= cfg.maxRequestsPerMinute 100) "maxRequestsPerMinute refutes divergence")
    (assert (= cfg.burstLimit 5) "burstLimit is 5")
    (assert (= cfg.currentTokens 5) "initial currentTokens matches burstLimit")
    (assert cfg.requireAuth "requireAuth is true")
    (refute (not cfg.requireAuth) "requireAuth refutes false"))
  true

fn testRateLimitEnforcement -> Bool
  (let [(cfg0 (gw/makeGatewayConfig 60 2 "http://127.0.0.1:9000/mesh" false))
        (chk1 (gw/rateLimitCheck cfg0 1))
        (cfg1 (pairFirst chk1))
        (allowed1 (pairSecond chk1))
        (chk2 (gw/rateLimitCheck cfg1 1))
        (cfg2 (pairFirst chk2))
        (allowed2 (pairSecond chk2))
        (chk3 (gw/rateLimitCheck cfg2 1))
        (cfg3 (pairFirst chk3))
        (allowed3 (pairSecond chk3))]
    (assert allowed1 "first request within burst is allowed")
    (refute (not allowed1) "first request refutes rejection")
    (assert allowed2 "second request within burst is allowed")
    (refute (not allowed2) "second request refutes rejection")
    (assert (not allowed3) "third request exceeding burst is rejected")
    (refute allowed3 "third request refutes allowed")
    (assert (= cfg2.currentTokens 0) "tokens depleted to zero"))
  true

fn testThinkingQuarantine -> Bool
  (let [(raw "<think>Hidden reasoning trace</think>Public visible answer.")
        (res (gw/quarantineThinkingTags raw))
        (think (pairFirst res))
        (clean (pairSecond res))]
    (assert (= think "Hidden reasoning trace") "quarantine extracts exact thinking content")
    (refute (!= think "Hidden reasoning trace") "thinking content refutes divergence")
    (assert (= clean "Public visible answer.") "quarantine produces clean public answer")
    (refute (stringContains? clean "<think>") "clean output refutes think open tag")
    (refute (stringContains? clean "</think>") "clean output refutes think close tag"))
  true

fn testDispatchAuthAndMeshForwarding -> Bool
  (let [(cfgAuth (gw/makeGatewayConfig 60 5 "http://127.0.0.1:9000/mesh" true))
        (resNoAuth (gw/dispatchGatewayRequest cfgAuth "/api/v1/agent" "(:query :q 1)" ""))
        (respNoAuth (pairSecond resNoAuth))]
    (assert (= respNoAuth.status 401) "unauthenticated request returns 401")
    (refute (!= respNoAuth.status 401) "unauthenticated request refutes non-401")
    (assert (stringContains? respNoAuth.body "Unauthorized") "body indicates unauthorized")
    (let [(resAuth (gw/dispatchGatewayRequest cfgAuth "/api/v1/agent" "<think>step</think>(:task :id 1)" "sk-valid-key"))
          (respAuth (pairSecond resAuth))]
      (assert (= respAuth.status 200) "authenticated request returns 200")
      (refute (!= respAuth.status 200) "authenticated request refutes non-200")
      (assert (= respAuth.quarantinedThink "step") "thinking quarantined on dispatch")
      (assert (stringContains? respAuth.body ":mesh-response") "mesh response generated")
      (assert (stringContains? respAuth.body "(:task :id 1)") "clean payload forwarded")))
  true

fn testDualPolarityRefutations -> Bool
  (let [(cfgZeroBurst (gw/makeGatewayConfig 0 0 "http://127.0.0.1:9000/mesh" false))]
    (assert (> cfgZeroBurst.maxRequestsPerMinute 0) "zero RPM defaults to positive bound")
    (assert (> cfgZeroBurst.burstLimit 0) "zero burst defaults to positive bound")
    (refute (<= cfgZeroBurst.burstLimit 0) "burstLimit refutes non-positive"))
  (let [(cleanText "Just pure text without think block")
        (res (gw/quarantineThinkingTags cleanText))]
    (assert (= (pairFirst res) "") "text without think has empty quarantine")
    (refute (!= (pairFirst res) "") "text without think refutes non-empty quarantine")
    (assert (= (pairSecond res) cleanText) "text without think preserves full content"))
  true

fn runTests -> Bool
  (do
    (assert (testGatewayConfigInitialization) "testGatewayConfigInitialization passed")
    (assert (testRateLimitEnforcement) "testRateLimitEnforcement passed")
    (assert (testThinkingQuarantine) "testThinkingQuarantine passed")
    (assert (testDispatchAuthAndMeshForwarding) "testDispatchAuthAndMeshForwarding passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
