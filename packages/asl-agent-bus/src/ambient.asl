(module aslAgentBus/ambient :x [AmbientFrame createAmbientFrame validateAmbientFrame encodeAmbientAsn] :i [])

(schema AmbientFrame (:f peerId Str) (:f load F64) (:f claimed (List Str)) (:f ts I64))

fn createAmbientFrame peerId: Str load: F64 claimed: (List Str) ts: I64 -> AmbientFrame
  (AmbientFrame :peerId peerId :load load :claimed claimed :ts ts)

fn validateAmbientFrame frame: AmbientFrame -> Bool
  (and (not (stringEmpty? frame.peerId)) (and (>= frame.load 0.0) (and (<= frame.load 1.0) (>= frame.ts 0))))

fn formatClaimedBuffers items: (List Str) -> Str
  (if (listEmpty? items) "[]" (str "[" (stringJoin (map (fn [(s Str)] -> Str (str "\"" s "\"")) items) " ") "]"))

fn encodeAmbientAsn frame: AmbientFrame -> Str
  (let [(claimedStr (formatClaimedBuffers frame.claimed))] (str "(:ambient :peer-id \"" frame.peerId "\" :load " (stringFromFloat64 frame.load) " :claimed " claimedStr " :ts " (stringFromInt64 frame.ts) ")"))
