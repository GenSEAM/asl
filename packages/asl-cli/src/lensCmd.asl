(module asl-cli/lensCmd
  :x [formatLensHelp formatLensList formatLensVersion formatLensInfo formatLensRules formatLensPayload lensTargetKind! lensTestResult runLensCommand]
  :i [])

fn formatLensHelp -> Str
  (str "asl-lens: Multi-Lens Discovery & Multi-Agent Popperian Audit Engine\n"
       "Usage: lens [command|option] [args...]\n\n"
       "Commands:\n"
       "  info, describe <lens>       Describe lens attractor, verification probes, and guidance\n"
       "  discover, search <target>   Search and rank relevant audit lenses for target (file, plan, or diff)\n"
       "  run <target> [options]      Execute multi-lens audit on target with active lenses\n"
       "  audit <target> [options]    End-to-end: auto-discover lenses and execute full audit\n"
       "  list                        List all registered lenses, invariants, and falsification probes\n\n"
       "S-Expression Usage:\n"
       "  Agents should prefer direct pure-ASN S-expressions:\n"
       "    (:lens :text \"<target>\")\n"
       "    (:lens :file \"<path>\" [:lenses (\"falsification\" \"invariants\")])\n\n"
       "Options:\n"
       "  --pack <name>               Select domain lens pack: coding, editorial, design, mesh\n"
       "  --lenses <list>             Comma-separated list of lens IDs (for 'run')\n"
       "  --strict                    Exit non-zero if consensus < 0.80 or defects found\n"
       "  --matrix                    Print full model x lens consensus evaluation matrix\n"
       "  --format <asn|json|text>    Output format (default: asn)\n"
       "  --output <path>             Write structured verdict to file\n"
       "  --setup, --rules            Output cognitive potential and steering rules (CLAUDE.md / .cursorrules)\n"
       "  --test                      Execute native ASL test suite\n"
       "  -v, --version               Print version information\n"
       "  -h, --help                  Show this help message\n\n"
       "Examples:\n"
       "  lens info falsification\n"
       "  lens discover asl/packages/asl-compiler/src/wasi.asl --pack coding\n"
       "  lens audit asl/packages/asl-compiler/src/wasi.asl --strict\n"
       "  lens run asl/packages/asl-compiler/src/wasi.asl --lenses invariants,falsification\n"
       "  lens list\n")

fn formatLensList -> Str
  (str "=== 13 CANONICAL INQUIRY LENSES ===\n"
       "  1. falsification      - Three-point red-green causality, assertion inversion, fault detection, kill mutants\n"
       "  2. invariants         - Teleological hierarchy (V0-V6), C1-C5 boundaries, workspace zero-remote isolation\n"
       "  3. concurrency        - Swarm leases, circular ring buffer epoch wrap, channel race hazards, deadlocks\n"
       "  4. security           - Monorepo sovereignty, sandbox permissions, path traversal containment inside :owns\n"
       "  5. attention-density  - Attention density, CamelCase BPE subword efficiency (-44% tax), bounded slices (alias: token-economics)\n"
       "  6. architecture       - Minimal causal surface, L0-L3 stratification, modular cohesion, zero integer lines\n"
       "  7. non-vacuity        - Mock eradication, vacuous green pass fraud, non-asserting tests, round-trip fidelity\n"
       "  8. optimization       - Algorithmic complexity bounds, minimal intermediate allocations, bounded memory\n"
       "  9. resilience         - Dynamic witness circuit breakers, limit cycles (max 3 retries), fallback paths\n"
       "  10. contract-precision - Zero integer line numbers, typed Option/Result contracts, subword-efficient naming (alias: api-ergonomics)\n"
       "  11. minimal-surface   - Occam's razor, minimal diff, eliminate speculative bloat, high signal-to-noise ratio\n"
       "  12. consistency       - Popperian Tri-Map closed bijection (S <-> F <-> B), cross-layer semantic harmony\n"
       "  13. coupling          - Intra-package cohesion, inter-package fan-in/fan-out, cycle eradication, module fictions\n")

fn formatLensVersion -> Str
  "asl-lens v2.1.0 (Multi-Lens Sovereign Audit Engine - 100% Pure AgentSlang)"

fn formatLensRules -> Str
  (str "# Cognitive Potential Landscape & Lens Steering Directives\n"
       "- Focus reads on symbol anchors and targeted slices (:limit 50) to preserve KV-cache attention density.\n"
       "- Verify dependency impact before mutating shared interfaces via symbol references.\n"
       "- Utilize 'asl intel outline <file>' to inspect module structure and signatures.\n"
       "- Utilize 'asl intel impact <symbol>' before modifying shared functions.\n"
       "- Prefer direct pure-ASN S-expressions e.g. (:query ...), (:read ...), (:edit ...) for dense tool execution.\n")

fn formatLensInfo lensId: Str -> (Result Str Str)
  (cond
    ((= lensId "falsification")
     (ok (str "Lens:             falsification\n"
              "Attractor Focus:  Three-point red-green causality, assertion inversion, fault detection, kill mutants\n"
              "Inquiry Probes:\n"
              "  • Does the baseline gate fail on revert or discard (gate(discard) = FAIL)?\n"
              "  • Does the gate pass after modification (gate(apply) = PASS)?\n"
              "  • Does mutation of production logic kill at least one mutant?\n"
              "  • Are executed assertions strictly positive (> 0)?\n"
              "Target Invariants: V3 (evidence-backed falsifiability), gate red-green baseline\n"
              "Operational Guidance:\n"
              "  Author gates in pure ASL with explicit assertCount > 0. Never use static string mocking or vacuous asserts.\n"
              "  Invoke via pure S-expression: (:lens :target \"<path>\" :lenses (\"falsification\"))\n")))
    ((= lensId "invariants")
     (ok (str "Lens:             invariants\n"
              "Attractor Focus:  Teleological value hierarchy (V0-V6), C1-C5 preservation boundaries, workspace sovereignty\n"
              "Inquiry Probes:\n"
              "  • Is the teleological hierarchy preserved (V0 human > V1 invariants > V2 contractual intent)?\n"
              "  • Are S-expressions 100% balanced with zero delimiter leakage?\n"
              "  • Is the workspace zero-remote invariant preserved (zero git remotes on workspace root)?\n"
              "  • Are monorepo packages 100% pure ASL?\n"
              "Target Invariants: V0, V1, C1 (delimiter balance), C2 (zero-emoji), C3 (zero-foreign), workspaceIsolation\n"
              "Operational Guidance:\n"
              "  Run './bin/asl audit gates' and './bin/asl audit consistency' to verify invariant reconciliation.\n")))
    ((= lensId "concurrency")
     (ok (str "Lens:             concurrency\n"
              "Attractor Focus:  Swarm leases, circular ring buffer epoch wrap, channel race hazards, deadlocks\n"
              "Inquiry Probes:\n"
              "  • Are buffer indexes masked with (capacity - 1) on powers of 2?\n"
              "  • Are cross-process locks and leases leased with timeouts and cleanup traps?\n"
              "  • Are file system writes staged in RAM VFS and committed atomically via fsync + rename?\n"
              "Target Invariants: ramTxn, atomic transaction commits\n"
              "Operational Guidance:\n"
              "  Stage edits in RAM buffers before disk commit. Verify buffer wrapping on large iterations.\n")))
    ((= lensId "security")
     (ok (str "Lens:             security\n"
              "Attractor Focus:  Monorepo sovereignty, sandbox permissions, path traversal containment inside :owns\n"
              "Inquiry Probes:\n"
              "  • Are process-tree writes strictly bounded within declared :owns sets?\n"
              "  • Are command arguments escaped against shell injection?\n"
              "  • Is workspace isolation maintained (zero remotes, no unauthorized data exfiltration)?\n"
              "Target Invariants: workspaceIsolation, process-tree write closure\n"
              "Operational Guidance:\n"
              "  Use declared boundaries. Do not execute unvalidated shell strings or bypass sandbox without justification.\n")))
    ((or (= lensId "attention-density") (= lensId "token-economics"))
     (ok (str "Lens:             attention-density (alias: token-economics)\n"
              "Attractor Focus:  Attention density, CamelCase BPE subword efficiency (-44% tax), bounded slices\n"
              "Inquiry Probes:\n"
              "  • Are code slices bounded (:limit 50, :start, :end) rather than loading full files?\n"
              "  • Are identifiers formatted in CamelCase to maximize BPE token efficiency?\n"
              "  • Are delimiters pure Dyck-1 parens to avoid BPE bracket confusion?\n"
              "Target Invariants: dyck1Purity, tokenEconomics, context preservation\n"
              "Operational Guidance:\n"
              "  Prefer S-expression batching and progressive disclosure (compact catalog <= 250 tokens).\n")))
    ((= lensId "architecture")
     (ok (str "Lens:             architecture\n"
              "Attractor Focus:  Minimal causal surface, L0-L3 stratification, modular cohesion, zero integer lines\n"
              "Inquiry Probes:\n"
              "  • Does the change introduce unnecessary abstraction or speculative bloat?\n"
              "  • Are code locations anchored by symbol (:file ?f :symbol ?s) without integer line numbers?\n"
              "  • Is the package boundary declared with clean manifest exports?\n"
              "Target Invariants: astAddressing (Zero-Line-Number Invariant), minimal causal surface (V4)\n"
              "Operational Guidance:\n"
              "  Anchor all diffs and references to symbol definitions rather than ephemeral line numbers.\n")))
    ((= lensId "non-vacuity")
     (ok (str "Lens:             non-vacuity\n"
              "Attractor Focus:  Mock eradication, non-vacuous assertion counts (>0), genuine dynamic roundtripping\n"
              "Inquiry Probes:\n"
              "  • Does the test parse genuine artifacts rather than hardcoded canned strings?\n"
              "  • Does the gate report executed assertion count > 0?\n"
              "  • Is round-trip determinism satisfied (project(parse(project(ast))) = project(ast))?\n"
              "Target Invariants: semantics (zero truthiness, positive assertions required)\n"
              "Operational Guidance:\n"
              "  Refute simulated test doubles. Every test must execute against live engine ASTs and physical files.\n")))
    ((= lensId "optimization")
     (ok (str "Lens:             optimization\n"
              "Attractor Focus:  Algorithmic complexity bounds, minimal intermediate allocations, bounded memory\n"
              "Inquiry Probes:\n"
              "  • Are inner loops free of quadratic scans or repeated string concatenations?\n"
              "  • Does peak memory remain within bounded footprint?\n"
              "  • Are lookup tables indexed via O(1) hashes or sorted arrays?\n"
              "Target Invariants: minimal memory footprint, bounded latency\n"
              "Operational Guidance:\n"
              "  Measure with micro-benchmarks. Retain stack buffers and pre-allocated slices for hot paths.\n")))
    ((= lensId "resilience")
     (ok (str "Lens:             resilience\n"
              "Attractor Focus:  Dynamic witness circuit breakers, limit cycles (max 3 retries), fallback paths\n"
              "Inquiry Probes:\n"
              "  • Does the failure handler trip after 3 identical failure signatures?\n"
              "  • Does the agent transition to scouting or escalate when blocked rather than looping?\n"
              "  • Are fallback paths declared for every absent or lying capability?\n"
              "Target Invariants: limitCycle (circuit breaker), capabilities fallback\n"
              "Operational Guidance:\n"
              "  Record witness signatures on failure. Break loops by pivoting causal hypotheses.\n")))
    ((or (= lensId "contract-precision") (= lensId "api-ergonomics"))
     (ok (str "Lens:             contract-precision (alias: api-ergonomics)\n"
              "Attractor Focus:  Zero integer line numbers, typed Option/Result contracts, subword-efficient naming\n"
              "Inquiry Probes:\n"
              "  • Do tool invocations return typed receipts with status and message?\n"
              "  • Are errors modeled as typed Result/Option types rather than swallowed or silent exits?\n"
              "  • Are signatures self-describing with clear parameter types and documentation?\n"
              "Target Invariants: astAddressing, output receipt structure\n"
              "Operational Guidance:\n"
              "  Provide complete descriptors with whenToUse, whenNotToUse, and concrete examples.\n")))
    ((= lensId "minimal-surface")
     (ok (str "Lens:             minimal-surface\n"
              "Attractor Focus:  Occam's razor, minimal diff, eliminate speculative bloat, high signal-to-noise ratio\n"
              "Inquiry Probes:\n"
              "  • Does the change introduce speculative abstractions or diff bloat beyond intent?\n"
              "  • Is every diff hunk causally connected to a registered intent atom?\n"
              "  • Are dead branches, obsolete shims, and unused dependencies aggressively pruned?\n"
              "Target Invariants: minimal causal surface (V4), Popperian Tri-Map B-Map closure\n"
              "Operational Guidance:\n"
              "  Prune ungrounded diffs. Keep diffs strictly bounded to intent-satisfying mutations.\n")))
    ((= lensId "consistency")
     (ok (str "Lens:             consistency\n"
              "Attractor Focus:  Popperian Tri-Map closed bijection (Intent S <-> Gate F <-> Diff B), cross-layer harmony\n"
              "Inquiry Probes:\n"
              "  • Are intent atoms, gates, and diff hunks in closed one-to-one correspondence?\n"
              "  • Is there zero omission (all S caused by B) and zero speculative bloat (all B justified by S)?\n"
              "  • Do cross-layer interfaces, SSOT rules, and package manifests agree without contradiction?\n"
              "Target Invariants: triMap (closed reconciliation), teleology (V1-V2 alignment)\n"
              "Operational Guidance:\n"
              "  Run './bin/asl audit consistency' and verify closed Tri-Map bijection before committing.\n")))
    ((= lensId "coupling")
     (ok (str "Lens:             coupling\n"
              "Attractor Focus:  Intra-package cohesion, inter-package fan-in/fan-out, boundary leaks, cycle eradication, module fictions\n"
              "Inquiry Probes:\n"
              "  • Does the change increase inter-package fan-out or introduce undeclared cross-package dependencies?\n"
              "  • Are modules within the package tightly cohesive without kitchen-sink sprawl?\n"
              "  • Are there dead module fictions, unreferenced internal modules, or vacuous non-asserting stubs?\n"
              "  • Is the package dependency graph an acyclic DAG (zero circular cycles)?\n"
              "Target Invariants: minimal causal surface (V4), L0-L3 stratification, clean modular cohesion\n"
              "Operational Guidance:\n"
              "  Run './bin/asl audit coupling' to compute intra-package cohesion, inter-package DAG, and detect module fictions.\n")))
    (else (err (str "Error: Unknown lens '" lensId "'. Run 'lens list' for registered lenses."))))

fn quoteLensText value: Str -> Str
  (stringReplace (stringReplace value "\\" "\\\\") "\"" "\\\"")

fn formatLensPayload kind: Str args: (List Str) -> Str
  (let [(target (stringJoin args " "))]
    (if (= kind "file")
      (str "(:lens :file \"" (quoteLensText (optionOr (listHead args) "")) "\")")
      (str "(:lens :text \"" (quoteLensText target) "\")")))

fn ! lensTargetKind! sub: Str -> Str
  (if (fileExists? sub) "file" "text")

fn shellQuoteLens value: Str -> Str
  (str "'" (stringReplace value "'" "'\\''") "'")

fn lensRepoRoot! -> (Result Str Str)
  (let [(result (processRun "git rev-parse --show-toplevel"))
        (root (stringTrim result.stdout))]
    (if (and (= result.exitCode 0) (not (stringEmpty? root)))
      (ok root)
      (err (str "ERR_REPO_ROOT: cannot resolve workspace root: " result.stderr))))

fn runLensPayload! kind: Str args: (List Str) -> (Result Str Str)
  (mt (lensRepoRoot!)
    ((err e) (err e))
    ((ok root)
     (let [(payload (formatLensPayload kind args))
           (command (str (shellQuoteLens (str root "/bin/asl")) " " (shellQuoteLens payload)))
           (result (processRun command))]
       (if (= result.exitCode 0)
         (ok result.stdout)
         (err (if (stringEmpty? result.stderr) result.stdout result.stderr))))))

fn lensTestResult res: ProcessOutput -> (Result Str Str)
  (if (= res.exitCode 0)
    (ok (str "--> Running asl-lens pure ASL test suite...\n" res.stdout "✓ [Lens Test] All tests passed cleanly (100% pure AgentSlang).\n"))
    (err (if (stringEmpty? res.stderr) res.stdout res.stderr)))

fn runLensTests! -> (Result Str Str)
  (mt (lensRepoRoot!)
    ((err e) (err e))
    ((ok root)
     (let [(command (str (shellQuoteLens (str root "/bin/asl")) " test " (shellQuoteLens (str root "/tools/lens/tests/lensTest.asl"))))
           (res (processRun command))]
       (lensTestResult res))))

fn ! runLensCommand args: (List Str) -> (Result Str Str)
  (if (listEmpty? args)
    (ok (formatLensHelp))
    (let [(sub (optionOr (listHead args) ""))
          (rest (optionOr (listTail args) (list)))]
      (cond
        ((or (= sub "--help") (= sub "-h")) (ok (formatLensHelp)))
        ((or (= sub "--version") (= sub "-v")) (ok (formatLensVersion)))
        ((= sub "list") (ok (formatLensList)))
        ((or (= sub "--setup") (= sub "--rules")) (ok (formatLensRules)))
        ((= sub "--test") (runLensTests!))
        ((or (= sub "info") (= sub "describe"))
         (let [(lensId (optionOr (listHead rest) ""))]
           (if (stringEmpty? lensId)
             (err "Usage: lens info <lens-id>\nRun 'lens list' to view the 10 canonical lenses.")
             (formatLensInfo lensId))))
        ((or (= sub "discover") (or (= sub "search") (or (= sub "run") (= sub "audit"))))
         (runLensPayload! "text" rest))
        (else (runLensPayload! (lensTargetKind! sub) args)))))
