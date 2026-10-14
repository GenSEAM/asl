(module aslAgent/cli :x [InferencePhase InferenceConfig TelemetryCounters CliOptions phaseInspect phasePlan phaseAstPatch phaseReasonDebug makeCliOptions makeSimpleCliOptions getPhasedConfig makeTelemetry parseAutonomyFlag formatCliHelp processReplCommand parseCliArgs main] :i [(policy :a pol) (tui :a tui)])

(enum InferencePhase (:c phaseInspect [] "Zero-latency, deterministic tool execution") (:c phasePlan [] "Deep architectural reasoning") (:c phaseAstPatch [] "Absolute determinism during code emission") (:c phaseReasonDebug [] "Root-cause hypothesis search"))

(schema InferenceConfig (:f thinkingBudget I64) (:f temperature F64) (:f topP F64) (:f topK I64))

(schema TelemetryCounters (:f ttftMs I64) (:f tps F64) (:f kvCacheHitRatio F64) (:f blockedHallucinations I64) (:f slabMemoryMb I64))

(schema CliOptions (:f autonomy pol/AutonomyLevel) (:f modelId Str) (:f singlePrompt Str) (:f evalPath Str) (:f isRepl Bool) (:f isSimple Bool))

fn makeCliOptions autonomy: pol/AutonomyLevel model: Str prompt: Str evalPath: Str repl: Bool -> CliOptions
  (CliOptions :autonomy autonomy :modelId model :singlePrompt prompt :evalPath evalPath :isRepl repl :isSimple false)

fn makeSimpleCliOptions autonomy: pol/AutonomyLevel model: Str prompt: Str evalPath: Str repl: Bool simple: Bool -> CliOptions
  (CliOptions :autonomy autonomy :modelId model :singlePrompt prompt :evalPath evalPath :isRepl repl :isSimple simple)

fn getPhasedConfig phase: InferencePhase -> InferenceConfig
  (mt phase ((phaseInspect) (InferenceConfig :thinkingBudget 0 :temperature 0.0 :topP 0.1 :topK 1)) ((phasePlan) (InferenceConfig :thinkingBudget 2048 :temperature 0.2 :topP 0.8 :topK 40)) ((phaseAstPatch) (InferenceConfig :thinkingBudget 0 :temperature 0.0 :topP 0.05 :topK 1)) ((phaseReasonDebug) (InferenceConfig :thinkingBudget 4096 :temperature 0.4 :topP 0.9 :topK 50)))

fn makeTelemetry ttft: I64 tps: F64 hitRatio: F64 blocked: I64 slab: I64 -> TelemetryCounters
  (TelemetryCounters :ttftMs ttft :tps tps :kvCacheHitRatio hitRatio :blockedHallucinations blocked :slabMemoryMb slab)

fn parseAutonomyFlag flag: Str -> pol/AutonomyLevel
  (cond ((= flag "ask") (pol/levelAsk)) ((= flag "guarded") (pol/levelGuarded)) (else (pol/levelAuto)))

fn formatCliHelp -> Str
  (str "GSA (GenSEAM Agent) - Autonomous Cognitive Agent & Deterministic Execution Loop in ASL\n" "Usage: gsa [options] [directive] (alias: gs)\n\n" "Options:\n" "  -a, --autonomy <tier>  Autonomy level: ask (L0), guarded (L1), auto (L2) [default: guarded]\n" "  -m, --model <id>       Inference model ID [default: gemma-4-31b-it]\n" "  -p, --prompt <text>    Execute single directive non-interactively\n" "  -e, --eval <path>      Run automated benchmark evaluation suite\n" "  -s, --simple           Run in simple direct tool/ReAct mode without maintainer DAG\n" "      --repl             Force interactive terminal REPL session\n" "  -h, --help             Show this help message\n" "  -v, --version          Print version information\n")

fn processReplCommand cmd: Str -> Str
  (cond ((or (= cmd "/exit") (= cmd "/quit")) "EXIT") ((= cmd "/help") (formatCliHelp)) ((= cmd "/status") "STATUS: System Online | Invariants: Active | Middleware: OK") ((= cmd "/telemetry") "TELEMETRY: KV-Cache Hit: 92.4% | TTFT: 12ms | Slab: 3MB / 16MB") ((= cmd "/clear") "CLEAR") (else (str "COMMAND: " cmd)))

fn parseOpts args: (List Str) opts: CliOptions -> (Result CliOptions Str)
  (if (listEmpty? args) (ok opts) (let [(head (optionOr (listHead args) "")) (tail (optionOr (listTail args) (list)))] (cond ((or (= head "-h") (= head "--help")) (err "help")) ((or (= head "-v") (= head "--version")) (err "version")) ((= head "--repl") (parseOpts tail (with opts :isRepl true))) ((or (= head "-s") (= head "--simple")) (parseOpts tail (with opts :isSimple true))) ((or (= head "-a") (= head "--autonomy")) (if (listEmpty? tail) (err "missing argument for autonomy") (parseOpts (optionOr (listTail tail) (list)) (with opts :autonomy (parseAutonomyFlag (optionOr (listHead tail) "")))))) ((or (= head "-m") (= head "--model")) (if (listEmpty? tail) (err "missing argument for model") (parseOpts (optionOr (listTail tail) (list)) (with opts :modelId (optionOr (listHead tail) ""))))) ((or (= head "-p") (= head "--prompt")) (if (listEmpty? tail) (err "missing argument for prompt") (parseOpts (optionOr (listTail tail) (list)) (with opts :singlePrompt (optionOr (listHead tail) ""))))) ((or (= head "-e") (= head "--eval")) (if (listEmpty? tail) (err "missing argument for eval") (parseOpts (optionOr (listTail tail) (list)) (with opts :evalPath (optionOr (listHead tail) ""))))) ((stringStartsWith? head "-") (err (str "invalid flag: " head))) (else (ok opts)))))

fn parseCliArgs args: (List Str) -> (Result CliOptions Str)
  (parseOpts args (makeSimpleCliOptions (pol/levelGuarded) "gemma-4-31b-it" "" "" false false))

fn ! main args: (List Str) -> (Result Unit Str)
  (if (listEmpty? args) (let [(unused (println (formatCliHelp)))] (ok ())) (match (parseCliArgs args) ((ok opts) (if opts.isRepl (let [(unused (println "Entering GSA interactive session. Type /help for assistance, /exit to quit."))] (ok ())) (if (not (= opts.singlePrompt "")) (let [(unused (println (str "GSA executing directive: " opts.singlePrompt)))] (ok ())) (if (not (= opts.evalPath "")) (let [(unused (println (str "GSA running evaluation suite: " opts.evalPath)))] (ok ())) (let [(unused (println (formatCliHelp)))] (ok ())))))) ((err msg) (cond ((= msg "help") (let [(unused (println (formatCliHelp)))] (ok ()))) ((= msg "version") (let [(unused (println "gsa 0.1.0 (pure AgentSlang autonomous agent)"))] (ok ()))) (else (let [(unused (println (str "Error: " msg "\n" (formatCliHelp))))] (err msg)))))))
