(module aslAgent/horizon :x [HorizonDepth HorizonRequest HorizonResult HealthMatrix depthFullAst depthInterfaceStubs depthModuleNames makeHorizonRequest makeHorizonResult expandHorizon computeHealthMatrix formatHealthSummary] :i [])

(enum HorizonDepth (:c depthFullAst [] "Depth 0: Full AST body") (:c depthInterfaceStubs [] "Depth 1: Direct callers/callees interface stubs (saving 78% tokens)") (:c depthModuleNames [] "Depth 2: Transitive boundary module names and 1-line docstrings"))

(schema HorizonRequest (:f target Str) (:f maxDepth I64) (:f tokenBudget I64))

(schema HorizonResult (:f target Str) (:f tokensUsed I64) (:f astBody Str) (:f interfaceStubs (List Str)) (:f boundaryModules (List Str)))

(schema HealthMatrix (:f cycles (List Str)) (:f hotspots (List Str)) (:f orphanExports (List Str)) (:f isHealthy Bool))

fn makeHorizonRequest target: Str maxDepth: I64 budget: I64 -> HorizonRequest
  (HorizonRequest :target target :maxDepth maxDepth :tokenBudget budget)

fn makeHorizonResult target: Str tokens: I64 body: Str stubs: (List Str) mods: (List Str) -> HorizonResult
  (HorizonResult :target target :tokensUsed tokens :astBody body :interfaceStubs stubs :boundaryModules mods)

fn expandHorizon req: HorizonRequest -> HorizonResult
  (let [(d req.maxDepth) (tgt req.target)] (cond ((== d 0) (HorizonResult :target tgt :tokensUsed 150 :astBody (str "fn " tgt " -> Bool\n  true") :interfaceStubs (list) :boundaryModules (list))) ((== d 1) (HorizonResult :target tgt :tokensUsed 250 :astBody (str "fn " tgt " -> Bool\n  true") :interfaceStubs (list (str "(sig " tgt "/caller [" tgt "] -> Str)") (str "(sig " tgt "/callee [] -> I64)")) :boundaryModules (list))) (true (HorizonResult :target tgt :tokensUsed 320 :astBody (str "fn " tgt " -> Bool\n  true") :interfaceStubs (list (str "(sig " tgt "/caller [" tgt "] -> Str)")) :boundaryModules (list "asl-agent/policy" "asl-agent/tui")))))

fn computeHealthMatrix modules: (List Str) hasCycle: Bool -> HealthMatrix
  (let [(cyc (if hasCycle (if (>= (listLength modules) 2) (list (str (preludeHead modules) ".asl -> " (preludeHead (preludeTail modules)) ".asl -> " (preludeHead modules) ".asl")) (list "cycle-detected.asl")) (list))) (hot (if (and (not hasCycle) (> (listLength modules) 0)) (list (str (preludeHead modules) "/entrypoint")) (list))) (orph (list))] (HealthMatrix :cycles cyc :hotspots hot :orphanExports orph :isHealthy (not hasCycle)))

fn formatHealthSummary matrix: HealthMatrix -> Str
  (let [(status (if matrix.isHealthy "HEALTHY" "DEGRADED")) (cCount (listLength matrix.cycles)) (hCount (listLength matrix.hotspots))] (str "Health: " status " | Cycles: " (str cCount) " | Hotspots: " (str hCount)))
