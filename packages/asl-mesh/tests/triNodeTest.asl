(module asl-mesh/tests/triNodeTest
  :x [testMeshStateCreation testSupervisorHealth testContextHealth testGatewayHealth testFrameDispatch testDualPolarityRefutations runTests]
  :i [(asl-mesh/triNode :a tn)])

fn testMeshStateCreation -> Bool
  (let [(sup (tn/makeSupervisorState (list 1234 5678) 0 5 1000 true))
        (ctx (tn/makeContextState 1024 134217728 2 500 true))
        (gw (tn/makeGatewayState 4 64 false 4096 true))
        (mesh (tn/makeTriNodeMesh "1.0.0" "ADR0104" sup ctx gw "/tmp/asl_mesh"))]
    (assert (= mesh.version "1.0.0") "Mesh version equals 1.0.0")
    (assert (= mesh.authority "ADR0104") "Authority equals ADR0104")
    (assert (= (listLength mesh.supervisor.activePids) 2) "Active PIDs count is 2")
    (assert (= mesh.context.astCacheSize 1024) "Context cache size is 1024")
    (assert (= mesh.gateway.maxConnections 64) "Gateway max connections is 64")
    true)

fn testSupervisorHealth -> Bool
  (let [(healthySup (tn/makeSupervisorState (list 100) 1 5 1000 true))
        (unhealthySup (tn/makeSupervisorState (list 100) 6 5 1000 true))
        (staleSup (tn/makeSupervisorState (list 100) 0 5 1000 true))]
    (assert (tn/isSupervisorHealthy? healthySup 2000) "Supervisor with 1 restart is healthy")
    (assert (tn/canSpawn? healthySup) "Healthy supervisor can spawn")
    (refute (tn/isSupervisorHealthy? unhealthySup 2000) "Supervisor exceeding restart threshold must fail health check")
    (refute (tn/canSpawn? unhealthySup) "Supervisor exceeding restart threshold cannot spawn")
    (refute (tn/isSupervisorHealthy? staleSup 8000) "Supervisor with stale heartbeat (>5000ms) must fail health check")
    true)

fn testContextHealth -> Bool
  (let [(healthyCtx (tn/makeContextState 500 1000 3 50 true))
        (overflowCtx (tn/makeContextState 1500 1000 0 50 true))]
    (assert (tn/isContextHealthy? healthyCtx) "Context within memory budget is healthy")
    (assert (tn/canFlushVfs? healthyCtx) "Context with dirty buffers can flush")
    (refute (tn/isContextHealthy? overflowCtx) "Context exceeding cache budget must be degraded")
    (refute (tn/canFlushVfs? overflowCtx) "Context without dirty buffers cannot flush")
    true)

fn testGatewayHealth -> Bool
  (let [(healthyGw (tn/makeGatewayState 10 64 false 1000 true))
        (saturatedGw (tn/makeGatewayState 65 64 true 5000 true))]
    (assert (tn/isGatewayHealthy? healthyGw) "Gateway below max connections is healthy")
    (refute (tn/isGatewayHealthy? saturatedGw) "Gateway over limit must report unhealthy")
    true)

fn testFrameDispatch -> Bool
  (let [(sup (tn/makeSupervisorState (list 10) 0 5 1000 true))
        (ctx (tn/makeContextState 100 1000 1 10 true))
        (gw (tn/makeGatewayState 1 64 false 100 true))
        (mesh (tn/makeTriNodeMesh "1.0.0" "ADR0104" sup ctx gw "/tmp/asl_mesh"))
        (fSup (tn/makeTriFrame 1 "gateway" "supervisor" "spawn" "(:cmd \"test\")"))
        (fCtx (tn/makeTriFrame 2 "gateway" "context" "eval" "(:eval (foo))"))
        (fGw (tn/makeTriFrame 3 "context" "gateway" "stream" "(:chunk \"ok\")"))
        (resSup (tn/dispatchFrame mesh fSup))
        (resCtx (tn/dispatchFrame mesh fCtx))
        (resGw (tn/dispatchFrame mesh fGw))]
    (assert (ok? resSup) "Dispatch to supervisor succeeds")
    (assert (ok? resCtx) "Dispatch to context succeeds")
    (assert (ok? resGw) "Dispatch to gateway succeeds")
    true)

fn testDualPolarityRefutations -> Bool
  (let [(sup (tn/makeSupervisorState (list) 0 5 1000 false))
        (ctx (tn/makeContextState 0 1000 0 0 false))
        (gw (tn/makeGatewayState 0 64 false 0 false))
        (deadMesh (tn/makeTriNodeMesh "1.0.0" "D104" sup ctx gw "/tmp"))
        (badFrame (tn/makeTriFrame 1 "a" "unknownNode" "op" "data"))
        (emptyFrame (tn/makeTriFrame 2 "a" "supervisor" "" "data"))
        (resBad (tn/dispatchFrame deadMesh badFrame))
        (resEmpty (tn/dispatchFrame deadMesh emptyFrame))
        (resDead (tn/dispatchFrame deadMesh (tn/makeTriFrame 3 "a" "supervisor" "op" "d")))]
    (refute (ok? resBad) "Dispatch to unknown node must fail")
    (refute (ok? resEmpty) "Dispatch with empty op must fail")
    (refute (ok? resDead) "Dispatch to dead supervisor must fail")
    true)

fn runTests -> Bool
  (do
    (assert (testMeshStateCreation) "Mesh state creation test must pass")
    (assert (testSupervisorHealth) "Supervisor health test must pass")
    (assert (testContextHealth) "Context health test must pass")
    (assert (testGatewayHealth) "Gateway health test must pass")
    (assert (testFrameDispatch) "Frame dispatch test must pass")
    (assert (testDualPolarityRefutations) "Dual-polarity refutations must pass")
    true)
