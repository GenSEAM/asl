(module aslAgentCore/tests/fiberPoolTest
  :x [testFiberPoolLifecycle testFiberStepAndYield testFastKnowledgeCache testZeroCopyLookup runTests]
  :i [(asl/packages/asl-agent-core/src/fiberPool :a fp)
      (asl/packages/asl-agent-core/src/fastKnowledgeCache :a kc)])

fn testFiberPoolLifecycle -> Bool
  (let [(pool (fp/fiberPoolCreate 32))
        (s1 (fp/fiberSpawn pool (fp/prioCritical) "(+ 1 1)" 1000))
        (p1 (pairFirst s1))
        (id1 (pairSecond s1))
        (s2 (fp/fiberSpawn p1 (fp/prioInteractive) "(lookup 'foo)" 1005))
        (p2 (pairFirst s2))
        (id2 (pairSecond s2))
        (s3 (fp/fiberSpawn p2 (fp/prioBackground) "(index 'all)" 1010))
        (p3 (pairFirst s3))
        (id3 (pairSecond s3))]
    (assert (= (mapSize p3.activeFibers) 3) "Must have 3 active fibers")
    (assert (= (listLength p3.criticalQueue) 1) "Critical queue has 1 fiber")
    (assert (= (listLength p3.interactiveQueue) 1) "Interactive queue has 1 fiber")
    (assert (= (listLength p3.backgroundQueue) 1) "Background queue has 1 fiber")
    (assert (= (optionOr (fp/fiberNextRunnable p3) "") id1) "Critical fiber runs first")
    true)

fn testFiberStepAndYield -> Bool
  (let [(pool (fp/fiberPoolCreate 16))
        (s (fp/fiberSpawn pool (fp/prioInteractive) "(eval '(+ 20 22))" 2000))
        (p1 (pairFirst s))
        (fid (pairSecond s))
        (p2 (fp/fiberStep p1 fid 25 "interm-42"))
        (p3 (fp/fiberYield p2 fid))
        (p4 (fp/fiberComplete p3 fid "42"))]
    (assert (= p4.totalCompleted 1) "Completed count must increment to 1")
    (assert (= (mapSize p4.activeFibers) 1) "Fiber remains in pool as completed")
    true)

fn testFastKnowledgeCache -> Bool
  (let [(cache (kc/knowledgeCacheCreate))
        (c1 (kc/knowledgeIndexSymbol cache "FiberPool" "aslAgentCore/fiberPool" "asl/packages/asl-agent-core/src/fiberPool.asl" "anchor-fp" "schema"))
        (c2 (kc/knowledgeUpdateTask c1 "Task59301" ":active"))
        (c3 (kc/knowledgeRecordDefect c2 "DEF-NONE"))
        (c4 (kc/knowledgeAddNote c3 "Fast cache initialized with zero IPC tax"))
        (symOpt (kc/knowledgeLookupSymbol c4 "FiberPool"))
        (taskStatus (kc/knowledgeGetTaskStatus c4 "Task59301"))]
    (assert (some? symOpt) "Must find indexed symbol FiberPool")
    (assert (= (optionOr symOpt (kc/AstSymbolEntry :symbol "" :module "" :file "" :anchor "" :kind "")).anchor "anchor-fp") "Anchor matches")
    (assert (= (optionOr taskStatus "") ":active") "Task status matches")
    (assert (= (listLength c4.defectLedger) 1) "Defect ledger has 1 entry")
    (assert (= (listLength c4.notesSnapshot) 1) "Notes snapshot has 1 entry")
    true)

fn testZeroCopyLookup -> Bool
  (let [(cache (kc/knowledgeCacheCreate))
        (c1 (kc/knowledgeIndexSymbol cache "astAddressing" "asl/grammar/rules" "asl/grammar/rules.asn" "rule-ast" "rule"))
        (sym (kc/knowledgeLookupSymbol c1 "astAddressing"))]
    (assert (some? sym) "Symbol astAddressing found")
    (assert (= (optionOr sym (kc/AstSymbolEntry :symbol "" :module "" :file "" :anchor "" :kind "")).kind "rule") "Symbol is rule")
    true)

fn runTests -> Bool
  (do
    (assert (testFiberPoolLifecycle) "Fiber pool lifecycle must pass")
    (assert (testFiberStepAndYield) "Fiber step and yield must pass")
    (assert (testFastKnowledgeCache) "Fast knowledge cache must pass")
    (assert (testZeroCopyLookup) "Zero-copy lookup must pass")
    true)
