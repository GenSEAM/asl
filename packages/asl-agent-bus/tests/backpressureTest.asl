(module aslAgentBus/tests/backpressureTest
  :x [RunTests runTests]
  :i [(bus :a b)])

fn testPriorityLanesAndBackpressure -> Bool
  (let [(msgAudit (b/AgentMessage :sender "verifier" :target "bus" :payload "(:audit-receipt :status :pass)" :timestamp 100))
        (msgControl (b/AgentMessage :sender "coord" :target "worker1" :payload "(:task-lease :grant t1)" :timestamp 101))
        (msgTelem (b/AgentMessage :sender "worker1" :target "bus" :payload "(:sparkline :val 42)" :timestamp 102))
        (isAuditHigh (b/isHighPriorityChannel? (b/audit)))
        (isControlHigh (b/isHighPriorityChannel? (b/control)))
        (isTelemHigh (b/isHighPriorityChannel? (b/telemetry)))
        (rawEvents (list msgAudit msgControl msgTelem))
        (sheddedEvents (b/filterBackpressureEvents rawEvents true))
        (normalEvents (b/filterBackpressureEvents rawEvents false))]
    (assert isAuditHigh "Audit channel is high priority")
    (assert isControlHigh "Control channel is high priority")
    (assert (not isTelemHigh) "Telemetry channel is low priority")
    (assert (= (listLength sheddedEvents) 2) "Backpressure filter sheds low priority telemetry")
    (assert (= (listLength normalEvents) 3) "Normal operation retains all events")
    (refute (not isAuditHigh) "Refutation: Audit channel must never be low priority")
    (refute isTelemHigh "Refutation: Telemetry must be low priority")
    true)

fn runTests -> Bool
  (testPriorityLanesAndBackpressure)

fn RunTests -> Bool
  (runTests)
