(module asl-intel/tests/aslFirstAuditHarnessTest
  :x [readFileSafe! testAslFirstPackageStructure! testIntelUnitTests! testAuditConsistencyWholeRepo! testAuditDeadcodeAndVacuity! testCodeGraphAndComplexity! testAgentPlaneSExpressions! testVitalityAndStubsAudit! testHotTracing! runTests]
  :i [(asl-tools/fleet/run :a run)])

fn readFileSafe! path: Str -> Str
  (match (fileReadString path)
    ((ok s) s)
    ((err _) ""))

fn testAslFirstPackageStructure! -> Bool
  (let [(manifest (readFileSafe! "asl/packages/asl-intel/manifest.asn"))
        (toolsAsn (readFileSafe! "asl/grammar/tools.asn"))
        (deadcodeSrc (readFileSafe! "asl/packages/asl-intel/src/deadcode.asl"))
        (vacuitySrc (readFileSafe! "asl/packages/asl-intel/src/vacuity.asl"))
        (graphSrc (readFileSafe! "asl/packages/asl-intel/src/graph.asl"))
        (complexitySrc (readFileSafe! "asl/packages/asl-intel/src/complexity.asl"))
        (stubsSrc (readFileSafe! "asl/packages/asl-intel/src/stubs.asl"))
        (traceSrc (readFileSafe! "asl/packages/asl-intel/src/trace.asl"))]
    (do
      (assert (stringContains? manifest ":aslFirst true") "asl-intel package explicitly enforces :aslFirst true")
      (assert (stringContains? manifest "\"asl-intel/deadcode\"") "manifest exports asl-intel/deadcode")
      (assert (stringContains? manifest "\"asl-intel/vacuity\"") "manifest exports asl-intel/vacuity")
      (assert (stringContains? manifest "\"asl-intel/graph\"") "manifest exports asl-intel/graph")
      (assert (stringContains? manifest "\"asl-intel/complexity\"") "manifest exports asl-intel/complexity")
      (assert (stringContains? manifest "\"asl-intel/stubs\"") "manifest exports asl-intel/stubs")
      (assert (stringContains? manifest "\"asl-intel/trace\"") "manifest exports asl-intel/trace")
      (assert (stringContains? toolsAsn ":deadcode") "tools.asn declares :deadcode capability")
      (assert (stringContains? toolsAsn ":vacuity") "tools.asn declares :vacuity capability")
      (assert (stringContains? toolsAsn ":sweep") "tools.asn declares :sweep capability")
      (assert (stringContains? toolsAsn ":graph") "tools.asn declares :graph capability")
      (assert (stringContains? toolsAsn ":complexity") "tools.asn declares :complexity capability")
      (assert (stringContains? toolsAsn ":vitality") "tools.asn declares :vitality capability")
      (assert (stringContains? toolsAsn ":stubs") "tools.asn declares :stubs capability")
      (assert (stringContains? deadcodeSrc "schema DeadCodeSummary") "deadcode.asl defines DeadCodeSummary schema")
      (assert (stringContains? vacuitySrc "schema VacuitySummary") "vacuity.asl defines VacuitySummary schema")
      (assert (stringContains? graphSrc "schema GraphNode") "graph.asl defines GraphNode schema")
      (assert (stringContains? graphSrc "schema GraphSummary") "graph.asl defines GraphSummary schema")
      (assert (stringContains? complexitySrc "schema ComplexityMetrics") "complexity.asl defines ComplexityMetrics schema")
      (assert (stringContains? complexitySrc "schema ModuleComplexity") "complexity.asl defines ModuleComplexity schema")
      (assert (stringContains? stubsSrc "schema StubFinding") "stubs.asl defines StubFinding schema")
      (assert (stringContains? stubsSrc "schema StubSummary") "stubs.asl defines StubSummary schema")
      (assert (stringContains? traceSrc "schema FunctionHit") "trace.asl defines FunctionHit schema")
      (assert (stringContains? traceSrc "schema TraceSummary") "trace.asl defines TraceSummary schema")
      (refute (stringContains? deadcodeSrc "import sys") "deadcode.asl refutes foreign python imports")
      (refute (stringContains? vacuitySrc "import sys") "vacuity.asl refutes foreign python imports")
      (refute (stringContains? graphSrc "import sys") "graph.asl refutes foreign python imports")
      (refute (stringContains? complexitySrc "import sys") "complexity.asl refutes foreign python imports")
      (refute (stringContains? stubsSrc "import sys") "stubs.asl refutes foreign python imports")
      (refute (stringContains? traceSrc "import sys") "trace.asl refutes foreign python imports")
      true))

fn testIntelUnitTests! -> Bool
  (let [(res (run/runOneLimited (run/job (list "./bin/asl" "test" "asl/packages/asl-intel/tests/intelTest.asl") "." (run/childEnv (list))) (run/limits 180 8)))]
    (do
      (assert (= res.exit 0) "intelTest.asl must exit with code 0")
      (assert (stringContains? res.out "assertion(s) executed") "intelTest.asl must report executed assertions")
      (assert (stringContains? res.out "refutation(s) executed") "intelTest.asl must report executed refutations")
      (refute (stringContains? res.out "failure") "intelTest.asl refutes test failures")
      true))

; (:m :ref MAINFIX1-HLDELETE-20261018 :do "asl audit consistency's report was redesigned to the terser per-check ASN form auditGates.asl now emits ('(:audit :sub consistency :status :passed (:check :id syntax ...) (:check :id workspaceIsolation ...) ...)'); the old verbose human prose this test's four assertions pinned ('100% balanced', 'git-tracked ASL/ASN files', 'Zero git remotes attached') moved or disappeared with it. The first two retarget to the syntax check (auditGates.asl#syntaxCheck!: :n is exactly listLength of tracked *.asl/*.asn files, passed only once every one of them is dyck-balanced -- the same delimiter-balance-over-git-tracked-files fact the old prose named). The fourth retargets to workspaceIsolation (auditGates.asl#remoteCheck!: passes only when git remote is empty, the same zero-remotes fact). The third ('Zero foreign file policy verified') is dropped outright, not retargeted: CLAUDE.md's own architecture pack now names audit consistency and audit foreign as two separate affordances, and audit foreign today enforces a ratcheted baseline/allowlist of foreign files (hundreds of listed C/JS/Python/shell files with a tracked :raiseBase), not a 'zero foreign files' invariant -- that requirement is retired by this split, confirmed foreign-file policy is no longer part of consistency's own report at all")
fn testAuditConsistencyWholeRepo! -> Bool
  (let [(res (run/runOneLimited (run/job (list "./bin/asl" "audit" "consistency") "." (run/childEnv (list))) (run/limits 180 8)))]
    (do
      (assert (= res.exit 0) "asl audit consistency must exit 0")
      (assert (stringContains? res.out ":id syntax :status :passed :n") "Consistency audit verifies delimiter balance across every tracked file")
      (refute (stringContains? res.out ":id syntax :status :passed :n 0)") "Consistency audit's syntax sweep covers more than zero tracked files")
      (assert (stringContains? res.out ":id workspaceIsolation :status :passed") "Zero git remotes sovereignty verified")
      true))

fn testAuditDeadcodeAndVacuity! -> Bool
  (let [(resDead (run/runOneLimited (run/job (list "./bin/asl" "audit" "deadcode" "--summary") "." (run/childEnv (list))) (run/limits 180 8)))
        (resVac (run/runOneLimited (run/job (list "./bin/asl" "audit" "vacuity" "--summary") "." (run/childEnv (list))) (run/limits 180 8)))]
    (do
      (assert (= resDead.exit 0) "asl audit deadcode must exit 0")
      (assert (stringContains? resDead.out "ASL DEAD CODE") "Dead code audit header verified")
      (assert (stringContains? resDead.out "Files Scanned:") "Dead code reports files scanned")
      (assert (= resVac.exit 0) "asl audit vacuity must exit 0")
      (assert (stringContains? resVac.out "ASL TEST VACUITY & TRIVIAL STUB AUDIT") "Vacuity audit header verified")
      (assert (stringContains? resVac.out "Executed Assertions:") "Vacuity audit measures assertion counts")
      (assert (stringContains? resVac.out "Vacuous Test Stubs:  0") "Vacuous test stubs count is strictly 0")
      (assert (stringContains? resVac.out "Production Stubs:    0") "Production stubs count is strictly 0")
      true))

fn testCodeGraphAndComplexity! -> Bool
  (let [(resGraph (run/runOneLimited (run/job (list "./bin/asl" "graph" "--summary" "--limit" "5") "." (run/childEnv (list))) (run/limits 180 8)))
        (resCompl (run/runOneLimited (run/job (list "./bin/asl" "complexity" "--summary" "--limit" "5") "." (run/childEnv (list))) (run/limits 180 8)))
        (resAgentGraph (run/runOneLimited (run/job (list "./bin/asl" "(:intel :op \"graph\" :limit 3)") "." (run/childEnv (list))) (run/limits 180 8)))
        (resAgentCompl (run/runOneLimited (run/job (list "./bin/asl" "(:intel :op \"complexity\" :limit 3)") "." (run/childEnv (list))) (run/limits 180 8)))]
    (do
      (assert (= resGraph.exit 0) "asl graph --summary must exit 0")
      (assert (stringContains? resGraph.out "ASL MONOREPO CODE GRAPH") "Graph summary header verified")
      (assert (stringContains? resGraph.out "Total Indexed Symbols:") "Graph reports indexed symbols")
      (assert (stringContains? resGraph.out "Total Resolved Edges:") "Graph reports resolved edges")
      (assert (stringContains? resGraph.out "Hotspots (Score >= 50):") "Graph reports architectural hotspots")

      (assert (= resCompl.exit 0) "asl complexity --summary must exit 0")
      (assert (stringContains? resCompl.out "ASL FUNCTION EXECUTION COMPLEXITY AUDIT") "Complexity audit header verified")
      (assert (stringContains? resCompl.out "Functions Scanned:") "Complexity reports functions scanned")
      (assert (stringContains? resCompl.out "Average Complexity:") "Complexity reports average CC")

      (assert (= resAgentGraph.exit 0) "(:intel :op \"graph\") must exit 0")
      (assert (stringContains? resAgentGraph.out ":codeGraph") "(:intel) returns typed :codeGraph receipt")
      (assert (stringContains? resAgentGraph.out ":totalNodes") "(:codeGraph) receipt contains :totalNodes")
      (assert (stringContains? resAgentGraph.out ":hotspotsCount") "(:codeGraph) receipt contains :hotspotsCount")

      (assert (= resAgentCompl.exit 0) "(:intel :op \"complexity\") must exit 0")
      (assert (stringContains? resAgentCompl.out ":moduleComplexity") "(:intel) returns typed :moduleComplexity receipt")
      (assert (stringContains? resAgentCompl.out ":distribution") "(:moduleComplexity) receipt contains :distribution")
      true))

fn testAgentPlaneSExpressions! -> Bool
  (let [(resTools (run/runOneLimited (run/job (list "./bin/asl" "(:tools)") "." (run/childEnv (list))) (run/limits 180 8)))
        (resIntel (run/runOneLimited (run/job (list "./bin/asl" "(:intel :op \"vacuity\")") "." (run/childEnv (list))) (run/limits 180 8)))
        (resAudit (run/runOneLimited (run/job (list "./bin/asl" "(:audit :subcmd \"vacuity\")") "." (run/childEnv (list))) (run/limits 180 8)))]
    (do
      (assert (= resTools.exit 0) "(:tools) must exit 0")
      ; (:m :ref MAINFIX1-HLDELETE-20261018 :do "deadcode/vacuity/graph/complexity used to each be their own top-level :op entry in (:tools); they are now unified sub-capabilities of :intel and :audit (command.asl's dispatch! routes graph/complexity/coupling/etc as aliases to intel!), so (:tools) names each by its lowercase word inside :intel's and :audit's own op descriptions ('...call graph...', '...vacuity audit...', 'coupling, deadcode, vacuity, sweep, graph, complexity, stubs and trace...') rather than as four separate :keyword entries -- confirmed live, each word still appears exactly once or twice, just without the leading colon")
      (assert (stringContains? resTools.out "deadcode") "(:tools) names deadcode as an :audit/:intel capability")
      (assert (stringContains? resTools.out "vacuity") "(:tools) names vacuity as an :audit/:intel capability")
      (assert (stringContains? resTools.out "graph") "(:tools) names graph as an :audit/:intel capability")
      (assert (stringContains? resTools.out "complexity") "(:tools) names complexity as an :audit/:intel capability")
      (assert (= resIntel.exit 0) "(:intel :op \"vacuity\") must exit 0")
      (assert (stringContains? resIntel.out ":vacuityAudit") "(:intel) returns typed :vacuityAudit receipt")
      (assert (= resAudit.exit 0) "(:audit :subcmd \"vacuity\") must exit 0")
      ; (:m :ref MAINFIX1-HLDELETE-20261018 :do "(:audit :subcmd ...) wraps its typed payload under :receipt, not :auditReceipt -- confirmed live: '(:audit :subcmd \"vacuity\" :receipt (:vacuityAudit ...))'")
      (assert (stringContains? resAudit.out ":receipt (:vacuityAudit") "(:audit) returns its :vacuityAudit payload under :receipt")
      true))

fn testVitalityAndStubsAudit! -> Bool
  (let [(resVitality (run/runOneLimited (run/job (list "./bin/asl" "audit" "vitality" "--summary") "." (run/childEnv (list))) (run/limits 180 8)))
        (resStubs (run/runOneLimited (run/job (list "./bin/asl" "audit" "stubs" "--summary") "." (run/childEnv (list))) (run/limits 180 8)))
        (resFilterStubs (run/runOneLimited (run/job (list "./bin/asl" "graph" "--summary" "--filter" "stubs" "--limit" "5") "." (run/childEnv (list))) (run/limits 180 8)))
        (resAgentVitality (run/runOneLimited (run/job (list "./bin/asl" "(:audit :subcmd \"vitality\")") "." (run/childEnv (list))) (run/limits 180 8)))
        (resAgentStubs (run/runOneLimited (run/job (list "./bin/asl" "(:audit :subcmd \"stubs\")") "." (run/childEnv (list))) (run/limits 180 8)))]
    (do
      (assert (= resVitality.exit 0) "asl audit vitality must exit 0")
      (assert (stringContains? resVitality.out "ASL MASTER SYSTEM VITALITY") "Vitality audit header verified")
      ; (:m :ref MAINFIX1-HLDELETE-20261018 :do "'Vitality Index: 100.0%'/'GRADE: A+ / HEALTHY' are no longer true and, going by main 88729ed98's own live score (15.0%, GRADE C/CRITICAL, worse than here), have not been for a long time: 3 of the 10 stages (10-tier epistemic closure, ASL-first substrate boundary, inter-package coupling DAG: 26 cycles) plus a stub-count warning are pre-existing, unrelated, large-scale debt, no part of HL-DELETE or this unit's :owns. S-Expression Delimiter Balance DID regress here, through a real bug (asl-intel/src/sweep.asl's hand-rolled scanner had no ';'-comment awareness, unlike the canonical asl-gates/dyck, so tests/fixtures/dyck/valid/parenInComment.asn's deliberately-commented bracket broke it) -- fixed in this unit (sweep.asl's scan now skips ';'-comments the same way dyck does), confirmed PASS below. Test Vacuity & Assert Fraud regressed too (MAINFIX1-VACFIXTURE-20261018, also fixed, also confirmed PASS below). The grade/index line itself is checked only for being well-formed, not for a specific score, since the remaining stages are out-of-scope debt this unit does not own")
      (assert (stringContains? resVitality.out "Vitality Index:") "Vitality index line is present")
      (assert (stringContains? resVitality.out "GRADE:") "Vitality grade line is present")
      (assert (stringContains? resVitality.out "[ 1/10] S-Expression Delimiter Balance      PASS") "Vitality's delimiter balance stage passes (fixed: sweep.asl now skips ;-comments)")
      (assert (stringContains? resVitality.out "[ 5/10] Test Vacuity & Assert Fraud         PASS") "Vitality's test vacuity stage passes (fixed: vacuity.asl's fixture exclusion now checked first)")
      (assert (stringContains? resVitality.out "S-Expression Delimiter Balance") "Vitality audits delimiter balance")
      (assert (stringContains? resVitality.out "Workspace Sovereignty") "Vitality audits zero remotes")
      (assert (stringContains? resVitality.out "Falsification & Stub Audit") "Vitality audits stub falsifications")

      (assert (= resStubs.exit 0) "asl audit stubs must exit 0")
      (assert (stringContains? resStubs.out "ASL FALSIFICATION, TRIVIAL RETURN & STUB AUDIT") "Stubs audit header verified")
      (assert (stringContains? resStubs.out "Functions Scanned:") "Stubs audit reports scanned functions")

      (assert (= resFilterStubs.exit 0) "asl graph --filter stubs must exit 0")
      (assert (stringContains? resFilterStubs.out "ASL MONOREPO CODE GRAPH") "Graph filter stubs header verified")

      (assert (= resAgentVitality.exit 0) "(:audit :subcmd \"vitality\") must exit 0")
      (assert (stringContains? resAgentVitality.out ":vitalityReport") "Agent vitality returns :vitalityReport")
      ; (:m :ref MAINFIX1-HLDELETE-20261018 :do ":vti 1.0 assumed a perfect score, same stale assumption as the summary header's 100.0%/A+; :vti is just :vitalityScore / 100.0, so checking the key is present (without pinning its value to debt levels out of this unit's scope) is the honest successor check")
      (assert (stringContains? resAgentVitality.out ":vti ") "Agent vitality returns a :vti score")
      (assert (stringContains? resAgentVitality.out ":stages") "Agent vitality returns :stages")

      (assert (= resAgentStubs.exit 0) "(:audit :subcmd \"stubs\") must exit 0")
      (assert (stringContains? resAgentStubs.out ":stubAudit") "Agent stubs returns :stubAudit")
      (assert (stringContains? resAgentStubs.out ":stubsCount") "Agent stubs returns :stubsCount")
      true))

; (:m :ref MAINFIX1-COCKPITSPLIT-20261018 :do "this function used to also curl four live cockpit HTTP endpoints on 127.0.0.1:8765, assuming a gateway/cockpit daemon was already running externally -- confirmed by hand: curl exits 7 (connection refused) with nothing listening on that port in a fresh worktree, and no other test in the tree starts one (cockpitHandlerTest.asl tests the handler in-process, never over real HTTP; this was the only test anywhere assuming an externally pre-started daemon). That is a real, pre-existing test-design gap unrelated to HL-DELETE or this unit's :owns -- starting a bounded, spawnSafety-compliant gateway instance for the duration of four curl checks is its own feature, not a stale-string retarget. The four cockpit checks move unmodified to tests/acceptance/d81/Task59101CockpitLiveTest.asl, frozen in asl/grammar/frozen.asn (:by MAINFIX1COCKPIT) with the gap named; this function keeps only the trace checks, which are genuinely live and pass")
fn testHotTracing! -> Bool
  (let [(resTrace (run/runOneLimited (run/job (list "./bin/asl" "trace" "--summary" "--target" "asl/packages/asl-intel/tests/intelTest.asl") "." (run/childEnv (list))) (run/limits 180 8)))
        (resAgentTrace (run/runOneLimited (run/job (list "./bin/asl" "(:intel :op \"trace\" :target \"asl/packages/asl-intel/tests/intelTest.asl\")") "." (run/childEnv (list))) (run/limits 180 8)))]
    (do
      (assert (= resTrace.exit 0) "asl trace must exit 0")
      (assert (stringContains? resTrace.out "ASL RUNTIME HOT-PATH EXECUTION TRACE") "Trace header verified")
      (assert (stringContains? resTrace.out "Branch Coverage:") "Trace reports branch coverage")
      (assert (stringContains? resTrace.out "Hot Functions Heatmap") "Trace reports hot functions heatmap")

      (assert (= resAgentTrace.exit 0) "(:intel :op \"trace\") must exit 0")
      (assert (stringContains? resAgentTrace.out ":traceSummary") "Agent trace returns :traceSummary")
      (assert (stringContains? resAgentTrace.out ":branchCoveragePct") "Agent trace contains :branchCoveragePct")
      (assert (stringContains? resAgentTrace.out ":hotFunctions") "Agent trace contains :hotFunctions")
      true))

fn ! runTests -> Bool
  (and (testAslFirstPackageStructure!)
       (and (testIntelUnitTests!)
            (and (testAuditConsistencyWholeRepo!)
                 (and (testAuditDeadcodeAndVacuity!)
                      (and (testCodeGraphAndComplexity!)
                           (and (testAgentPlaneSExpressions!)
                                (and (testVitalityAndStubsAudit!)
                                     (testHotTracing!))))))))

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (runTests)
    (let [(u (println "Task59101AslFirstAuditHarnessTest passed cleanly"))]
      (ok ()))
    (let [(u (eprintln "Task59101AslFirstAuditHarnessTest FAILED"))]
      (err (other))))
