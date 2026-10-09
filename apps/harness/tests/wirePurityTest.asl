(module harness/tests/wirePurityTest
  :x [runTests RunTests testCognitiveScratchpadDyckPurity testAgentBusWirePurity testCompactRecordDyckPurity testDualPolarityProbes]
  :i [(aslHarness/cognition :a cog)
      (aslAgentBus/ndAsn :a bus)
      (aslMem/compact :a cmp)])

fn testCognitiveScratchpadDyckPurity -> Bool
  (let [(trace1 "(:perceive \"observe\" :hypotheses ((h1 \"good\") (h2 \"bad\")) :gates ((g1 \"fail\")))")
        (isBal1 (cog/checkDyckBalance trace1))]
    (assert isBal1 "pure Dyck-1 cognitive trace is balanced")
    (refute (not isBal1) "pure Dyck-1 cognitive trace refutes imbalance"))
  (let [(unbalTrace "(:perceive \"observe\" :hypotheses ((h1 \"good\")")
        (isBal2 (cog/checkDyckBalance unbalTrace))]
    (assert (not isBal2) "unclosed cognitive trace fails Dyck balance")
    (refute isBal2 "unclosed cognitive trace refutes balance"))
  (let [(invertedTrace ")( (:foo \"bar\")")
        (isBal3 (cog/checkDyckBalance invertedTrace))]
    (assert (not isBal3) "inverted cognitive trace fails Dyck balance")
    (refute isBal3 "inverted cognitive trace refutes balance"))
  (let [(pad (cog/makeCognitiveScratchpad "observe" (list "h1" "h2") (list "g1") "h1" (list "act1") 50 5))]
    (assert (= pad.tokenCount 50) "tokenCount matches 50")
    (refute (!= pad.tokenCount 50) "tokenCount refutes mismatch")
    (assert (= pad.constraintCount 5) "constraintCount matches 5")
    (refute (!= pad.constraintCount 5) "constraintCount refutes mismatch")
    (let [(sud (cog/calculateSud pad.constraintCount pad.tokenCount))]
      (assert (> sud 0.09) "SUD density is approximately 0.1")
      (refute (<= sud 0.0) "SUD density refutes non-positive value")))
  true

fn testAgentBusWirePurity -> Bool
  (let [(metaMap (mapSet (mapSet (mapEmpty) "src" "agent-1") "dst" "agent-2"))
        (frame (bus/ndAsnFrame "test-topic" 1 1789745000 "(echo \"hello world\")" metaMap))
        (wire (bus/ndAsnSerializeSingle frame))]
    (assert (> (stringLength wire) 0) "serialized wire frame is non-empty")
    (refute (= (stringLength wire) 0) "serialized wire frame refutes empty string")
    (refute (stringContains? wire "[") "wire frame refutes square open bracket [")
    (refute (stringContains? wire "]") "wire frame refutes square close bracket ]")
    (refute (stringContains? wire "{") "wire frame refutes curly open brace {")
    (refute (stringContains? wire "}") "wire frame refutes curly close brace }")
    (assert (stringStartsWith? wire "(:frame ") "wire frame starts with (:frame ")
    (assert (stringEndsWith? wire ")") "wire frame ends with )")
    (assert (cog/checkDyckBalance wire) "serialized wire frame satisfies pure Dyck balance")
    (refute (not (cog/checkDyckBalance wire)) "serialized wire frame refutes Dyck imbalance"))
  (let [(toolCallFrame (bus/ndAsnMakeToolcall "search" "knowledge" "query text" 10))
        (tcWire (bus/ndAsnSerializeSingle toolCallFrame))]
    (assert (cog/checkDyckBalance tcWire) "toolcall wire frame satisfies Dyck balance")
    (refute (not (cog/checkDyckBalance tcWire)) "toolcall wire frame refutes Dyck imbalance")
    (refute (stringContains? tcWire "[") "toolcall wire frame refutes square brackets")
    (refute (stringContains? tcWire "{") "toolcall wire frame refutes curly braces"))
  true

fn testCompactRecordDyckPurity -> Bool
  (let [(rec (cmp/encodeVectorFrame "vec-dyck1" "sample text" (list 1.0 2.0 3.0)))
        (formatted (cmp/formatCompactRecord rec))]
    (assert (> (stringLength formatted) 0) "formatCompactRecord produces non-empty output")
    (refute (= (stringLength formatted) 0) "formatCompactRecord refutes empty output")
    (assert (stringStartsWith? formatted "(:vector ") "formatted vector record starts with (:vector")
    (assert (stringEndsWith? formatted ")") "formatted vector record ends with )")
    (refute (stringContains? formatted "{") "compact record refutes curly braces")
    (refute (stringContains? formatted "}") "compact record refutes curly braces"))
  true

fn testDualPolarityProbes -> Bool
  (let [(emptyFrame (bus/ndAsnFrame "empty" 0 0 "" (mapEmpty)))
        (emptyWire (bus/ndAsnSerializeSingle emptyFrame))]
    (refute (stringContains? emptyWire "[") "empty metadata wire refutes square brackets")
    (refute (stringContains? emptyWire "]") "empty metadata wire refutes square brackets")
    (assert (cog/checkDyckBalance emptyWire) "empty metadata wire satisfies Dyck balance"))
  (let [(deserRes (bus/ndAsnDeserializeSingle "(:frame :topic \"t\" :seq 1 :ts 100 :payload \"(test)\" :meta ((\"k\" \"v\")))"))]
    (assert (ok? deserRes) "deserializing pure Dyck-1 meta frame succeeds")
    (refute (err? deserRes) "deserializing pure Dyck-1 meta frame refutes error"))
  true

fn runTests -> Bool
  (do
    (assert (testCognitiveScratchpadDyckPurity) "testCognitiveScratchpadDyckPurity passed")
    (assert (testAgentBusWirePurity) "testAgentBusWirePurity passed")
    (assert (testCompactRecordDyckPurity) "testCompactRecordDyckPurity passed")
    (assert (testDualPolarityProbes) "testDualPolarityProbes passed")
    true)

fn RunTests -> Bool
  (runTests)
