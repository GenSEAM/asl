(module asl-cli/consiliumCmd
  :x [formatConsiliumHelp formatConsiliumList formatConsiliumInfo formatConsiliumVersion consiliumTestResults runConsiliumCommand]
  :i [])

fn formatConsiliumHelp -> Str
  (str "asl-consilium: Sovereign Multi-LLM Frontier Council Deliberation Engine\n"
       "Council: Flagship Trio (gpt-6-astra, deepseek-v4.1-flash, glm-5.3) + Fast Reserve (muse-spark-1.3, hy4-preview, qwen3.8-max)\n"
       "Consensus Threshold: >= 75% Supermajority required for certification\n"
       "Protocol: 2-Stage Deliberation (Stage 1: Question 1 Initialization -> Stage 2: Question 2 Peer Cross-Verification)\n\n"
       "Usage: consilium [command|option] [args...]\n\n"
       "Commands:\n"
       "  run <target> [options]      Execute 2-stage Council deliberation on target artifact\n"
       "  audit <target> [options]    End-to-end: discover lenses and execute 2-stage Council deliberation\n"
       "  info, describe              Print Council composition, defaults, stages, and consensus threshold\n"
       "  list                        List Flagship Trio, fast reserve pool, 10 inquiry lenses, and consensus rules\n\n"
       "Options:\n"
       "  --lenses <list>             Comma-separated list of inquiry lenses\n"
       "  --strict                    Exit non-zero if consensus < 0.75 or defects detected\n"
       "  --matrix                    Print full 5-model x lens consensus evaluation matrix\n"
       "  --format <asn|json>         Output format (default: asn)\n"
       "  --output <path>             Write structured verdict to file\n"
       "  --test                      Execute native ASL Consilium test suites\n"
       "  -v, --version               Print version information\n"
       "  -h, --help                  Show this help message\n\n"
       "Examples:\n"
       "  consilium run spec.asn --strict\n"
       "  consilium audit asl/packages/asl-compiler/src/wasi.asl --matrix\n"
       "  consilium list\n"
       "  consilium --test\n")

fn formatConsiliumList -> Str
  (str "=== TIER 2: FLAGSHIP TRIO (Default Operational Council: ~85s, ~10¢) ===\n"
       "  1. gpt-6-astra          - Flagship Architectural Synthesis & Rigor (OpenAI | 32s | temp 0.25 | ceiling 16k | conf 0.94)\n"
       "  2. deepseek-v4.1-flash  - Algorithmic Falsification & Substrate Integrity (DeepSeek | 24s | temp 0.25 | ceiling 16k | conf 0.86)\n"
       "  3. glm-5.3              - Deep Contractual & Invariant Verification (Zhipu AI | 85s | temp 0.45 | ceiling 32k | conf 0.88)\n\n"
       "=== FAST RESERVE (<30s Sub-Council) ===\n"
       "  • muse-spark-1.3        - Structural Boundary Defense & Lexical SNR (Meta | 28s | temp 0.25 | conf 0.84)\n"
       "  • hy4-preview           - Sub-second Intent Router & Triage (Tencent | 12s | temp 0.00 | conf 0.87)\n\n"
       "=== TIER 3: FULL SENATE (Phase Gates & Final Releases: ~95s) ===\n"
       "  • 5 Independent Labs: OpenAI (Astra) + DeepSeek + Zhipu (GLM) + Meta (Muse) + Alibaba (Qwen)\n\n"
       "=== CONSENSUS RULES ===\n"
       "  Threshold: >= 75% Supermajority required for certification\n"
       "  Protocol: 2-Stage Popperian Deliberation\n"
       "    • Stage 1 (Question 1): Initialization & independent critique generation\n"
       "    • Stage 2 (Question 2): Peer critique cross-examination, refuting false positives & binding votes\n\n"
       "=== 10 CANONICAL INQUIRY LENSES ===\n"
       "  1. falsification    - Red-green causality, mutant killing, baseline failure\n"
       "  2. invariants       - Teleological hierarchy (V0-V6), C1-C5 boundaries, zero-remote\n"
       "  3. concurrency      - Race conditions, channel deadlocks, atomic VFS transactions\n"
       "  4. security         - Sandbox containment, injection defense, path traversal\n"
       "  5. token-economics  - Attention density, KV cache stability, BPE CamelCase\n"
       "  6. architecture     - Minimal causal surface, L0-L3 stratification, modular cohesion\n"
       "  7. non-vacuity      - Mock eradication, vacuous green pass fraud, non-asserting tests\n"
       "  8. optimization     - Algorithmic complexity, hot loop allocations, latency\n"
       "  9. resilience       - Dynamic witness circuit breakers, limit cycles, fallback paths\n"
       "  10. api-ergonomics  - Zero integer line numbers, ASN receipts, typed contracts\n")

fn formatConsiliumInfo -> Str
  (str "Frontier Council Configuration & Teleology\n"
       "========================================================================================\n"
       "Default Council:     Flagship Trio (3-Model Supermajority)\n"
       "  1. gpt-6-astra          Architectural Rigor & Synthesis (OpenAI | 32s | temp 0.25 | ceiling 16k)\n"
       "  2. deepseek-v4.1-flash  Algorithmic Falsification & Substrate Integrity (DeepSeek | 24s | temp 0.25 | ceiling 16k)\n"
       "  3. glm-5.3              Deep Invariant & Contractual Verification (Zhipu AI | 85s | temp 0.45 | ceiling 32k)\n\n"
       "Fast Reserve Pool:   (<30s Sub-Council)\n"
       "  • muse-spark-1.3        Structural Boundary Defense & Lexical SNR (Meta | 28s | temp 0.25)\n"
       "  • hy4-preview           Sub-second Intent Router & Triage (Tencent | 12s | temp 0.00)\n"
       "  • qwen3.8-max           Cross-Language Synthesis & Scale Verification (Alibaba | 40s | temp 0.30)\n\n"
       "Protocol:            2-Stage Popperian Deliberation\n"
       "  • Stage 1 (Q1):    Independent initial critique generation across active lenses\n"
       "  • Stage 2 (Q2):    Cross-examination of peer critiques, refuting false positives & binding votes\n"
       "Certification:       >= 75% Supermajority (>= 0.75 approving consensus score)\n"
       "========================================================================================\n")

fn formatConsiliumVersion -> Str
  "asl-consilium v2.1.0 (5-Model Frontier Council Consensus Engine - 100% Pure AgentScript)"

fn quoteConsiliumShell value: Str -> Str
  (str "'" (stringReplace value "'" "'\\''") "'")

fn consiliumRepoRoot! -> (Result Str Str)
  (let [(result (processRun "git rev-parse --show-toplevel"))
        (root (stringTrim result.stdout))]
    (if (and (= result.exitCode 0) (not (stringEmpty? root)))
      (ok root)
      (err (str "ERR_REPO_ROOT: cannot resolve workspace root: " result.stderr))))

fn consiliumPayload target: Str -> Str
  (str "(:consilium :target \"" (stringReplace (stringReplace target "\\" "\\\\") "\"" "\\\"") "\")")

fn ! runConsiliumTarget action: Str args: (List Str) -> (Result Str Str)
  (let [(target (stringJoin args " "))]
    (if (stringEmpty? target)
      (err (str "Usage: consilium " action " <target>"))
      (mt (consiliumRepoRoot!)
        ((err e) (err e))
        ((ok root)
         (let [(result (processRun (str (quoteConsiliumShell (str root "/bin/asl")) " " (quoteConsiliumShell (consiliumPayload target)))))]
           (if (= result.exitCode 0)
             (ok result.stdout)
             (err (if (stringEmpty? result.stderr) result.stdout result.stderr))))))))

fn consiliumTestResults first: ProcessOutput second: ProcessOutput -> (Result Str Str)
  (if (!= first.exitCode 0)
    (err (if (stringEmpty? first.stderr) first.stdout first.stderr))
    (if (!= second.exitCode 0)
      (err (if (stringEmpty? second.stderr) second.stdout second.stderr))
      (ok (str "--> Running asl-consilium pure ASL test suites...\n" first.stdout second.stdout "✓ [Consilium Test] All pure AgentScript test suites passed cleanly.\n"))))

fn runConsiliumTests! -> (Result Str Str)
  (mt (consiliumRepoRoot!)
    ((err e) (err e))
    ((ok root)
     (let [(host (quoteConsiliumShell (str root "/bin/asl")))
           (first (processRun (str host " test " (quoteConsiliumShell (str root "/tools/tests/consiliumTest.asl")))))]
       (if (!= first.exitCode 0)
         (consiliumTestResults first first)
         (let [(second (processRun (str host " test " (quoteConsiliumShell (str root "/harness/tests/consensusCouncilTest.asl")))))]
           (consiliumTestResults first second))))))

fn ! runConsiliumCommand args: (List Str) -> (Result Str Str)
  (if (listEmpty? args)
    (ok (formatConsiliumHelp))
    (let [(sub (optionOr (listHead args) ""))
          (rest (optionOr (listTail args) (list)))]
      (cond
        ((or (= sub "--help") (= sub "-h")) (ok (formatConsiliumHelp)))
        ((or (= sub "--version") (= sub "-v")) (ok (formatConsiliumVersion)))
        ((= sub "list") (ok (formatConsiliumList)))
        ((or (= sub "info") (= sub "describe")) (ok (formatConsiliumInfo)))
        ((= sub "--test") (runConsiliumTests!))
        ((or (= sub "run") (= sub "audit")) (runConsiliumTarget sub rest))
        (else (runConsiliumTarget "run" args)))))
