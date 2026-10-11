(module aslAgent/onionTest :x [testOnionPipelineNormal testOnionFirewallBlock testOnionCostGuardBlock testOnionSanitizerTruncate runTests] :i [(aslAgentCore/onion :a on) (policy :a pol)])

fn testOnionPipelineNormal -> Bool
  (let [(ctx (on/makeContext "read-file" "src/app.asl" "hello world" 100 1000 (pol/levelAuto))) (pipe (on/makeLegacyPipeline ctx)) (res (on/executePipeline pipe))] (assert (= res.status "PROCEED") "normal pipeline status is PROCEED") (assert (= res.payload "hello world") "payload matches") true)

fn testOnionFirewallBlock -> Bool
  (let [(ctx (on/makeContext "read-file" "../etc/passwd" "" 100 1000 (pol/levelAuto))) (pipe (on/makeLegacyPipeline ctx)) (res (on/executePipeline pipe))] (assert (= res.status "BLOCKED") "firewall status is BLOCKED") (assert (= res.payload "ERROR: Blocked by mw-firewall") "firewall payload matches") true)

fn testOnionCostGuardBlock -> Bool
  (let [(ctx (on/makeContext "read-file" "src/app.asl" "" 2500 1000 (pol/levelAuto))) (pipe (on/makeLegacyPipeline ctx)) (res (on/executePipeline pipe))] (assert (= res.status "BLOCKED") "cost guard status is BLOCKED") (assert (= res.payload "ERROR: Blocked by mw-cost-guard (token budget exceeded)") "cost guard payload matches") true)

fn testOnionSanitizerTruncate -> Bool
  (let [(longTrace (str "Trace: line 1\n" "Trace: line 2\n" "Trace: line 3\n" "Error details: memory dump stack frame 0x42424242\n" "Extra log information repeating over multiple lines to test the sanitizer boundary condition.\n")) (sanitized (on/runSanitizer longTrace))] (assert (<= (stringLength sanitized) 1300) "sanitizer length <= 1300") (assert (> (stringLength sanitized) 0) "sanitizer length > 0") true)

fn runTests -> Bool
  (do (testOnionPipelineNormal) (testOnionFirewallBlock) (testOnionCostGuardBlock) (testOnionSanitizerTruncate) true)
