(module asl-mesh/descriptor
  :x [ShardDescriptor
      StaticGateDescriptor
      EventHookDescriptor
      ThermodynamicsDescriptor
      MeshConfigDescriptor
      DefectCategoryDescriptor
      SafetyPolicyDescriptor
      makeShardDescriptor
      makeStaticGateDescriptor
      makeEventHookDescriptor
      makeMeshConfigDescriptor
      makeDefectCategoryDescriptor
      makeSafetyPolicyDescriptor
      validateShardDescriptor
      validateStaticGateDescriptor
      validateEventHookDescriptor
      validateDefectCategoryDescriptor
      validateSafetyPolicyDescriptor
      isExecutionAllowed]
  :i [])

(schema ShardDescriptor
  (:f id Str)
  (:f name Str)
  (:f paths (List Str))
  (:f intent Str)
  (:f attractor Str)
  (:f model Str)
  (:f temp F64)
  (:f suggestedSeverity Str)
  (:f focus Str))

(schema StaticGateDescriptor
  (:f id Str)
  (:f cmd Str)
  (:f evalExpr Str)
  (:f doc Str))

(schema EventHookDescriptor
  (:f event Str)
  (:f action Str)
  (:f doc Str))

(schema ThermodynamicsDescriptor
  (:f intent Str)
  (:f temperature F64)
  (:f floorTokens I64)
  (:f policy Str))

(schema MeshConfigDescriptor
  (:f version Str)
  (:f authority Str)
  (:f shards (List ShardDescriptor))
  (:f staticPipeline (List StaticGateDescriptor))
  (:f hooks (List EventHookDescriptor))
  (:f thermodynamics (List ThermodynamicsDescriptor)))

(schema DefectCategoryDescriptor
  (:f id Str)
  (:f severity Str)
  (:f doc Str))

(schema SafetyPolicyDescriptor
  (:f zeroLineNumbers Bool)
  (:f pureDyck1Only Bool)
  (:f antiVacuity Bool)
  (:f readOnlyProposals Bool))

fn makeShardDescriptor id: Str name: Str paths: (List Str) intent: Str attractor: Str model: Str temp: F64 sev: Str focus: Str -> ShardDescriptor
  (ShardDescriptor
    :id id
    :name name
    :paths paths
    :intent intent
    :attractor attractor
    :model model
    :temp temp
    :suggestedSeverity sev
    :focus focus)

fn makeStaticGateDescriptor id: Str cmd: Str evalExpr: Str doc: Str -> StaticGateDescriptor
  (StaticGateDescriptor
    :id id
    :cmd cmd
    :evalExpr evalExpr
    :doc doc)

fn makeEventHookDescriptor event: Str action: Str doc: Str -> EventHookDescriptor
  (EventHookDescriptor
    :event event
    :action action
    :doc doc)

fn makeMeshConfigDescriptor ver: Str auth: Str shards: (List ShardDescriptor) gates: (List StaticGateDescriptor) hooks: (List EventHookDescriptor) thermo: (List ThermodynamicsDescriptor) -> MeshConfigDescriptor
  (MeshConfigDescriptor
    :version ver
    :authority auth
    :shards shards
    :staticPipeline gates
    :hooks hooks
    :thermodynamics thermo)

fn validateShardDescriptor shard: ShardDescriptor -> Bool
  (and (not (stringEmpty? shard.id))
  (and (not (listEmpty? shard.paths))
  (and (>= shard.temp 0.0)
  (and (<= shard.temp 1.0)
  (not (stringEmpty? shard.intent))))))

fn validateStaticGateDescriptor gate: StaticGateDescriptor -> Bool
  (and (not (stringEmpty? gate.id))
  (or (not (stringEmpty? gate.cmd))
      (not (stringEmpty? gate.evalExpr))))

fn makeDefectCategoryDescriptor id: Str sev: Str doc: Str -> DefectCategoryDescriptor
  (DefectCategoryDescriptor
    :id id
    :severity sev
    :doc doc)

fn makeSafetyPolicyDescriptor zeroLines: Bool pureDyck1: Bool antiVacuity: Bool readOnly: Bool -> SafetyPolicyDescriptor
  (SafetyPolicyDescriptor
    :zeroLineNumbers zeroLines
    :pureDyck1Only pureDyck1
    :antiVacuity antiVacuity
    :readOnlyProposals readOnly)

fn validateEventHookDescriptor hook: EventHookDescriptor -> Bool
  (and (not (stringEmpty? hook.event))
       (not (stringEmpty? hook.action)))

fn validateDefectCategoryDescriptor cat: DefectCategoryDescriptor -> Bool
  (and (not (stringEmpty? cat.id))
       (not (stringEmpty? cat.severity)))

fn validateSafetyPolicyDescriptor pol: SafetyPolicyDescriptor -> Bool
  (and pol.zeroLineNumbers
       pol.pureDyck1Only)

fn isExecutionAllowed plane: Str cmd: Str -> Bool
  (if (= plane "worker")
    (not (or (= cmd "start") (= cmd "stop")))
    true)
