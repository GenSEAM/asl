(module asl-lens :x [LensConfig SteeringDirectives LensResult CanonicalLens D102Horizon SubagentDispatchFrame makeLensConfig makeD102Horizon generateSteeringDirectives formatOnboardingMessage runLensDiagnostics makeCanonicalLens canonicalLensIds allCanonicalLenses findLensById discoverLensesForText formatLevel1Probe formatLevel2Probe formatSubagentDispatchFrame tier1EssentialMetaLensIds availableDomainPacks domainPackLensIds composeLensesWithPack] :i [])

(schema LensConfig (:f targetAgent Str) (:f maxViewLines I64) (:f enforceAslIntel Bool))

(schema D102Horizon (:f confidence F64) (:f mvpHorizon Str) (:f staleWhen Str))

(schema SteeringDirectives (:f agent Str) (:f negativeConstraints Str) (:f steeringRules Str))

(schema LensResult (:f success Bool) (:f directives SteeringDirectives) (:f onboardingNotice Str))

(schema CanonicalLens (:f id Str) (:f name Str) (:f role Str) (:f focus Str) (:f attractor Str) (:f keywords (List Str)) (:f level1Probe Str) (:f level2Drilldown Str))

(schema SubagentDispatchFrame (:f lensId Str) (:f role Str) (:f focus Str) (:f systemAttractor Str) (:f initialPrompt Str))

fn makeLensConfig agent: Str maxLines: I64 enforce: Bool -> LensConfig
  (LensConfig :targetAgent agent :maxViewLines maxLines :enforceAslIntel enforce)

fn makeD102Horizon conf: F64 mvp: Str stale: Str -> D102Horizon
  (D102Horizon :confidence conf :mvpHorizon mvp :staleWhen stale)

fn generateSteeringDirectives cfg: LensConfig -> SteeringDirectives
  (let [(agent cfg.targetAgent)
        (neg (str "# Preservation Boundaries (" agent ")\n"
                  "- Context Economy: Avoid whole-file reads over 50 lines; slice by symbol anchor.\n"
                  "- Dependency Impact: Verify caller blast radius before mutating module contracts.\n"
                  "- Rationale Decay (:staleWhen): Re-evaluate assumptions when dependent evidence shifts.\n"))
        (steer (str "# Cognitive Attractor Field (D102)\n"
                    "- Structural Intelligence: Prefer 'asl intel outline <file>' for sub-15ms symbol resolution.\n"
                    "- Token Economy: Prefer compact ASN format for single-roundtrip batch execution.\n"
                    "- Calibrated Doubt (:confidence): Pair recommendations with falsifiable evidence.\n"
                    "- MVP Horizon (:mvpHorizon): Deliver minimal viable increments without speculative bloat.\n"))]
    (SteeringDirectives :agent agent :negativeConstraints neg :steeringRules steer))

fn formatOnboardingMessage -> Str
  (str "[genseam/lens] ERROR: AgentScript (asl) runtime is required but not found on PATH.\n"
       "To install AgentScript instantly, run:\n\n"
       "  curl -fsSL https://aslang.dev/install.sh | bash\n\n"
       "For documentation, visit https://aslang.dev\n")

fn runLensDiagnostics agent: Str -> LensResult
  (let [(cfg (makeLensConfig agent 50 true))
        (dirs (generateSteeringDirectives cfg))
        (onboard (formatOnboardingMessage))]
    (LensResult :success true :directives dirs :onboardingNotice onboard))

fn makeCanonicalLens id: Str name: Str role: Str attractor: Str keywords: (List Str) l1: Str l2: Str -> CanonicalLens
  (CanonicalLens :id id :name name :role role :focus role :attractor attractor :keywords keywords :level1Probe l1 :level2Drilldown l2)

fn canonicalLensIds -> (List Str)
  (list "falsification" "invariants" "concurrency" "security" "token-economics" "architecture" "non-vacuity" "optimization" "resilience" "api-ergonomics" "minimal-surface" "consistency" "coupling")

fn allCanonicalLenses -> (List CanonicalLens)
  (list
    (makeCanonicalLens
      "falsification"
      "Popperian Falsification"
      "Falsification Verifier"
      "Three-point red-green causality, assertion inversion, fault detection, kill production mutants."
      (list "gate" "test" "assert" "refute" "fail" "baseline" "mutant" "falsif")
      "Does the change declare baseline-failing gates that fail before and pass after?"
      "Invert assertions and inject production mutations: does at least one mutant get killed?")

    (makeCanonicalLens
      "invariants"
      "Monorepo Invariants"
      "Invariant & Boundary Guardian"
      "Teleological hierarchy (V0-V6), C1-C5 boundaries, zero-remote, Dyck-1 purity."
      (list "invariant" "remote" "teleology" "dyck" "balance" "boundary" "comment")
      "Are all expressions Dyck-1 balanced with zero remote git references and zero production comments?"
      "Audit AST boundaries, C1-C5 preservation, and verify lexicographic value dominance (V0 > V1 > V2).")

    (makeCanonicalLens
      "concurrency"
      "Concurrency & State Machine"
      "Concurrency & State Analyst"
      "Race conditions, channel deadlocks, lock ordering, atomic VFS transactions."
      (list "async" "channel" "lock" "mutex" "thread" "race" "deadlock" "concur" "atomic")
      "Are shared state modifications protected against race conditions and deadlocks?"
      "Trace async execution interleavings and verify atomic RAM VFS staging transaction closure.")

    (makeCanonicalLens
      "security"
      "Security & Containment"
      "Security & Sandbox Auditor"
      "Sandbox containment, input sanitization, injection defense, path traversal prevention."
      (list "security" "sandbox" "inject" "escape" "sanitiz" "path" "travers" "vulnerab")
      "Does the code sanitize inputs and prevent path traversal or shell injection?"
      "Verify permission tier enforcement and ensure operations stay within declared sandboxes.")

    (makeCanonicalLens
      "token-economics"
      "Token Economics & Attention"
      "Token Economics Optimizer"
      "Attention density, KV cache preservation, BPE CamelCase efficiency, observation masking."
      (list "token" "context" "cache" "compress" "mask" "budget" "density" "compact")
      "Are identifiers and messages optimized for BPE token density without verbose noise?"
      "Measure attention dilution, enforce observation masking, and verify KV-cache prefix stability.")

    (makeCanonicalLens
      "architecture"
      "Architecture & Stratification"
      "Architecture Reviewer"
      "Minimal causal surface, L0-L3 stratification, modular cohesion, circular dependency eradication."
      (list "arch" "strat" "layer" "cohes" "decoupl" "depend" "module" "boundar")
      "Does the module respect architectural boundaries and avoid leaking implementation details?"
      "Audit causal surfaces, check L0-L3 stratification compliance, and refute circular couplings.")

    (makeCanonicalLens
      "non-vacuity"
      "Non-Vacuity Verification"
      "Non-Vacuity Auditor"
      "Mock eradication, vacuous green pass fraud, non-asserting tests, genuine dynamic roundtripping."
      (list "mock" "stub" "vacuous" "fake" "synthetic" "assert(true)" "non-vacuity")
      "Are tests executing real assertions rather than returning synthetic passes or vacuous trues?"
      "Audit assertion execution counts (assertCount > 0), eradicate stubs, and prove round-trip fidelity.")

    (makeCanonicalLens
      "optimization"
      "Algorithmic Optimization"
      "Optimization Engineer"
      "Algorithmic complexity, hot loop allocations, redundant AST traversals, memory footprint."
      (list "perf" "optimiz" "alloc" "hot" "slow" "speed" "latenc" "mem" "complex")
      "Are there obvious performance bottlenecks or unnecessary allocations in hot paths?"
      "Profile algorithmic complexity, measure execution latencies, and minimize memory footprint.")

    (makeCanonicalLens
      "resilience"
      "Resilience & Fault Tolerance"
      "Resilience Supervisor"
      "Dynamic witness circuit breakers, limit cycle phase transitions, graceful degradation, fallback paths."
      (list "resilien" "fault" "recover" "circuit" "breaker" "fallback" "retry" "limit")
      "Are failures handled with explicit recovery paths and circuit breakers?"
      "Test error injection, verify limit cycle trip count (<= 3), and confirm graceful basin transition.")

    (makeCanonicalLens
      "api-ergonomics"
      "API Ergonomics & Contracts"
      "API Ergonomics Reviewer"
      "Zero integer line numbers, ASN receipts, typed contracts, intuitive composition."
      (list "api" "ergonom" "receipt" "contract" "interfac" "anchor" "symbol" "line-number")
      "Does the API use symbol anchors and typed ASN receipts instead of brittle line numbers?"
      "Verify end-to-end composability, typed return contracts, and zero line number invariance.")

    (makeCanonicalLens
      "minimal-surface"
      "Minimal Surface & Occam's Razor"
      "Causal Minimality Auditor"
      "Occam's razor, minimal diff, eliminate speculative bloat, high signal-to-noise ratio."
      (list "minimal" "surface" "diff" "bloat" "speculative" "occam" "snr" "noise")
      "Does the change introduce speculative abstractions or diff bloat beyond intent?"
      "Prove that every hunk is causally necessary for intent satisfaction and prune ungrounded diffs.")

    (makeCanonicalLens
      "consistency"
      "Tri-Map Consistency & Non-Contradiction"
      "Tri-Map Reconciliation Verifier"
      "Popperian Tri-Map closed bijection, non-contradiction, semantic harmony across layers."
      (list "consistency" "trimap" "bijective" "contradict" "harmony" "closure")
      "Are intent atoms, gates, and diff hunks in closed one-to-one correspondence?"
      "Audit cross-layer contracts and verify zero omissions or ungrounded claims.")

    (makeCanonicalLens
      "coupling"
      "Coupling & Structural Boundary"
      "Coupling & Boundary Auditor"
      "Intra-package cohesion, inter-package fan-in/fan-out, boundary leaks, cycle eradication, module fictions."
      (list "coupling" "fan-in" "fan-out" "instability" "boundary" "fiction" "stub" "orphan" "cycle" "cohesion")
      "Does the change increase inter-package fan-out or introduce undeclared cross-package dependencies or ghost modules?"
      "Trace the afferent/efferent coupling delta, verify boundary containment inside :owns, and refute vacuous module stubs."))

fn canonicalizeLensId id: Str -> Str
  (if (or (= id "token-economics") (= id "attention-density")) "token-economics"
    (if (or (= id "api-ergonomics") (= id "contract-precision")) "api-ergonomics"
      id))

fn findLensById id: Str -> (Option CanonicalLens)
  (let [(canonId (canonicalizeLensId id))]
    (fold (fn [(acc (Option CanonicalLens)) (l CanonicalLens)] -> (Option CanonicalLens)
            (mt acc
              ((some found) (some found))
              ((none) (if (or (= l.id id) (= l.id canonId)) (some l) (none)))))
          (none)
          (allCanonicalLenses)))

fn anyKeywordMatch text: Str kws: (List Str) -> Bool
  (fold (fn [(acc Bool) (kw Str)] -> Bool
          (if acc true (stringContains? text kw)))
        false
        kws)

fn discoverLensesForText text: Str -> (List Str)
  (let [(matched (fold (fn [(acc (List Str)) (l CanonicalLens)] -> (List Str)
                         (if (anyKeywordMatch text l.keywords)
                           (listAppend acc (list l.id))
                           acc))
                       (list)
                       (allCanonicalLenses)))]
    (if (> (listLength matched) 0)
      matched
      (list "falsification" "invariants")))

fn formatLevel1Probe lensId: Str target: Str -> Str
  (let [(lensOpt (findLensById lensId))]
    (mt lensOpt
      ((some l) (str "(:level-1-probe :lens \"" lensId "\" :target \"" target "\" :question \"" l.level1Probe "\")"))
      ((none) (str "(:level-1-probe :lens \"" lensId "\" :target \"" target "\" :question \"Audit target under " lensId " criteria.\")"))))

fn formatLevel2Probe lensId: Str target: Str observations: Str -> Str
  (let [(lensOpt (findLensById lensId))]
    (mt lensOpt
      ((some l) (str "(:level-2-drilldown :lens \"" lensId "\" :target \"" target "\" :observations \"" observations "\" :drilldown \"" l.level2Drilldown "\")"))
      ((none) (str "(:level-2-drilldown :lens \"" lensId "\" :target \"" target "\" :observations \"" observations "\" :drilldown \"Drill down into " lensId " anomalies.\")"))))

fn formatSubagentDispatchFrame lensId: Str target: Str -> SubagentDispatchFrame
  (let [(lensOpt (findLensById lensId))]
    (mt lensOpt
      ((some l)
        (let [(role l.role)
              (focus l.focus)
              (attractor (str "Role: " role "\n"
                              "Focus: " focus "\n"
                              "Attractor: " l.attractor "\n"
                              "Level 1 Probe: " l.level1Probe "\n"
                              "Level 2 Drilldown: " l.level2Drilldown))
              (prompt (str "Perform a focused " l.id " audit on target: " target ".\n"
                           "Mandate: Execute Level 1 probe first: " l.level1Probe "\n"
                           "If anomalies or potential defects are detected, execute Level 2 drilldown: " l.level2Drilldown "\n"
                           "Emit findings as a typed ASN receipt with verified evidence and refutations."))]
          (SubagentDispatchFrame :lensId lensId :role role :focus focus :systemAttractor attractor :initialPrompt prompt)))
      ((none)
        (SubagentDispatchFrame :lensId lensId :role "Auditor" :focus "Auditor" :systemAttractor (str "Focus on " lensId) :initialPrompt (str "Audit " target " under " lensId)))))

fn tier1EssentialMetaLensIds -> (List Str)
  (list "falsification" "invariants" "non-vacuity" "minimal-surface" "consistency")

fn availableDomainPacks -> (List Str)
  (list "coding" "editorial" "design" "mesh")

fn domainPackLensIds packName: Str -> (List Str)
  (if (= packName "coding")
    (list "concurrency" "security" "token-economics" "optimization" "api-ergonomics")
    (if (= packName "editorial")
      (list "factuality" "voice-and-tone" "narrative-arc" "anti-ai-cliche")
      (if (= packName "design")
        (list "vdom-density" "layout-boundaries" "typography-scale")
        (if (= packName "mesh")
          (list "governance" "attractor-alignment" "shard-partitioning")
          (list)))))

fn composeLensesWithPack packName: Str -> (List Str)
  (let [(essentials (tier1EssentialMetaLensIds))
        (packLenses (domainPackLensIds packName))]
    (listAppend essentials packLenses))
