(module aslAgent/testIntentUx :x [testIntentClassification testFocusGuardDisruption testNudgeStreakAndInterval testNudgeGuardHoldAndRelease runAllUxTests runTests] :i [(aslAgent/intentUx :a ux) (aslAgent/nudgeGuard :a ng)])

fn testIntentClassification -> Bool
  (let [(iFast (ux/classifyIntent "стоп")) (iIntel (ux/classifyIntent "где находится символ VadConfig")) (iMeta (ux/classifyIntent "почему упало тестирование")) (iRes (ux/classifyIntent "найди в документации api")) (iDev (ux/classifyIntent "исправь ошибку в парсере")) (iMesh (ux/classifyIntent "распредели на claude и antigravity"))] (assert (= iFast.intentId "fast-path") "fast-path intent classified") (assert (= iIntel.intentId "intel") "intel intent classified") (assert (= iMeta.intentId "meta") "meta intent classified") (assert (= iRes.intentId "research") "research intent classified") (assert (= iDev.intentId "dev") "dev intent classified") (assert iDev.requiresWorktree "dev intent requires worktree isolation") (assert iDev.requiresGate "dev intent requires failing gate") (assert (= iMesh.intentId "mesh") "mesh intent classified") true)

fn testFocusGuardDisruption -> Bool
  (let [(iFast (ux/classifyIntent "stop")) (iDev (ux/classifyIntent "добавь фичу"))] (assert (not (ux/isDisruptiveToUser? iFast true)) "fast-path is never disruptive even during active speech") (assert (ux/isDisruptiveToUser? iDev true) "dev intent is held while user is actively speaking") (assert (not (ux/isDisruptiveToUser? iDev false)) "dev intent is not disruptive when user is idle") true)

fn testNudgeStreakAndInterval -> Bool
  (let [(g0 (ng/makeInitialNudgeGuard)) (g1 (ng/recordTaskOutcome g0 "asex" false)) (g2 (ng/recordTaskOutcome g1 "asex" false)) (nEarly (ng/evaluateProactiveNudge g2 10000)) (g3 (ng/recordTaskOutcome g2 "asex" false)) (nStreak (ng/evaluateProactiveNudge g3 70000))] (assert (not (some? nEarly)) "streak of 2 should not fire nudge") (assert (some? nStreak) "streak of 3 with >60s elapsed should fire nudge") (mt nStreak ((some ev) (do (assert (= ev.reason "failure-run") "nudge reason is failure-run") (assert (stringContains? ev.text "failed 3 times") "nudge text reports 3 failures") true)) (none false)) true)

fn testNudgeGuardHoldAndRelease -> Bool
  (let [(g0 (ng/makeInitialNudgeGuard)) (g1 (ng/holdDisruptiveIntent g0 "intent-01")) (g2 (ng/holdDisruptiveIntent g1 "intent-02")) (drainedPair (ng/releaseHeldIntentsOnIdle g2)) (gCleared (pairFirst drainedPair)) (intents (pairSecond drainedPair))] (assert (= (listLength g2.heldIntentIds) 2) "two intents held") (assert (= (listLength intents) 2) "two intents drained on idle") (assert (= (listLength gCleared.heldIntentIds) 0) "guard queue empty after idle release") true)

fn runAllUxTests -> Bool
  (do (testIntentClassification) (testFocusGuardDisruption) (testNudgeStreakAndInterval) (testNudgeGuardHoldAndRelease) true)

fn runTests -> Bool
  (runAllUxTests)
