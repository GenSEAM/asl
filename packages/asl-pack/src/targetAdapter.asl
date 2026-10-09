(module aslPack/targetAdapter
  :x [TargetProjection TargetAdapter TargetAdapterPlan TargetBuildBridge validateTargetAdapterContract emitTargetAdapterPlan projectionToBuildTarget]
  :i [])

(schema TargetProjection
  (:f id Str)
  (:f backend Str)
  (:f outputArtifact Str)
  (:f options (List Str)))

(schema TargetAdapter
  (:f package Str)
  (:f authority Str)
  (:f substrate Str)
  (:f projections (List TargetProjection)))

(schema TargetAdapterPlan
  (:f targetId Str)
  (:f backend Str)
  (:f output Str)
  (:f ready Bool))

(schema TargetBuildBridge
  (:f name Str)
  (:f backend Str)
  (:f targetTriple Str)
  (:f optLevel Str)
  (:f outputArtifact Str))

fn isSupportedBackend b: Str -> Bool
  (or (= b "llvm")
      (or (= b "wat")
          (or (= b "wasm")
              (= b "native"))))

fn validateProjection proj: TargetProjection -> Bool
  (and (not (stringEmpty? proj.id))
       (and (isSupportedBackend proj.backend)
            (not (stringEmpty? proj.outputArtifact))))

fn validateTargetAdapterContract adapter: TargetAdapter -> Bool
  (if (not (= adapter.substrate "pure-asl"))
    false
    (let [(projs adapter.projections)]
      (if (listEmpty? projs)
        false
        (fold
          (fn [(validSoFar Bool) (p TargetProjection)] -> Bool
            (if (not validSoFar)
              false
              (validateProjection p)))
          true
          projs))))

fn findProjectionById projs: (List TargetProjection) targetId: Str -> (Option TargetProjection)
  (fold
    (fn [(found (Option TargetProjection)) (p TargetProjection)] -> (Option TargetProjection)
      (if (some? found)
        found
        (if (= p.id targetId)
          (some p)
          none)))
    none
    projs)

fn emitTargetAdapterPlan adapter: TargetAdapter targetId: Str -> TargetAdapterPlan
  (let [(projOpt (findProjectionById adapter.projections targetId))]
    (if (some? projOpt)
      (let [(proj (optionOr projOpt (TargetProjection :id "" :backend "" :outputArtifact "" :options (list))))]
        (TargetAdapterPlan
          :targetId targetId
          :backend proj.backend
          :output proj.outputArtifact
          :ready (validateTargetAdapterContract adapter)))
      (TargetAdapterPlan
        :targetId targetId
        :backend "unknown"
        :output ""
        :ready false)))

fn extractOptLevel opts: (List Str) defaultLevel: Str -> Str
  (fold
    (fn [(acc Str) (opt Str)] -> Str
      (if (stringStartsWith? opt "-O")
        (optionOr (stringSlice opt 1 (stringLength opt)) defaultLevel)
        acc))
    defaultLevel
    opts)

fn projectionToBuildTarget proj: TargetProjection triple: Str -> TargetBuildBridge
  (let [(optLvl (extractOptLevel proj.options "O2"))]
    (TargetBuildBridge
      :name proj.id
      :backend proj.backend
      :targetTriple triple
      :optLevel optLvl
      :outputArtifact proj.outputArtifact))
