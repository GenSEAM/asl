(module aslAgentBus/test :x [testSseFormatting testBroadcastEvent testDirectEvent testPingEvent testQueryEventsAndConditionWake runTests] :i [(bus :a bus)])

fn testSseFormatting -> Bool
  (let [(formatted (bus/formatSseEvent "task-update" "status:ready"))] (assert (stringContains? formatted "event: task-update") "SSE format must contain event name") (assert (stringContains? formatted "data: status:ready") "SSE format must contain data payload") (assert (stringEndsWith? formatted "\n\n") "SSE format must end with double newline") true)

fn testBroadcastEvent -> Bool
  (let [(msg (bus/AgentMessage :sender "agent-a" :target "all" :payload "ping" :timestamp 1700000000)) (evt (bus/broadcast msg))] (assert (bus/isBroadcast evt) "Broadcast event must be detected as broadcast") (assert (= msg.sender "agent-a") "Sender must match agent-a") (assert (= msg.target "all") "Target must match all") true)

fn testDirectEvent -> Bool
  (let [(msg (bus/AgentMessage :sender "agent-a" :target "agent-b" :payload "req" :timestamp 1700000001)) (evt (bus/direct msg))] (assert (not (bus/isBroadcast evt)) "Direct event must not be detected as broadcast") (assert (= msg.target "agent-b") "Target must match agent-b") true)

fn testPingEvent -> Bool
  (let [(evt (bus/ping)) (msg (bus/AgentMessage :sender "kernel" :target "all" :payload "ping" :timestamp 1700000002)) (bEvt (bus/broadcast msg))] (assert (not (bus/isBroadcast evt)) "Ping event must not be broadcast") (assert (bus/isBroadcast bEvt) "Broadcast event must be detected as broadcast") (assert (= msg.sender "kernel") "Ping sender matches") true)

fn testQueryEventsAndConditionWake -> Bool
  (let [(m1 (bus/AgentMessage :sender "a1" :target "bus" :payload "(:change :path \"engine/asl.c\")" :timestamp 100)) (m2 (bus/AgentMessage :sender "a2" :target "bus" :payload "(:change :path \"asl/packages/asl-mem/src/vfs.asl\")" :timestamp 101)) (m3 (bus/AgentMessage :sender "a3" :target "worker" :payload "(:change :path \"engine/asl.c\")" :timestamp 102)) (events (list m1 m2 m3)) (q1 (bus/queryBusEvents events "change" "bus")) (q2 (bus/queryBusEvents events "" "worker")) (w0 (bus/makeConditionWake "watch-asl" "engine/asl.c" "supervisor")) (w1 (bus/evalConditionWake w0 m1)) (w2 (bus/evalConditionWake w0 m2))] (assert (= (listLength q1) 2) "Query matching 'change' payload and 'bus' target must return 2 messages") (assert (= (listLength q2) 1) "Query matching 'worker' target must return exactly 1 message") (assert (= (optionOr (listHead q2) m1).target "worker") "Target must match worker") (assert (not w0.triggered) "Initial wake must not be triggered") (assert w1.triggered "Wake against m1 must be triggered") (assert (not w2.triggered) "Wake against m2 must not be triggered") true)

fn testCasEpochValidation -> Bool
  (let [(env1 (bus/makeBusEnvelope "env-1" "worker-1" "supervisor" "(:task :complete)" 1700000010 "corr-1"))
        (env2 (bus/makeSequencedBusEnvelope "env-2" "worker-1" "supervisor" "(:task :step)" 1700000011 "corr-2" 5 42))
        (staleEnv (bus/makeSequencedBusEnvelope "env-stale" "worker-old" "supervisor" "(:task :step)" 1700000005 "corr-0" 4 99))]
    (assert (= env1.epoch 1) "Default envelope epoch must be 1")
    (assert (= env1.seq 1) "Default envelope seq must be 1")
    (assert (= env2.epoch 5) "Sequenced envelope epoch must be 5")
    (assert (= env2.seq 42) "Sequenced envelope seq must be 42")
    (assert (bus/validateBusCasEpoch env2 5 40) "Matching epoch and higher seq must validate")
    (assert (bus/validateBusCasEpoch env2 5 42) "Exact seq match must validate")
    (assert (not (bus/validateBusCasEpoch env2 5 43)) "Lower seq than expected min must be rejected")
    (assert (not (bus/validateBusCasEpoch staleEnv 5 1)) "Stale epoch from previous reset must be rejected")
    true)

fn runTests -> Bool
  (and (testSseFormatting) (testBroadcastEvent) (testDirectEvent) (testPingEvent) (testQueryEventsAndConditionWake) (testCasEpochValidation))
