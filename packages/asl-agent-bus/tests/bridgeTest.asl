(module aslAgentBus/tests/bridgeTest :x [runTests] :i [(bridge :a b)])

fn runTests -> Bool
  (let [(ev (b/makeBridgeEvent "id" "src" "dst" "payload"))] (assert (= ev.id "id") "event id matches") true)
