(module aslHarness/config :x [ModelProfile PluginHook HarnessPlugin HarnessConfig HookPredicate CoverageConfig AsnValue AsnField asnNil asnBool asnUnit asnInt asnFloat asnStr asnKw asnSym asnVec asnMap asnRec asnCtor asnRows asnTable asnCase asnPair WorkspaceScope RepoKind WorktreeInfo StorageConfig WorkspaceContext profileGemma31b profileQwen05b profileDefault profileDeepSeek profileDeepSeekFlash profileMuseSpark1 profileMuseSpark3 defaultHarnessConfig benchmarkHarnessConfig productionHarnessConfig defaultCoverageConfig coverageConfigToAsnNode coverageConfigFromAsnNode toggleFeature featureEnabled? registerPlugin enableExperimental experimentalEnabled? makePlugin detectRepoKind parseGitdirFile extractWorktreeId detectWorktree defaultStorageConfig routeStorageTarget resolveCascadedConfig modelProfileFromAsnNode modelProfileToAsnNode storageConfigFromAsnNode storageConfigToAsnNode harnessConfigFromAsnTree evaluateHookPredicate] :i [])

(schema ModelProfile (:f name Str) (:f family Str) (:f strictFirewall Bool) (:f strictNormalizer Bool) (:f inMemoryRepl Bool) (:f maxTokens I64))

(enum PluginHook (:c hookPreCall [] "Hook executed before tool call dispatch") (:c hookPostCall [] "Hook executed after tool call completion") (:c hookModelResponse [] "Hook executed on raw model output stream") (:c hookError [] "Hook executed on execution boundary failure"))

(schema HookPredicate (:f hookType PluginHook) (:f name Str) (:f targetPattern Str) (:f actionOverride Str))

(schema AsnField (:f key Str) (:f val AsnValue))

(enum AsnValue (:c asnNil [] "The nil sentinel `_`") (:c asnBool [(b Bool)] "true or false") (:c asnUnit [] "The unit literal `()`") (:c asnInt [(lex Str)] "Integer literal, held as its source lexeme") (:c asnFloat [(lex Str)] "Float literal, held as its source lexeme") (:c asnStr [(lex Str)] "String literal, held as its source lexeme with quotes") (:c asnKw [(k Str)] "Keyword scalar, including its leading colon") (:c asnSym [(name Str)] "A bare name. Legal as a head, never as a value") (:c asnVec [(items (List AsnValue))] "A bracketed vector") (:c asnMap [(entries (List AsnField))] "A brace map") (:c asnRec [(fields (List AsnField))] "An anonymous record `(:k v ...)`") (:c asnCtor [(name Str) (fields (List AsnField))] "Named construction `(Name :k v ...)`") (:c asnRows [(name Str) (rows (List AsnValue))] "Schema-grouped rows `(Name [..] ..)`") (:c asnTable [(cols (List AsnValue)) (rows (List AsnValue))] "Ad-hoc table `([:c ..] [[..]])`") (:c asnCase [(name Str) (args (List AsnValue))] "Union case value `(name v ..)`") (:c asnPair [(key AsnValue) (val AsnValue)] "A parenthesised map entry, legal only in a map"))

(schema HarnessPlugin (:f id Str) (:f name Str) (:f version Str) (:f enabled Bool) (:f description Str))

(schema CoverageConfig (:f desiredCoverage Float) (:f minAssertionsPerTest I64) (:f discountZeroAsserts Bool))

(schema HarnessConfig (:f profile ModelProfile) (:f flags (Map Str Bool)) (:f plugins (List HarnessPlugin)) (:f experimental (List Str)) (:f customSettings (Map Str Str)) (:f coverage CoverageConfig))

(enum WorkspaceScope (:c scopeGlobal [] "Global fallback defaults") (:c scopeMaster [] "Master workspace root (genseam)") (:c scopeSubrepo [] "Sub-repository scope") (:c scopeWorktree [] "Isolated git worktree local override"))

(enum RepoKind (:c repoMain [] "Standard Git repository root with .git directory") (:c repoWorktree [] "Git worktree with .git file pointing to worktrees/") (:c repoSubmodule [] "Git submodule with .git file pointing to modules/") (:c repoNone [] "Directory is not a git repository"))

(schema WorktreeInfo (:f isWorktree Bool) (:f gitDir Str) (:f commonDir Str) (:f worktreeId Str))

(schema StorageConfig (:f masterResearchRoot Str) (:f masterScratchRoot Str) (:f worktreeScratchRoot Str) (:f localRepoRoot Str))

(schema WorkspaceContext (:f scope WorkspaceScope) (:f repoKind RepoKind) (:f name Str) (:f worktreeId Str) (:f isWorktree Bool) (:f parentRepoRoot Str) (:f testRunner Str) (:f preExecutionGate Bool) (:f storage StorageConfig))

fn profileGemma31b -> ModelProfile
  (ModelProfile :name "gemma-4-31b-it" :family "gemma" :strictFirewall true :strictNormalizer true :inMemoryRepl true :maxTokens 8192)

fn profileQwen05b -> ModelProfile
  (ModelProfile :name "qwen-2.5-0.5b" :family "qwen" :strictFirewall true :strictNormalizer true :inMemoryRepl true :maxTokens 2048)

fn profileDefault -> ModelProfile
  (ModelProfile :name "generic-llm" :family "generic" :strictFirewall true :strictNormalizer false :inMemoryRepl false :maxTokens 4096)

fn profileDeepSeek -> ModelProfile
  (ModelProfile :name "deepseek-v3" :family "deepseek" :strictFirewall true :strictNormalizer true :inMemoryRepl true :maxTokens 65536)

fn profileDeepSeekFlash -> ModelProfile
  (ModelProfile :name "deepseek-flash-4.1" :family "deepseek" :strictFirewall true :strictNormalizer true :inMemoryRepl true :maxTokens 32768)

fn profileMuseSpark1 -> ModelProfile
  (ModelProfile :name "muse-spark-1" :family "muse" :strictFirewall true :strictNormalizer true :inMemoryRepl false :maxTokens 32768)

fn profileMuseSpark3 -> ModelProfile
  (ModelProfile :name "muse-spark-3" :family "muse" :strictFirewall true :strictNormalizer true :inMemoryRepl true :maxTokens 65536)

fn makePlugin id: Str name: Str version: Str enabled: Bool description: Str -> HarnessPlugin
  (HarnessPlugin :id id :name name :version version :enabled enabled :description description)

fn defaultHarnessConfig -> HarnessConfig
  (let [(prof (profileGemma31b)) (initFlags (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapSet (mapEmpty) "firewall" true) "fsm-normalizer" true) "repl-in-memory" true) "rpc-descriptions" true) "command-descriptions" false) "rpc-only-tools" true) "batch-required" true))] (HarnessConfig :profile prof :flags initFlags :plugins (list) :experimental (list) :customSettings (mapEmpty) :coverage (defaultCoverageConfig)))

fn benchmarkHarnessConfig -> HarnessConfig
  (let [(prof (profileGemma31b)) (flags1 (mapSet (mapEmpty) "airgap" true)) (flags2 (mapSet flags1 "strict-falsification" true)) (flags3 (mapSet flags2 "ctrf-tracking" true)) (flags4 (mapSet flags3 "fsm-normalizer" true)) (flags5 (mapSet flags4 "firewall" true)) (sets1 (mapSet (mapEmpty) "gateway-url" "http://127.0.0.1:8765/v1")) (sets2 (mapSet sets1 "timeout-seconds" "300"))] (HarnessConfig :profile prof :flags flags5 :plugins (list) :experimental (list "hermetic-sandbox" "scalar-loss") :customSettings sets2 :coverage (defaultCoverageConfig)))

fn productionHarnessConfig -> HarnessConfig
  (let [(prof (profileDefault)) (flags1 (mapSet (mapEmpty) "airgap" false)) (flags2 (mapSet flags1 "epistemic-cycle" true)) (flags3 (mapSet flags2 "git-worktrees" true)) (flags4 (mapSet flags3 "compiler-feedback" true)) (flags5 (mapSet flags4 "repl-in-memory" true)) (flags6 (mapSet flags5 "intent-teleology" true)) (sets1 (mapSet (mapEmpty) "gateway-url" "http://127.0.0.1:8765/v1")) (sets2 (mapSet sets1 "epistemic-pipeline" "scout->plan->gap-audit->implement->reconcile")) (sets3 (mapSet sets2 "routing-mode" "role-based-gateway"))] (HarnessConfig :profile prof :flags flags6 :plugins (list) :experimental (list "ast-patch" "worktree-isolation" "intent-driven-orchestration") :customSettings sets3 :coverage (defaultCoverageConfig)))

fn toggleFeature cfg: HarnessConfig featureName: Str enable: Bool -> HarnessConfig
  (let [(updatedFlags (mapSet cfg.flags featureName enable))] (with cfg :flags updatedFlags))

fn featureEnabled? cfg: HarnessConfig featureName: Str -> Bool
  (let [(val (mapGet cfg.flags featureName))] (optionOr val false))

fn registerPlugin cfg: HarnessConfig plugin: HarnessPlugin -> HarnessConfig
  (let [(updatedPlugins (cons plugin cfg.plugins))] (with cfg :plugins updatedPlugins))

fn enableExperimental cfg: HarnessConfig flag: Str -> HarnessConfig
  (let [(existing cfg.experimental) (updated (cons flag existing))] (with cfg :experimental updated))

fn experimentalEnabled? cfg: HarnessConfig flag: Str -> Bool
  (let [(active (filter (fn [(f Str)] -> Bool (= f flag)) cfg.experimental))] (not (listEmpty? active)))

fn detectRepoKind gitPathType: Str gitContent: Str -> RepoKind
  (cond ((= gitPathType "dir") (repoMain)) ((= gitPathType "file") (let [(clean (stringTrim gitContent))] (cond ((stringContains? clean "/worktrees/") (repoWorktree)) ((stringContains? clean "/modules/") (repoSubmodule)) ((stringStartsWith? clean "gitdir:") (repoWorktree)) (else (repoNone))))) (else (repoNone)))

fn parseGitdirFile dotGitContent: Str workspacePath: Str -> (Option Str)
  (let [(trimmed (stringTrim dotGitContent))] (if (stringStartsWith? trimmed "gitdir:") (let [(rawPath (stringTrim (optionOr (stringSlice trimmed 7 (stringLength trimmed)) "")))] (if (stringStartsWith? rawPath "/") (some rawPath) (some (str workspacePath "/" rawPath)))) (none)))

fn extractWorktreeId normalizedGitdir: Str -> Str
  (let [(segments (stringSplit normalizedGitdir "/"))] (if (listEmpty? segments) "default" (fold (fn [(acc Str) (seg Str)] -> Str (if (stringEmpty? seg) acc seg)) "default" segments)))

fn detectWorktree gitPathType: Str gitContent: Str workspacePath: Str -> WorktreeInfo
  (let [(kind (detectRepoKind gitPathType gitContent))] (mt kind ((repoWorktree) (let [(parsed (parseGitdirFile gitContent workspacePath)) (gdir (optionOr parsed (str workspacePath "/.git"))) (wtId (extractWorktreeId gdir))] (WorktreeInfo :isWorktree true :gitDir gdir :commonDir (str gdir "/../../..") :worktreeId wtId))) ((repoMain) (WorktreeInfo :isWorktree false :gitDir (str workspacePath "/.git") :commonDir (str workspacePath "/.git") :worktreeId "")) ((repoSubmodule) (WorktreeInfo :isWorktree false :gitDir (str workspacePath "/.git") :commonDir (str workspacePath "/.git") :worktreeId "")) ((repoNone) (WorktreeInfo :isWorktree false :gitDir (str workspacePath "/.git") :commonDir (str workspacePath "/.git") :worktreeId ""))))

fn defaultStorageConfig workspaceRoot: Str -> StorageConfig
  (StorageConfig :masterResearchRoot (str workspaceRoot "/.research") :masterScratchRoot (str workspaceRoot "/scratch") :worktreeScratchRoot (str workspaceRoot "/.worktree-scratch") :localRepoRoot workspaceRoot)

fn routeStorageTarget scopeType: Str relativeFilename: Str storage: StorageConfig -> Str
  (let [(cleanFile (if (stringStartsWith? relativeFilename "/") (optionOr (stringSlice relativeFilename 1 (stringLength relativeFilename)) relativeFilename) relativeFilename))] (cond ((or (= scopeType ":research") (= scopeType "research")) (str storage.masterResearchRoot "/" cleanFile)) ((or (= scopeType ":worktree-scratch") (= scopeType "worktree-scratch")) (str storage.worktreeScratchRoot "/" cleanFile)) (else (str storage.masterScratchRoot "/" cleanFile))))

fn findFieldVal fields: (List AsnField) targetKey: Str -> (Option AsnValue)
  (fold (fn [(acc (Option AsnValue)) (f AsnField)] -> (Option AsnValue) (mt acc ((some _) acc) ((none) (if (= f.key targetKey) (some f.val) (none))))) (none) fields)

fn stripQuotes s: Str -> Str
  (let [(len (stringLength s))] (if (and (>= len 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\""))) (optionOr (stringSlice s 1 (- len 1)) "") s))

fn asnExtractStr v: AsnValue defaultVal: Str -> Str
  (mt v ((asnStr s) (stripQuotes s)) ((asnSym s) s) ((asnKw k) (if (stringStartsWith? k ":") (optionOr (stringSlice k 1 (stringLength k)) "") k)) (_ defaultVal))

fn asnExtractBool v: AsnValue defaultVal: Bool -> Bool
  (mt v ((asnBool b) b) (_ defaultVal))

fn asnExtractInt v: AsnValue defaultVal: I64 -> I64
  (mt v ((asnInt s) (optionOr (stringToInt64 s) defaultVal)) (_ defaultVal))

fn asnExtractFloat v: AsnValue defaultVal: Float -> Float
  (mt v ((asnFloat s) (optionOr (stringToFloat64 s) defaultVal)) ((asnInt s) (mt (stringToInt64 s) ((some n) (int64ToFloat64 n)) ((none) defaultVal))) (_ defaultVal))

fn defaultCoverageConfig -> CoverageConfig
  (CoverageConfig :desiredCoverage 80.0 :minAssertionsPerTest 2 :discountZeroAsserts true)

fn coverageConfigToAsnNode cfg: CoverageConfig -> AsnValue
  (asnCtor "CoverageConfig" (list (AsnField :key ":desired" :val (asnFloat (stringFromFloat64 cfg.desiredCoverage))) (AsnField :key ":min-assertions" :val (asnInt (stringFromInt64 cfg.minAssertionsPerTest))) (AsnField :key ":discount-zero-asserts" :val (asnBool cfg.discountZeroAsserts))))

fn coverageConfigFromAsnNode node: AsnValue -> (Option CoverageConfig)
  (let [(fieldsOpt (mt node ((asnCtor _ fs) (some fs)) ((asnRec fs) (some fs)) (_ (none))))] (mt fieldsOpt ((none) (none)) ((some fields) (let [(optDes (findFieldVal fields ":desired")) (optMin (findFieldVal fields ":min-assertions")) (optDisc (findFieldVal fields ":discount-zero-asserts")) (desVal (mt optDes ((some v) (asnExtractFloat v 80.0)) ((none) 80.0))) (minVal (mt optMin ((some v) (asnExtractInt v 2)) ((none) 2))) (discVal (mt optDisc ((some v) (asnExtractBool v true)) ((none) true)))] (some (CoverageConfig :desiredCoverage desVal :minAssertionsPerTest minVal :discountZeroAsserts discVal))))))

fn modelProfileToAsnNode prof: ModelProfile -> AsnValue
  (asnCtor "ModelProfile" (list (AsnField :key ":name" :val (asnStr (str "\"" prof.name "\""))) (AsnField :key ":family" :val (asnStr (str "\"" prof.family "\""))) (AsnField :key ":strict-firewall" :val (asnBool prof.strictFirewall)) (AsnField :key ":strict-normalizer" :val (asnBool prof.strictNormalizer)) (AsnField :key ":in-memory-repl" :val (asnBool prof.inMemoryRepl)) (AsnField :key ":max-tokens" :val (asnInt (stringFromInt64 prof.maxTokens)))))

fn modelProfileFromAsnNode node: AsnValue -> (Option ModelProfile)
  (let [(fieldsOpt (mt node ((asnCtor _ fs) (some fs)) ((asnRec fs) (some fs)) (_ (none))))] (mt fieldsOpt ((none) (none)) ((some fields) (let [(optName (findFieldVal fields ":name")) (optFamily (findFieldVal fields ":family")) (optFirewall (findFieldVal fields ":strict-firewall")) (optNormalizer (findFieldVal fields ":strict-normalizer")) (optRepl (findFieldVal fields ":in-memory-repl")) (optTokens (findFieldVal fields ":max-tokens"))] (if (or (none? optName) (none? optFamily)) (none) (some (ModelProfile :name (asnExtractStr (optionOr optName (asnNil)) "generic-llm") :family (asnExtractStr (optionOr optFamily (asnNil)) "generic") :strictFirewall (if (some? optFirewall) (asnExtractBool (optionOr optFirewall (asnNil)) true) true) :strictNormalizer (if (some? optNormalizer) (asnExtractBool (optionOr optNormalizer (asnNil)) false) false) :inMemoryRepl (if (some? optRepl) (asnExtractBool (optionOr optRepl (asnNil)) false) false) :maxTokens (if (some? optTokens) (asnExtractInt (optionOr optTokens (asnNil)) 4096) 4096))))))))

fn storageConfigToAsnNode cfg: StorageConfig -> AsnValue
  (asnCtor "StorageConfig" (list (AsnField :key ":master-research-root" :val (asnStr (str "\"" cfg.masterResearchRoot "\""))) (AsnField :key ":master-scratch-root" :val (asnStr (str "\"" cfg.masterScratchRoot "\""))) (AsnField :key ":worktree-scratch-root" :val (asnStr (str "\"" cfg.worktreeScratchRoot "\""))) (AsnField :key ":local-repo-root" :val (asnStr (str "\"" cfg.localRepoRoot "\"")))))

fn storageConfigFromAsnNode node: AsnValue -> (Option StorageConfig)
  (let [(fieldsOpt (mt node ((asnCtor _ fs) (some fs)) ((asnRec fs) (some fs)) (_ (none))))] (mt fieldsOpt ((none) (none)) ((some fields) (let [(optRes (findFieldVal fields ":master-research-root")) (optScratch (findFieldVal fields ":master-scratch-root")) (optWt (findFieldVal fields ":worktree-scratch-root")) (optLocal (findFieldVal fields ":local-repo-root"))] (if (and (some? optRes) (some? optScratch)) (some (StorageConfig :masterResearchRoot (asnExtractStr (optionOr optRes (asnNil)) "") :masterScratchRoot (asnExtractStr (optionOr optScratch (asnNil)) "") :worktreeScratchRoot (if (some? optWt) (asnExtractStr (optionOr optWt (asnNil)) "") "") :localRepoRoot (if (some? optLocal) (asnExtractStr (optionOr optLocal (asnNil)) "") ""))) (none))))))

fn harnessConfigFromAsnTree root: AsnValue -> (Option HarnessConfig)
  (let [(fieldsOpt (mt root ((asnCtor _ fs) (some fs)) ((asnRec fs) (some fs)) (_ (none))))] (mt fieldsOpt ((none) (none)) ((some fields) (let [(base (defaultHarnessConfig)) (profNode (findFieldVal fields ":profile")) (prof (mt profNode ((some pn) (optionOr (modelProfileFromAsnNode pn) base.profile)) ((none) base.profile))) (fwNode (findFieldVal fields ":firewall")) (normNode (findFieldVal fields ":fsm-normalizer")) (replNode (findFieldVal fields ":repl-in-memory")) (c1 (mt fwNode ((some fn) (toggleFeature base "firewall" (asnExtractBool fn true))) ((none) base))) (c2 (mt normNode ((some nn) (toggleFeature c1 "fsm-normalizer" (asnExtractBool nn true))) ((none) c1))) (c3 (mt replNode ((some rn) (toggleFeature c2 "repl-in-memory" (asnExtractBool rn true))) ((none) c2))) (covNode (findFieldVal fields ":coverage")) (covCfg (mt covNode ((some cn) (optionOr (coverageConfigFromAsnNode cn) base.coverage)) ((none) base.coverage)))] (some (HarnessConfig :profile prof :flags c3.flags :plugins base.plugins :experimental base.experimental :customSettings base.customSettings :coverage covCfg))))))

fn evaluateHookPredicate pred: HookPredicate targetName: Str contextTag: Str -> Bool
  (let [(pat pred.targetPattern) (targetMatch (or (stringEmpty? pat) (or (= pat "*") (or (= pat targetName) (stringContains? targetName pat))))) (ctxMatch (or (stringEmpty? contextTag) (or (= contextTag "*") (or (= contextTag "guard") (or (stringContains? pred.name contextTag) (stringContains? pred.actionOverride contextTag))))))] (and targetMatch ctxMatch))

fn applyConfigTier cfg: HarnessConfig rawInput: Str -> HarnessConfig
  (let [(clean (stringTrim rawInput))] (if (stringEmpty? clean) cfg (let [(c1 (if (or (stringContains? clean "fsm-normalizer: false") (stringContains? clean ":fsm-normalizer false")) (toggleFeature cfg "fsm-normalizer" false) (if (or (stringContains? clean "fsm-normalizer: true") (stringContains? clean ":fsm-normalizer true")) (toggleFeature cfg "fsm-normalizer" true) cfg))) (c2 (if (or (stringContains? clean "firewall: false") (stringContains? clean ":firewall false")) (toggleFeature c1 "firewall" false) (if (or (stringContains? clean "firewall: true") (stringContains? clean ":firewall true")) (toggleFeature c1 "firewall" true) c1))) (c3 (if (or (stringContains? clean "repl-in-memory: false") (stringContains? clean ":repl-in-memory false")) (toggleFeature c2 "repl-in-memory" false) (if (or (stringContains? clean "repl-in-memory: true") (stringContains? clean ":repl-in-memory true")) (toggleFeature c2 "repl-in-memory" true) c2)))] c3)))

fn resolveCascadedConfig globalCfg: HarnessConfig workspaceRaw: Str subrepoRaw: Str worktreeRaw: Str -> HarnessConfig
  (let [(c1 (applyConfigTier globalCfg workspaceRaw)) (c2 (applyConfigTier c1 subrepoRaw)) (c3 (applyConfigTier c2 worktreeRaw))] c3)
