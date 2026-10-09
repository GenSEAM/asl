(module aslHarness/providerTest :x [runTests] :i [(provider :a prov) (coding :a c)])

fn testGatewayConfig -> Bool
  (let [(cfg (prov/defaultGatewayConfig)) (oac (prov/OpenAiConfig :apiKey "test" :model "test-model" :baseUrl "test" :maxTokens 10 :temperature 0.5)) (cm (prov/ChatMessage :role "user" :content "test")) (pr (prov/ProviderResponse :id "test" :content "test" :finishReason "test" :promptTokens 1 :completionTokens 1))] (assert (= cfg.model "gemma-4-31b-it") "model is gemma-4-31b-it") (assert (= cfg.baseUrl "http://127.0.0.1:8765/v1") "base url matches") (assert (= cfg.maxTokens 4096) "max tokens is 4096") (assert (= oac.apiKey "test") "OpenAiConfig explicit property matches") (assert (= cm.role "user") "ChatMessage explicit property matches") (assert (= pr.id "test") "ProviderResponse explicit property matches") (refute (= pr.id "wrong") "Refute ProviderResponse wrong id") true)

fn testMessageCreation -> Bool
  (let [(m1 (prov/makeMessage "user" "hello world")) (m2 (prov/makeMessage "system" "you are eddie"))] (assert (= m1.role "user") "m1 role is user") (assert (= m1.content "hello world") "m1 content matches") (assert (= m2.role "system") "m2 role is system") (assert (= m2.content "you are eddie") "m2 content matches") true)

fn testPayloadSerialization -> Bool
  (let [(cfg (prov/defaultGatewayConfig)) (msgs (list (prov/makeMessage "user" "list files"))) (tools (c/standardCodingTools)) (payload (prov/buildRequestPayload cfg msgs tools))] (assert (stringContains? payload "gemma-4-31b-it") "payload contains model") (assert (stringContains? payload "list files") "payload contains user message") (assert (stringContains? payload "rpc_batch") "payload exposes rpc batch tool") (assert (not (stringContains? payload "fs_read")) "payload hides direct command tools") true)

fn testResponseParsing -> Bool
  (let [(r1 (prov/parseModelResponse "Task resolved cleanly" false)) (r2 (prov/parseModelResponse "Calling tool" true))] (assert (= r1.text "Task resolved cleanly") "r1 text matches") (assert (= r1.finishReason "stop") "r1 finish reason is stop") (assert (= r2.text "Calling tool") "r2 text matches") (assert (= r2.finishReason "stop") "r2 finish reason is stop") true)

fn testThinkQuarantine -> Bool
  (let [(raw "<think>internal reasoning steps</think>Hello user") (r (prov/parseModelResponse raw false))] (assert (= r.text "Hello user") "think block quarantined") (assert (= r.finishReason "stop") "finish reason is stop") true)

fn testEshRejection -> Bool
  (let [(raw "I completed the work. All tests pass cleanly.") (r (prov/parseModelResponse raw false))] (assert (= r.finishReason "esh_rejected") "verbal ESH flagged") (assert (not (= r.finishReason "stop")) "finish reason is not stop") true)

fn runTests -> Bool
  (do (testGatewayConfig) (testMessageCreation) (testPayloadSerialization) (testResponseParsing) (testThinkQuarantine) (testEshRejection) true)
