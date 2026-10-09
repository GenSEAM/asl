(module aslGateway/lmk :x [LmkKeySource LmkProfile LmkHierarchyInput makeLmkProfile maskApiKey resolveLmkProfile formatLmkProfileAsn] :i [])

(enum LmkKeySource (:c sourceUi [] "Dynamic override from UI or request headers") (:c sourceLocal [] "Resolved from local workspace .asl/gateway.asn") (:c sourceGlobal [] "Resolved from global user ~/.asl/gateway.asn") (:c sourceEnv [] "Resolved from system environment variable") (:c sourceFallback [] "Hardcoded default fallback"))

(schema LmkProfile (:f provider Str) (:f baseUrl Str) (:f modelId Str) (:f apiKey Str) (:f keySource LmkKeySource) (:f maxTokens I64) (:f temperature F64))

(schema LmkHierarchyInput (:f provider Str) (:f modelId Str) (:f uiApiKey Str) (:f uiBaseUrl Str) (:f localApiKey Str) (:f localBaseUrl Str) (:f globalApiKey Str) (:f globalBaseUrl Str) (:f envApiKey Str) (:f envBaseUrl Str))

fn makeLmkProfile p: Str url: Str m: Str k: Str src: LmkKeySource maxT: I64 temp: F64 -> LmkProfile
  (LmkProfile :provider p :baseUrl url :modelId m :apiKey k :keySource src :maxTokens maxT :temperature temp)

fn maskApiKey key: Str -> Str
  (let [(len (stringLength key))] (if (= len 0) "" (if (<= len 8) "********" (let [(prefix (optionOr (stringSlice key 0 3) "sk-")) (suffix (optionOr (stringSlice key (- len 4) len) "****"))] (str prefix "..." suffix)))))

fn resolveLmkProfile input: LmkHierarchyInput -> LmkProfile
  (let [(p input.provider) (m input.modelId) (ui-ok? (or (> (stringLength input.uiApiKey) 0) (> (stringLength input.uiBaseUrl) 0))) (local-ok? (or (> (stringLength input.localApiKey) 0) (> (stringLength input.localBaseUrl) 0))) (global-ok? (or (> (stringLength input.globalApiKey) 0) (> (stringLength input.globalBaseUrl) 0))) (env-ok? (or (> (stringLength input.envApiKey) 0) (> (stringLength input.envBaseUrl) 0))) (key (if ui-ok? input.uiApiKey (if local-ok? input.localApiKey (if global-ok? input.globalApiKey (if env-ok? input.envApiKey ""))))) (src (if ui-ok? (sourceUi) (if local-ok? (sourceLocal) (if global-ok? (sourceGlobal) (if env-ok? (sourceEnv) (sourceFallback)))))) (url-raw (if ui-ok? input.uiBaseUrl (if local-ok? input.localBaseUrl (if global-ok? input.globalBaseUrl (if env-ok? input.envBaseUrl ""))))) (url (if (> (stringLength url-raw) 0) url-raw "http://127.0.0.1:8765/v1")) (maxT (if (mt src ((sourceFallback) true) (_ false)) 2048 4096))] (makeLmkProfile p url m key src maxT 0.2))

fn formatLmkProfileAsn profile: LmkProfile maskKey: Bool -> Str
  (let [(displayKey (if maskKey (maskApiKey profile.apiKey) profile.apiKey)) (srcStr (mt profile.keySource ((sourceUi) "ui-override") ((sourceLocal) "local-workspace") ((sourceGlobal) "global-user") ((sourceEnv) "environment") ((sourceFallback) "fallback")))] (str "(:lmk-profile\n" "  :provider \"" profile.provider "\"\n" "  :base-url \"" profile.baseUrl "\"\n" "  :model-id \"" profile.modelId "\"\n" "  :api-key \"" displayKey "\"\n" "  :source \"" srcStr "\"\n" "  :max-tokens " (stringFromInt64 profile.maxTokens) "\n" "  :temperature " (stringFromFloat64 profile.temperature) "\n" ")"))
