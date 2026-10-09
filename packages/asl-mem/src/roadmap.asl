(module aslMem/roadmap :x [ItemRecord PhaseRecord LeaseRecord RoadmapRecord ClaimResult makeItem makePhase makeLease makeRoadmap isLeaseActive? formatPhaseDefrecord formatRoadmapAsn phaseGet phaseRegister phaseClaim itemComplete phaseComplete] :i [])

(schema ItemRecord (:f id Str) (:f name Str) (:f status Str) (:f gate Str))

(schema PhaseRecord (:f id Str) (:f name Str) (:f status Str) (:f wave Str) (:f gate Str) (:f items (List ItemRecord)))

(schema LeaseRecord (:f phaseId Str) (:f agentId Str) (:f acquiredEpoch I64) (:f ttlMs I64) (:f isActive Bool))

(schema RoadmapRecord (:f iteration Str) (:f phases (List PhaseRecord)) (:f leases (List LeaseRecord)) (:f version I64))

(schema ClaimResult (:f roadmap RoadmapRecord) (:f lease (Option LeaseRecord)) (:f success Bool) (:f reason Str))

fn makeItem id: Str name: Str status: Str gate: Str -> ItemRecord
  (ItemRecord :id id :name name :status status :gate gate)

fn makePhase id: Str name: Str status: Str wave: Str gate: Str items: (List ItemRecord) -> PhaseRecord
  (PhaseRecord :id id :name name :status status :wave wave :gate gate :items items)

fn makeLease phaseId: Str agentId: Str acquired: I64 ttl: I64 -> LeaseRecord
  (LeaseRecord :phaseId phaseId :agentId agentId :acquiredEpoch acquired :ttlMs ttl :isActive true)

fn makeRoadmap iteration: Str phases: (List PhaseRecord) -> RoadmapRecord
  (RoadmapRecord :iteration iteration :phases phases :leases (list) :version 1)

fn isLeaseActive? lease: LeaseRecord nowEpoch: I64 -> Bool
  (and lease.isActive (< nowEpoch (+ lease.acquiredEpoch lease.ttlMs)))

fn formatPhaseDefrecord p: PhaseRecord -> Str
  (str "    (\"" p.id "\" \"" p.name "\" \"" p.status "\" \"" p.wave "\" \"" p.gate "\")")

fn formatRoadmapAsn rm: RoadmapRecord -> Str
  (let [(phaseLines (map (fn [(p PhaseRecord)] -> Str (formatPhaseDefrecord p)) rm.phases)) (body (stringJoin phaseLines "\n"))] (str "(:roadmap\n" "  :iteration \"" rm.iteration "\"\n" "  :version " (stringFromInt64 rm.version) "\n" "  (:phases\n" "    :schema (id name status wave gate)\n" "    (\n" body "\n" "    )))\n"))

fn phaseGet rm: RoadmapRecord phaseId: Str -> (Option PhaseRecord)
  (let [(matches (filter (fn [(p PhaseRecord)] -> Bool (= p.id phaseId)) rm.phases))] (listHead matches))

fn phaseRegister rm: RoadmapRecord phase: PhaseRecord -> RoadmapRecord
  (let [(filtered (filter (fn [(p PhaseRecord)] -> Bool (!= p.id phase.id)) rm.phases))] (with rm :phases (listAppend filtered (list phase)) :version (+ rm.version 1)))

fn phaseClaim rm: RoadmapRecord phaseId: Str agentId: Str nowEpoch: I64 ttlMs: I64 -> ClaimResult
  (let [(pOpt (phaseGet rm phaseId)) (activeLeases (filter (fn [(l LeaseRecord)] -> Bool (isLeaseActive? l nowEpoch)) rm.leases)) (existingActive (filter (fn [(l LeaseRecord)] -> Bool (and (= l.phaseId phaseId) (!= l.agentId agentId))) activeLeases))] (if (> (listLength existingActive) 0) (ClaimResult :roadmap rm :lease (none) :success false :reason "ERR_LEASE_ACTIVE_CONFLICT") (mt pOpt ((none) (ClaimResult :roadmap rm :lease (none) :success false :reason "Phase not found")) ((some p) (let [(newLease (makeLease phaseId agentId nowEpoch ttlMs)) (updPhase (makePhase p.id p.name "claimed" p.wave p.gate p.items)) (otherPh (filter (fn [(ph PhaseRecord)] -> Bool (!= ph.id phaseId)) rm.phases)) (otherActive (filter (fn [(l LeaseRecord)] -> Bool (!= l.phaseId phaseId)) activeLeases))] (ClaimResult :roadmap (with rm :phases (listAppend otherPh (list updPhase)) :leases (listAppend otherActive (list newLease)) :version (+ rm.version 1)) :lease (some newLease) :success true :reason "Lease acquired"))))))

fn itemComplete rm: RoadmapRecord phaseId: Str itemId: Str agentId: Str nowEpoch: I64 -> RoadmapRecord
  (let [(pOpt (phaseGet rm phaseId)) (activeLeases (filter (fn [(l LeaseRecord)] -> Bool (isLeaseActive? l nowEpoch)) rm.leases)) (authorized (filter (fn [(l LeaseRecord)] -> Bool (and (= l.phaseId phaseId) (= l.agentId agentId))) activeLeases))] (if (= (listLength authorized) 0) rm (mt pOpt ((none) rm) ((some p) (let [(updItems (map (fn [(it ItemRecord)] -> ItemRecord (if (= it.id itemId) (makeItem it.id it.name "completed" it.gate) it)) p.items)) (updPhase (makePhase p.id p.name p.status p.wave p.gate updItems)) (otherPh (filter (fn [(ph PhaseRecord)] -> Bool (!= ph.id phaseId)) rm.phases))] (with rm :phases (listAppend otherPh (list updPhase)) :leases activeLeases :version (+ rm.version 1)))))))

fn phaseComplete rm: RoadmapRecord phaseId: Str agentId: Str nowEpoch: I64 -> RoadmapRecord
  (let [(pOpt (phaseGet rm phaseId)) (activeLeases (filter (fn [(l LeaseRecord)] -> Bool (isLeaseActive? l nowEpoch)) rm.leases)) (authorized (filter (fn [(l LeaseRecord)] -> Bool (and (= l.phaseId phaseId) (= l.agentId agentId))) activeLeases))] (if (= (listLength authorized) 0) rm (mt pOpt ((none) rm) ((some p) (let [(updItems (map (fn [(it ItemRecord)] -> ItemRecord (makeItem it.id it.name "completed" it.gate)) p.items)) (updPhase (makePhase p.id p.name "completed" p.wave p.gate updItems)) (otherPh (filter (fn [(ph PhaseRecord)] -> Bool (!= ph.id phaseId)) rm.phases)) (otherL (filter (fn [(l LeaseRecord)] -> Bool (!= l.phaseId phaseId)) activeLeases))] (with rm :phases (listAppend otherPh (list updPhase)) :leases otherL :version (+ rm.version 1)))))))
