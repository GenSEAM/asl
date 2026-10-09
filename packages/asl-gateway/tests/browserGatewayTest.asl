(module aslGateway/tests/browserGatewayTest :x [testBrowserThinkQuarantine testBrowserEshInterception testBrowserCleanTurn testJsonToAsnToolcallConversion testFormatBrowserWirePayload testTargetToString runTests] :i [(browserGateway :a bgw) (server :a server)])

fn testBrowserThinkQuarantine -> Bool
  (let [(raw "<think>WebGPU reasoning scratchpad</think>Here is the clean reply.") (res (server/extractThinkBlocks raw)) (thinkPart (pairFirst res)) (uiPart (pairSecond res))] (do (assert (= thinkPart "WebGPU reasoning scratchpad") "Think content must match") (assert (= uiPart "Here is the clean reply.") "UI content must be clean") true))

fn testBrowserEshInterception -> Bool
  (do (assert (server/detectEshViolation "I ran all 5 tests pass") "Must detect all 5 tests pass") (assert (server/detectEshViolation "verified that gate passes cleanly") "Must detect gate passes cleanly") (assert (not (server/detectEshViolation "Processing inference turn...")) "Normal progress must not flag") true)

fn testBrowserCleanTurn -> Bool
  (let [(raw "(:call :tool \"bash\" :args \"asl test\")") (verdict (bgw/inspectBrowserTurn raw true))] (do (assert verdict.allowed "Clean turn must be allowed") (assert (= (listLength verdict.toolCalls) 1) "Tool call must be extracted") true))

fn testJsonToAsnToolcallConversion -> Bool
  (let [(res (bgw/convertJsonToAsnToolcall "search" "{\"q\": \"asl\"}"))] (do (assert (stringContains? res ":tool \"search\"") "Must include tool name") (assert (stringContains? res ":args") "Must include args tag") true))

fn testFormatBrowserWirePayload -> Bool
  (let [(payload (bgw/formatBrowserWirePayload "Hello model" (bgw/targetWebgpu)))] (do (assert (stringContains? payload ":target") "Must specify target") (assert (stringContains? payload "target-webgpu") "Must specify webgpu variant") (assert (stringContains? payload "Hello model") "Must specify prompt") true))

fn testTargetToString -> Bool
  (do (assert (= (bgw/targetToString (bgw/targetWasm)) "target-wasm") "Must convert wasm target") (assert (= (bgw/targetToString (bgw/targetLocalOllama)) "target-local-ollama") "Must convert ollama target") (assert (= (bgw/targetToString (bgw/targetLocalVllm)) "target-local-vllm") "Must convert vllm target") true)

fn runTests -> Bool
  (do (assert (testBrowserThinkQuarantine) "test-browser-think-quarantine must pass") (assert (testBrowserEshInterception) "test-browser-esh-interception must pass") (assert (testBrowserCleanTurn) "test-browser-clean-turn must pass") (assert (testJsonToAsnToolcallConversion) "test-json-to-asn-toolcall-conversion must pass") (assert (testFormatBrowserWirePayload) "test-format-browser-wire-payload must pass") (assert (testTargetToString) "test-target-to-string must pass") true)
