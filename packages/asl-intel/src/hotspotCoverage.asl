(module aslIntel/hotspotCoverage
  :x [HotspotTarget
      PlannedTraversal
      ActualVisit
      ActualCoverage
      CoverageGap
      CoverageComparison
      createHotspotTarget
      createPlannedTraversal
      planAddTarget
      planTargetCount
      recordVisit
      createActualCoverage
      coverageAddVisit
      coverageVisitCount
      isTargetVisited?
      findGaps
      calculateDrift
      compareTraversalPaths
      formatCoverageReport
      renderTraversalGraph]
  :i [])

(schema HotspotTarget
  (:f id Str)
  (:f file Str)
  (:f symbol Str)
  (:f fanIn I64)
  (:f priority I64)
  (:f rationale Str)
  (:f plannedDepth I64))

(schema PlannedTraversal
  (:f planId Str)
  (:f title Str)
  (:f targets (List HotspotTarget))
  (:f totalBudget I64))

(schema ActualVisit
  (:f targetId Str)
  (:f file Str)
  (:f actualDepth I64)
  (:f status Str)
  (:f findingsCount I64)
  (:f tokensSpent I64))

(schema ActualCoverage
  (:f runId Str)
  (:f sessionId Str)
  (:f visits (List ActualVisit))
  (:f totalTokens I64))

(schema CoverageGap
  (:f targetId Str)
  (:f file Str)
  (:f expectedDepth I64)
  (:f severity Str)
  (:f reason Str))

(schema CoverageComparison
  (:f planId Str)
  (:f totalPlanned I64)
  (:f totalVisited I64)
  (:f coveredCount I64)
  (:f gapCount I64)
  (:f driftCount I64)
  (:f coveragePct I64)
  (:f gaps (List CoverageGap))
  (:f isComplete Bool))

"Constructs a planned HotspotTarget record."
fn createHotspotTarget id: Str file: Str symbol: Str fanIn: I64 priority: I64 rationale: Str depth: I64 -> HotspotTarget
  (HotspotTarget
    :id id
    :file file
    :symbol symbol
    :fanIn fanIn
    :priority priority
    :rationale rationale
    :plannedDepth depth)

"Initializes an empty PlannedTraversal record."
fn createPlannedTraversal id: Str title: Str budget: I64 -> PlannedTraversal
  (PlannedTraversal
    :planId id
    :title title
    :targets (list)
    :totalBudget budget)

"Appends a target to the PlannedTraversal."
fn planAddTarget plan: PlannedTraversal target: HotspotTarget -> PlannedTraversal
  (with plan :targets (listAppend plan.targets (list target)))

"Returns count of planned hotspot targets."
fn planTargetCount plan: PlannedTraversal -> I64
  (listLength plan.targets)

"Constructs an ActualVisit record."
fn recordVisit targetId: Str file: Str depth: I64 status: Str findings: I64 tokens: I64 -> ActualVisit
  (ActualVisit
    :targetId targetId
    :file file
    :actualDepth depth
    :status status
    :findingsCount findings
    :tokensSpent tokens)

"Initializes an empty ActualCoverage tracking ledger."
fn createActualCoverage runId: Str sessionId: Str -> ActualCoverage
  (ActualCoverage
    :runId runId
    :sessionId sessionId
    :visits (list)
    :totalTokens 0)

"Appends a visit to ActualCoverage."
fn coverageAddVisit cov: ActualCoverage visit: ActualVisit -> ActualCoverage
  (with cov :visits (listAppend cov.visits (list visit)) :totalTokens (+ cov.totalTokens visit.tokensSpent))

"Returns count of recorded inspection visits."
fn coverageVisitCount cov: ActualCoverage -> I64
  (listLength cov.visits)

"Checks if a target has been visited."
fn isTargetVisited? targetId: Str visits: (List ActualVisit) -> Bool
  (fold (fn [(found Bool) (v ActualVisit)] -> Bool
          (if found true (= v.targetId targetId)))
        false
        visits)

"Returns achieved depth for a visited target, or -1 if unvisited."
fn findVisitDepth targetId: Str visits: (List ActualVisit) -> I64
  (fold (fn [(d I64) (v ActualVisit)] -> I64
          (if (>= d 0) d (if (= v.targetId targetId) v.actualDepth -1)))
        -1
        visits)

"Identifies missing or depth-degraded hotspots by comparing planned targets against visits."
fn findGaps targets: (List HotspotTarget) visits: (List ActualVisit) -> (List CoverageGap)
  (fold (fn [(gaps (List CoverageGap)) (t HotspotTarget)] -> (List CoverageGap)
          (let [(tid t.id)
                (actualD (findVisitDepth tid visits))]
            (cond
              ((< actualD 0)
               (let [(gap (CoverageGap
                            :targetId tid
                            :file t.file
                            :expectedDepth t.plannedDepth
                            :severity (if (<= t.priority 2) "critical" "warning")
                            :reason "unvisited"))]
                 (listAppend gaps (list gap))))
              ((< actualD t.plannedDepth)
               (let [(gap (CoverageGap
                            :targetId tid
                            :file t.file
                            :expectedDepth t.plannedDepth
                            :severity "warning"
                            :reason "depth-incongruity"))]
                 (listAppend gaps (list gap))))
              (true gaps))))
        (list)
        targets)

"Checks if visited target was declared in plan."
fn isTargetInPlan? tid: Str targets: (List HotspotTarget) -> Bool
  (fold (fn [(inPlan Bool) (t HotspotTarget)] -> Bool
          (if inPlan true (= t.id tid)))
        false
        targets)

"Counts visits to targets not declared in original traversal plan."
fn calculateDrift visits: (List ActualVisit) targets: (List HotspotTarget) -> I64
  (fold (fn [(acc I64) (v ActualVisit)] -> I64
          (if (isTargetInPlan? v.targetId targets) acc (+ acc 1)))
        0
        visits)

"Counts planned targets that were visited with sufficient depth."
fn countCovered targets: (List HotspotTarget) visits: (List ActualVisit) -> I64
  (fold (fn [(acc I64) (t HotspotTarget)] -> I64
          (let [(d (findVisitDepth t.id visits))]
            (if (>= d t.plannedDepth) (+ acc 1) acc)))
        0
        targets)

"Compares planned traversal DAG against actual coverage."
fn compareTraversalPaths plan: PlannedTraversal actual: ActualCoverage -> CoverageComparison
  (let [(targets plan.targets)
        (visits actual.visits)
        (totPlan (listLength targets))
        (totVis (listLength visits))
        (gaps (findGaps targets visits))
        (gapCnt (listLength gaps))
        (covCnt (countCovered targets visits))
        (drift (calculateDrift visits targets))
        (pct (if (> totPlan 0) (/ (* covCnt 100) totPlan) 100))]
    (CoverageComparison
      :planId plan.planId
      :totalPlanned totPlan
      :totalVisited totVis
      :coveredCount covCnt
      :gapCount gapCnt
      :driftCount drift
      :coveragePct pct
      :gaps gaps
      :isComplete (= gapCnt 0)))

"Formats a single CoverageGap S-expression item."
fn formatGapItem g: CoverageGap -> Str
  (str "(:gap :target " g.targetId " :file " g.file " :severity " g.severity " :reason " g.reason ")")

"Formats a structured S-expression coverage report."
fn formatCoverageReport comp: CoverageComparison -> Str
  (let [(gapsStr (stringJoin (fold (fn [(acc (List Str)) (g CoverageGap)] -> (List Str)
                                       (listAppend acc (list (formatGapItem g))))
                                     (list)
                                     comp.gaps)
                               " "))]
    (str "(:coverage-report"
         " :plan-id " comp.planId
         " :planned " (stringFromInt64 comp.totalPlanned)
         " :visited " (stringFromInt64 comp.totalVisited)
         " :covered " (stringFromInt64 comp.coveredCount)
         " :gaps-count " (stringFromInt64 comp.gapCount)
         " :drift " (stringFromInt64 comp.driftCount)
         " :coverage-pct " (stringFromInt64 comp.coveragePct)
         " :is-complete " (if comp.isComplete "true" "false")
         " :gaps [ " gapsStr " ])"))

"Renders Adjacency DSL graph representation of planned versus actual traversal."
fn renderTraversalGraph plan: PlannedTraversal actual: ActualCoverage -> Str
  (let [(targets plan.targets)
        (visits actual.visits)
        (edges (fold (fn [(acc (List Str)) (t HotspotTarget)] -> (List Str)
                       (let [(tid t.id)
                             (isVis (isTargetVisited? tid visits))
                             (status (if isVis "covered" "gap"))]
                         (listAppend acc (list (str tid ":" status)))))
                     (list)
                     targets))
        (edgesStr (stringJoin edges " "))]
    (str "(:traversal-graph (" plan.planId " > " edgesStr "))"))
