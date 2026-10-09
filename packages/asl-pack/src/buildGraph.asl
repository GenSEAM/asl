(module aslPack/buildGraph
  :x [BuildModule BuildTarget BuildPipelineStage BuildGraph BuildPlan DagValidation makeBuildGraph validateModuleDag computeTopologicalOrder computeCompilationWaves planTargetCompilation emitBuildReceipt]
  :i [])

(schema BuildModule
  (:f id Str)
  (:f directory Str)
  (:f moduleType Str)
  (:f entry Str)
  (:f sources (List Str))
  (:f deps (List Str))
  (:f capabilities (List Str))
  (:f doc Str))

(schema BuildTarget
  (:f id Str)
  (:f rootModule Str)
  (:f backend Str)
  (:f output Str)
  (:f triple Str)
  (:f optLevel Str)
  (:f postBuildGates (List Str))
  (:f doc Str))

(schema BuildPipelineStage
  (:f name Str)
  (:f doc Str))

(schema BuildGraph
  (:f version Str)
  (:f substrate Str)
  (:f defaultBackend Str)
  (:f modules (List BuildModule))
  (:f targets (List BuildTarget)))

(schema DagValidation
  (:f acyclic Bool)
  (:f cyclePath Str)
  (:f unresolvedDeps (List Str)))

(schema BuildPlan
  (:f targetId Str)
  (:f rootModule Str)
  (:f backend Str)
  (:f output Str)
  (:f triple Str)
  (:f optLevel Str)
  (:f stages (List Str))
  (:f topoOrder (List Str))
  (:f valid Bool))

fn makeBuildGraph version: Str substrate: Str defaultBackend: Str modules: (List BuildModule) targets: (List BuildTarget) -> BuildGraph
  (BuildGraph
    :version version
    :substrate substrate
    :defaultBackend defaultBackend
    :modules modules
    :targets targets)

fn findModuleById modules: (List BuildModule) id: Str -> (Option BuildModule)
  (fold
    (fn [(found (Option BuildModule)) (m BuildModule)] -> (Option BuildModule)
      (if (some? found)
        found
        (if (= m.id id)
          (some m)
          none)))
    none
    modules)

fn collectUnresolvedDeps modules: (List BuildModule) -> (List Str)
  (let [(declaredIds (map (fn [(m BuildModule)] -> Str m.id) modules))]
    (fold
      (fn [(acc (List Str)) (m BuildModule)] -> (List Str)
        (fold
          (fn [(inner (List Str)) (dep Str)] -> (List Str)
            (if (or (listContains? declaredIds dep) (listContains? inner dep))
              inner
              (listAppend inner (list dep))))
          acc
          m.deps))
      (list)
      modules))

fn detectCycleInDag modules: (List BuildModule) -> (Option Str)
  (fold
    (fn [(detected (Option Str)) (root BuildModule)] -> (Option Str)
      (if (some? detected)
        detected
        (detectCycleFromNode modules root.id (list))))
    none
    modules)

fn detectCycleFromNode modules: (List BuildModule) currentId: Str visitedTrail: (List Str) -> (Option Str)
  (if (listContains? visitedTrail currentId)
    (some (str "Cycle: " (stringJoin visitedTrail " -> ") " -> " currentId))
    (let [(mOpt (findModuleById modules currentId))]
      (if (none? mOpt)
        none
        (let [(m (optionOr mOpt (BuildModule :id "" :directory "" :moduleType "" :entry "" :sources (list) :deps (list) :capabilities (list) :doc "")))
              (newTrail (listAppend visitedTrail (list currentId)))]
          (fold
            (fn [(res (Option Str)) (dep Str)] -> (Option Str)
              (if (some? res)
                res
                (detectCycleFromNode modules dep newTrail)))
            none
            m.deps)))))

fn validateModuleDag graph: BuildGraph -> DagValidation
  (let [(mods graph.modules)
        (unresolved (collectUnresolvedDeps mods))
        (cycleOpt (detectCycleInDag mods))]
    (if (some? cycleOpt)
      (DagValidation :acyclic false :cyclePath (optionOr cycleOpt "") :unresolvedDeps unresolved)
      (DagValidation
        :acyclic (listEmpty? unresolved)
        :cyclePath ""
        :unresolvedDeps unresolved)))

fn computeTopologicalOrder graph: BuildGraph -> (List Str)
  (let [(mods graph.modules)
        (total (listLength mods))]
    (computeTopoLoop mods (list) total))

fn computeTopoLoop mods: (List BuildModule) resolved: (List Str) remainingSteps: I64 -> (List Str)
  (if (or (<= remainingSteps 0) (= (listLength resolved) (listLength mods)))
    resolved
    (let [(readyModules
            (fold
              (fn [(acc (List Str)) (m BuildModule)] -> (List Str)
                (let [(id m.id)]
                  (if (listContains? resolved id)
                    acc
                    (let [(depsReady
                            (fold
                              (fn [(ok Bool) (dep Str)] -> Bool
                                (if (not ok)
                                  false
                                  (listContains? resolved dep)))
                              true
                              m.deps))]
                      (if depsReady
                        (listAppend acc (list id))
                        acc)))))
              (list)
              mods))]
      (if (listEmpty? readyModules)
        resolved
        (let [(nextResolved (listAppend resolved readyModules))]
          (computeTopoLoop mods nextResolved (- remainingSteps 1))))))

fn computeCompilationWaves graph: BuildGraph -> (List (List Str))
  (let [(mods graph.modules)
        (total (listLength mods))]
    (computeWaveLoop mods (list) (list) total))

fn computeWaveLoop mods: (List BuildModule) waves: (List (List Str)) allResolved: (List Str) remainingSteps: I64 -> (List (List Str))
  (if (or (<= remainingSteps 0) (= (listLength allResolved) (listLength mods)))
    waves
    (let [(ready
            (fold
              (fn [(acc (List Str)) (m BuildModule)] -> (List Str)
                (let [(id m.id)]
                  (if (listContains? allResolved id)
                    acc
                    (let [(depsReady
                            (fold
                              (fn [(ok Bool) (dep Str)] -> Bool
                                (if (not ok)
                                  false
                                  (listContains? allResolved dep)))
                              true
                              m.deps))]
                      (if depsReady
                        (listAppend acc (list id))
                        acc)))))
              (list)
              mods))]
      (if (listEmpty? ready)
        waves
        (let [(nextWaves (listAppend waves (list ready)))
              (nextResolved (listAppend allResolved ready))]
          (computeWaveLoop mods nextWaves nextResolved (- remainingSteps 1))))))

fn planTargetCompilation graph: BuildGraph targetId: Str -> BuildPlan
  (let [(tOpt
          (fold
            (fn [(found (Option BuildTarget)) (t BuildTarget)] -> (Option BuildTarget)
              (if (some? found)
                found
                (if (= t.id targetId)
                  (some t)
                  none)))
            none
            graph.targets))]
    (if (none? tOpt)
      (BuildPlan
        :targetId targetId
        :rootModule ""
        :backend ""
        :output ""
        :triple ""
        :optLevel ""
        :stages (list)
        :topoOrder (list)
        :valid false)
      (let [(target (optionOr tOpt (BuildTarget :id "" :rootModule "" :backend "" :output "" :triple "" :optLevel "" :postBuildGates (list) :doc "")))
            (validation (validateModuleDag graph))]
        (if (not validation.acyclic)
          (BuildPlan
            :targetId targetId
            :rootModule target.rootModule
            :backend target.backend
            :output target.output
            :triple target.triple
            :optLevel target.optLevel
            :stages (list)
            :topoOrder (list)
            :valid false)
          (let [(stages (list "parse" "check" "anf" "optimize" "codegen" "assemble"))
                (topo (computeTopologicalOrder graph))]
            (BuildPlan
              :targetId targetId
              :rootModule target.rootModule
              :backend target.backend
              :output target.output
              :triple target.triple
              :optLevel target.optLevel
              :stages stages
              :topoOrder topo
              :valid true))))))

fn emitBuildReceipt plan: BuildPlan elapsedMs: I64 -> Str
  (str "(:buildReceipt"
       " :target \"" plan.targetId "\""
       " :backend \"" plan.backend "\""
       " :output \"" plan.output "\""
       " :status " (if plan.valid ":ok" ":failed")
       " :elapsedMs " (stringFromInt64 elapsedMs)
       " :stagesCount " (stringFromInt64 (listLength plan.stages))
       " :modulesCount " (stringFromInt64 (listLength plan.topoOrder))
       " :substrate \"pure-asl\")")
