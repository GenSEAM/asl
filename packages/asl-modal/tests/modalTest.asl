(module asl-modal/tests/modalTest
  :x [runTests main]
  :i [(asl-modal/modal :a md)
      (asl-json/json :a j)
      (asl-http/http11 :a http)
      (asl-harness/launch :a la)
      (aslGateway/budget :a bg)
      (aslGateway/plugin :a pg)
      (aslGateway/upstream :a up)
      (aslGateway/config :a cfg)
      (aslGateway/dispatch :a dp)
      (asl-parser/reader :a rd)])

fn presetPath -> String
  "asl/packages/asl-modal/presets/bonsai2.asn"

fn appPath -> String
  "/home/op/.asl/run/modal/asl-bonsai2-l4/app.py"

fn vllmPresetPath -> String
  "asl/packages/asl-modal/presets/bonsai2Vllm.asn"

fn ! presetText! -> String
  (mt (fileReadString (presetPath))
    ((ok t) t)
    ((err e) (do (assert false (str "read preset: " e)) "")))

fn ! shipped! -> (Option md/ModalPreset)
  (mt (md/modalPresetLoad! (presetPath))
    ((ok p) (some p))
    ((err e) (do (assert false (str "shipped preset parses: " (md/modalErrorText e))) (none))))

fn ! shippedTier! tier: String -> (Option (Pair md/ModalPreset md/GpuTier))
  (mt (shipped!)
    ((none) (none))
    ((some p)
      (mt (md/modalTier p tier)
        ((ok t) (some (pair p t)))
        ((err e) (do (assert false (str "tier " tier ": " (md/modalErrorText e))) (none))))))


fn ! testShippedPreset! -> Bool
  (mt (shipped!)
    ((none) false)
    ((some p)
      (do
        (assert (= p.id "bonsai2") "preset id")
        (assert (= p.model "prism-ml/Ternary-Bonsai-2-27B-gguf") "preset model")
        (assert (= p.engine "prismLlamaCpp") "default engine is the official fork")
        (assert (= p.maxTokens 16384) "reasoning model max_tokens follows the model card's -n 16384")
        (assert (= p.modalVersion "1.6.1") "Modal client pinned in the preset")
        (assert (= p.baseImage "nvidia/cuda:12.8.1-devel-ubuntu24.04") "CUDA 12.8 devel base pinned (KNOWN_ISSUES #222)")
        (assert (and (listEmpty? p.packages) (= (stringJoin p.preparePackages " ") "huggingface_hub==2.1.1")) "pip pins")
        (assert (= (mt p.sampling ((some x) (str x.temperature " " x.topP " " (stringFromInt64 x.topK) " " x.minP)) ((none) "none")) "1.0 0.95 20 0.05") "thinking-mode sampling from the model card")
        (assert (= p.coldStartMs 90000) "adopted cold start")
        (assert (= (stringJoin (map (fn [(t md/GpuTier)] -> String (stringFromInt64 t.microUsdPerSec)) p.gpus) " ") "164 222 306 542 583") "per-tier GPU price in micro-USD per second")
        (assert (= (stringJoin (map (fn [(t md/GpuTier)] -> String (if (stringContains? t.weightFile "PQ2_0") "PQ2" "PTQ1")) p.gpus) " ") "PTQ1 PTQ1 PQ2 PTQ1 PQ2") "Ampere tiers override the weight file with PQ2_0")
        (assert p.reasoning "preset is a reasoning model")
        (assert (= p.scaledownSec 2) "scale-down window minimal")
        (assert (= p.maxContainers 1) "one container caps spend")
        (assert (= (stringJoin (map (fn [(t md/GpuTier)] -> String t.tier) p.gpus) " ") "T4 L4 A10 L40S A100") "gpu ladder in order")
        (assert (= (stringJoin (map (fn [(t md/GpuTier)] -> String (stringFromInt64 t.maxConcurrency)) p.gpus) " ") "2 4 4 8 16") "per-tier max concurrency")
        (assert (= p.pool.windowMs 7000) "pool windowMs")
        (assert (= p.pool.peakCount 16) "pool peakCount")
        (assert p.pool.bypassWhileBusy "pool bypassWhileBusy")
        true)))

fn errorOf text: String -> String
  (mt (md/modalPresetParse text)
    ((ok p) (str "parsed " p.id))
    ((err e) (md/modalErrorText e)))

fn swap text: String from: String to: String -> String
  (do
    (assert (stringContains? text from) (str "fixture anchor present: " from))
    (stringReplace text from to))

fn ! testTypedErrors! -> Bool
  (let [(t (presetText!))]
    (assert (= (errorOf t) "parsed bonsai2") "unchanged preset parses")
    (assert (stringStartsWith? (errorOf (swap t ":pool (:windowMs 7000 :peakCount 16 :bypassWhileBusy true))" ":pool (:windowMs 7000")) "(:modalError :presetSyntax :line ") "unclosed form is a presetSyntax error with its line")
    (assert (= (errorOf (str t "(:modalPreset)")) "(:modalError :presetShape :reason \"expected one (:modalPreset ...) form, found 2\")") "two forms")
    (assert (= (errorOf (swap t ":model \"prism-ml/Ternary-Bonsai-2-27B-gguf\"" "")) "(:modalError :fieldMissing :field model)") "missing model")
    (assert (= (errorOf (swap t ":maxTokens 16384" ":maxTokens 16384 :modle 1")) "(:modalError :fieldUnknown :field modle)") "unknown field")
    (assert (= (errorOf (swap t ":maxTokens 16384" ":maxTokens 4096")) "(:modalError :fieldRange :field maxTokens :value 4096 :bound \">= 8192 for a reasoning model\")") "reasoning floor")
    (assert (= (errorOf (swap t ":contextTokens 32768" ":contextTokens 16384")) "(:modalError :fieldRange :field contextTokens :value 16384 :bound \"> maxTokens 16384\")") "context must exceed the reply budget")
    (assert (= (errorOf (swap t ":v 2 " ":v 1 ")) "(:modalError :fieldRange :field v :value 1 :bound \"= 2\")") "preset version 2")
    (assert (= (errorOf (swap t ":modalVersion \"1.6.1\"" ":modalVersion \"1.6\" :x 1")) "(:modalError :fieldUnknown :field x)") "unknown key wins over values")
    (assert (= (errorOf (swap t ":modalVersion \"1.6.1\"" ":modalVersion \">=1.6\"")) "(:modalError :nameInvalid :field modalVersion :value \">=1.6\")") "modal client is an exact version")
    (assert (= (errorOf (swap t "devel-ubuntu24.04\"" "devel-ubuntu24.04:latest\"")) "(:modalError :nameInvalid :field baseImage :value \"nvidia/cuda:12.8.1-devel-ubuntu24.04:latest\")") "base image has one tag")
    (assert (= (errorOf (swap t ":baseImage \"nvidia/cuda:12.8.1-devel-ubuntu24.04\"" ":baseImage \"nvidia/cuda:latest\"")) "(:modalError :nameInvalid :field baseImage :value \"nvidia/cuda:latest\")") "base image tag is not latest")
    (assert (= (errorOf (swap t ":baseImage \"nvidia/cuda:12.8.1-devel-ubuntu24.04\"" ":baseImage \"nvidia/cuda:12.8.1-runtime-ubuntu24.04\"")) "(:modalError :engineNeeds :engine prismLlamaCpp :field baseImage :reason \"the fork is compiled in the image, which needs a CUDA -devel- base with nvcc\")") "fork build needs a devel base")
    (assert (= (errorOf (swap t "\"huggingface_hub==2.1.1\"" "\"huggingface_hub>=2.1\"")) "(:modalError :nameInvalid :field preparePackages :value \"huggingface_hub>=2.1\")") "packages are exact pins")
    (assert (= (errorOf (swap t "\"huggingface_hub==2.1.1\"" "\"huggingface_hub\"")) "(:modalError :nameInvalid :field preparePackages :value \"huggingface_hub\")") "a package without a version is not a pin")
    (assert (= (errorOf (swap t "\"huggingface_hub==2.1.1\"" "\"huggingface_hub==2.1.1==3\"")) "(:modalError :nameInvalid :field preparePackages :value \"huggingface_hub==2.1.1==3\")") "a pin has one ==")
    (assert (= (errorOf (swap t ":modalVersion \"1.6.1\"" ":modalVersion \"\"")) "(:modalError :nameInvalid :field modalVersion :value \"\")") "an empty client version is not a pin")
    (assert (= (errorOf (swap t ":preparePackages (\"huggingface_hub==2.1.1\")" ":preparePackages ()")) "(:modalError :fieldRange :field preparePackages :value 0 :bound \">= 1 pinned package\")") "prepare needs its hub client pinned")
    (assert (= (errorOf (swap t ":topP 0.95" ":topP high")) "(:modalError :fieldType :field sampling.topP :expected decimal)") "sampling values are decimals")
    (assert (= (errorOf (swap t ":minP 0.05" ":minP 0.05 :seed 1")) "(:modalError :fieldUnknown :field sampling.seed)") "sampling unknown key")
    (assert (= (errorOf (swap t " :microUsdPerSec 164" "")) "(:modalError :fieldMissing :field gpus.microUsdPerSec)") "every tier carries its price")
    (assert (= (errorOf (swap t ":coldStartMs 90000" "")) "(:modalError :fieldMissing :field coldStartMs)") "cold start is declared")
    (assert (= (errorOf (swap t ":scaledownSec 2" ":scaledownSec 0")) "(:modalError :fieldRange :field scaledownSec :value 0 :bound \">= 1\")") "scaledown must be positive")
    (assert (= (errorOf (swap t ":snapshot true" ":snapshot yes")) "(:modalError :fieldType :field snapshot :expected bool)") "bool type")
    (assert (= (errorOf (swap t ":app \"asl-bonsai2\"" ":app asl-bonsai2")) "(:modalError :fieldType :field app :expected string)") "string type")
    (assert (= (errorOf (swap t ":app \"asl-bonsai2\"" ":app \"Bad_App\"")) "(:modalError :nameInvalid :field app :value \"Bad_App\")") "app must be a DNS label")
    (assert (= (errorOf (swap t ":engine prismLlamaCpp" ":engine sglang")) "(:modalError :engineUnknown :engine sglang)") "unknown engine")
    (assert (= (errorOf (swap t "(:tier T4 " "(:tier H900 ")) "(:modalError :gpuUnknown :tier H900)") "unknown gpu")
    (assert (= (errorOf (swap t "(:tier A10 " "(:tier L4 ")) "(:modalError :gpuDuplicate :tier L4)") "duplicate tier")
    (assert (= (errorOf (swap t "(:tier T4 :maxConcurrency 2" "(:tier T4 :maxConcurrency 0")) "(:modalError :fieldRange :field maxConcurrency :value 0 :bound \">= 1\")") "tier concurrency positive")
    (assert (= (errorOf (swap t ":peakCount 16" ":peakCount 0")) "(:modalError :fieldRange :field pool.peakCount :value 0 :bound \">= 1\")") "pool peak positive")
    (assert (= (errorOf (swap t ":bypassWhileBusy true" ":bypassWhileBusy true :maxWait 3")) "(:modalError :fieldUnknown :field pool.maxWait)") "pool unknown key")
    (assert (= (errorOf (swap t ":cudaArch \"75;80;86;89\"" "")) "(:modalError :engineNeeds :engine prismLlamaCpp :field cudaArch :reason \"the fork builds with -DCMAKE_CUDA_ARCHITECTURES (KNOWN_ISSUES #182)\")") "fork needs cuda arch")
    (assert (= (errorOf (swap t ":engine prismLlamaCpp" ":engine vllmBonsai")) "(:modalError :engineNeeds :engine vllmBonsai :field tokenizerRepo :reason \"the GGUF repo ships no config.json or tokenizer files\")") "vllm port needs a tokenizer repo")
    (let [(v (mt (fileReadString (vllmPresetPath)) ((ok x) x) ((err e) (do (assert false (str "read vllm preset: " e)) ""))))]
      (do
        (assert (= (errorOf v) "parsed bonsai2Vllm") "shipped vllm preset parses")
        (assert (= (errorOf (swap v ":servedName \"bonsai2-27b\"" ":servedName \"bonsai\"")) "(:modalError :engineNeeds :engine vllmBonsai :field servedName :reason \"serve_bonsai.py fixes --served-model-name bonsai2-27b\")") "vllm port fixes the served name")
        (assert (= (errorOf (swap v "(\"vllm==0.26.0\" " "(")) "(:modalError :engineNeeds :engine vllmBonsai :field packages :reason \"the port needs a pinned vllm==version\")") "vllm port needs vllm pinned")
        (assert (= (errorOf (swap v ":contextTokens 32768" ":sampling (:temperature 1.0 :topP 0.95 :topK 20 :minP 0.05) :contextTokens 32768")) "(:modalError :engineNeeds :engine vllmBonsai :field sampling :reason \"serve_bonsai.py takes no sampling flags; vLLM reads generation_config.json\")") "vllm port takes no sampling flags")
        (assert (= (errorOf (swap v ":weightFile \"Ternary-Bonsai-2-27B-PTQ1_0.gguf\"" ":weightFile \"Ternary-Bonsai-2-27B-PQ2_0.gguf\"")) "(:modalError :engineNeeds :engine vllmBonsai :field weightFile :reason \"serve_bonsai.py --ternary loads Ternary-Bonsai-2-27B-PTQ1_0.gguf only\")") "vllm port loads PTQ1_0 only")
        (assert (= (errorOf (swap v ":microUsdPerSec 694)" ":microUsdPerSec 694 :weightFile \"Ternary-Bonsai-2-27B-PQ2_0.gguf\")")) "(:modalError :engineNeeds :engine vllmBonsai :field gpus.A100-80GB.weightFile :reason \"serve_bonsai.py --ternary loads Ternary-Bonsai-2-27B-PTQ1_0.gguf only\")") "vllm port loads PTQ1_0 on every tier")))
    (assert (= (errorOf (swap t ":gpus ((:tier T4 :maxConcurrency 2 :timeoutSec 1800 :microUsdPerSec 164)" ":gpus () :x ((:tier T4 :maxConcurrency 2 :timeoutSec 1800 :microUsdPerSec 164)")) "(:modalError :fieldUnknown :field x)") "unknown key checked before ladder")
    (mt (md/modalPresetLoad! "asl/packages/asl-modal/presets/absent.asn")
      ((ok _) (assert false "absent preset loads"))
      ((err e) (assert (mt e ((md/presetUnreadable path reason) (= path "asl/packages/asl-modal/presets/absent.asn")) (_ false)) "absent preset is presetUnreadable")))
    true)

fn ! testEmptyLadder! -> Bool
  (let [(t (presetText!))
        (start (optionOr (stringIndexOf t ":gpus (") 0))
        (stop (optionOr (stringIndexOf t ":pool") 0))
        (cut (str (optionOr (stringSlice t 0 start) "") ":gpus ()\n  " (optionOr (stringSlice t stop (stringLength t)) "")))]
    (assert (> stop start) "ladder anchors found")
    (assert (= (errorOf cut) "(:modalError :ladderEmpty)") "empty ladder")
    true)


fn ! testEnvAndCommands! -> Bool
  (mt (shippedTier! "L4")
    ((none) false)
    ((some pt)
      (let [(p (pairFirst pt))
            (t (pairSecond pt))
            (envLine (stringJoin (map (fn [(kv (Pair String String))] -> String (str (pairFirst kv) "=" (pairSecond kv))) (md/modalAppEnv (presetPath) t)) " "))
            (envPrefix "env ASL_MODAL_PRESET=asl/packages/asl-modal/presets/bonsai2.asn ASL_MODAL_TIER=L4 uvx --from modal==1.6.1 modal")]
        (assert (= envLine "ASL_MODAL_PRESET=asl/packages/asl-modal/presets/bonsai2.asn ASL_MODAL_TIER=L4") "app environment names the preset file and the tier")
        (assert (= (md/modalCommandLine (md/modalDeployArgv p t (presetPath) (appPath))) (str envPrefix " deploy /home/op/.asl/run/modal/asl-bonsai2-l4/app.py")) "deploy runs the pinned Modal client")
        (assert (= (md/modalCommandLine (md/modalPrepareArgv p t (presetPath) (appPath))) (str envPrefix " run /home/op/.asl/run/modal/asl-bonsai2-l4/app.py::prepare")) "prepare command line")
        (assert (= (stringJoin (md/modalStopArgv p t) " ") "uvx --from modal==1.6.1 modal app stop --yes asl-bonsai2-l4") "stop argv")
        (assert (= (stringJoin (md/modalStatusArgv p) " ") "uvx --from modal==1.6.1 modal app list --json") "status argv")
        (assert (= (md/modalCommandLine (list "a b" "it's" "")) "'a b' 'it'\\''s' ''") "shell quoting")
        (mt (md/modalTier p "A100")
          ((ok big) (do (assert (= (md/modalAppName p big) "asl-bonsai2-a100") "app name per tier")
                        (assert (= big.weightFile "Ternary-Bonsai-2-27B-PQ2_0.gguf") "A100 tier resolves its own weight file")))
          ((err e) (assert false (md/modalErrorText e))))
        (mt (md/modalTier p "H100")
          ((ok _) (assert false "H100 is not in the ladder"))
          ((err e) (assert (= (md/modalErrorText e) "(:modalError :gpuAbsent :tier H100)") "absent tier is typed")))
        true)))

fn gatewayText entry: String -> String
  (let [(lines (stringSplit (stringTrim entry) "\n"))]
    (str "(:gateway :v 2 :providers (" (optionOr (listGet lines 0) "") ") :models (" (optionOr (listGet lines 1) "")
         ") :profiles ((:profile :id main :routes ((:intent any :chain (bonsai2))))) :uses ((:use :for default :profile main)))"))

fn ! testGatewayEntry! -> Bool
  (mt (shippedTier! "L4")
    ((none) false)
    ((some pt)
      (let [(p (pairFirst pt))
            (t (pairSecond pt))]
        (assert (= (errorOf "") "(:modalError :presetShape :reason \"expected one (:modalPreset ...) form, found 0\")") "empty preset text")
        (mt (md/modalGatewayEntry p t "Bad Space")
          ((ok _) (assert false "invalid workspace renders"))
          ((err e) (assert (= (md/modalErrorText e) "(:modalError :nameInvalid :field workspace :value \"Bad Space\")") "workspace is validated")))
        (mt (md/modalGatewayEntry p t "genseam")
          ((err e) (do (assert false (md/modalErrorText e)) false))
          ((ok entry)
            (do
              (assert (= entry (str "(:provider :id modal :kind openai :base \"https://genseam--asl-bonsai2-l4.modal.run/v1\" :keyEnv ASL_MODAL_API_KEY :timeoutSec 1200"
                                    " :pool (:windowMs 7000 :peakCount 4 :bypassWhileBusy true :requestTimeoutMs 1200000))\n"
                                    "(:model :id bonsai2 :provider modal :name \"bonsai2-27b\" :maxTokens 16384 :timeoutSec 1200 :reasoning true)\n"))
                "gateway entry renders exactly, peakCount capped by tier concurrency")
              (mt (cfg/gatewayConfigParse! (gatewayText entry) "modalTest" "")
                ((err e) (assert false (str "gateway v2 parser accepts the entry: " e)))
                ((ok table)
                  (mt (mapGet table.providers "modal")
                    ((none) (assert false "parsed table has provider modal"))
                    ((some pv)
                      (do
                        (assert (= pv.base "https://genseam--asl-bonsai2-l4.modal.run/v1") "gateway reads the base url")
                        (assert (= pv.keyEnv "ASL_MODAL_API_KEY") "gateway reads the key env name")
                        (assert (= pv.timeoutSec 1200.0) "gateway reads the tier timeout"))))))
              true))))))


fn ! runQuiet! argv: (List String) env: (List String) -> (Result Int64 String)
  (mt (procSpawnv argv (some ".") (some env))
    ((err e) (err e))
    ((ok sp)
      (do
        (fdClose sp.stdin)
        (fdRead sp.stderr 65536)
        (fdClose sp.stdout)
        (fdClose sp.stderr)
        (mt (procWaitPid sp.pid false)
          ((err e) (err e))
          ((ok status) (mt status ((some code) (ok code)) ((none) (err "no exit status"))))))))

fn ! tempDir! -> (Result String String)
  (mt (procSpawnv (list "mktemp" "-d" "/tmp/modalTest.XXXXXX") (none) (none))
    ((err e) (err e))
    ((ok sp)
      (do
        (fdClose sp.stdin)
        (let [(out (mt (fdRead sp.stdout 4096) ((ok s) (stringTrim s)) ((err _) "")))]
          (fdClose sp.stdout)
          (fdClose sp.stderr)
          (procWaitPid sp.pid false)
          (if (stringStartsWith? out "/tmp/modalTest.") (ok out) (err (str "mktemp printed " out)))))))

fn ! testAppRenders! -> Bool
  (mt (tempDir!)
    ((err e) (do (assert false (str "temp dir: " e)) false))
    ((ok dir)
      (let [(env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "PYTHONPYCACHEPREFIX=" dir)))
            (broken (str dir "/broken.py"))
            (source (md/modalAppSource))]
        (assert (= (mt (md/modalRenderApp! "relative/dir") ((ok _) "ok") ((err e) (md/modalErrorText e))) "(:modalError :renderFailed :path \"relative/dir\" :reason \"absolute directory expected\")") "render takes an absolute directory")
        (mt (md/modalRenderApp! (str dir "/asl-bonsai2-l4"))
          ((err e) (assert false (str "render app.py: " (md/modalErrorText e))))
          ((ok app)
            (do
              (assert (= app (str dir "/asl-bonsai2-l4/app.py")) "render creates the directory and names app.py")
              (assert (= (mt (fileReadString app) ((ok x) x) ((err _) "")) source) "the rendered file is byte-equal to modalAppSource")
              (assert (stringStartsWith? source "\"\"\"Modal app serving one asl-modal preset") "render starts with the module docstring")
              (assert (stringEndsWith? source "            self.process.wait()\n") "render ends with the exit hook and one newline")
              (assert (stringContains? source "@modal.web_server(port=ENGINE_PORT") "app.py exposes the engine port as a Modal web server")
              (assert (stringContains? source "scaledown_window=S[\"scaledownSec\"]") "app.py takes the scale-down window from the preset")
              (assert (stringContains? source "if modal.__version__ != S[\"modalVersion\"]:") "app.py refuses a Modal client other than the pinned one")
              (assert (stringContains? source "\"enable_gpu_snapshot\": True") "app.py asks for GPU memory snapshots")
              (mt (runQuiet! (list "python3" "-c" "import ast,sys; ast.parse(open(sys.argv[1]).read())" app) env)
                ((ok code) (assert (= code 0) "the render parses as Python (ast.parse)"))
                ((err e) (assert false (str "python3 spawn: " e))))
              (mt (runQuiet! (list "python3" "-m" "py_compile" app) env)
                ((ok code) (assert (= code 0) "the render passes python3 -m py_compile"))
                ((err e) (assert false (str "py_compile spawn: " e))))
              (mt (fileWrite broken (stringReplace source "def wait_ready(process, deadline_sec):" "def wait_ready(process, deadline_sec)"))
                ((err e) (assert false (str "write broken copy: " e)))
                ((ok _)
                  (mt (runQuiet! (list "python3" "-c" "import ast,sys; ast.parse(open(sys.argv[1]).read())" broken) env)
                    ((ok code) (assert (!= code 0) "ast.parse rejects a syntax error, so the check is live"))
                    ((err e) (assert false (str "python3 spawn: " e))))))
              (testSettingsParity! app))))
        (mt (runQuiet! (list "rm" "-rf" dir) env)
          ((ok code) (assert (= code 0) "temp dir removed"))
          ((err e) (assert false (str "rm: " e))))
        true)))


fn ! writeAll fd: Int64 data: String offset: Int64 -> (Result Unit String)
  (if (>= offset (stringLength data)) (ok ())
    (mt (fdWrite fd (optionOr (stringSlice data offset (stringLength data)) ""))
      ((err e) (err e))
      ((ok n) (if (<= n 0) (err "ERR_WRITE_ZERO") (writeAll fd data (+ offset n))))))

fn requestComplete? raw: String -> Bool
  (mt (stringIndexOf raw "\r\n\r\n")
    ((none) false)
    ((some at)
      (mt (http/parseHttpRequest raw)
        ((err _) false)
        ((ok req)
          (let [(want (optionOr (stringToInt64 (stringTrim (optionOr (http/getHeader req "Content-Length") "0"))) 0))]
            (>= (- (stringLength raw) (+ at 4)) want))))))

fn ! readRequest fd: Int64 acc: String -> (Result String String)
  (if (requestComplete? acc) (ok acc)
    (mt (fdRead fd 65536)
      ((err e) (err e))
      ((ok chunk) (if (stringEmpty? chunk) (err (str "client closed after " (stringFromInt64 (stringLength acc)) " bytes")) (readRequest fd (str acc chunk))))))

fn jsonStr v: (Option j/Json) -> String
  (mt v ((some x) (mt x ((j/jstr s) s) (_ ""))) ((none) ""))

fn jsonNum v: (Option j/Json) -> Int64
  (mt v ((some x) (mt x ((j/jint n) n) (_ -1))) ((none) -1))

fn lastUserText doc: j/Json -> String
  (mt (j/jsonGet doc "messages")
    ((some x)
      (mt x
        ((j/jarr xs) (fold (fn [(acc String) (m j/Json)] -> String (if (= (jsonStr (j/jsonGet m "role")) "user") (jsonStr (j/jsonGet m "content")) acc)) "" xs))
        (_ "")))
    ((none) ""))

fn response status: Int64 reason: String body: String -> String
  (str "HTTP/1.1 " (stringFromInt64 status) " " reason "\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body)

fn stubAnswer mode: String raw: String -> String
  (mt (http/parseHttpRequest raw)
    ((err e) (response 400 "Bad Request" (str "{\"error\":\"" e "\"}")))
    ((ok req)
      (cond
        ((or (!= req.method "POST") (!= req.path "/v1/chat/completions")) (response 404 "Not Found" "{\"error\":\"route\"}"))
        ((!= (optionOr (http/getHeader req "Authorization") "") "Bearer stub-key") (response 401 "Unauthorized" "{\"error\":\"key\"}"))
        ((= mode "busy") (response 503 "Service Unavailable" "{\"error\":\"warming\"}"))
        (else
          (mt (j/jsonParse req.body)
            ((err e) (response 400 "Bad Request" "{\"error\":\"json\"}"))
            ((ok doc)
              (cond
                ((!= (jsonStr (j/jsonGet doc "model")) "bonsai2-27b") (response 400 "Bad Request" "{\"error\":\"model\"}"))
                ((!= (jsonNum (j/jsonGet doc "max_tokens")) 8192) (response 400 "Bad Request" "{\"error\":\"max_tokens\"}"))
                ((= mode "truncated") (response 200 "OK" "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning_content\":\"still thinking\"},\"finish_reason\":\"length\"}],\"usage\":{\"completion_tokens\":8192}}"))
                (else
                  (let [(text (lastUserText doc))]
                    (response 200 "OK" (j/jsonEmit (j/jobj (list
                      (pair "choices" (j/jarr (list (j/jobj (list (pair "index" (j/jint 0))
                                                                 (pair "message" (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jstr (str "echo:" text))) (pair "reasoning_content" (j/jstr (str "thought about " text))))))
                                                                 (pair "finish_reason" (j/jstr "stop")))))))
                      (pair "usage" (j/jobj (list (pair "completion_tokens" (j/jint (stringLength text)))))))))))))))))))

fn ! serveStub mode: String -> (Result Int64 String)
  (mt (tcpListen 0)
    ((err e) (err e))
    ((ok listener)
      (mt (sockLocalPort listener)
        ((err e) (do (fdClose listener) (err e)))
        ((ok port)
          (do
            (fdWrite 1 (str "PORT " (stringFromInt64 port) "\n"))
            (mt (sockAccept listener)
              ((err e) (do (fdClose listener) (err e)))
              ((ok client)
                (let [(answer (mt (readRequest client "") ((ok raw) (stubAnswer mode raw)) ((err e) (response 400 "Bad Request" "{\"error\":\"read\"}"))))]
                  (writeAll client answer 0)
                  (fdClose client)
                  (fdClose listener)
                  (ok 0)))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (if (= (optionOr (listGet args 0) "") "stub")
    (serveStub (optionOr (listGet args 1) "ok"))
    (err "ERR_TEST_MODE: modalTest main serves only the stub"))

fn ! readLine fd: Int64 acc: String -> (Result String String)
  (if (stringContains? acc "\n") (ok acc)
    (mt (fdRead fd 64)
      ((err e) (err e))
      ((ok chunk) (if (stringEmpty? chunk) (err (str "stub closed stdout: " acc)) (readLine fd (str acc chunk))))))

fn ! startStub! mode: String -> (Result (Pair SpawnedProc Int64) String)
  (mt (procSpawnv (list "./asl/host/out/asl-host" "run" "asl/packages/asl-modal/tests/modalTest.asl" "stub" mode) (some ".") (none))
    ((err e) (err (str "spawn stub: " e)))
    ((ok sp)
      (do
        (fdClose sp.stdin)
        (let [(line (readLine sp.stdout ""))]
          (fdClose sp.stdout)
          (fdClose sp.stderr)
          (mt line
            ((ok l) (mt (stringToInt64 (stringTrim (stringReplace l "PORT " "")))
                      ((some port) (ok (pair sp port)))
                      ((none) (do (procKill sp.pid "SIGKILL") (procWaitPid sp.pid false) (err (str "stub said " l))))))
            ((err e) (do (procKill sp.pid "SIGKILL") (procWaitPid sp.pid false) (err e))))))))

fn ! stubCall! req: up/UpstreamRequest env: (Map String String) timeoutSec: Float64 -> (Result up/UpstreamResponse up/UpstreamFailure)
  (do
    (assert (= req.url "http://modal.test/v1/chat/completions") "chat joins the endpoint path")
    (assert (= req.method "POST") "chat uses POST")
    (assert (= (optionOr (up/headerGet req.headers "Authorization") "") (str "Bearer " (optionOr (mapGet env "MODAL_TEST_KEY") ""))) "chat forwards the bearer key")
    (assert (and (= req.data (optionOr (mapGet env "MODAL_TEST_BODY") "")) (= timeoutSec 20.0)) "chat forwards JSON and timeout")
    (let [(mode (optionOr (mapGet env "MODAL_TEST_MODE") "ok"))]
      (cond
        ((= mode "transport") (err (up/transportFailure 7 "connection refused")))
        ((= (optionOr (up/headerGet req.headers "Authorization") "") "Bearer wrong-key") (err (up/httpFailure 401 "Unauthorized" "{\"error\":\"key\"}")) )
        ((= mode "busy") (ok (up/UpstreamResponse :status 503 :reason "Service Unavailable" :body "{\"error\":\"warming\"}")))
        ((= mode "truncated") (ok (up/UpstreamResponse :status 200 :reason "OK" :body "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning_content\":\"still thinking\"},\"finish_reason\":\"length\"}],\"usage\":{\"completion_tokens\":8192}}")))
        (else (ok (up/UpstreamResponse :status 200 :reason "OK" :body "{\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"echo:add 2 and 3\",\"reasoning_content\":\"thought about add 2 and 3\"},\"finish_reason\":\"stop\"}],\"usage\":{\"completion_tokens\":11}}"))))))

fn ! chatAgainst! mode: String key: String -> (Result md/ChatReply md/ModalError)
  (mt (shipped!)
    ((none) (err (md/endpointTransport "no preset")))
    ((some p)
      (let [(body (md/modalChatBody p (list (pair "system" "be terse") (pair "user" "add 2 and 3")) 0))
            (env (mapSet (mapSet (mapSet (mapEmpty) "MODAL_TEST_MODE" mode) "MODAL_TEST_KEY" key) "MODAL_TEST_BODY" body))]
        (md/modalChatWith! "http://modal.test/v1" key body p.maxTokens 20.0 env stubCall!))))

fn ! testChatBody! -> Bool
  (mt (shipped!)
    ((none) false)
    ((some p)
      (do
        (assert (= (md/modalChatBody p (list (pair "user" "hi")) 0) "{\"model\":\"bonsai2-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":16384}") "chat body defaults max_tokens to the preset")
        (assert (= (mt (md/modalParseReply 303 "" 16384) ((ok _) "ok") ((err e) (mt e ((md/endpointRedirect d) "endpointRedirect") (_ (md/modalErrorText e))))) "endpointRedirect") "Modal's 303 after 150 s is typed, not a status error")
        (assert (= (md/modalChatBody p (list (pair "user" "hi")) 9000) "{\"model\":\"bonsai2-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":9000}") "explicit max_tokens wins")
        (assert (= (mt (md/modalParseReply 401 "{\"error\":\"a\\b\"}" 8192) ((ok _) "ok") ((err e) (md/modalErrorText e))) "(:modalError :endpointStatus :status 401 :body \"{\\\"error\\\":\\\"a\\\\b\\\"}\")") "error text escapes quotes and backslashes")
        (assert (= (mt (md/modalParseReply 200 "not json" 8192) ((ok _) "ok") ((err e) (mt e ((md/endpointReply d) "endpointReply") (_ "other")))) "endpointReply") "non-JSON reply is endpointReply")
        (assert (= (mt (md/modalParseReply 200 "{\"choices\":[]}" 8192) ((ok _) "ok") ((err e) (md/modalErrorText e))) "(:modalError :endpointReply :detail \"reply has no choices[0]\")") "empty choices")
        (assert (= (mt (md/modalParseReply 200 "{\"choices\":[{\"message\":{\"content\":\"x\",\"reasoning\":\"r\"},\"finish_reason\":\"stop\"}]}" 8192) ((ok r) r.reasoning) ((err e) (md/modalErrorText e))) "r") "vLLM reasoning field is read")
        true)))

fn ! testEndpointContract! -> Bool
  (do
    (mt (chatAgainst! "ok" "stub-key")
      ((err e) (assert false (str "chat ok: " (md/modalErrorText e))))
      ((ok r)
        (do
          (assert (= r.content "echo:add 2 and 3") "reply content")
          (assert (= r.reasoning "thought about add 2 and 3") "reasoning_content is kept apart")
          (assert (= r.finishReason "stop") "finish reason")
          (assert (= r.completionTokens 11) "usage completion tokens"))))
    (mt (chatAgainst! "ok" "wrong-key")
      ((ok _) (assert false "wrong key accepted"))
      ((err e) (assert (mt e ((md/endpointStatus status body) (and (= status 401) (stringContains? body "key"))) (_ false)) (str "wrong key is endpointStatus 401: " (md/modalErrorText e)))))
    (mt (chatAgainst! "busy" "stub-key")
      ((ok _) (assert false "busy endpoint answered"))
      ((err e) (assert (mt e ((md/endpointStatus status body) (= status 503)) (_ false)) (str "busy is endpointStatus 503: " (md/modalErrorText e)))))
    (mt (chatAgainst! "truncated" "stub-key")
      ((ok _) (assert false "truncated reasoning accepted"))
      ((err e) (assert (= (md/modalErrorText e) "(:modalError :reasoningTruncated :maxTokens 16384)") "reasoning that eats the budget is typed")))
    (mt (md/modalChat! "http://127.0.0.1:9/v1" "stub-key" "{}" 8192 5.0 (mapSet (mapEmpty) "PATH" (optionOr (envGet "PATH") "/usr/bin:/bin")))
      ((ok _) (assert false "closed port answered"))
      ((err e) (assert (mt e ((md/endpointTransport d) true) (_ false)) (str "closed port is endpointTransport: " (md/modalErrorText e)))))
    true)


fn ! pythonSettings! app: String preset: String tier: String -> String
  (mt (la/runCapture! (list "python3" "-I" app "--settings" preset tier) (some ".") (some (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) "PYTHONDONTWRITEBYTECODE=1")))
    ((err e) (do (assert false (str "python3 spawn: " e)) ""))
    ((ok c) (do (assert (= c.code 0) (str "app.py --settings exits 0: " c.errText)) (stringTrim c.out))))

fn ! settingsMatch! app: String preset: String tier: String -> Bool
  (mt (md/modalPresetLoad! preset)
    ((err e) (do (assert false (md/modalErrorText e)) false))
    ((ok p)
      (mt (md/modalTier p tier)
        ((err e) (do (assert false (md/modalErrorText e)) false))
        ((ok t)
          (let [(mine (md/modalAppSettings p t))
                (theirs (pythonSettings! app preset tier))]
            (do
              (assert (= mine theirs) (str "app.py derives the settings modal.asl renders for " preset " " tier ": " theirs))
              (= mine theirs)))))))

fn ! testSettingsParity! app: String -> Bool
  (do
    (settingsMatch! app (presetPath) "L4")
    (settingsMatch! app (presetPath) "A100")
    (settingsMatch! app (vllmPresetPath) "RTX-PRO-6000")
    (mt (shippedTier! "A100")
      ((none) false)
      ((some pt)
        (let [(json (md/modalAppSettings (pairFirst pt) (pairSecond pt)))]
          (do
            (assert (stringContains? json "\"weightFile\":\"Ternary-Bonsai-2-27B-PQ2_0.gguf\"") "settings carry the tier's weight file")
            (assert (stringContains? json "\"sampling\":{\"minP\":\"0.05\",\"temperature\":\"1.0\",\"topK\":20,\"topP\":\"0.95\"}") "settings carry sampling")
            (assert (stringContains? json "\"modalVersion\":\"1.6.1\"") "settings carry the client pin")
            true))))
    true)


fn near? a: Float64 b: Float64 -> Bool
  (and (< (- a b) 0.000000000001) (< (- b a) 0.000000000001))

fn ! testCapability! -> Bool
  (mt (shippedTier! "L4")
    ((none) false)
    ((some pt)
      (let [(p (pairFirst pt))
            (t (pairSecond pt))
            (c (md/modalCapabilities p t))]
        (assert (= (md/modalCapabilityText p t)
                   "(:capability :plugin modal :endpoint asl-bonsai2-l4 :api openaiChat :batching continuous :maxConcurrency 4 :streaming true :tools true :json true :scaleModel (:serverless :idleTimeoutSec 2 :coldStartMs 90000) :priceModel (:perGpuSecond :usd ((T4 164e-6) (L4 222e-6) (A10 306e-6) (L40S 542e-6) (A100 583e-6))) :lifecycle (deploy start stop status))")
                "capability record renders exactly")
        (assert (not (some? (pg/capabilitiesError c))) "the contract accepts the capability record")
        (assert (mt c.api ((pg/openaiChat) true) (_ false)) "api openaiChat")
        (assert (and (= c.redirectAfterSec 150) (= (pg/maxRedirects c (int64ToFloat64 t.timeoutSec)) 8)) "Modal's 303 every 150 s is followed: L4's 1200 s timeout allows 8 hops")
        (assert (mt c.batching ((pg/continuous) true) (_ false)) "continuous batching")
        (assert (mt c.scaleModel ((pg/serverless idle cold) (and (= idle 2) (= cold 90000))) (_ false)) "serverless scale-to-zero with the preset's idle window and cold start")
        (assert (mt c.priceModel
                  ((pg/perGpuSecond rates) (and (= (stringJoin (map (fn [(r (Pair String Float64))] -> String (pairFirst r)) rates) " ") "T4 L4 A10 L40S A100")
                                                (near? (optionOr (mt (listGet rates 1) ((some r) (some (pairSecond r))) ((none) (none))) 0.0) 0.000222)))
                  (_ false))
                "price is USD per GPU-second for every ladder tier")
        (assert (= (md/modalStartCost p t) 20424) "a start costs one cold start plus the idle window: 222 x 92 s, in micro-USD")
        (assert (= (md/modalVersionTag p) "modal==1.6.1 prismLlamaCpp@prism-b10743-adfffbe") "version tag pins client and engine")
        (let [(r (md/modalLifecycleRequest p t "MODALAPP-unit"))]
          (assert (and (= r.endpoint "asl-bonsai2-l4") (and (= r.gpu "L4") (and (= r.unit "MODALAPP-unit") (= r.expectedCost 20424)))) "lifecycle request: endpoint, tier in gpu, work unit in unit, cost in micro-USD"))
        true)))

fn modalLine cap: Int64 -> bg/BudgetLine
  (bg/BudgetLine :id "modalDay" :scope (bg/scopeEndpoint "asl-bonsai2-l4") :period (bg/periodDay) :cap cap :approved false)

fn ledgerOf lines: (List bg/BudgetLine) approvals: (List bg/Approval) -> bg/Ledger
  (bg/makeLedger lines approvals 16)

fn ! runWith! out: String argv: (List String) -> (Result la/Captured String)
  (ok (la/Captured :code 0 :out out :errText ""))

fn ! runFails! argv: (List String) -> (Result la/Captured String)
  (ok (la/Captured :code 1 :out "" :errText "Error: app not found\n"))

fn ! runForbidden! argv: (List String) -> (Result la/Captured String)
  (do (assert false (str "a refused op reached the runner: " (stringJoin argv " "))) (err "forbidden"))

fn ! pluginOf! appDir: String run: (Fn [(List String)] (Result la/Captured String)) -> (Option (Pair pg/Plugin md/ModalPreset))
  (mt (shippedTier! "L4")
    ((none) (none))
    ((some pt)
      (mt (up/upstreamSettings (mapEmpty))
        ((err e) (do (assert false (str "upstream settings: " e)) (none)))
        ((ok st)
          (mt (md/modalPluginWith! (pairFirst pt) (pairSecond pt) (presetPath) appDir "genseam" st run)
            ((err e) (do (assert false (str "makePlugin accepts the Modal plugin: " e)) (none)))
            ((ok plugin) (some (pair plugin (pairFirst pt)))))))))

fn statusText r: (Result pg/LifecycleStatus pg/PluginFailure) -> String
  (mt r
    ((ok s) (str (mt s.state ((pg/cold) "cold") ((pg/warming) "warming") ((pg/warm) "warm") ((pg/draining) "draining") ((pg/down) "down")) " " s.detail))
    ((err f) (mt f
               ((pg/spendGate reason) (str "spendGate " reason))
               ((pg/lifecycleFailed reason) (str "lifecycleFailed " reason))
               (_ "other failure"))))

fn ! request! unit: String -> pg/LifecycleRequest
  (mt (shippedTier! "L4")
    ((some pt) (md/modalLifecycleRequest (pairFirst pt) (pairSecond pt) unit))
    ((none) (pg/LifecycleRequest :endpoint "" :model "" :gpu "" :region "" :version "" :unit unit :expectedCost 0)))

fn ! statusOf! out: String -> String
  (mt (pluginOf! "/nonexistent/app" (fn [(argv (List String))] -> (Result la/Captured String) (runWith! out argv)))
    ((none) "no plugin")
    ((some pp) (statusText (pg/pluginStatus! (pairFirst pp) (request! "u1")))))

fn ! testPlugin! -> Bool
  (mt (tempDir!)
    ((err e) (do (assert false (str "temp dir: " e)) false))
    ((ok dir)
      (let [(appDir (str dir "/asl-bonsai2-l4"))
            (req (request! "MODALAPP-unit"))
            (unapproved (ledgerOf (list (modalLine 1000000)) (list)))
            (approved (ledgerOf (list (modalLine 1000000)) (list (bg/Approval :endpoint "asl-bonsai2-l4" :cap 1000000))))
            (tight (ledgerOf (list (modalLine 20000)) (list (bg/Approval :endpoint "asl-bonsai2-l4" :cap 20000))))
            (deployArgv (str "env ASL_MODAL_PRESET=asl/packages/asl-modal/presets/bonsai2.asn ASL_MODAL_TIER=L4 uvx --from modal==1.6.1 modal deploy " appDir "/app.py"))]
        (mt (pluginOf! appDir runForbidden!)
          ((none) (assert false "plugin builds"))
          ((some pp)
            (let [(plugin (pairFirst pp))]
              (assert (= plugin.id "modal") "plugin id modal")
              (assert (= (mt (pg/pluginHealth! plugin (mapEmpty)) ((ok u) u) ((err e) e)) "https://genseam--asl-bonsai2-l4.modal.run/v1") "health reports the tier's endpoint")
              (assert (= (statusText (pg/pluginDeploy! plugin (none) req 1760000000000)) "spendGate deploy needs a budget ledger") "deploy without a ledger never runs")
              (assert (= (statusText (pg/pluginDeploy! plugin (some unapproved) req 1760000000000)) "spendGate deploy lacks a budget line and approval for its endpoint") "unapproved paid deploy never runs")
              (assert (= (statusText (pg/pluginStart! plugin (some tight) req 1760000000000)) "spendGate budget cap exceeded") "a start dearer than the cap never runs")
              (assert (= (statusText (pg/pluginStop! plugin (pg/LifecycleRequest :endpoint "asl-bonsai2-l4" :model "bonsai2" :gpu "A100" :region "" :version req.version :unit "u" :expectedCost 0))) "lifecycleFailed gpu A100 is not the deployed tier L4") "a request for another tier is refused")
              (assert (= (statusText (pg/pluginStop! plugin (pg/LifecycleRequest :endpoint "asl-bonsai2-l4" :model "bonsai2" :gpu "L4" :region "" :version "modal==1.5.5" :unit "u" :expectedCost 0))) "lifecycleFailed version modal==1.5.5 is not the pinned modal==1.6.1 prismLlamaCpp@prism-b10743-adfffbe") "a request for another pinned version is refused"))))
        (mt (pluginOf! appDir (fn [(argv (List String))] -> (Result la/Captured String) (do (assert (= (stringJoin argv " ") deployArgv) "approved deploy runs the pinned deploy of the rendered app") (runWith! "" argv))))
          ((none) (assert false "plugin builds"))
          ((some pp)
            (do
              (assert (= (statusText (pg/pluginDeploy! (pairFirst pp) (some approved) req 1760000000000)) "cold deployed; scales from zero") "approved deploy ends cold")
              (assert (= (mt (fileReadString (str appDir "/app.py")) ((ok x) x) ((err _) "")) (md/modalAppSource)) "deploy rendered app.py first"))))
        (mt (pluginOf! appDir (fn [(argv (List String))] -> (Result la/Captured String) (runWith! "200" argv)))
          ((none) (assert false "plugin builds"))
          ((some pp) (assert (= (statusText (pg/pluginStart! (pairFirst pp) (some approved) req 1760000000000)) "warm health 200") "start within budget probes health: 200 is warm")))
        (mt (pluginOf! appDir (fn [(argv (List String))] -> (Result la/Captured String) (runWith! "303" argv)))
          ((none) (assert false "plugin builds"))
          ((some pp) (assert (= (statusText (pg/pluginStart! (pairFirst pp) (some approved) req 1760000000000)) "warming health 303") "a health probe still waiting is warming")))
        (mt (pluginOf! appDir runFails!)
          ((none) (assert false "plugin builds"))
          ((some pp) (assert (= (statusText (pg/pluginStop! (pairFirst pp) req)) "lifecycleFailed (:modalError :lifecycleFailed :op stop :code 1 :detail \"Error: app not found\")") "a failing command is typed with its exit code")))
        (mt (pluginOf! appDir (fn [(argv (List String))] -> (Result la/Captured String) (do (assert (= (stringJoin argv " ") "uvx --from modal==1.6.1 modal app stop --yes asl-bonsai2-l4") "stop runs app stop without a ledger") (runWith! "" argv))))
          ((none) (assert false "plugin builds"))
          ((some pp) (assert (= (statusText (pg/pluginStop! (pairFirst pp) req)) "down stopped") "stop ends down")))
        (assert (= (statusOf! "[]") "down not deployed") "no app row is down")
        (assert (= (statusOf! "[{\"app_id\":\"ap-1\",\"description\":\"asl-bonsai2-l4\",\"state\":\"stopped\",\"tasks\":\"0\"}]") "down stopped") "a stopped app is down")
        (assert (= (statusOf! "[{\"app_id\":\"ap-9\",\"description\":\"other\",\"state\":\"deployed\",\"tasks\":\"3\"},{\"app_id\":\"ap-2\",\"description\":\"asl-bonsai2-l4\",\"state\":\"deployed\",\"tasks\":\"0\"}]") "cold deployed tasks 0") "deployed with no task is cold; other apps are ignored")
        (assert (= (statusOf! "[{\"app_id\":\"ap-2\",\"description\":\"asl-bonsai2-l4\",\"state\":\"deployed\",\"tasks\":\"1\"}]") "warm deployed tasks 1") "a running task is warm")
        (assert (= (statusOf! "[{\"app_id\":\"ap-2\",\"description\":\"asl-bonsai2-l4\",\"state\":\"initializing...\",\"tasks\":\"0\"}]") "warming initializing... tasks 0") "initializing is warming")
        (assert (= (statusOf! "[{\"app_id\":\"ap-2\",\"description\":\"asl-bonsai2-l4\",\"state\":\"stopping...\",\"tasks\":\"1\"}]") "draining stopping... tasks 1") "stopping is draining")
        (assert (stringStartsWith? (statusOf! "not json") "lifecycleFailed modal app list --json is not JSON: ") (str "unparseable status is a failure: " (statusOf! "not json")))
        (mt (runQuiet! (list "rm" "-rf" dir) (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin"))))
          ((ok code) (assert (= code 0) "temp dir removed"))
          ((err e) (assert false (str "rm: " e))))
        true)))


fn ! testConfig! -> Bool
  (mt (shippedTier! "L4")
    ((none) false)
    ((some pt)
      (let [(p (pairFirst pt))
            (t (pairSecond pt))]
        (assert (= (mt (md/modalConfig p t "genseam" 0) ((ok _) "ok") ((err e) (md/modalErrorText e))) "(:modalError :fieldRange :field cap :value 0 :bound \">= 1 microUSD\")") "config needs a positive cap")
        (mt (md/modalConfig p t "genseam" 2000000)
          ((err e) (do (assert false (md/modalErrorText e)) false))
          ((ok text)
            (let [(form (rd/parseSexpr text))]
              (mt (cfg/asnProps form (some ":gatewayAdditions"))
                ((err e) (do (assert false (str "config output parses as ASN: " e)) false))
                ((ok props)
                  (do
                    (mt (mapGet props "budget")
                      ((none) (assert false "config carries :budget"))
                      ((some budgetForm)
                        (mt (bg/parseBudgetConfig budgetForm 16)
                          ((err e) (assert false (str "budget.asl parses the :budget form: " e)))
                          ((ok ledger)
                            (do
                              (assert (mt (bg/gate ledger (bg/actionDeploy "asl-bonsai2-l4") 1760000000000) ((bg/allow) true) (_ false)) "the printed line and approval allow the tier's deploy")
                              (assert (mt (bg/gate ledger (bg/actionDeploy "asl-bonsai2-a100") 1760000000000) ((bg/allow) false) (_ true)) "another tier's deploy stays denied")
                              (assert (mt (bg/gate ledger (bg/actionScaleUp "asl-bonsai2-l4" "modal" "u" 20424) 1760000000000) ((bg/allow) true) (_ false)) "a start within the cap is allowed")
                              (assert (mt (bg/gate ledger (bg/actionScaleUp "asl-bonsai2-l4" "modal" "u" 2000001) 1760000000000) ((bg/allow) false) (_ true)) "a start above the cap is denied"))))))
                    (let [(part (fn [(k String)] -> String (mt (mapGet props k) ((some e) (rd/renderSexpr e)) ((none) ""))))
                          (gateway (str "(:gateway :v 2 :providers " (part "providers") " :models " (part "models")
                                        " :profiles ((:profile :id main :routes ((:intent any :chain (bonsai2))))) :uses ((:use :for default :profile main))"
                                        " :endpoints " (part "endpoints") " :budget " (part "budget") ")"))]
                      (do
                        (assert (ok? (dp/parseWiring gateway)) (str "dispatch wiring accepts the additions: " (mt (dp/parseWiring gateway) ((ok _) "") ((err e) e))))
                        (assert (ok? (cfg/gatewayConfigParse! gateway "modalTest" "")) "gateway v2 parser accepts the additions")))
                    true)))))))))

fn ! bump! path: String step: Int64 -> Int64
  (let [(n (+ step (optionOr (stringToInt64 (stringTrim (mt (fileReadString path) ((ok x) x) ((err _) "0")))) 0)))]
    (do (assert (ok? (fileWrite path (stringFromInt64 n))) (str "fake state written: " path)) n))

fn statusJson state: String tasks: String -> String
  (str "[{\"app_id\":\"ap-2\",\"description\":\"asl-bonsai2-l4\",\"state\":\"" state "\",\"tasks\":\"" tasks "\"}]")

fn ! fakeIo! dir: String state: String healthyAfter: Int64 -> md/SmokeIo
  (do
   (assert (ok? (dirCreate dir)) (str "fake io dir: " dir))
   (md/SmokeIo
    :run (fn [(argv (List String))] -> (Result la/Captured String)
           (if (= (optionOr (listHead argv) "") "curl")
             (do (assert (= (optionOr (listGet argv 8) "") "https://genseam--asl-bonsai2-l4.modal.run/health") "smoke probes the tier's /health")
                 (ok (la/Captured :code 0 :out (if (>= (bump! (str dir "/probes") 1) healthyAfter) "200" "503") :errText "")))
             (do (assert (= (stringJoin argv " ") "uvx --from modal==1.6.1 modal app list --json") "smoke reads status with the pinned client")
                 (ok (la/Captured :code 0 :out (statusJson state "0") :errText "")))))
    :call (fn [(req up/UpstreamRequest) (env (Map String String)) (timeoutSec Float64)] -> (Result up/UpstreamResponse up/UpstreamFailure)
            (do (assert (= req.url "http://127.0.0.1:8080/v1/chat/completions") "smoke chats through the gateway URL")
                (assert (stringContains? req.data "\"model\":\"bonsai2\"") "smoke names the gateway model id")
                (let [(maxTokens (mt (j/jsonParse req.data) ((ok d) (jsonNum (j/jsonGet d "max_tokens"))) ((err _) 0)))]
                  (ok (up/UpstreamResponse :status 200 :reason "OK" :body (str "{\"choices\":[{\"message\":{\"content\":\"\"},\"finish_reason\":\"length\"}],\"usage\":{\"completion_tokens\":" (stringFromInt64 maxTokens) "}}"))))))
    :nowMs (fn [] -> Int64 (bump! (str dir "/clock") 10000))
    :sleep (fn [(ms Int64)] -> Unit ())
    :env (mapEmpty)))

fn ! smokeText! p: md/ModalPreset t: md/GpuTier args: (List String) io: md/SmokeIo -> String
  (mt (md/modalSmokeWith! p t "genseam" "http://127.0.0.1:8080/v1" args io)
    ((ok s) s)
    ((err e) (md/modalErrorText e)))

fn ! testSmoke! -> Bool
  (mt (tempDir!)
    ((err e) (do (assert false (str "temp dir: " e)) false))
    ((ok dir)
      (mt (shippedTier! "L4")
        ((none) false)
        ((some pt)
          (let [(p (pairFirst pt))
                (t (pairSecond pt))
                (refusing (md/SmokeIo :run runForbidden! :call (fn [(req up/UpstreamRequest) (env (Map String String)) (timeoutSec Float64)] -> (Result up/UpstreamResponse up/UpstreamFailure) (do (assert false "a refused smoke chatted") (err (up/protocolFailure "forbidden"))))
                                      :nowMs (fn [] -> Int64 0) :sleep (fn [(ms Int64)] -> Unit ()) :env (mapEmpty)))]
            (assert (= (md/modalSmokeWorstCost p t) 320124) "worst case: 222 x (1200 startup + 2 x 120 chat + 2 idle)")
            (assert (= (smokeText! p t (list "--cap" "400000") refusing) "(:modalError :smokeRefused :reason \"smoke starts a GPU container and spends money: pass --yes\")") "smoke refuses without --yes")
            (assert (= (smokeText! p t (list "--yes") refusing) "(:modalError :smokeRefused :reason \"pass --cap MICROUSD, the most this smoke may spend\")") "smoke refuses without a cap")
            (assert (= (smokeText! p t (list "--yes" "--cap" "lots") refusing) "(:modalError :smokeRefused :reason \"pass --cap MICROUSD, the most this smoke may spend\")") "smoke refuses a non-numeric cap")
            (assert (= (smokeText! p t (list "--yes" "--cap" "320123") refusing) "(:modalError :smokeRefused :reason \"worst case 320124 microUSD exceeds --cap 320123\")") "smoke refuses a cap below its worst case")
            (assert (= (smokeText! p t (list "--yes" "--cap" "400000") (fakeIo! (str dir "/stopped") "stopped" 1)) "(:modalError :smokeRefused :reason \"asl-bonsai2-l4 is down (stopped): deploy it first\")") "smoke refuses an endpoint that is down")
            (assert (= (smokeText! p t (list "--yes" "--cap" "400000") (fakeIo! (str dir "/cold") "deployed" 3))
                       "(:modalSmoke :endpoint asl-bonsai2-l4 :wasCold true :coldStartMs 30000 :firstTokenMs 10000 :tokS 25.6 :completionTokens 256 :costMicroUsd 18204 :capMicroUsd 400000)")
                    "smoke measures cold start, first token, tok/s and cost")
            (mt (md/modalPresetParse (stringReplace (presetText!) ":startupSec 1200" ":startupSec 25"))
              ((err e) (assert false (md/modalErrorText e)))
              ((ok quick)
                (mt (md/modalTier quick "L4")
                  ((err e) (assert false (md/modalErrorText e)))
                  ((ok qt) (assert (= (smokeText! quick qt (list "--yes" "--cap" "400000") (fakeIo! (str dir "/never") "deployed" 99)) "(:modalError :smokeFailed :reason \"no 200 from /health within 25 s; last 503\")") "smoke gives up after the startup bound")))))
            (mt (runQuiet! (list "rm" "-rf" dir) (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin"))))
              ((ok code) (assert (= code 0) "temp dir removed"))
              ((err e) (assert false (str "rm: " e))))
            true)))))

fn ! runTests -> Bool
  (do
    (testShippedPreset!)
    (testTypedErrors!)
    (testEmptyLadder!)
    (testEnvAndCommands!)
    (testGatewayEntry!)
    (testAppRenders!)
    (testCapability!)
    (testPlugin!)
    (testConfig!)
    (testSmoke!)
    (testChatBody!)
    (testEndpointContract!)
    true)
