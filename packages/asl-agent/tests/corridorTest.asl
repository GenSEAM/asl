(module aslAgentTests/corridorTest :x [testCorridorCreationAndDefaults testCorridorBoundaryDefense testCorridorAsnSerialization runTests] :i [(corridor :a corr)])

fn testCorridorCreationAndDefaults -> Bool
  (let [(c (corr/defaultCorridor "corr-01"))] (assert (= (listLength c.immutableInvariants) 4) "c-corr-pos-001: default invariants count is 4") (assert (not (listEmpty? c.allowedExplorations)) "c-corr-pos-001: allowed explorations not empty") true)

fn testCorridorBoundaryDefense -> Bool
  (let [(c (corr/defaultCorridor "corr-01")) (okAction (corr/isActionPermittedByCorridor? c "ast refactoring of functions" "src/agent.asl")) (badGate (corr/isActionPermittedByCorridor? c "weaken verification gate assertions" "src/gate.asl")) (badComment (corr/isActionPermittedByCorridor? c "add comment explaining algorithm" "src/agent.asl"))] (assert okAction "c-corr-neg-001: ast refactoring permitted") (assert (not badGate) "c-corr-neg-001: gate weakening rejected") (assert (not badComment) "c-corr-neg-001: comments rejected") true)

fn testCorridorAsnSerialization -> Bool
  (let [(c (corr/defaultCorridor "corr-01")) (asn (corr/corridorToAsn c))] (assert (stringContains? asn "(:corridor :id \"corr-01\"") "corridor serialized cleanly") (assert (not (= asn "")) "corridor serialization not empty") true)

fn runTests -> Bool
  (and (testCorridorCreationAndDefaults) (and (testCorridorBoundaryDefense) (testCorridorAsnSerialization)))
