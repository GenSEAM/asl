(module asl-coord/presence
  :x [beat agentsList]
  :i [(asl-store/types :a ty) (asl-coord/lease :a ls) (asl-coord/core :a co)])

; (:m :ref VS-COORD :do "presence is one row per agent whose TTL the store enforces from the caller's now, so an agent that stops beating drops out of the list without any sweeper; rows carry project and unit but are never consulted by claims")
fn beat ctx: co/Ctx agent: String project: String unit: String ttlMs: Int64 -> (Result Int64 String)
  (match (ctx.call (ty/opPut (ty/Key :collection "agents" :id agent)
                      (str "(:agent :id " (ls/q agent) " :project " (ls/q project) " :unit " (ls/q unit) " :at " (stringFromInt64 ctx.now) ")")
                      ttlMs ctx.now))
    ((ty/rWritten rev) (ok rev))
    ((ty/rErr code text) (err (str code ": " text)))
    (_ (err "unexpected reply")))

fn agentsList ctx: co/Ctx -> (Result (List String) String)
  (match (ctx.call (ty/opScan "agents" "" "" 1000 ctx.now))
    ((ty/rPage rows _) (ok (map (fn [(r ty/ScanRow)] -> String r.value) rows)))
    ((ty/rErr code text) (err (str code ": " text)))
    (_ (err "unexpected reply")))
