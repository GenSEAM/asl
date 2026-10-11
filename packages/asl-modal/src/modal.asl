(module asl-modal/modal
  :x [GpuTier PoolSettings Sampling ModalPreset ModalError ChatReply ModalOp
      modalErrorText modalPresetParse modalPresetLoad! modalTier modalAppName
      modalAppEnv modalAppSettings modalDeployArgv modalPrepareArgv modalStopArgv modalStatusArgv modalCommandLine
      modalBaseUrl modalGatewayEntry modalCapabilities modalCapabilityText modalStartCost modalVersionTag
      modalLifecycleRequest modalLifecycleArgv modalStatusFrom modalLifecycle modalRow modalPluginWith! modalPlugin!
      modalChatBody modalParseReply modalChatWith! modalChat! modalAppSource modalAppDir! modalRenderApp!
      SmokeIo modalConfig modalSmokeWorstCost modalSmokeGate modalSmokeWith! main]
  :i [(asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)
      (asl-json/json :a j)
      (asl-harness/launch :a la)
      (aslGateway/plugin :a pg)
      (aslGateway/upstream :a up)])

(schema GpuTier
  (:f tier String)
  (:f maxConcurrency Int64)
  (:f timeoutSec Int64)
  (:f microUsdPerSec Int64)
  (:f weightFile String))

(schema PoolSettings
  (:f windowMs Int64)
  (:f peakCount Int64)
  (:f bypassWhileBusy Bool))

(schema Sampling
  (:f temperature String)
  (:f topP String)
  (:f topK Int64)
  (:f minP String))

(schema ModalPreset
  (:f id String)
  (:f app String)
  (:f modalVersion String)
  (:f baseImage String)
  (:f python String)
  (:f packages (List String))
  (:f preparePackages (List String))
  (:f model String)
  (:f revision String)
  (:f weightFile String)
  (:f servedName String)
  (:f engine String)
  (:f engineRef String)
  (:f cudaArch String)
  (:f sampling (Option Sampling))
  (:f contextTokens Int64)
  (:f maxTokens Int64)
  (:f reasoning Bool)
  (:f scaledownSec Int64)
  (:f startupSec Int64)
  (:f snapshot Bool)
  (:f maxContainers Int64)
  (:f coldStartMs Int64)
  (:f volume String)
  (:f secret String)
  (:f keyEnv String)
  (:f tokenizerRepo String)
  (:f tokenizerRevision String)
  (:f convertedDir String)
  (:f gpus (List GpuTier))
  (:f pool PoolSettings))

(enum ModalError
  (:c presetUnreadable [(path String) (reason String)])
  (:c presetSyntax [(line Int64) (col Int64) (reason String)])
  (:c presetShape [(reason String)])
  (:c fieldMissing [(field String)])
  (:c fieldUnknown [(field String)])
  (:c fieldType [(field String) (expected String)])
  (:c fieldRange [(field String) (value Int64) (bound String)])
  (:c nameInvalid [(field String) (value String)])
  (:c engineUnknown [(engine String)])
  (:c engineNeeds [(engine String) (field String) (reason String)])
  (:c gpuUnknown [(tier String)])
  (:c gpuDuplicate [(tier String)])
  (:c gpuAbsent [(tier String)])
  (:c ladderEmpty [])
  (:c endpointTransport [(detail String)])
  (:c endpointStatus [(status Int64) (body String)])
  (:c endpointReply [(detail String)])
  (:c endpointRedirect [(detail String)])
  (:c reasoningTruncated [(maxTokens Int64)])
  (:c spendDenied [(op String) (reason String)])
  (:c lifecycleFailed [(op String) (code Int64) (detail String)])
  (:c renderFailed [(path String) (reason String)])
  (:c smokeRefused [(reason String)])
  (:c smokeFailed [(reason String)]))

(schema ChatReply
  (:f content String)
  (:f reasoning String)
  (:f finishReason String)
  (:f completionTokens Int64))

(enum ModalOp
  (:c opDeploy [])
  (:c opStart [])
  (:c opStop [])
  (:c opStatus []))

fn asnQuote s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn modalErrorText e: ModalError -> String
  (mt e
    ((presetUnreadable path reason) (str "(:modalError :presetUnreadable :path " (asnQuote path) " :reason " (asnQuote reason) ")"))
    ((presetSyntax line col reason) (str "(:modalError :presetSyntax :line " (stringFromInt64 line) " :col " (stringFromInt64 col) " :reason " (asnQuote reason) ")"))
    ((presetShape reason) (str "(:modalError :presetShape :reason " (asnQuote reason) ")"))
    ((fieldMissing field) (str "(:modalError :fieldMissing :field " field ")"))
    ((fieldUnknown field) (str "(:modalError :fieldUnknown :field " field ")"))
    ((fieldType field expected) (str "(:modalError :fieldType :field " field " :expected " expected ")"))
    ((fieldRange field value bound) (str "(:modalError :fieldRange :field " field " :value " (stringFromInt64 value) " :bound " (asnQuote bound) ")"))
    ((nameInvalid field value) (str "(:modalError :nameInvalid :field " field " :value " (asnQuote value) ")"))
    ((engineUnknown engine) (str "(:modalError :engineUnknown :engine " engine ")"))
    ((engineNeeds engine field reason) (str "(:modalError :engineNeeds :engine " engine " :field " field " :reason " (asnQuote reason) ")"))
    ((gpuUnknown tier) (str "(:modalError :gpuUnknown :tier " tier ")"))
    ((gpuDuplicate tier) (str "(:modalError :gpuDuplicate :tier " tier ")"))
    ((gpuAbsent tier) (str "(:modalError :gpuAbsent :tier " tier ")"))
    ((ladderEmpty) "(:modalError :ladderEmpty)")
    ((endpointTransport detail) (str "(:modalError :endpointTransport :detail " (asnQuote detail) ")"))
    ((endpointStatus status body) (str "(:modalError :endpointStatus :status " (stringFromInt64 status) " :body " (asnQuote body) ")"))
    ((endpointReply detail) (str "(:modalError :endpointReply :detail " (asnQuote detail) ")"))
    ((endpointRedirect detail) (str "(:modalError :endpointRedirect :detail " (asnQuote detail) ")"))
    ((reasoningTruncated maxTokens) (str "(:modalError :reasoningTruncated :maxTokens " (stringFromInt64 maxTokens) ")"))
    ((spendDenied op reason) (str "(:modalError :spendDenied :op " op " :reason " (asnQuote reason) ")"))
    ((smokeRefused reason) (str "(:modalError :smokeRefused :reason " (asnQuote reason) ")"))
    ((smokeFailed reason) (str "(:modalError :smokeFailed :reason " (asnQuote reason) ")"))
    ((renderFailed path reason) (str "(:modalError :renderFailed :path " (asnQuote path) " :reason " (asnQuote reason) ")"))
    ((lifecycleFailed op code detail) (str "(:modalError :lifecycleFailed :op " op " :code " (stringFromInt64 code) " :detail " (asnQuote detail) ")")))


fn lowerAlphabet -> String
  "abcdefghijklmnopqrstuvwxyz"

fn upperAlphabet -> String
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

fn digitAlphabet -> String
  "0123456789"

fn allIn? s: String alphabet: String -> Bool
  (listAll? (fn [(c String)] -> Bool (stringContains? alphabet c)) (stringChars s))

fn dnsName? s: String -> Bool
  (and (not (stringEmpty? s))
    (and (stringContains? (lowerAlphabet) (optionOr (stringSlice s 0 1) ""))
      (and (not (stringEndsWith? s "-")) (allIn? s (str (lowerAlphabet) (digitAlphabet) "-")))))

fn tokenName? s: String -> Bool
  (and (not (stringEmpty? s)) (allIn? s (str (lowerAlphabet) (upperAlphabet) (digitAlphabet) "._-")))

fn repoName? s: String -> Bool
  (and (tokenName? (stringReplace s "/" "")) (and (= (listLength (stringSplit s "/")) 2) (not (stringContains? s ".."))))

fn relativePath? s: String -> Bool
  (and (tokenName? (stringReplace s "/" "")) (and (not (stringStartsWith? s "/")) (not (stringContains? s ".."))))

fn envName? s: String -> Bool
  (and (not (stringEmpty? s))
    (and (stringContains? (str (upperAlphabet) "_") (optionOr (stringSlice s 0 1) ""))
      (allIn? s (str (upperAlphabet) (digitAlphabet) "_"))))

fn cudaArch? s: String -> Bool
  (and (not (stringEmpty? s)) (allIn? s (str (lowerAlphabet) (digitAlphabet) ";-")))

fn versionText? s: String -> Bool
  (and (not (stringEmpty? s)) (and (allIn? s (str (digitAlphabet) "."))
    (and (stringContains? (digitAlphabet) (optionOr (stringSlice s 0 1) ""))
      (and (not (stringEndsWith? s ".")) (not (stringContains? s ".."))))))

fn decimalText? s: String -> Bool
  (and (versionText? s) (<= (listLength (stringSplit s ".")) 2))

fn imageRef? s: String -> Bool
  (let [(parts (stringSplit s ":"))]
    (and (= (listLength parts) 2)
      (and (allIn? s (str (lowerAlphabet) (digitAlphabet) "./:_-"))
        (and (not (stringEmpty? (optionOr (listGet parts 0) "")))
          (let [(tag (optionOr (listGet parts 1) ""))]
            (and (not (stringEmpty? tag)) (!= tag "latest")))))))

fn pinSpec? s: String -> Bool
  (let [(parts (stringSplit s "=="))]
    (and (= (listLength parts) 2)
      (and (tokenName? (optionOr (listGet parts 0) ""))
        (versionText? (optionOr (listGet parts 1) "")))))

fn modalGpus -> (List String)
  (list "T4" "L4" "A10" "A10G" "L40S" "A100" "A100-40GB" "A100-80GB" "H100" "H200" "B200" "RTX-PRO-6000")

fn engines -> (List String)
  (list "prismLlamaCpp" "vllmBonsai")

fn presetFields -> (List String)
  (list "v" "id" "doc" "app" "modalVersion" "baseImage" "python" "packages" "preparePackages"
        "model" "revision" "weightFile" "servedName" "engine" "engineRef" "cudaArch" "sampling"
        "contextTokens" "maxTokens" "reasoning" "scaledownSec" "startupSec" "snapshot" "maxContainers" "coldStartMs"
        "volume" "secret" "keyEnv" "tokenizerRepo" "tokenizerRevision" "convertedDir" "gpus" "pool")

fn bonsaiTernaryFile -> String
  "Ternary-Bonsai-2-27B-PTQ1_0.gguf"


fn atomText e: rd/SExpr -> (Option String)
  (mt e
    ((rd/sexprAtom v) (some v))
    (_ (none)))

fn keyName k: rd/SExpr -> (Option String)
  (mt (atomText k)
    ((some v) (if (and (> (stringLength v) 1) (stringStartsWith? v ":")) (some (optionOr (stringSlice v 1 (stringLength v)) "")) (none)))
    ((none) (none)))

fn pairsLoop items: (List rd/SExpr) what: String acc: (Map String rd/SExpr) -> (Result (Map String rd/SExpr) ModalError)
  (mt (listHead items)
    ((none) (ok acc))
    ((some k)
      (mt (listGet items 1)
        ((none) (err (presetShape (str what " has a key without a value"))))
        ((some v)
          (mt (keyName k)
            ((none) (err (presetShape (str what " expects :key value pairs"))))
            ((some name)
              (if (mapHas? acc name)
                (err (presetShape (str what " repeats :" name)))
                (pairsLoop (listDrop items 2) what (mapSet acc name v)))))))))

fn propsOf e: rd/SExpr head: String what: String -> (Result (Map String rd/SExpr) ModalError)
  (mt e
    ((rd/sexprList items)
      (mt (listHead items)
        ((some h) (if (= (optionOr (atomText h) "") head)
                    (pairsLoop (listDrop items 1) what (mapEmpty))
                    (err (presetShape (str "expected (" head " ...) for " what)))))
        ((none) (err (presetShape (str "expected (" head " ...) for " what))))))
    (_ (err (presetShape (str "expected (" head " ...) for " what)))))

fn plistOf e: rd/SExpr field: String what: String -> (Result (Map String rd/SExpr) ModalError)
  (mt e
    ((rd/sexprList items) (pairsLoop items what (mapEmpty)))
    (_ (err (fieldType field "list"))))

fn firstOutside keys: (List String) allowed: (List String) -> (Option String)
  (mt (listHead keys)
    ((none) (none))
    ((some k) (if (listContains? allowed k) (firstOutside (listDrop keys 1) allowed) (some k))))

fn unknownField props: (Map String rd/SExpr) allowed: (List String) -> (Option String)
  (firstOutside (mapKeys props) allowed)

fn rawField props: (Map String rd/SExpr) name: String -> (Result rd/SExpr ModalError)
  (mt (mapGet props name)
    ((some v) (ok v))
    ((none) (err (fieldMissing name))))

fn stringValue name: String e: rd/SExpr -> (Result String ModalError)
  (mt (atomText e)
    ((some v)
      (let [(n (stringLength v))]
        (if (and (>= n 2) (and (stringStartsWith? v "\"") (stringEndsWith? v "\"")))
          (let [(inner (optionOr (stringSlice v 1 (- n 1)) ""))]
            (if (or (stringContains? inner "\\") (stringContains? inner "\""))
              (err (fieldType name "stringWithoutEscapes"))
              (ok inner)))
          (err (fieldType name "string")))))
    ((none) (err (fieldType name "string"))))

fn stringField props: (Map String rd/SExpr) name: String -> (Result String ModalError)
  (mt (rawField props name)
    ((err e) (err e))
    ((ok v) (stringValue name v)))

fn optionalStringField props: (Map String rd/SExpr) name: String -> (Result String ModalError)
  (if (mapHas? props name) (stringField props name) (ok ""))

fn atomValue name: String e: rd/SExpr -> (Result String ModalError)
  (mt (atomText e)
    ((some v) (if (or (stringEmpty? v) (or (stringStartsWith? v "\"") (stringStartsWith? v ":")))
                (err (fieldType name "atom"))
                (ok v)))
    ((none) (err (fieldType name "atom"))))

fn atomField props: (Map String rd/SExpr) name: String -> (Result String ModalError)
  (mt (rawField props name)
    ((err e) (err e))
    ((ok v) (atomValue name v)))

fn intValue name: String e: rd/SExpr minimum: Int64 -> (Result Int64 ModalError)
  (mt (atomText e)
    ((some v)
      (if (not (allIn? v (str (digitAlphabet) "-")))
        (err (fieldType name "integer"))
        (mt (stringToInt64 v)
          ((some n) (if (< n minimum) (err (fieldRange name n (str ">= " (stringFromInt64 minimum)))) (ok n)))
          ((none) (err (fieldType name "integer"))))))
    ((none) (err (fieldType name "integer"))))

fn intField props: (Map String rd/SExpr) name: String minimum: Int64 -> (Result Int64 ModalError)
  (mt (rawField props name)
    ((err e) (err e))
    ((ok v) (intValue name v minimum)))

fn boolField props: (Map String rd/SExpr) name: String -> (Result Bool ModalError)
  (mt (rawField props name)
    ((err e) (err e))
    ((ok v)
      (mt (atomText v)
        ((some a) (cond ((= a "true") (ok true)) ((= a "false") (ok false)) (else (err (fieldType name "bool")))))
        ((none) (err (fieldType name "bool"))))))


fn parseTier e: rd/SExpr weightFile: String -> (Result GpuTier ModalError)
  (mt (plistOf e "gpus" "a :gpus entry")
    ((err x) (err x))
    ((ok props)
      (mt (unknownField props (list "tier" "maxConcurrency" "timeoutSec" "microUsdPerSec" "weightFile"))
        ((some k) (err (fieldUnknown (str "gpus." k))))
        ((none)
          (mt (atomField props "tier")
            ((err x) (err x))
            ((ok tier)
              (if (not (listContains? (modalGpus) tier))
                (err (gpuUnknown tier))
                (mt (intField props "maxConcurrency" 1)
                  ((err x) (err x))
                  ((ok conc)
                    (mt (intField props "timeoutSec" 1)
                      ((err x) (err x))
                      ((ok timeout)
                        (mt (intField props "microUsdPerSec" 1)
                          ((err x) (err (rename x "gpus.")))
                          ((ok price)
                            (mt (named "gpus.weightFile" (if (mapHas? props "weightFile") (stringField props "weightFile") (ok weightFile)) tokenName?)
                              ((err x) (err x))
                              ((ok file) (ok (GpuTier :tier tier :maxConcurrency conc :timeoutSec timeout :microUsdPerSec price :weightFile file)))))))))))))))))

fn tiersLoop items: (List rd/SExpr) weightFile: String acc: (List GpuTier) -> (Result (List GpuTier) ModalError)
  (mt (listHead items)
    ((none) (ok acc))
    ((some e)
      (mt (parseTier e weightFile)
        ((err x) (err x))
        ((ok t)
          (if (listAny? (fn [(o GpuTier)] -> Bool (= o.tier t.tier)) acc)
            (err (gpuDuplicate t.tier))
            (tiersLoop (listDrop items 1) weightFile (listAppend acc (list t))))))))

fn parseLadder props: (Map String rd/SExpr) weightFile: String -> (Result (List GpuTier) ModalError)
  (mt (rawField props "gpus")
    ((err x) (err x))
    ((ok e)
      (mt e
        ((rd/sexprList items) (if (listEmpty? items) (err (ladderEmpty)) (tiersLoop items weightFile (list))))
        (_ (err (fieldType "gpus" "list"))))))

fn parsePool props: (Map String rd/SExpr) -> (Result PoolSettings ModalError)
  (mt (rawField props "pool")
    ((err x) (err x))
    ((ok e)
      (mt (plistOf e "pool" "the :pool list")
        ((err x) (err x))
        ((ok pool)
          (mt (unknownField pool (list "windowMs" "peakCount" "bypassWhileBusy"))
            ((some k) (err (fieldUnknown (str "pool." k))))
            ((none)
              (mt (intField pool "windowMs" 1)
                ((err x) (err (rename x "pool.")))
                ((ok window)
                  (mt (intField pool "peakCount" 1)
                    ((err x) (err (rename x "pool.")))
                    ((ok peak)
                      (mt (boolField pool "bypassWhileBusy")
                        ((err x) (err (rename x "pool.")))
                        ((ok bypass) (ok (PoolSettings :windowMs window :peakCount peak :bypassWhileBusy bypass))))))))))))))

fn rename e: ModalError prefix: String -> ModalError
  (mt e
    ((fieldMissing f) (fieldMissing (str prefix f)))
    ((fieldType f x) (fieldType (str prefix f) x))
    ((fieldRange f v b) (fieldRange (str prefix f) v b))
    (_ e))

fn decimalField props: (Map String rd/SExpr) name: String -> (Result String ModalError)
  (mt (rawField props name)
    ((err x) (err x))
    ((ok v)
      (mt (atomText v)
        ((some a) (if (decimalText? a) (ok a) (err (fieldType name "decimal"))))
        ((none) (err (fieldType name "decimal"))))))

fn parseSampling props: (Map String rd/SExpr) -> (Result (Option Sampling) ModalError)
  (mt (mapGet props "sampling")
    ((none) (ok (none)))
    ((some e)
      (mt (plistOf e "sampling" "the :sampling list")
        ((err x) (err x))
        ((ok sp)
          (mt (unknownField sp (list "temperature" "topP" "topK" "minP"))
            ((some k) (err (fieldUnknown (str "sampling." k))))
            ((none)
              (let [(temperature (decimalField sp "temperature"))
                    (topP (decimalField sp "topP"))
                    (topK (intField sp "topK" 1))
                    (minP (decimalField sp "minP"))]
                (mt (firstError (list (errS temperature) (errS topP) (errI topK) (errS minP)))
                  ((some x) (err (rename x "sampling.")))
                  ((none) (ok (some (Sampling :temperature (valS temperature) :topP (valS topP) :topK (valI topK) :minP (valS minP)))))))))))))

fn pinsLoop items: (List rd/SExpr) field: String acc: (List String) -> (Result (List String) ModalError)
  (mt (listHead items)
    ((none) (ok acc))
    ((some e)
      (mt (stringValue field e)
        ((err x) (err x))
        ((ok v) (if (pinSpec? v) (pinsLoop (listDrop items 1) field (listAppend acc (list v))) (err (nameInvalid field v)))))))

fn pinsField props: (Map String rd/SExpr) name: String -> (Result (List String) ModalError)
  (mt (rawField props name)
    ((err x) (err x))
    ((ok e)
      (mt e
        ((rd/sexprList items) (pinsLoop items name (list)))
        (_ (err (fieldType name "list"))))))


fn tierFilesAre? tiers: (List GpuTier) file: String -> (Option String)
  (mt (listHead tiers)
    ((none) (none))
    ((some t) (if (= t.weightFile file) (tierFilesAre? (listDrop tiers 1) file) (some t.tier))))

fn engineRules p: ModalPreset -> (Result ModalPreset ModalError)
  (cond
    ((= p.engine "prismLlamaCpp")
      (cond
        ((not (cudaArch? p.cudaArch)) (err (engineNeeds "prismLlamaCpp" "cudaArch" "the fork builds with -DCMAKE_CUDA_ARCHITECTURES (KNOWN_ISSUES #182)")))
        ((not (stringEmpty? p.convertedDir)) (err (engineNeeds "prismLlamaCpp" "convertedDir" "pre-converted safetensors are a vllmBonsai input")))
        ((not (stringContains? p.baseImage "-devel-")) (err (engineNeeds "prismLlamaCpp" "baseImage" "the fork is compiled in the image, which needs a CUDA -devel- base with nvcc")))
        (else (ok p))))
    ((= p.engine "vllmBonsai")
      (cond
        ((not (repoName? p.tokenizerRepo)) (err (engineNeeds "vllmBonsai" "tokenizerRepo" "the GGUF repo ships no config.json or tokenizer files")))
        ((!= p.servedName "bonsai2-27b") (err (engineNeeds "vllmBonsai" "servedName" "serve_bonsai.py fixes --served-model-name bonsai2-27b")))
        ((and (not (stringEmpty? p.convertedDir)) (not (relativePath? p.convertedDir))) (err (nameInvalid "convertedDir" p.convertedDir)))
        ((not (listAny? (fn [(x String)] -> Bool (stringStartsWith? x "vllm==")) p.packages)) (err (engineNeeds "vllmBonsai" "packages" "the port needs a pinned vllm==version")))
        ((some? p.sampling) (err (engineNeeds "vllmBonsai" "sampling" "serve_bonsai.py takes no sampling flags; vLLM reads generation_config.json")))
        ((!= p.weightFile (bonsaiTernaryFile)) (err (engineNeeds "vllmBonsai" "weightFile" "serve_bonsai.py --ternary loads Ternary-Bonsai-2-27B-PTQ1_0.gguf only")))
        (else
          (mt (tierFilesAre? p.gpus (bonsaiTernaryFile))
            ((some tier) (err (engineNeeds "vllmBonsai" (str "gpus." tier ".weightFile") "serve_bonsai.py --ternary loads Ternary-Bonsai-2-27B-PTQ1_0.gguf only")))
            ((none) (ok p))))))
    (else (err (engineUnknown p.engine))))

fn limits p: ModalPreset -> (Result ModalPreset ModalError)
  (cond
    ((and p.reasoning (< p.maxTokens 8192)) (err (fieldRange "maxTokens" p.maxTokens ">= 8192 for a reasoning model")))
    ((<= p.contextTokens p.maxTokens) (err (fieldRange "contextTokens" p.contextTokens (str "> maxTokens " (stringFromInt64 p.maxTokens)))))
    ((> (stringLength p.app) 40) (err (nameInvalid "app" p.app)))
    (else (ok p)))

fn errS r: (Result String ModalError) -> (Option ModalError)
  (mt r ((err x) (some x)) ((ok _) (none)))

fn errI r: (Result Int64 ModalError) -> (Option ModalError)
  (mt r ((err x) (some x)) ((ok _) (none)))

fn errB r: (Result Bool ModalError) -> (Option ModalError)
  (mt r ((err x) (some x)) ((ok _) (none)))

fn errL r: (Result (List String) ModalError) -> (Option ModalError)
  (mt r ((err x) (some x)) ((ok _) (none)))

fn errO r: (Result (Option Sampling) ModalError) -> (Option ModalError)
  (mt r ((err x) (some x)) ((ok _) (none)))

fn valL r: (Result (List String) ModalError) -> (List String)
  (mt r ((ok v) v) ((err _) (list)))

fn valS r: (Result String ModalError) -> String
  (mt r ((ok v) v) ((err _) ""))

fn valI r: (Result Int64 ModalError) -> Int64
  (mt r ((ok v) v) ((err _) 0))

fn valB r: (Result Bool ModalError) -> Bool
  (mt r ((ok v) v) ((err _) false))

fn named name: String r: (Result String ModalError) good: (Fn [String] Bool) -> (Result String ModalError)
  (mt r
    ((err x) (err x))
    ((ok v) (if (good v) (ok v) (err (nameInvalid name v)))))

fn engineField props: (Map String rd/SExpr) -> (Result String ModalError)
  (mt (atomField props "engine")
    ((err x) (err x))
    ((ok e) (if (listContains? (engines) e) (ok e) (err (engineUnknown e)))))

fn versionField props: (Map String rd/SExpr) -> (Result Int64 ModalError)
  (mt (intField props "v" 1)
    ((err x) (err x))
    ((ok v) (if (= v 2) (ok v) (err (fieldRange "v" v "= 2")))))

fn optionalName name: String r: (Result String ModalError) good: (Fn [String] Bool) -> (Result String ModalError)
  (mt r
    ((err x) (err x))
    ((ok v) (if (or (stringEmpty? v) (good v)) (ok v) (err (nameInvalid name v)))))

fn firstError xs: (List (Option ModalError)) -> (Option ModalError)
  (mt (listHead xs)
    ((none) (none))
    ((some o) (mt o ((some x) (some x)) ((none) (firstError (listDrop xs 1))))))

fn presetFrom props: (Map String rd/SExpr) -> (Result ModalPreset ModalError)
  (mt (unknownField props (presetFields))
    ((some k) (err (fieldUnknown k)))
    ((none)
      (let [(version (versionField props))
            (id (named "id" (atomField props "id") tokenName?))
            (app (named "app" (stringField props "app") dnsName?))
            (modalVersion (named "modalVersion" (stringField props "modalVersion") versionText?))
            (baseImage (named "baseImage" (stringField props "baseImage") imageRef?))
            (python (named "python" (stringField props "python") decimalText?))
            (packages (pinsField props "packages"))
            (preparePackages (pinsField props "preparePackages"))
            (model (named "model" (stringField props "model") repoName?))
            (revision (named "revision" (stringField props "revision") tokenName?))
            (weightFile (named "weightFile" (stringField props "weightFile") tokenName?))
            (servedName (named "servedName" (stringField props "servedName") tokenName?))
            (engine (engineField props))
            (engineRef (named "engineRef" (stringField props "engineRef") tokenName?))
            (cudaArch (optionalStringField props "cudaArch"))
            (sampling (parseSampling props))
            (contextTokens (intField props "contextTokens" 1))
            (maxTokens (intField props "maxTokens" 1))
            (reasoning (boolField props "reasoning"))
            (scaledownSec (intField props "scaledownSec" 1))
            (startupSec (intField props "startupSec" 1))
            (snapshot (boolField props "snapshot"))
            (maxContainers (if (mapHas? props "maxContainers") (intField props "maxContainers" 1) (ok 1)))
            (coldStartMs (intField props "coldStartMs" 1))
            (volume (named "volume" (stringField props "volume") dnsName?))
            (secret (named "secret" (stringField props "secret") dnsName?))
            (keyEnv (named "keyEnv" (atomField props "keyEnv") envName?))
            (tokenizerRepo (optionalStringField props "tokenizerRepo"))
            (tokenizerRevision (optionalName "tokenizerRevision" (optionalStringField props "tokenizerRevision") tokenName?))
            (convertedDir (optionalStringField props "convertedDir"))
            (first (firstError (list (errI version) (errS id) (errS app) (errS modalVersion) (errS baseImage) (errS python)
                                   (errL packages) (errL preparePackages) (errS model) (errS revision) (errS weightFile)
                                   (errS servedName) (errS engine) (errS engineRef) (errS cudaArch) (errO sampling) (errI contextTokens)
                                   (errI maxTokens) (errB reasoning) (errI scaledownSec) (errI startupSec) (errB snapshot)
                                   (errI maxContainers) (errI coldStartMs) (errS volume) (errS secret) (errS keyEnv) (errS tokenizerRepo)
                                   (errS tokenizerRevision) (errS convertedDir))))]
        (mt first
          ((some x) (err x))
          (_
            (cond
              ((listEmpty? (valL preparePackages)) (err (fieldRange "preparePackages" 0 ">= 1 pinned package")))
              (else
                (mt (parseLadder props (valS weightFile))
                  ((err x) (err x))
                  ((ok gpus)
                    (mt (parsePool props)
                      ((err x) (err x))
                      ((ok pool)
                        (mt (limits (ModalPreset :id (valS id) :app (valS app) :modalVersion (valS modalVersion)
                                      :baseImage (valS baseImage) :python (valS python) :packages (valL packages)
                                      :preparePackages (valL preparePackages) :model (valS model) :revision (valS revision)
                                      :weightFile (valS weightFile) :servedName (valS servedName) :engine (valS engine)
                                      :engineRef (valS engineRef) :cudaArch (valS cudaArch) :sampling (mt sampling ((ok v) v) ((err _) (none)))
                                      :contextTokens (valI contextTokens)
                                      :maxTokens (valI maxTokens) :reasoning (valB reasoning) :scaledownSec (valI scaledownSec)
                                      :startupSec (valI startupSec) :snapshot (valB snapshot) :maxContainers (valI maxContainers)
                                      :coldStartMs (valI coldStartMs) :volume (valS volume) :secret (valS secret) :keyEnv (valS keyEnv)
                                      :tokenizerRepo (valS tokenizerRepo) :tokenizerRevision (valS tokenizerRevision)
                                      :convertedDir (valS convertedDir) :gpus gpus :pool pool))
                          ((err x) (err x))
                          ((ok p) (engineRules p))))))))))))))

fn modalPresetParse text: String -> (Result ModalPreset ModalError)
  (mt (ast/readForms (lx/tokenize text))
    ((err e) (err (presetSyntax e.line e.col e.msg)))
    ((ok forms)
      (if (!= (listLength forms) 1)
        (err (presetShape (str "expected one (:modalPreset ...) form, found " (stringFromInt64 (listLength forms)))))
        (mt (listHead forms)
          ((some f) (mt (propsOf f.expr ":modalPreset" "the preset") ((err x) (err x)) ((ok props) (presetFrom props))))
          ((none) (err (presetShape "expected one (:modalPreset ...) form, found 0")))))))

fn ! modalPresetLoad! path: String -> (Result ModalPreset ModalError)
  (mt (fileReadString path)
    ((err e) (err (presetUnreadable path e)))
    ((ok text) (modalPresetParse text)))

fn tierIn tiers: (List GpuTier) tier: String -> (Result GpuTier ModalError)
  (mt (listHead tiers)
    ((none) (err (gpuAbsent tier)))
    ((some t) (if (= t.tier tier) (ok t) (tierIn (listDrop tiers 1) tier))))

fn modalTier p: ModalPreset tier: String -> (Result GpuTier ModalError)
  (tierIn p.gpus tier)


fn modalAppName p: ModalPreset t: GpuTier -> String
  (str p.app "-" (stringLower t.tier))

fn boolText b: Bool -> String
  (if b "true" "false")

fn modalAppEnv presetPath: String t: GpuTier -> (List (Pair String String))
  (list (pair "ASL_MODAL_PRESET" presetPath)
        (pair "ASL_MODAL_TIER" t.tier))

fn samplingJson s: (Option Sampling) -> j/Json
  (mt s
    ((none) (j/jnull))
    ((some x) (j/jobj (list (pair "minP" (j/jstr x.minP)) (pair "temperature" (j/jstr x.temperature))
                            (pair "topK" (j/jint x.topK)) (pair "topP" (j/jstr x.topP))))))

fn modalAppSettings p: ModalPreset t: GpuTier -> String
  (let [(strs (fn [(xs (List String))] -> j/Json (j/jarr (map (fn [(x String)] -> j/Json (j/jstr x)) xs))))]
    (j/jsonEmit (j/jobj (list (pair "app" (j/jstr (modalAppName p t)))
                              (pair "baseImage" (j/jstr p.baseImage))
                              (pair "contextTokens" (j/jint p.contextTokens))
                              (pair "convertedDir" (j/jstr p.convertedDir))
                              (pair "cudaArch" (j/jstr p.cudaArch))
                              (pair "engine" (j/jstr p.engine))
                              (pair "engineRef" (j/jstr p.engineRef))
                              (pair "gpu" (j/jstr t.tier))
                              (pair "keyEnv" (j/jstr p.keyEnv))
                              (pair "maxBatch" (j/jint t.maxConcurrency))
                              (pair "maxContainers" (j/jint p.maxContainers))
                              (pair "modalVersion" (j/jstr p.modalVersion))
                              (pair "model" (j/jstr p.model))
                              (pair "packages" (strs p.packages))
                              (pair "preparePackages" (strs p.preparePackages))
                              (pair "python" (j/jstr p.python))
                              (pair "revision" (j/jstr p.revision))
                              (pair "sampling" (samplingJson p.sampling))
                              (pair "scaledownSec" (j/jint p.scaledownSec))
                              (pair "secret" (j/jstr p.secret))
                              (pair "servedName" (j/jstr p.servedName))
                              (pair "snapshot" (j/jbool p.snapshot))
                              (pair "startupSec" (j/jint p.startupSec))
                              (pair "timeoutSec" (j/jint t.timeoutSec))
                              (pair "tokenizerRepo" (j/jstr p.tokenizerRepo))
                              (pair "tokenizerRevision" (j/jstr p.tokenizerRevision))
                              (pair "volume" (j/jstr p.volume))
                              (pair "weightFile" (j/jstr t.weightFile))))))

fn modalCli p: ModalPreset -> (List String)
  (list "uvx" "--from" (str "modal==" p.modalVersion) "modal")

fn envArgv presetPath: String t: GpuTier -> (List String)
  (listAppend (list "env") (map (fn [(kv (Pair String String))] -> String (str (pairFirst kv) "=" (pairSecond kv))) (modalAppEnv presetPath t)))

fn modalDeployArgv p: ModalPreset t: GpuTier presetPath: String appPath: String -> (List String)
  (listAppend (listAppend (envArgv presetPath t) (modalCli p)) (list "deploy" appPath))

fn modalPrepareArgv p: ModalPreset t: GpuTier presetPath: String appPath: String -> (List String)
  (listAppend (listAppend (envArgv presetPath t) (modalCli p)) (list "run" (str appPath "::prepare")))

fn modalStopArgv p: ModalPreset t: GpuTier -> (List String)
  (listAppend (modalCli p) (list "app" "stop" "--yes" (modalAppName p t)))

fn modalStatusArgv p: ModalPreset -> (List String)
  (listAppend (modalCli p) (list "app" "list" "--json"))

fn shellWord w: String -> String
  (if (and (not (stringEmpty? w)) (allIn? w (str (lowerAlphabet) (upperAlphabet) (digitAlphabet) "_./:=,@%+-")))
    w
    (str "'" (stringReplace w "'" "'\\''") "'"))

fn modalCommandLine argv: (List String) -> String
  (stringJoin (map shellWord argv) " ")

fn modalBaseUrl p: ModalPreset t: GpuTier workspace: String -> (Result String ModalError)
  (if (not (dnsName? workspace))
    (err (nameInvalid "workspace" workspace))
    (ok (str "https://" workspace "--" (modalAppName p t) ".modal.run/v1")))

fn modalGatewayEntry p: ModalPreset t: GpuTier workspace: String -> (Result String ModalError)
  (mt (modalBaseUrl p t workspace)
    ((err x) (err x))
    ((ok base)
      (let [(pool p.pool)
            (capacity (* t.maxConcurrency p.maxContainers))
            (peak (min pool.peakCount capacity))
            (timeout (stringFromInt64 t.timeoutSec))]
        (ok (str "(:provider :id modal :kind openai :base \"" base "\" :keyEnv " p.keyEnv " :timeoutSec " timeout
                 " :pool (:windowMs " (stringFromInt64 pool.windowMs) " :peakCount " (stringFromInt64 peak)
                 " :bypassWhileBusy " (boolText pool.bypassWhileBusy) " :requestTimeoutMs " (stringFromInt64 (* 1000 t.timeoutSec)) "))\n"
                 "(:model :id " p.id " :provider modal :name \"" p.servedName "\" :maxTokens " (stringFromInt64 p.maxTokens)
                 " :timeoutSec " timeout " :reasoning " (boolText p.reasoning) ")\n")))))


fn modalCapabilities p: ModalPreset t: GpuTier -> pg/PluginCapabilities
  (pg/followingRedirects
    (pg/openaiCompatCapabilities (* t.maxConcurrency p.maxContainers)
      (pg/serverless p.scaledownSec p.coldStartMs)
      (pg/perGpuSecond (map (fn [(g GpuTier)] -> (Pair String Float64) (pair g.tier (/ (int64ToFloat64 g.microUsdPerSec) 1000000.0))) p.gpus))
      (list))
    150)

fn modalCapabilityText p: ModalPreset t: GpuTier -> String
  (let [(c (modalCapabilities p t))]
    (str "(:capability :plugin modal :endpoint " (modalAppName p t) " :api openaiChat :batching continuous"
         " :maxConcurrency " (stringFromInt64 c.maxConcurrency)
         " :streaming " (boolText c.streaming) " :tools " (boolText c.tools) " :json " (boolText c.json)
         " :scaleModel (:serverless :idleTimeoutSec " (stringFromInt64 p.scaledownSec) " :coldStartMs " (stringFromInt64 p.coldStartMs) ")"
         " :priceModel (:perGpuSecond :usd (" (stringJoin (map (fn [(g GpuTier)] -> String (str "(" g.tier " " (stringFromInt64 g.microUsdPerSec) "e-6)")) p.gpus) " ") "))"
         " :lifecycle (deploy start stop status))"))

fn modalStartCost p: ModalPreset t: GpuTier -> Int64
  (/ (* t.microUsdPerSec (+ p.coldStartMs (* 1000 p.scaledownSec))) 1000)

fn modalVersionTag p: ModalPreset -> String
  (str "modal==" p.modalVersion " " p.engine "@" p.engineRef)

fn modalLifecycleRequest p: ModalPreset t: GpuTier unit: String -> pg/LifecycleRequest
  (pg/LifecycleRequest :endpoint (modalAppName p t) :model p.id :gpu t.tier :region "" :version (modalVersionTag p)
                       :unit unit :expectedCost (modalStartCost p t))

fn opName op: ModalOp -> String
  (mt op ((opDeploy) "deploy") ((opStart) "start") ((opStop) "stop") ((opStatus) "status"))

fn modalLifecycleArgv op: ModalOp p: ModalPreset t: GpuTier presetPath: String appPath: String workspace: String -> (Result (List String) ModalError)
  (mt op
    ((opDeploy) (ok (modalDeployArgv p t presetPath appPath)))
    ((opStop) (ok (modalStopArgv p t)))
    ((opStatus) (ok (modalStatusArgv p)))
    ((opStart)
      (mt (modalBaseUrl p t workspace)
        ((err x) (err x))
        ((ok base)
          (ok (list "curl" "-sS" "-o" "/dev/null" "-w" "%{http_code}" "--max-time" (stringFromInt64 (/ p.coldStartMs 1000))
                    (str (optionOr (stringSlice base 0 (- (stringLength base) 3)) "") "/health")))))))

fn requestError p: ModalPreset t: GpuTier r: pg/LifecycleRequest -> (Option String)
  (cond
    ((!= r.endpoint (modalAppName p t)) (some (str "endpoint " r.endpoint " is not " (modalAppName p t))))
    ((!= r.gpu t.tier) (some (str "gpu " r.gpu " is not the deployed tier " t.tier)))
    ((and (!= r.model p.id) (!= r.model p.servedName)) (some (str "model " r.model " is not " p.id)))
    ((!= r.version (modalVersionTag p)) (some (str "version " r.version " is not the pinned " (modalVersionTag p))))
    (else (none)))

fn jsonStrOr v: (Option j/Json) -> String
  (optionOr (jsonText v) "")

fn liveRow? row: j/Json -> Bool
  (let [(state (jsonStrOr (j/jsonGet row "state")))]
    (and (!= state "stopped") (!= state "disabled")))

fn modalStatusFrom p: ModalPreset t: GpuTier out: String -> (Result pg/LifecycleStatus String)
  (mt (j/jsonParse out)
    ((err e) (err (str "modal app list --json is not JSON: " e)))
    ((ok doc)
      (mt doc
        ((j/jarr rows)
          (let [(name (modalAppName p t))
                (mine (filter (fn [(row j/Json)] -> Bool (= (jsonStrOr (j/jsonGet row "description")) name)) rows))
                (live (filter liveRow? mine))]
            (mt (listHead live)
              ((none) (ok (pg/LifecycleStatus :endpoint name :state (pg/down) :detail (if (listEmpty? mine) "not deployed" "stopped"))))
              ((some row)
                (let [(state (jsonStrOr (j/jsonGet row "state")))
                      (tasks (optionOr (stringToInt64 (jsonStrOr (j/jsonGet row "tasks"))) 0))
                      (detail (str state " tasks " (stringFromInt64 tasks)))]
                  (ok (pg/LifecycleStatus :endpoint name :detail detail
                        :state (cond
                                 ((stringStartsWith? state "stopping") (pg/draining))
                                 ((stringStartsWith? state "initializing") (pg/warming))
                                 ((> tasks 0) (pg/warm))
                                 (else (pg/cold))))))))))
        (_ (err "modal app list --json is not a JSON array")))))

fn ! runOp! op: ModalOp p: ModalPreset t: GpuTier presetPath: String appPath: String workspace: String run: (Fn [(List String)] (Result la/Captured String)) -> (Result String String)
  (mt (modalLifecycleArgv op p t presetPath appPath workspace)
    ((err x) (err (modalErrorText x)))
    ((ok argv)
      (mt (run argv)
        ((err e) (err (modalErrorText (lifecycleFailed (opName op) -1 e))))
        ((ok c) (if (= c.code 0)
                  (ok (stringTrim c.out))
                  (err (modalErrorText (lifecycleFailed (opName op) c.code (stringTrim c.errText)))))))))

fn ! lifecycleOp! op: ModalOp p: ModalPreset t: GpuTier presetPath: String appDir: String workspace: String run: (Fn [(List String)] (Result la/Captured String)) r: pg/LifecycleRequest -> (Result pg/LifecycleStatus String)
  (mt (requestError p t r)
    ((some e) (err e))
    ((none)
      (let [(name (modalAppName p t))
            (appPath (str appDir "/app.py"))]
        (mt op
          ((opDeploy)
            (mt (modalRenderApp! appDir)
              ((err x) (err (modalErrorText x)))
              ((ok app) (mt (runOp! op p t presetPath app workspace run)
                          ((err e) (err e))
                          ((ok _) (ok (pg/LifecycleStatus :endpoint name :state (pg/cold) :detail "deployed; scales from zero")))))))
          ((opStart)
            (mt (runOp! op p t presetPath appPath workspace run)
              ((err e) (err e))
              ((ok code) (ok (pg/LifecycleStatus :endpoint name :state (if (= code "200") (pg/warm) (pg/warming)) :detail (str "health " code))))))
          ((opStop)
            (mt (runOp! op p t presetPath appPath workspace run)
              ((err e) (err e))
              ((ok _) (ok (pg/LifecycleStatus :endpoint name :state (pg/down) :detail "stopped")))))
          ((opStatus)
            (mt (runOp! op p t presetPath appPath workspace run)
              ((err e) (err e))
              ((ok out) (modalStatusFrom p t out))))))))

fn ! modalLifecycle p: ModalPreset t: GpuTier presetPath: String appDir: String workspace: String run: (Fn [(List String)] (Result la/Captured String)) -> pg/Lifecycle
  (pg/Lifecycle
    :deploy (fn [(r pg/LifecycleRequest)] -> (Result pg/LifecycleStatus String) (lifecycleOp! (opDeploy) p t presetPath appDir workspace run r))
    :start (fn [(r pg/LifecycleRequest)] -> (Result pg/LifecycleStatus String) (lifecycleOp! (opStart) p t presetPath appDir workspace run r))
    :stop (fn [(r pg/LifecycleRequest)] -> (Result pg/LifecycleStatus String) (lifecycleOp! (opStop) p t presetPath appDir workspace run r))
    :status (fn [(r pg/LifecycleRequest)] -> (Result pg/LifecycleStatus String) (lifecycleOp! (opStatus) p t presetPath appDir workspace run r)))

fn modalRow p: ModalPreset t: GpuTier base: String -> up/UpstreamProvider
  (up/UpstreamProvider :id "modal" :prefixes (list "modal/") :names (list p.servedName)
    :url (fn [(st up/UpstreamSettings) (env (Map String String))] -> String base)
    :key (fn [(st up/UpstreamSettings) (env (Map String String))] -> String (optionOr (mapGet env p.keyEnv) ""))
    :timeoutSec (fn [(st up/UpstreamSettings)] -> Float64 (int64ToFloat64 t.timeoutSec)))

fn ! runArgv! argv: (List String) -> (Result la/Captured String)
  (la/runCapture! argv (none) (none))

fn ! modalPluginWith! p: ModalPreset t: GpuTier presetPath: String appDir: String workspace: String st: up/UpstreamSettings run: (Fn [(List String)] (Result la/Captured String)) -> (Result pg/Plugin String)
  (mt (modalBaseUrl p t workspace)
    ((err x) (err (modalErrorText x)))
    ((ok base) (pg/openaiCompat (modalRow p t base) st (modalCapabilities p t) (some (modalLifecycle p t presetPath appDir workspace run)))))

fn ! modalPlugin! p: ModalPreset t: GpuTier presetPath: String workspace: String st: up/UpstreamSettings -> (Result pg/Plugin String)
  (mt (modalAppDir! p t)
    ((err x) (err (modalErrorText x)))
    ((ok dir) (modalPluginWith! p t presetPath dir workspace st runArgv!)))


fn modalChatBody p: ModalPreset messages: (List (Pair String String)) maxTokens: Int64 -> String
  (j/jsonEmit (j/jobj (list (pair "model" (j/jstr p.servedName))
                            (pair "messages" (j/jarr (map (fn [(m (Pair String String))] -> j/Json
                                                            (j/jobj (list (pair "role" (j/jstr (pairFirst m))) (pair "content" (j/jstr (pairSecond m))))))
                                                          messages)))
                            (pair "max_tokens" (j/jint (if (> maxTokens 0) maxTokens p.maxTokens))))))

fn jsonText v: (Option j/Json) -> (Option String)
  (mt v
    ((some x) (mt x ((j/jstr s) (some s)) (_ (none))))
    ((none) (none)))

fn jsonInt v: (Option j/Json) -> (Option Int64)
  (mt v
    ((some x) (mt x ((j/jint n) (some n)) (_ (none))))
    ((none) (none)))

fn firstChoice body: j/Json -> (Option j/Json)
  (mt (j/jsonGet body "choices")
    ((some x) (mt x ((j/jarr xs) (listHead xs)) (_ (none))))
    ((none) (none)))

fn modalParseReply status: Int64 body: String maxTokens: Int64 -> (Result ChatReply ModalError)
  (cond
    ((= status 303) (err (endpointRedirect "Modal answers 303 after its 150 s web request limit; the transport must follow the redirect to the result URL")))
    ((!= status 200) (err (endpointStatus status body)))
    (else
    (mt (j/jsonParse body)
      ((err e) (err (endpointReply (str "body is not JSON: " e))))
      ((ok doc)
        (mt (firstChoice doc)
          ((none) (err (endpointReply "reply has no choices[0]")))
          ((some choice)
            (mt (j/jsonGet choice "message")
              ((none) (err (endpointReply "choices[0] has no message")))
              ((some message)
                (let [(content (optionOr (jsonText (j/jsonGet message "content")) ""))
                      (reasoning (optionOr (jsonText (j/jsonGet message "reasoning_content")) (optionOr (jsonText (j/jsonGet message "reasoning")) "")))
                      (finish (optionOr (jsonText (j/jsonGet choice "finish_reason")) ""))
                      (tokens (mt (j/jsonGet doc "usage") ((some u) (optionOr (jsonInt (j/jsonGet u "completion_tokens")) 0)) ((none) 0)))]
                  (if (and (stringEmpty? (stringTrim content)) (= finish "length"))
                    (err (reasoningTruncated maxTokens))
                    (ok (ChatReply :content content :reasoning reasoning :finishReason finish :completionTokens tokens))))))))))))

fn ! modalChatWith! baseUrl: String key: String body: String maxTokens: Int64 timeoutSec: Float64 env: (Map String String) call: (Fn [up/UpstreamRequest (Map String String) Float64] (Result up/UpstreamResponse up/UpstreamFailure)) -> (Result ChatReply ModalError)
  (mt (up/upstreamRequest baseUrl "/chat/completions" key body (list (pair "Content-Type" "application/json")))
    ((err e) (err (endpointTransport e)))
    ((ok req)
      (mt (call req env timeoutSec)
        ((ok resp) (modalParseReply resp.status resp.body maxTokens))
        ((err failure)
          (mt failure
            ((up/httpFailure status reason text) (err (endpointStatus status text)))
            ((up/transportFailure code text) (err (endpointTransport (str "curl exit " (stringFromInt64 code) ": " (stringTrim text)))))
            ((up/toolAbsent tool detail) (err (endpointTransport (str tool ": " detail))))
            ((up/protocolFailure detail) (err (endpointTransport detail))))))))

fn ! modalChat! baseUrl: String key: String body: String maxTokens: Int64 timeoutSec: Float64 env: (Map String String) -> (Result ChatReply ModalError)
  (modalChatWith! baseUrl key body maxTokens timeoutSec env up/callUpstream!)


fn modalConfig p: ModalPreset t: GpuTier workspace: String capMicroUsd: Int64 -> (Result String ModalError)
  (cond
    ((< capMicroUsd 1) (err (fieldRange "cap" capMicroUsd ">= 1 microUSD")))
    (else
      (mt (modalGatewayEntry p t workspace)
        ((err x) (err x))
        ((ok entry)
          (let [(lines (stringSplit (stringTrim entry) "\n"))
                (name (modalAppName p t))
                (cap (stringFromInt64 capMicroUsd))]
            (ok (str "(:gatewayAdditions :for \"" name "\" :unit microUsd\n"
                     " :providers (" (optionOr (listGet lines 0) "") ")\n"
                     " :models (" (optionOr (listGet lines 1) "") ")\n"
                     " :endpoints [(:endpoint :id \"" name "\" :provider \"modal\" :model \"" p.servedName "\" :admission concurrencyCap :maxConcurrency "
                     (stringFromInt64 (* t.maxConcurrency p.maxContainers)) ")]\n"
                     " :budget (:budgetConfig :lines [(:line :id \"" name "Day\" :scope :endpoint :key \"" name "\" :period :day :cap " cap " :approved true)]"
                     " :approvals [(:approval :endpoint \"" name "\" :cap " cap ")]))")))))))

(schema SmokeIo
  (:f run (fn [(List String)] -> (Result la/Captured String)))
  (:f call (fn [up/UpstreamRequest (Map String String) Float64] -> (Result up/UpstreamResponse up/UpstreamFailure)))
  (:f nowMs (fn [] -> Int64))
  (:f sleep (fn [Int64] -> Unit))
  (:f env (Map String String)))

fn smokeChatSec -> Int64
  120

fn modalSmokeWorstCost p: ModalPreset t: GpuTier -> Int64
  (* t.microUsdPerSec (+ p.startupSec (+ (* 2 (smokeChatSec)) p.scaledownSec)))

fn ! smokeArg args: (List String) flag: String -> (Option String)
  (mt (listHead args)
    ((none) (none))
    ((some a) (if (= a flag) (listGet args 1) (smokeArg (listDrop args 1) flag))))

fn ! modalSmokeGate p: ModalPreset t: GpuTier args: (List String) -> (Result Int64 ModalError)
  (cond
    ((not (listContains? args "--yes")) (err (smokeRefused "smoke starts a GPU container and spends money: pass --yes")))
    (else
      (mt (mt (smokeArg args "--cap") ((some c) (stringToInt64 c)) ((none) (none)))
        ((none) (err (smokeRefused "pass --cap MICROUSD, the most this smoke may spend")))
        ((some cap)
          (let [(worst (modalSmokeWorstCost p t))]
            (if (< cap worst)
              (err (smokeRefused (str "worst case " (stringFromInt64 worst) " microUSD exceeds --cap " (stringFromInt64 cap))))
              (ok cap)))))))

fn ! waitHealthy! io: SmokeIo argv: (List String) startMs: Int64 limitMs: Int64 -> (Result Int64 ModalError)
  (mt (io.run argv)
    ((err e) (err (lifecycleFailed "smoke" -1 e)))
    ((ok c)
      (let [(now (io.nowMs))]
        (cond
          ((and (= c.code 0) (= (stringTrim c.out) "200")) (ok now))
          ((> (- now startMs) limitMs) (err (smokeFailed (str "no 200 from /health within " (stringFromInt64 (/ limitMs 1000)) " s; last " (stringTrim c.out) (stringTrim c.errText)))))
          (else (do (io.sleep 1000) (waitHealthy! io argv startMs limitMs)))))))

fn smokeBody p: ModalPreset maxTokens: Int64 -> String
  (j/jsonEmit (j/jobj (list (pair "model" (j/jstr p.id))
                            (pair "messages" (j/jarr (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr "Reply with the single word OK.")))))))
                            (pair "max_tokens" (j/jint maxTokens)))))

fn ! smokeChat! io: SmokeIo gatewayUrl: String p: ModalPreset maxTokens: Int64 -> (Result (Pair Int64 Int64) ModalError)
  (mt (up/upstreamRequest gatewayUrl "/chat/completions" (optionOr (mapGet io.env "ASL_GATEWAY_KEY") "") (smokeBody p maxTokens) (list (pair "Content-Type" "application/json")))
    ((err e) (err (endpointTransport e)))
    ((ok req)
      (let [(start (io.nowMs))]
        (mt (io.call req io.env (int64ToFloat64 (smokeChatSec)))
          ((err f) (err (smokeFailed (str "chat through " gatewayUrl " failed"))))
          ((ok resp)
            (if (!= resp.status 200)
              (err (endpointStatus resp.status resp.body))
              (mt (j/jsonParse resp.body)
                ((err e) (err (endpointReply (str "body is not JSON: " e))))
                ((ok doc)
                  (let [(tokens (mt (j/jsonGet doc "usage") ((some u) (optionOr (jsonInt (j/jsonGet u "completion_tokens")) 0)) ((none) 0)))]
                    (ok (pair (- (io.nowMs) start) tokens)))))))))))

fn tenths n: Int64 -> String
  (str (stringFromInt64 (/ n 10)) "." (stringFromInt64 (- n (* 10 (/ n 10)))))

fn ! modalSmokeWith! p: ModalPreset t: GpuTier workspace: String gatewayUrl: String args: (List String) io: SmokeIo -> (Result String ModalError)
  (mt (modalSmokeGate p t args)
    ((err x) (err x))
    ((ok cap)
      (mt (io.run (modalStatusArgv p))
        ((err e) (err (lifecycleFailed "status" -1 e)))
        ((ok c)
          (mt (modalStatusFrom p t c.out)
            ((err e) (err (smokeFailed e)))
            ((ok status)
              (mt status.state
                ((pg/down) (err (smokeRefused (str (modalAppName p t) " is down (" status.detail "): deploy it first"))))
                (_
                  (let [(wasCold (mt status.state ((pg/cold) true) (_ false)))]
                    (mt (modalLifecycleArgv (opStart) p t "" "" workspace)
                      ((err x) (err x))
                      ((ok probe)
                        (let [(t0 (io.nowMs))]
                          (mt (waitHealthy! io probe t0 (* 1000 p.startupSec))
                            ((err x) (err x))
                            ((ok t1)
                              (mt (smokeChat! io gatewayUrl p 1)
                                ((err x) (err x))
                                ((ok first)
                                  (mt (smokeChat! io gatewayUrl p 256)
                                    ((err x) (err x))
                                    ((ok second)
                                      (let [(elapsed (max 1 (pairFirst second)))
                                            (tokS10 (/ (* (pairSecond second) 10000) elapsed))
                                            (billedMs (+ (- (io.nowMs) t0) (* 1000 p.scaledownSec)))
                                            (cost (/ (+ (* t.microUsdPerSec billedMs) 999) 1000))]
                                        (ok (str "(:modalSmoke :endpoint " (modalAppName p t) " :wasCold " (boolText wasCold)
                                                 " :coldStartMs " (stringFromInt64 (if wasCold (- t1 t0) -1))
                                                 " :firstTokenMs " (stringFromInt64 (pairFirst first))
                                                 " :tokS " (tenths tokS10) " :completionTokens " (stringFromInt64 (pairSecond second))
                                                 " :costMicroUsd " (stringFromInt64 cost) " :capMicroUsd " (stringFromInt64 cap) ")")))))))))))))))))))))

fn ! smokeIo! -> SmokeIo
  (SmokeIo :run runArgv! :call up/callUpstream!
           :nowMs (fn [] -> Int64 (/ (nowNs) 1000000))
           :sleep (fn [(ms Int64)] -> Unit (sleepMs ms))
           :env (mapFromPairs (filter (fn [(kv (Pair String String))] -> Bool (not (stringEmpty? (pairSecond kv))))
                                      (list (pair "PATH" (optionOr (envGet "PATH") "/usr/bin:/bin"))
                                            (pair "ASL_GATEWAY_KEY" (optionOr (envGet "ASL_GATEWAY_KEY") ""))
                                            (pair "SSL_CERT_FILE" (optionOr (envGet "SSL_CERT_FILE") ""))))))


fn modalAppLines -> (List String)
  (list
        "\"\"\"Modal app serving one asl-modal preset behind an OpenAI-compatible /v1/chat/completions."
        ""
        "Rendered by asl/packages/asl-modal/src/modal.asl (modalRenderApp!) under ~/.asl/run/modal; never tracked."
        ""
        "The preset file named by ASL_MODAL_PRESET is the one place every version is pinned; src/modal.asl"
        "validates it and renders the deploy command, and this app reads the same file for the tier named by"
        "ASL_MODAL_TIER. `python3 app.py --settings PRESET TIER` prints the settings derived here without"
        "importing modal, and the ASL test compares them with modalAppSettings. Deploying spends money: run"
        "the rendered command only after the principal's explicit yes."
        "\"\"\""
        ""
        "import json"
        "import os"
        "import subprocess"
        "import sys"
        "import time"
        "import urllib.error"
        "import urllib.request"
        ""
        "ENGINES = (\"prismLlamaCpp\", \"vllmBonsai\")"
        "ENGINE_PORT = 8000"
        "WEIGHTS_ROOT = \"/weights\""
        "LLAMA_DIR = \"/opt/llama.cpp\""
        "VLLM_PORT_DIR = \"/opt/bonsai2-vllm\""
        "PRESET_IN_IMAGE = \"/asl/preset.asn\""
        ""
        ""
        "def asn_tokens(text):"
        "    tokens, i, n = [], 0, len(text)"
        "    while i < n:"
        "        c = text[i]"
        "        if c in \" \\t\\r\\n,\":"
        "            i += 1"
        "        elif c == \";\":"
        "            while i < n and text[i] != \"\\n\":"
        "                i += 1"
        "        elif c in \"()[]\":"
        "            tokens.append(c)"
        "            i += 1"
        "        elif c == '\"':"
        "            j, out = i + 1, []"
        "            while j < n and text[j] != '\"':"
        "                if text[j] == \"\\\\\" and j + 1 < n:"
        "                    j += 1"
        "                out.append(text[j])"
        "                j += 1"
        "            if j >= n:"
        "                raise ValueError(\"preset: unterminated string\")"
        "            tokens.append((\"str\", \"\".join(out)))"
        "            i = j + 1"
        "        else:"
        "            j = i"
        "            while j < n and text[j] not in \" \\t\\r\\n,;()[]\\\"\":"
        "                j += 1"
        "            tokens.append((\"atom\", text[i:j]))"
        "            i = j"
        "    return tokens"
        ""
        ""
        "def asn_read(text):"
        "    \"\"\"Nested lists of strings: a quoted string and an atom both read as their text.\"\"\""
        "    stack = [[]]"
        "    for token in asn_tokens(text):"
        "        if token in (\"(\", \"[\"):"
        "            stack.append([])"
        "        elif token in (\")\", \"]\"):"
        "            if len(stack) == 1:"
        "                raise ValueError(\"preset: unmatched closing delimiter\")"
        "            done = stack.pop()"
        "            stack[-1].append(done)"
        "        else:"
        "            stack[-1].append(token[1])"
        "    if len(stack) != 1:"
        "        raise ValueError(\"preset: unclosed list\")"
        "    return stack[0]"
        ""
        ""
        "def plist(items, what):"
        "    if len(items) % 2:"
        "        raise ValueError(f\"preset: {what} has a key without a value\")"
        "    props = {}"
        "    for key, value in zip(items[0::2], items[1::2]):"
        "        if not isinstance(key, str) or not key.startswith(\":\"):"
        "            raise ValueError(f\"preset: {what} expects :key value pairs\")"
        "        props[key[1:]] = value"
        "    return props"
        ""
        ""
        "def load_settings(path, tier):"
        "    with open(path, encoding=\"utf-8\") as handle:"
        "        forms = asn_read(handle.read())"
        "    if len(forms) != 1 or not isinstance(forms[0], list) or not forms[0] or forms[0][0] != \":modalPreset\":"
        "        raise ValueError(\"preset: expected one (:modalPreset ...) form\")"
        "    p = plist(forms[0][1:], \"the preset\")"
        "    tiers = [plist(entry, \"a :gpus entry\") for entry in p[\"gpus\"]]"
        "    matches = [t for t in tiers if t[\"tier\"] == tier]"
        "    if len(matches) != 1:"
        "        raise ValueError(f\"preset: tier {tier} is not in the ladder\")"
        "    t = matches[0]"
        "    sampling = None"
        "    if \"sampling\" in p:"
        "        s = plist(p[\"sampling\"], \"the :sampling list\")"
        "        sampling = {\"minP\": s[\"minP\"], \"temperature\": s[\"temperature\"], \"topK\": int(s[\"topK\"]), \"topP\": s[\"topP\"]}"
        "    return {"
        "        \"app\": f\"{p['app']}-{tier.lower()}\","
        "        \"baseImage\": p[\"baseImage\"],"
        "        \"contextTokens\": int(p[\"contextTokens\"]),"
        "        \"convertedDir\": p.get(\"convertedDir\", \"\"),"
        "        \"cudaArch\": p.get(\"cudaArch\", \"\"),"
        "        \"engine\": p[\"engine\"],"
        "        \"engineRef\": p[\"engineRef\"],"
        "        \"gpu\": tier,"
        "        \"keyEnv\": p[\"keyEnv\"],"
        "        \"maxBatch\": int(t[\"maxConcurrency\"]),"
        "        \"maxContainers\": int(p.get(\"maxContainers\", \"1\")),"
        "        \"modalVersion\": p[\"modalVersion\"],"
        "        \"model\": p[\"model\"],"
        "        \"packages\": list(p[\"packages\"]),"
        "        \"preparePackages\": list(p[\"preparePackages\"]),"
        "        \"python\": p[\"python\"],"
        "        \"revision\": p[\"revision\"],"
        "        \"sampling\": sampling,"
        "        \"scaledownSec\": int(p[\"scaledownSec\"]),"
        "        \"secret\": p[\"secret\"],"
        "        \"servedName\": p[\"servedName\"],"
        "        \"snapshot\": p[\"snapshot\"] == \"true\","
        "        \"startupSec\": int(p[\"startupSec\"]),"
        "        \"timeoutSec\": int(t[\"timeoutSec\"]),"
        "        \"tokenizerRepo\": p.get(\"tokenizerRepo\", \"\"),"
        "        \"tokenizerRevision\": p.get(\"tokenizerRevision\", \"\"),"
        "        \"volume\": p[\"volume\"],"
        "        \"weightFile\": t.get(\"weightFile\", p[\"weightFile\"]),"
        "    }"
        ""
        ""
        "if __name__ == \"__main__\":"
        "    if len(sys.argv) != 4 or sys.argv[1] != \"--settings\":"
        "        sys.stderr.write(\"usage: python3 app.py --settings PRESET TIER\\n\")"
        "        sys.exit(2)"
        "    print(json.dumps(load_settings(sys.argv[2], sys.argv[3]), sort_keys=True, separators=(\",\", \":\")))"
        "    sys.exit(0)"
        ""
        "import modal  # noqa: E402  (after the --settings exit, so that check needs no Modal client)"
        ""
        "S = load_settings(os.environ[\"ASL_MODAL_PRESET\"], os.environ[\"ASL_MODAL_TIER\"])"
        "ENGINE = S[\"engine\"]"
        "if ENGINE not in ENGINES:"
        "    raise RuntimeError(f\"engine must be one of {ENGINES}, found {ENGINE!r}; validate the preset with asl-modal\")"
        "if modal.__version__ != S[\"modalVersion\"]:"
        "    raise RuntimeError(f\"preset pins modal=={S['modalVersion']} but {modal.__version__} is running; deploy with the rendered uvx command\")"
        "MODEL_DIR = f\"{WEIGHTS_ROOT}/{S['model']}/{S['revision']}\""
        "CONVERTED_DIR = f\"{WEIGHTS_ROOT}/{S['convertedDir']}\" if S[\"convertedDir\"] else \"\""
        "IMAGE_ENV = {\"ASL_MODAL_PRESET\": PRESET_IN_IMAGE, \"ASL_MODAL_TIER\": S[\"gpu\"]}"
        ""
        ""
        "def with_preset(image):"
        "    \"\"\"The container re-imports this file, so it gets the same preset, mounted last at container start.\"\"\""
        "    return image.add_local_file(os.environ[\"ASL_MODAL_PRESET\"], PRESET_IN_IMAGE)"
        ""
        ""
        "def engine_image():"
        "    base = modal.Image.from_registry(S[\"baseImage\"], add_python=S[\"python\"]).entrypoint([])"
        "    ref = S[\"engineRef\"]"
        "    if ENGINE == \"prismLlamaCpp\":"
        "        return with_preset("
        "            base.apt_install(\"git\", \"cmake\", \"build-essential\")"
        "            .run_commands("
        "                f\"git clone --depth 1 --branch {ref} https://github.com/PrismML-Eng/llama.cpp {LLAMA_DIR}\","
        "                f\"cmake -S {LLAMA_DIR} -B {LLAMA_DIR}/build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON\""
        "                f\" -DLLAMA_CURL=OFF '-DCMAKE_CUDA_ARCHITECTURES={S['cudaArch']}'\","
        "                f\"cmake --build {LLAMA_DIR}/build -j --target llama-server\","
        "            )"
        "            .env(IMAGE_ENV)"
        "        )"
        "    return with_preset("
        "        base.apt_install(\"git\")"
        "        .uv_pip_install(*S[\"packages\"])"
        "        .run_commands("
        "            f\"git clone https://github.com/shtjww/bonsai2-vllm {VLLM_PORT_DIR}\","
        "            f\"git -C {VLLM_PORT_DIR} checkout {ref}\","
        "        )"
        "        .env({**IMAGE_ENV, \"PYTHONPATH\": VLLM_PORT_DIR, \"VLLM_SERVER_DEV_MODE\": \"1\", \"TORCHINDUCTOR_COMPILE_THREADS\": \"1\"})"
        "    )"
        ""
        ""
        "app = modal.App(S[\"app\"])"
        "weights = modal.Volume.from_name(S[\"volume\"], create_if_missing=True)"
        "prepare_image = with_preset("
        "    modal.Image.debian_slim(python_version=S[\"python\"]).uv_pip_install(*S[\"preparePackages\"]).env(IMAGE_ENV)"
        ")"
        ""
        ""
        "@app.function(image=prepare_image, volumes={WEIGHTS_ROOT: weights}, timeout=3600)"
        "def prepare():"
        "    \"\"\"Download the tier's weights into the volume once, so containers load them without network.\"\"\""
        "    from huggingface_hub import hf_hub_download, snapshot_download"
        ""
        "    hf_hub_download(S[\"model\"], S[\"weightFile\"], revision=S[\"revision\"], local_dir=MODEL_DIR)"
        "    if ENGINE == \"vllmBonsai\":"
        "        snapshot_download("
        "            S[\"tokenizerRepo\"],"
        "            revision=S[\"tokenizerRevision\"] or None,"
        "            local_dir=MODEL_DIR,"
        "            allow_patterns=[\"config.json\", \"generation_config.json\", \"tokenizer*\", \"vocab.json\", \"merges.txt\","
        "                            \"special_tokens_map.json\", \"chat_template*\"],"
        "        )"
        "    weights.commit()"
        "    return MODEL_DIR"
        ""
        ""
        "def engine_command(api_key):"
        "    if ENGINE == \"prismLlamaCpp\":"
        "        argv = ["
        "            f\"{LLAMA_DIR}/build/bin/llama-server\","
        "            \"-m\", f\"{MODEL_DIR}/{S['weightFile']}\","
        "            \"--host\", \"0.0.0.0\", \"--port\", str(ENGINE_PORT),"
        "            \"-ngl\", \"99\", \"-fa\", \"on\","
        "            \"-c\", str(S[\"contextTokens\"] * S[\"maxBatch\"]), \"-np\", str(S[\"maxBatch\"]),"
        "            \"--alias\", S[\"servedName\"], \"--jinja\", \"--api-key\", api_key,"
        "        ]"
        "        if S[\"sampling\"]:"
        "            sampling = S[\"sampling\"]"
        "            argv += [\"--temp\", sampling[\"temperature\"], \"--top-p\", sampling[\"topP\"],"
        "                     \"--top-k\", str(sampling[\"topK\"]), \"--min-p\", sampling[\"minP\"]]"
        "        return argv, None, dict(os.environ)"
        "    argv = ["
        "        \"python\", f\"{VLLM_PORT_DIR}/vllm_bonsai/serve_bonsai.py\","
        "        \"--gguf-dir\", CONVERTED_DIR or MODEL_DIR, \"--ternary\", \"--port\", str(ENGINE_PORT),"
        "        \"--gpu-memory-utilization\", \"0.85\", \"--dtype\", \"float16\", \"--max-model-len\", str(S[\"contextTokens\"]),"
        "    ]"
        "    if CONVERTED_DIR:"
        "        argv.append(\"--from-safetensors\")"
        "    return argv, VLLM_PORT_DIR, {**os.environ, \"VLLM_API_KEY\": api_key}"
        ""
        ""
        "def wait_ready(process, deadline_sec):"
        "    deadline = time.monotonic() + deadline_sec"
        "    url = f\"http://127.0.0.1:{ENGINE_PORT}/health\""
        "    last = \"no answer\""
        "    while time.monotonic() < deadline:"
        "        code = process.poll()"
        "        if code is not None:"
        "            raise RuntimeError(f\"engine {ENGINE} exited with {code} before it was ready\")"
        "        try:"
        "            with urllib.request.urlopen(url, timeout=5) as response:"
        "                if response.status == 200:"
        "                    return"
        "                last = f\"status {response.status}\""
        "        except urllib.error.HTTPError as failure:"
        "            last = f\"status {failure.code}\""
        "        except OSError as failure:"
        "            last = str(failure)"
        "        time.sleep(1)"
        "    raise RuntimeError(f\"engine {ENGINE} not ready after {deadline_sec}s: {last}\")"
        ""
        ""
        "def vllm_post(path):"
        "    \"\"\"vLLM sleep mode (VLLM_SERVER_DEV_MODE=1): weights leave the GPU before the snapshot and return after it.\"\"\""
        "    request = urllib.request.Request(f\"http://127.0.0.1:{ENGINE_PORT}{path}\", data=b\"\", method=\"POST\")"
        "    with urllib.request.urlopen(request, timeout=300) as response:"
        "        if response.status != 200:"
        "            raise RuntimeError(f\"vLLM {path} answered {response.status}\")"
        ""
        ""
        "@app.cls("
        "    image=engine_image(),"
        "    gpu=S[\"gpu\"],"
        "    volumes={WEIGHTS_ROOT: weights},"
        "    secrets=[modal.Secret.from_name(S[\"secret\"])],"
        "    scaledown_window=S[\"scaledownSec\"],"
        "    timeout=S[\"timeoutSec\"],"
        "    startup_timeout=S[\"startupSec\"],"
        "    min_containers=0,"
        "    max_containers=S[\"maxContainers\"],"
        "    enable_memory_snapshot=S[\"snapshot\"],"
        "    experimental_options={\"enable_gpu_snapshot\": True} if S[\"snapshot\"] else None,"
        ")"
        "@modal.concurrent(max_inputs=S[\"maxBatch\"])"
        "class Server:"
        "    @modal.enter(snap=S[\"snapshot\"])"
        "    def start(self):"
        "        api_key = os.environ.get(S[\"keyEnv\"], \"\")"
        "        if not api_key:"
        "            raise RuntimeError(f\"secret {S['secret']} carries no {S['keyEnv']}\")"
        "        argv, cwd, env = engine_command(api_key)"
        "        self.process = subprocess.Popen(argv, cwd=cwd, env=env)"
        "        wait_ready(self.process, S[\"startupSec\"])"
        "        if S[\"snapshot\"] and ENGINE == \"vllmBonsai\":"
        "            vllm_post(\"/sleep?level=1\")"
        ""
        "    @modal.enter(snap=False)"
        "    def check(self):"
        "        if S[\"snapshot\"] and ENGINE == \"vllmBonsai\":"
        "            vllm_post(\"/wake_up\")"
        "        wait_ready(self.process, S[\"startupSec\"])"
        ""
        "    @modal.web_server(port=ENGINE_PORT, startup_timeout=S[\"startupSec\"], label=S[\"app\"])"
        "    def serve(self):"
        "        return None"
        ""
        "    @modal.exit()"
        "    def stop(self):"
        "        self.process.terminate()"
        "        try:"
        "            self.process.wait(timeout=30)"
        "        except subprocess.TimeoutExpired:"
        "            self.process.kill()"
        "            self.process.wait()")

fn modalAppSource -> String
  (str (stringJoin (modalAppLines) "\n") "\n")

fn ! dirReady? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isDir) ((err _) false))

fn ! ensureDirs! done: String parts: (List String) -> (Result Unit ModalError)
  (mt (listHead parts)
    ((none) (ok ()))
    ((some part)
      (let [(path (str done "/" part))]
        (if (or (stringEmpty? part) (dirReady? path))
          (ensureDirs! (if (stringEmpty? part) done path) (listDrop parts 1))
          (mt (dirCreate path)
            ((err e) (if (dirReady? path) (ensureDirs! path (listDrop parts 1)) (err (renderFailed path e))))
            ((ok _) (ensureDirs! path (listDrop parts 1))))))))

fn ! modalAppDir! p: ModalPreset t: GpuTier -> (Result String ModalError)
  (mt (envGet "HOME")
    ((none) (err (renderFailed "HOME" "unset")))
    ((some home) (if (stringStartsWith? home "/") (ok (str home "/.asl/run/modal/" (modalAppName p t))) (err (renderFailed "HOME" home)))))

fn ! modalRenderApp! dir: String -> (Result String ModalError)
  (if (not (stringStartsWith? dir "/"))
    (err (renderFailed dir "absolute directory expected"))
    (mt (ensureDirs! "" (stringSplit (optionOr (stringSlice dir 1 (stringLength dir)) "") "/"))
      ((err x) (err x))
      ((ok _)
        (let [(path (str dir "/app.py"))]
          (mt (fileWrite path (modalAppSource))
            ((err e) (err (renderFailed path e)))
            ((ok _) (ok path)))))))


fn usage -> String
  "(:usage \"bin/asl run asl/packages/asl-modal/src/modal.asl app|env|settings|deploy|prepare|stop|status|gateway|capability PRESET TIER [WORKSPACE] | config PRESET TIER WORKSPACE CAP_MICROUSD | smoke PRESET TIER WORKSPACE GATEWAY_URL --cap MICROUSD --yes\")"

fn ! render! cmd: String p: ModalPreset t: GpuTier presetPath: String rest: (List String) -> (Result String ModalError)
  (cond
    ((or (= cmd "app") (or (= cmd "deploy") (= cmd "prepare")))
      (mt (modalAppDir! p t)
        ((err x) (err x))
        ((ok dir)
          (mt (modalRenderApp! dir)
            ((err x) (err x))
            ((ok app) (cond
                        ((= cmd "deploy") (ok (modalCommandLine (modalDeployArgv p t presetPath app))))
                        ((= cmd "prepare") (ok (modalCommandLine (modalPrepareArgv p t presetPath app))))
                        (else (ok app))))))))
    ((= cmd "env") (ok (stringJoin (map (fn [(kv (Pair String String))] -> String (str (pairFirst kv) "=" (shellWord (pairSecond kv)))) (modalAppEnv presetPath t)) "\n")))
    ((= cmd "settings") (ok (modalAppSettings p t)))
    ((= cmd "stop") (ok (modalCommandLine (modalStopArgv p t))))
    ((= cmd "status") (ok (modalCommandLine (modalStatusArgv p))))
    ((= cmd "capability") (ok (modalCapabilityText p t)))
    ((= cmd "config") (mt (listGet rest 0)
                        ((none) (err (fieldMissing "workspace")))
                        ((some ws) (mt (mt (listGet rest 1) ((some c) (stringToInt64 c)) ((none) (none)))
                                     ((none) (err (fieldMissing "cap")))
                                     ((some cap) (modalConfig p t ws cap))))))
    ((= cmd "smoke") (mt (listGet rest 0)
                       ((none) (err (fieldMissing "workspace")))
                       ((some ws) (mt (listGet rest 1)
                                    ((none) (err (fieldMissing "gatewayUrl")))
                                    ((some gw) (modalSmokeWith! p t ws gw (listDrop rest 2) (smokeIo!)))))))
    ((= cmd "gateway") (mt (listHead rest)
                         ((some ws) (mt (modalGatewayEntry p t ws) ((ok s) (ok (stringTrim s))) ((err x) (err x))))
                         ((none) (err (fieldMissing "workspace")))))
    (else (err (presetShape (usage)))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (listGet args 0)
    ((none) (do (fdWrite 2 (str (usage) "\n")) (ok 2)))
    ((some cmd)
      (mt (listGet args 1)
        ((none) (do (fdWrite 2 (str (usage) "\n")) (ok 2)))
        ((some path)
          (mt (mt (modalPresetLoad! path)
                ((err x) (err x))
                ((ok p) (mt (modalTier p (optionOr (listGet args 2) (optionOr (listHead p.gpus) (GpuTier :tier "" :maxConcurrency 0 :timeoutSec 0 :microUsdPerSec 0 :weightFile "")).tier))
                          ((err x) (err x))
                          ((ok t) (render! cmd p t path (listDrop args 3))))))
            ((ok text) (do (fdWrite 1 (str text "\n")) (ok 0)))
            ((err x) (do (fdWrite 2 (str (modalErrorText x) "\n")) (ok 1))))))))
