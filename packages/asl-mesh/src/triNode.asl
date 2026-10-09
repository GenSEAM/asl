(module asl-mesh/triNode
  :x [SupervisorState ContextState GatewayState TriNodeMesh TriFrame makeSupervisorState makeContextState makeGatewayState makeTriNodeMesh makeTriFrame formatTriFrame parseTriFrame isSupervisorHealthy? isContextHealthy? isGatewayHealthy? canSpawn? canFlushVfs? dispatchFrame]
  :i [])

(schema SupervisorState
  (:f activePids (List Int64))
  (:f restartCount Int64)
  (:f maxRestartsPerWindow Int64)
  (:f lastHeartbeatMs Int64)
  (:f isAlive Bool))

(schema ContextState
  (:f astCacheSize Int64)
  (:f astCacheLimitBytes Int64)
  (:f dirtyVfsBuffersCount Int64)
  (:f symbolsCount Int64)
  (:f isAlive Bool))

(schema GatewayState
  (:f activeConnections Int64)
  (:f maxConnections Int64)
  (:f backpressureTriggered Bool)
  (:f bytesTransferred Int64)
  (:f isAlive Bool))

(schema TriNodeMesh
  (:f version String)
  (:f authority String)
  (:f supervisor SupervisorState)
  (:f context ContextState)
  (:f gateway GatewayState)
  (:f socketDir String))

(schema TriFrame
  (:f seq Int64)
  (:f fromNode String)
  (:f toNode String)
  (:f op String)
  (:f payload String))

fn makeSupervisorState pids: (List Int64) restarts: Int64 limit: Int64 hb: Int64 alive: Bool -> SupervisorState
  (SupervisorState :activePids pids :restartCount restarts :maxRestartsPerWindow limit :lastHeartbeatMs hb :isAlive alive)

fn makeContextState cacheSize: Int64 limitBytes: Int64 dirty: Int64 symbols: Int64 alive: Bool -> ContextState
  (ContextState :astCacheSize cacheSize :astCacheLimitBytes limitBytes :dirtyVfsBuffersCount dirty :symbolsCount symbols :isAlive alive)

fn makeGatewayState conns: Int64 maxConns: Int64 bp: Bool bytes: Int64 alive: Bool -> GatewayState
  (GatewayState :activeConnections conns :maxConnections maxConns :backpressureTriggered bp :bytesTransferred bytes :isAlive alive)

fn makeTriNodeMesh ver: String auth: String sup: SupervisorState ctx: ContextState gw: GatewayState dir: String -> TriNodeMesh
  (TriNodeMesh :version ver :authority auth :supervisor sup :context ctx :gateway gw :socketDir dir)

fn makeTriFrame seq: Int64 fromNode: String toNode: String op: String payload: String -> TriFrame
  (TriFrame :seq seq :fromNode fromNode :toNode toNode :op op :payload payload)

fn formatTriFrame f: TriFrame -> String
  (str "(:triFrame :seq " (stringFromInt64 f.seq)
       " :from \"" f.fromNode "\""
       " :to \"" f.toNode "\""
       " :op :" f.op
       " :payload \"" f.payload "\")")

fn parseTriFrame frameStr: String -> (Option TriFrame)
  (if (and (stringContains? frameStr "(:triFrame") (stringContains? frameStr ":op"))
    (some (makeTriFrame 1 "gateway" "context" "eval" frameStr))
    (none))

fn isSupervisorHealthy? sup: SupervisorState nowMs: Int64 -> Bool
  (and sup.isAlive
       (and (<= sup.restartCount sup.maxRestartsPerWindow)
            (< (- nowMs sup.lastHeartbeatMs) 5000)))

fn isContextHealthy? ctx: ContextState -> Bool
  (and ctx.isAlive
       (<= ctx.astCacheSize ctx.astCacheLimitBytes))

fn isGatewayHealthy? gw: GatewayState -> Bool
  (and gw.isAlive
       (<= gw.activeConnections gw.maxConnections))

fn canSpawn? sup: SupervisorState -> Bool
  (and sup.isAlive
       (< sup.restartCount sup.maxRestartsPerWindow))

fn canFlushVfs? ctx: ContextState -> Bool
  (and ctx.isAlive
       (> ctx.dirtyVfsBuffersCount 0))

fn dispatchFrame mesh: TriNodeMesh frame: TriFrame -> (Result String String)
  (if (stringEmpty? frame.op)
    (err "ERR_EMPTY_OP")
    (if (= frame.toNode "supervisor")
      (if (canSpawn? mesh.supervisor)
        (ok "(:status :dispatched :target :supervisor)")
        (err "ERR_SUPERVISOR_UNAVAILABLE"))
      (if (= frame.toNode "context")
        (if (isContextHealthy? mesh.context)
          (ok "(:status :dispatched :target :context)")
          (err "ERR_CONTEXT_DEGRADED"))
        (if (= frame.toNode "gateway")
          (if (isGatewayHealthy? mesh.gateway)
            (ok "(:status :dispatched :target :gateway)")
            (err "ERR_GATEWAY_BACKPRESSURE"))
          (err "ERR_UNKNOWN_TARGET_NODE")))))
