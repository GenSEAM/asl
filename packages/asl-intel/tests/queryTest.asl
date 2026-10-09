(module aslIntel/tests/queryTest :x [testQueryCallers testQueryCallees testQueryImpact testQueryCycleResilience runTests] :i [(symbolGraph :a g) (query :a q)])

fn makeNode id: Str name: Str -> g/GraphNode
  (g/GraphNode :id id :name name :kind "fn" :file "test.asl" :startLine 1 :endLine 10 :signature "() -> Unit" :exported true)

fn makeEdge src: Str dst: Str -> g/GraphEdge
  (g/GraphEdge :src src :dst dst :kind (g/edgeCalls) :file "test.asl" :line 5)

fn buildTestGraph -> g/SymbolGraph
  (let [(g0 (g/graphCreate)) (g1 (g/graphAddNode g0 (makeNode "mod/leaf" "leaf"))) (g2 (g/graphAddNode g1 (makeNode "mod/mid" "mid"))) (g3 (g/graphAddNode g2 (makeNode "mod/root" "root"))) (g4 (g/graphAddNode g3 (makeNode "mod/side" "side"))) (g5 (g/graphAddEdge g4 (makeEdge "mod/mid" "mod/leaf"))) (g6 (g/graphAddEdge g5 (makeEdge "mod/root" "mod/mid"))) (g7 (g/graphAddEdge g6 (makeEdge "mod/side" "mod/leaf")))] g7)

fn testQueryCallers -> Bool
  (let [(graph (buildTestGraph)) (res (q/queryCallers graph "mod/leaf"))] (assert (= res.total 2) "leaf must have exactly 2 callers") (let [(ids (map (fn [(it q/ImpactItem)] -> Str it.symbolId) res.items)) (allIds (stringJoin ids " "))] (assert (stringContains? allIds "mod/mid") "callers must contain mod/mid") (assert (stringContains? allIds "mod/side") "callers must contain mod/side") true))

fn testQueryCallees -> Bool
  (let [(graph (buildTestGraph)) (res (q/queryCallees graph "mod/root"))] (assert (= res.total 1) "root must have exactly 1 callee") (let [(firstIt (optionOr (listHead res.items) (q/ImpactItem :symbolId "" :name "" :file "" :depth 0)))] (assert (= firstIt.symbolId "mod/mid") "callee must be mod/mid") true))

fn testQueryImpact -> Bool
  (let [(graph (buildTestGraph)) (res1 (q/queryImpact graph "mod/leaf" 1)) (res2 (q/queryImpact graph "mod/leaf" 2))] (assert (= res1.total 2) "depth 1 must find 2 direct callers") (assert (= res2.total 3) "depth 2 must find 3 transitive callers") (let [(ids (map (fn [(it q/ImpactItem)] -> Str it.symbolId) res2.items)) (allIds (stringJoin ids " "))] (assert (stringContains? allIds "mod/root") "transitive callers must reach mod/root") true))

fn testQueryCycleResilience -> Bool
  (let [(g0 (g/graphCreate)) (g1 (g/graphAddNode g0 (makeNode "node/a" "a"))) (g2 (g/graphAddNode g1 (makeNode "node/b" "b"))) (g3 (g/graphAddEdge g2 (makeEdge "node/a" "node/b"))) (g4 (g/graphAddEdge g3 (makeEdge "node/b" "node/a"))) (res (q/queryImpact g4 "node/a" 5))] (assert (= res.total 1) "cyclical callers must terminate with visited deduplication") true)

fn runTests -> Bool
  (do (assert (testQueryCallers) "test-query-callers must pass") (assert (testQueryCallees) "test-query-callees must pass") (assert (testQueryImpact) "test-query-impact must pass") (assert (testQueryCycleResilience) "test-query-cycle-resilience must pass") true)
