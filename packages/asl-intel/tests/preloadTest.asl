(module aslIntel/tests/preloadTest :x [TestStubTokenEstimation TestPreloadTierConversion TestHorizonBudgetEnforcement TestHorizonAddStubBudget TestHorizonZeroBudget TestIntelPreloadGraphMultiTier TestIntelPreloadDepthScoping TestIntelPreloadEmptyTarget TestIntelPreloadMissingTarget TestIntelPreloadZeroDepth TestFormatPreloadContext TestIntelPreloadHydration! TestHydrateGraphSources runTests] :i [(preload :a pr) (symbolGraph :a g) (asl-text/text :a txt)])

fn buildTestGraph -> g/SymbolGraph
  (let [(n0 (g/GraphNode :id "app/main" :name "main" :kind "function" :file "src/main.asl" :startLine 1 :endLine 20 :signature "(fn main [] -> I64)" :exported true)) (n1 (g/GraphNode :id "app/caller" :name "caller" :kind "function" :file "src/caller.asl" :startLine 1 :endLine 15 :signature "(fn caller [] -> I64)" :exported true)) (n2 (g/GraphNode :id "app/callee" :name "callee" :kind "function" :file "src/callee.asl" :startLine 1 :endLine 10 :signature "(fn callee [] -> I64)" :exported true)) (n3 (g/GraphNode :id "app/transitive" :name "transitive" :kind "function" :file "src/trans.asl" :startLine 1 :endLine 8 :signature "(fn transitive [] -> I64)" :exported false)) (e1 (g/GraphEdge :src "app/caller" :dst "app/main" :kind (g/edgeCalls) :file "src/caller.asl" :line 5)) (e2 (g/GraphEdge :src "app/main" :dst "app/callee" :kind (g/edgeCalls) :file "src/main.asl" :line 10)) (e3 (g/GraphEdge :src "app/callee" :dst "app/transitive" :kind (g/edgeCalls) :file "src/callee.asl" :line 8)) (g0 (g/graphCreate)) (g1 (g/graphAddNode g0 n0)) (g2 (g/graphAddNode g1 n1)) (g3 (g/graphAddNode g2 n2)) (g4 (g/graphAddNode g3 n3)) (g5 (g/graphAddEdge g4 e1)) (g6 (g/graphAddEdge g5 e2)) (g7 (g/graphAddEdge g6 e3))] g7)

fn TestStubTokenEstimation -> Bool
  (let [(stubExplicit (pr/stubCreate "sym-a" (pr/tierMicroAst) "src/a.asl" "(fn sym-a [] -> I64)" "doc" 42)) (stubCalc (pr/stubCreate "sym-b" (pr/tierMesoSymbol) "src/b.asl" "(fn sym-b [] -> Str)" "" 0))] (assert (= (txt/estimateTokens "12345678") 2) "8-char string should estimate 2 tokens") (assert (= (txt/estimateTokens "") 0) "Empty string should estimate 0 tokens") (assert (= (pr/estimateStubTokens stubExplicit) 42) "Explicit token stub should return 42") (assert (> (pr/estimateStubTokens stubCalc) 0) "Calculated token stub should exceed 0") true)

fn TestPreloadTierConversion -> Bool
  (do (assert (= (pr/preloadTierToString (pr/tierMicroAst)) "micro-ast") "Tier micro-ast string must match") (assert (= (pr/preloadTierToString (pr/tierMesoSymbol)) "meso-symbol") "Tier meso-symbol string must match") (assert (= (pr/preloadTierToString (pr/tierMacroTopology)) "macro-topology") "Tier macro-topology string must match") true)

fn TestHorizonBudgetEnforcement -> Bool
  (let [(h0 (pr/horizonCreate "app/main" 2 100)) (s1 (pr/stubCreate "s1" (pr/tierMesoSymbol) "f1.asl" "sig1" "" 60)) (s2 (pr/stubCreate "s2" (pr/tierMesoSymbol) "f2.asl" "sig2" "" 50)) (h1 (pr/horizonAddStub h0 s1)) (h2 (pr/horizonAddStub h1 s2))] (assert (= h1.totalTokens 60) "h1 total tokens must be 60") (assert (not h1.truncated) "h1 must not be truncated") (assert (= (listLength h1.stubs) 1) "h1 stubs length must be 1") (assert (= h2.totalTokens 60) "h2 total tokens must remain 60") (assert h2.truncated "h2 must be marked truncated") (assert (= (listLength h2.stubs) 1) "h2 stubs length must remain 1") true)

fn TestHorizonAddStubBudget -> Bool
  (let [(h0 (pr/horizonCreate "app/main" 2 100)) (s1 (pr/stubCreate "s1" (pr/tierMesoSymbol) "f1.asl" "sig1" "" 60)) (s2 (pr/stubCreate "s2" (pr/tierMesoSymbol) "f2.asl" "sig2" "" 50)) (s3 (pr/stubCreate "s3" (pr/tierMacroTopology) "f3.asl" "" "doc" 5)) (h1 (pr/horizonAddStub h0 s1)) (h2 (pr/horizonAddStub h1 s2)) (h3 (pr/horizonAddStub h2 s3))] (assert h2.truncated "h2 must be truncated") (assert (= (listLength h2.stubs) 1) "h2 stubs length must be 1") (assert h3.truncated "h3 must remain truncated") (assert (= (listLength h3.stubs) 1) "h3 stubs length must remain 1") (assert (= h3.totalTokens 60) "h3 total tokens must remain 60") true)

fn TestHorizonZeroBudget -> Bool
  (let [(hz (pr/horizonCreate "app/main" 2 0)) (s1 (pr/stubCreate "s1" (pr/tierMicroAst) "f1.asl" "sig" "doc" 10)) (hzRes (pr/horizonAddStub hz s1))] (assert (= (listLength hzRes.stubs) 0) "Zero budget horizon stubs must be 0") (assert hzRes.truncated "Zero budget horizon must be marked truncated") true)

fn TestIntelPreloadGraphMultiTier -> Bool
  (let [(g (buildTestGraph)) (h (pr/intelPreloadGraph g "app/main" 2 10000)) (stubs h.stubs)] (assert (= (listLength stubs) 4) "Stubs length must be 4") (assert (not h.truncated) "Horizon must not be truncated") (assert (= h.targetSymbol "app/main") "Target symbol must be app/main") true)

fn TestIntelPreloadDepthScoping -> Bool
  (let [(g (buildTestGraph)) (hD1 (pr/intelPreloadGraph g "app/main" 1 10000)) (hName (pr/intelPreloadGraph g "main" 0 10000))] (assert (= (listLength hD1.stubs) 3) "Depth 1 stubs length must be 3") (assert (not hD1.truncated) "Depth 1 horizon must not be truncated") (assert (= (listLength hName.stubs) 1) "Exact name depth 0 stubs must be 1") (assert (not hName.truncated) "Exact name depth 0 must not be truncated") true)

fn TestIntelPreloadEmptyTarget -> Bool
  (let [(g (buildTestGraph)) (h1 (pr/intelPreloadGraph g "" 2 1000)) (h2 (pr/intelPreloadGraph g "   " 2 1000))] (assert (= (listLength h1.stubs) 0) "Empty target stubs must be 0") (assert (not h1.truncated) "Empty target must not be truncated") (assert (= h1.totalTokens 0) "Empty target total tokens must be 0") (assert (= (listLength h2.stubs) 0) "Whitespace target stubs must be 0") (assert (not h2.truncated) "Whitespace target must not be truncated") (assert (= h2.totalTokens 0) "Whitespace target total tokens must be 0") true)

fn TestIntelPreloadMissingTarget -> Bool
  (let [(g (buildTestGraph)) (h (pr/intelPreloadGraph g "nonexistent/symbol" 2 1000))] (assert (= (listLength h.stubs) 0) "Missing target stubs must be 0") (assert (not h.truncated) "Missing target must not be truncated") (assert (= h.totalTokens 0) "Missing target total tokens must be 0") true)

fn TestIntelPreloadZeroDepth -> Bool
  (let [(g (buildTestGraph)) (h0 (pr/intelPreloadGraph g "app/main" 0 1000)) (hNeg (pr/intelPreloadGraph g "app/main" -1 1000))] (assert (= (listLength h0.stubs) 1) "Zero depth stubs must be 1") (assert (not h0.truncated) "Zero depth must not be truncated") (assert (= (listLength hNeg.stubs) 1) "Negative depth stubs must be 1") (assert (not hNeg.truncated) "Negative depth must not be truncated") true)

fn TestFormatPreloadContext -> Bool
  (let [(g (buildTestGraph)) (h (pr/intelPreloadGraph g "app/main" 2 10000)) (ctx (pr/formatPreloadContext h))] (assert (stringContains? ctx ":horizon") "Context must contain :horizon") (assert (stringContains? ctx ":target \"app/main\"") "Context must contain target") (assert (stringContains? ctx ":budget 10000") "Context must contain budget 10000") (assert (stringContains? ctx ":tokens") "Context must contain :tokens") (assert (stringContains? ctx ":stub :symbol \"app/main\"") "Context must contain stub symbol") (assert (stringContains? ctx ":tier \"micro-ast\"") "Context must contain tier micro-ast") true)

fn TestIntelPreloadHydration! -> Bool
  (let [(h (pr/intelPreload! "stub-create" 1 10000))] (assert (> (listLength h.stubs) 0) "Preload must return stubs for stub-create") (assert (not h.truncated) "Preload horizon must not be truncated") true)

fn TestDefaultWorkspaceFilesIncludesSymbolGraph! -> Bool
  (assert (listContains? (pr/defaultWorkspaceFiles!) "asl/packages/asl-intel/src/symbolGraph.asl") "Default workspace files must include symbolGraph.asl")
  true

fn TestHydrateGraphSources -> Bool
  (let [(s1 (str "(module test/app\n" "  :x [foo bar])\n" "(fn bar [] -> I64 1)\n" "(fn foo [] -> I64\n" "  (test/app/bar))\n")) (sources (list (pair "app.asl" s1))) (g (pr/hydrateGraphFromSources sources))] (assert (>= (g/graphNodeCount g) 2) "Graph must contain 2 nodes") (assert (>= (g/graphEdgeCount g) 1) "Graph must contain 1 edge") true)

fn ! runTests -> Bool
  (let [(t1 (TestStubTokenEstimation)) (t2 (TestPreloadTierConversion)) (t3 (TestHorizonBudgetEnforcement)) (t4 (TestHorizonAddStubBudget)) (t5 (TestHorizonZeroBudget)) (t6 (TestIntelPreloadGraphMultiTier)) (t7 (TestIntelPreloadDepthScoping)) (t8 (TestIntelPreloadEmptyTarget)) (t9 (TestIntelPreloadMissingTarget)) (t10 (TestIntelPreloadZeroDepth)) (t11 (TestFormatPreloadContext)) (t12 (TestIntelPreloadHydration!)) (t13 (TestHydrateGraphSources)) (t14 (TestDefaultWorkspaceFilesIncludesSymbolGraph!))] (and t1 (and t2 (and t3 (and t4 (and t5 (and t6 (and t7 (and t8 (and t9 (and t10 (and t11 (and t12 (and t13 t14))))))))))))))
