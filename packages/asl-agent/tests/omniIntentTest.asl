(module aslAgent/tests/omniIntentTest
  :x [testSixDomainClassification testFrontAgentDirective runTests]
  :i [(asl/packages/asl-agent/src/omniIntent :a oi)
      (asl/packages/asl-agent/src/frontAgent :a fa)])

fn testSixDomainClassification -> Bool
  (let [(i1 (oi/classifyOmniIntent "refactor the compiler in engine/asl.c and run tests"))
        (i2 (oi/classifyOmniIntent "find where FiberRecord is defined in the codebase"))
        (i3 (oi/classifyOmniIntent "открой мне браузер и добавь продуктов в корзину на салат"))
        (i4 (oi/classifyOmniIntent "note: consider using HAMT for symbol table in Phase 594"))
        (i5 (oi/classifyOmniIntent "sync schemas between asex and stonefish"))
        (i6 (oi/classifyOmniIntent "asl daemon status and active worker count"))]
    (assert (oi/isCodeTask? i1) "i1 is codeTask")
    (assert (= i1.targetSubstrate "worker-jail") "i1 targets worker-jail")
    (assert i1.requiresGate "i1 requires red-green gate")
    (assert (oi/isResearch? i2) "i2 is research")
    (assert (= i2.targetSubstrate "cognitive-fiber") "i2 targets cognitive-fiber")
    (assert (not i2.requiresGate) "i2 does not require gate")
    (assert (oi/isBrowserAction? i3) "i3 is browserAction")
    (assert (= i3.targetSubstrate "gateway-browser") "i3 targets gateway-browser")
    (assert (= i4.targetSubstrate "notes-ledger") "i4 targets notes-ledger")
    (assert (= i5.targetSubstrate "sync-nexus") "i5 targets sync-nexus")
    (assert (= i6.targetSubstrate "daemon-loop") "i6 targets daemon-loop")
    true)

fn testFrontAgentDirective -> Bool
  (let [(cfg (fa/FrontAgentConfig :workspaceRoot "/work/repo" :daemonSocket "/tmp/asl-engine.sock" :voiceEnabled true))
        (st (fa/frontAgentInit cfg))
        (res (fa/frontAgentHandleDirective st "поправь в проекте баг с компилятором"))
        (nextSt (pairFirst res))
        (receipt (pairSecond res))]
    (assert (= nextSt.directivesHandled 1) "Handled 1 directive")
    (assert receipt.success "Receipt reports success")
    (assert (= receipt.dispatchedTarget "worker-jail") "Routed to worker-jail")
    (assert (stringContains? receipt.receiptText ":front-agent-receipt") "Formatted ASN receipt")
    true)

fn runTests -> Bool
  (do
    (assert (testSixDomainClassification) "6-Domain classification must pass")
    (assert (testFrontAgentDirective) "Front-Agent directive dispatch must pass")
    true)
