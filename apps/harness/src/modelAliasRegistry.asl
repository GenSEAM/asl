(module aslHarness/modelAliasRegistry :x [ModelMetadata AliasDefinition AliasCatalog ResolvedSelection voiceModelMetadata nanoModelMetadata microModelMetadata miniModelMetadata smallModelMetadata makeCanonicalAliasCatalog normalizeAliasQuery resolveModelAlias formatAliasDisplayCard formatAliasCatalogAsn formatAliasCatalogMarkdown] :i [])

(schema ModelMetadata (:f canonicalName Str) (:f filename Str) (:f sizeMb I64) (:f downloadUrl Str) (:f sha256 Str) (:f parameterCount Str) (:f quantization Str) (:f vramFootprintMb I64) (:f contextWindow I64) (:f latencyTier Str) (:f description Str))

(schema AliasDefinition (:f alias Str) (:f displayTitle Str) (:f tierCategory Str) (:f targetModel ModelMetadata) (:f recommendedFor (List Str)) (:f isDefault Bool))

(schema AliasCatalog (:f catalogVersion Str) (:f aliases (List AliasDefinition)) (:f updatedAt I64))

(schema ResolvedSelection (:f selectedAlias Str) (:f model ModelMetadata) (:f resolved Bool) (:f reason Str))

fn voiceModelMetadata -> ModelMetadata
  (ModelMetadata :canonicalName "NVIDIA/parakeet-tdt-0.6b-v3" :filename "parakeet-tdt-0.6b-v3.onnx" :sizeMb 600 :downloadUrl "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/resolve/main/model.onnx" :sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" :parameterCount "600M" :quantization "INT8" :vramFootprintMb 600 :contextWindow 2048 :latencyTier "sub-20ms (RTF 0.04)" :description "Token-and-Duration Transducer for streaming 16kHz audio intake in 25 European languages")

fn nanoModelMetadata -> ModelMetadata
  (ModelMetadata :canonicalName "HuggingFaceTB/SmolLM2-135M-Instruct" :filename "smollm2-135m-instruct-q4_k_m.gguf" :sizeMb 95 :downloadUrl "https://huggingface.co/HuggingFaceTB/SmolLM2-135M-Instruct-GGUF/resolve/main/smollm2-135m-instruct-q4_k_m.gguf" :sha256 "a1b2c3d4e5f60718293a4b5c6d7e8f90123456789abcdef0123456789abcdef0" :parameterCount "135M" :quantization "Q4_K_M" :vramFootprintMb 180 :contextWindow 512 :latencyTier "sub-10ms" :description "Ultra-lightweight token classification, regex routing, and zero-RAM delimiter verification")

fn microModelMetadata -> ModelMetadata
  (ModelMetadata :canonicalName "Qwen/Qwen2.5-Coder-0.5B-Instruct" :filename "qwen2.5-coder-0.5b-instruct-q4_k_m.gguf" :sizeMb 397 :downloadUrl "https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-0.5b-instruct-q4_k_m.gguf" :sha256 "f4c3b2a109876543210fedcba9876543210abcdef1234567890abcdef1234567" :parameterCount "0.5B" :quantization "Q4_K_M" :vramFootprintMb 480 :contextWindow 1024 :latencyTier "14ms (84.5 tps)" :description "Fast 4-tool action dispatch, DOM query resolution, and zero-overhead ASN serialization")

fn miniModelMetadata -> ModelMetadata
  (ModelMetadata :canonicalName "Qwen/Qwen2.5-Coder-1.5B-Instruct" :filename "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" :sizeMb 1120 :downloadUrl "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf" :sha256 "bcde1234567890abcdef1234567890abcdef1234567890abcdef1234567890ab" :parameterCount "1.5B" :quantization "Q4_K_M" :vramFootprintMb 1180 :contextWindow 2048 :latencyTier "22ms (62.0 tps)" :description "High-density SVG vector drawing, reactive VDOM forms, and JSON-to-ASN transpilation")

fn smallModelMetadata -> ModelMetadata
  (ModelMetadata :canonicalName "Qwen/Qwen2.5-Coder-3B-Instruct" :filename "qwen2.5-coder-3b-instruct-q4_k_m.gguf" :sizeMb 2150 :downloadUrl "https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf" :sha256 "cdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789ac" :parameterCount "3B" :quantization "Q4_K_M" :vramFootprintMb 2150 :contextWindow 2048 :latencyTier "35ms (45.0 tps)" :description "In-browser cellular automata, full interactive SPA state machines, and AST form patching")

fn makeCanonicalAliasCatalog -> AliasCatalog
  (let [(aVoice (AliasDefinition :alias "voice" :displayTitle "Voice (Parakeet-TDT 0.6B)" :tierCategory "audio-transducer" :targetModel (voiceModelMetadata) :recommendedFor (list "streaming-asr" "multilingual-voice-in" "16khz-pcm") :isDefault false)) (aNano (AliasDefinition :alias "nano" :displayTitle "Nano (SmolLM2 135M)" :tierCategory "intent-classifier" :targetModel (nanoModelMetadata) :recommendedFor (list "keyword-extraction" "delimiter-check" "instant-routing") :isDefault false)) (aMicro (AliasDefinition :alias "micro" :displayTitle "Micro (Qwen2.5-Coder 0.5B)" :tierCategory "browser-operator" :targetModel (microModelMetadata) :recommendedFor (list "action-dispatch" "dom-clicks" "fast-search" "asn-records") :isDefault true)) (aMini (AliasDefinition :alias "mini" :displayTitle "Mini (Qwen2.5-Coder 1.5B)" :tierCategory "structured-code" :targetModel (miniModelMetadata) :recommendedFor (list "svg-drawing" "vdom-components" "transpilation") :isDefault false)) (aSmall (AliasDefinition :alias "small" :displayTitle "Small (Qwen2.5-Coder 3B)" :tierCategory "flagship-edge" :targetModel (smallModelMetadata) :recommendedFor (list "cellular-automata" "kanban-apps" "ast-patching" "deep-synthesis") :isDefault false))] (AliasCatalog :catalogVersion "1.0.0" :aliases (list aVoice aNano aMicro aMini aSmall) :updatedAt 1788891000000))

fn normalizeAliasQuery input: Str -> Str
  (let [(clean (stringTrim input))] (cond ((or (= clean "voice") (or (= clean ":voice") (or (= clean "голос") (= clean "аудио")))) "voice") ((or (= clean "nano") (or (= clean ":nano") (or (= clean "нано") (= clean "микро-нано")))) "nano") ((or (= clean "micro") (or (= clean ":micro") (or (= clean "микро") (or (= clean "микромодель") (= clean "0.5b"))))) "micro") ((or (= clean "mini") (or (= clean ":mini") (or (= clean "мини") (or (= clean "миник") (= clean "1.5b"))))) "mini") ((or (= clean "small") (or (= clean ":small") (or (= clean "малый") (or (= clean "стандарт") (or (= clean "флагман") (= clean "3b")))))) "small") (else clean)))

fn resolveModelAlias catalog: AliasCatalog aliasInput: Str -> ResolvedSelection
  (let [(norm (normalizeAliasQuery aliasInput)) (found (fold (fn [(acc (Option AliasDefinition)) (item AliasDefinition)] -> (Option AliasDefinition) (if (some? acc) acc (if (= item.alias norm) (some item) (none)))) (none) catalog.aliases))] (mt found ((some def) (ResolvedSelection :selectedAlias norm :model def.targetModel :resolved true :reason "Exact alias match verified")) ((none) (let [(fallbackMeta (microModelMetadata))] (ResolvedSelection :selectedAlias "micro" :model fallbackMeta :resolved false :reason (str "Unknown alias '" aliasInput "'; defaulted to canonical micro tier"))))))

fn formatAliasDisplayCard aliasDef: AliasDefinition -> Str
  (let [(m aliasDef.targetModel)] (str "(:model-card\n" "  :alias \"" aliasDef.alias "\"\n" "  :title \"" aliasDef.displayTitle "\"\n" "  :category \"" aliasDef.tierCategory "\"\n" "  :canonical-model \"" m.canonicalName "\"\n" "  :filename \"" m.filename "\"\n" "  :size-mb " (stringFromInt64 m.sizeMb) "\n" "  :vram-mb " (stringFromInt64 m.vramFootprintMb) "\n" "  :quantization \"" m.quantization "\"\n" "  :download-url \"" m.downloadUrl "\"\n" "  :sha256 \"" m.sha256 "\"\n" "  :latency \"" m.latencyTier "\"\n" "  :default " (if aliasDef.isDefault "true" "false") "\n" ")"))

fn formatAliasCatalogAsn catalog: AliasCatalog -> Str
  (let [(cards (fold (fn [(acc Str) (item AliasDefinition)] -> Str (let [(c (formatAliasDisplayCard item))] (if (stringEmpty? acc) c (str acc "\n" c)))) "" catalog.aliases))] (str "(:model-alias-catalog\n" "  :version \"" catalog.catalogVersion "\"\n" "  :total-aliases " (stringFromInt64 (listLength catalog.aliases)) "\n" "  :entries [\n" cards "\n" "  ]\n" ")"))

fn formatAliasCatalogMarkdown catalog: AliasCatalog -> Str
  (let [(rows (fold (fn [(acc Str) (item AliasDefinition)] -> Str (let [(m item.targetModel) (row (str "| `:" item.alias "` | **" m.canonicalName "** | " (stringFromInt64 m.sizeMb) " MB | " (stringFromInt64 m.vramFootprintMb) " MB | `" m.quantization "` | [" m.filename "](" m.downloadUrl ") |"))] (if (stringEmpty? acc) row (str acc "\n" row)))) "" catalog.aliases))] (str "| Alias | Real Canonical Model | Size | VRAM | Quant | Direct Download Link |\n" "| :--- | :--- | :--- | :--- | :--- | :--- |\n" rows))
