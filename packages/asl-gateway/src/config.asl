(module aslGateway/config
  :x [AsnScalar
      scalarBool
      scalarInt
      scalarFloat
      scalarStr
      scalarToString
      GatewayParams
      emptyGatewayParams
      mergeParams
      GatewayRoute
      GatewayProfile
      GatewayModel
      GatewayProvider
      GatewayPool
      RetryPolicy
      noRetryPolicy
      mergedRetryPolicy
      GatewayUpstream
      GatewayEntry
      GatewayResolvedEntry
      entryResolved
      entryUnresolved
      GatewayV1Config
      GatewayTable
      GatewayLimit
      gatewayLimitsFromProps
      gatewayLimitWarnings
      gatewayLimitErrors
      GatewayGroup
      LimitScope
      emptyLimitScope
      gatewayLimitScopeFromText
      defaultConcurrencyLeaseSec
      defaultConcurrencyPollMs
      gatewayLimitsFromText
      gatewayLimitWindows
      defaultBucketWaitSec
      defaultQueueBudgetSec
      queueBudgetMaxSec
      defaultBusyRetrySec
      gatewayQueueBudgetSecFromProps
      gatewayBucketWaitSecFromProps
      asnScalar
      asnFigure
      asnProps
      asnName
      gatewayParams
      calibrationRegistryLoad!
      gatewayProfilesParse
      gatewayConfigV2Build!
      gatewayConfigParse!
      gatewayIntentLine
      gatewayV2Route
      gatewayV2RouteTemperature
      gatewayV2Entry!
      gatewayV2Entries!
      gatewayV2EntriesExact!
      gatewayV2AliasEntry!
      gatewayNoteIntent
      gatewayUndeclaredIntents
      gatewayAnyOnlyIntents
      gatewayEntryLabel
      ConfigKey
      keyBuiltin
      keyFiles
      ProfilesCache
      ProfileSelection
      RouteEntries
      ProfileHealth
      healthError
      healthV1
      healthV2
      ConfigHealth
      gatewayProfilesPath
      gatewayLedgerPathOverride
      gatewaySecretsFileOverride
      gatewaySecretsFileChoice
      keyFilesEnvOverlay!
      gatewaySharedUsagePathOverride
      gatewayDailyTokenBudget
      gatewayBreakerCooldownSecOverride
      gatewayTopIntOverride
      gatewayContextCap
      gatewayTopScalarOverride
      JudgeRules judgeDefault gatewayProfileMode gatewayProfileJudge gatewayProfileBudgetFirst
      expandUserPath keyFileLookup! resolveProviderKey! resolveProviderCredential! gatewaySecretsPathFromProps isValidSecretId? providerPromptCacheKey? gatewayKeyFilesFromProps keyFilesSuffix
      profilePinPath profilePinRead! writeProfilePin!
      gatewayConfigKey!
      configKeyEqual?
      gatewayProfilesLoadText!
      gatewayLoadWarningLines
      emptyProfilesCache
      gatewayProfilesLoad!
      gatewayProfileName
      gatewayProfileSelect
      gatewayProfileModels
      gatewayRouteEntries!
      gatewayRouteEntriesExact!
      gatewayChainContainingModel!
      gatewayProfileHealth
      gatewayConfigHealth
      gatewayProfileAsn
      gatewayConfigAsn
      gatewayConfigReceipt
      gatewayConfigCheckText!
      DecidePoint decideModes defaultDecidePoint gatewayDecideRows gatewayDecidePoint gatewayDecideLoad! CodeRoute gatewayCodeRoute!
      headerGet]
  :i [(wire :a wire)
      (asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)
      (aslGateway/batchPool :a bp)
      (aslGateway/usage :a ug)
      (aslGateway/secrets :a sc)])

(enum AsnScalar
  (:c scalarBool [(b Bool)])
  (:c scalarInt [(n Int64)])
  (:c scalarFloat [(f Float64)])
  (:c scalarStr [(s String)]))

fn scalarToString sc: AsnScalar -> String
  (match sc
    ((scalarBool b) (if b "true" "false"))
    ((scalarInt n) (stringFromInt64 n))
    ((scalarFloat f) (stringFromFloat64 f))
    ((scalarStr s) s))

(schema GatewayParams
  (:f topP (Option Float64) :default none)
  (:f temperature (Option Float64))
  (:f effort (Option String))
  (:f effortDialect (Option String))
  (:f maxTokens (Option Int64))
  (:f contextBudget (Option Int64))
  (:f timeoutSec (Option Float64))
  (:f firstByteSec (Option Float64))
  (:f reasoning (Option Bool))
  (:f rpm (Option Float64))
  (:f api (Option String))
  (:f prefill (Option Bool))
  (:f retry (Option RetryPolicy))
  (:f nativeTools (Option Bool) :default none)
  ; (:m :ref KIMI-TEMP-FIXED :do "a model that accepts one sampling temperature only (Kimi: 1): the gateway sends this value whatever the request or the route says; exclusive with :temperature on the same row")
  (:f temperatureFixed (Option Float64) :default none)
  ; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "a model row :stream true is a route that answers only with stream true (Synthetic infinite mode): the gateway sends stream and stream_options include_usage and folds the SSE reply into one chat completion")
  (:f stream (Option Bool) :default none))

fn emptyGatewayParams -> GatewayParams
  (GatewayParams
    :temperature (none)
    :effort (none)
    :effortDialect (none)
    :maxTokens (none)
    :contextBudget (none)
    :timeoutSec (none)
    :firstByteSec (none)
    :reasoning (none)
    :rpm (none)
    :api (none)
    :prefill (none)
    :retry (none))

fn mergeParams base: GatewayParams override: GatewayParams -> GatewayParams
  (GatewayParams
    :temperature (if (some? override.temperature) override.temperature base.temperature)
    :topP (if (some? override.topP) override.topP base.topP)
    :effort (if (some? override.effort) override.effort base.effort)
    :effortDialect (if (some? override.effortDialect) override.effortDialect base.effortDialect)
    :maxTokens (if (some? override.maxTokens) override.maxTokens base.maxTokens)
    :contextBudget (if (some? override.contextBudget) override.contextBudget base.contextBudget)
    :timeoutSec (if (some? override.timeoutSec) override.timeoutSec base.timeoutSec)
    :firstByteSec (if (some? override.firstByteSec) override.firstByteSec base.firstByteSec)
    :reasoning (if (some? override.reasoning) override.reasoning base.reasoning)
    :rpm (if (some? override.rpm) override.rpm base.rpm)
    :api (if (some? override.api) override.api base.api)
    :prefill (if (some? override.prefill) override.prefill base.prefill)
    :retry (if (some? override.retry) override.retry base.retry)
    :nativeTools (if (some? override.nativeTools) override.nativeTools base.nativeTools)
    :temperatureFixed (if (some? override.temperatureFixed) override.temperatureFixed base.temperatureFixed)
    :stream (if (some? override.stream) override.stream base.stream))

(schema GatewayRoute
  (:f intent String)
  (:f chain (List String))
  (:f models (List String))
  (:f temperature (Option Float64))
  ; (:m :ref GW-ROUTE-TEMPERATURE :do "a route-level sampling temperature that wins over the model row's :temperature for every entry this route contributes (a client-sent temperature still wins over it); :temperature stays the weaker per-route default, model-row :temperature stays the default for routes without an override, so a temperature sweep edits one route row instead of adding scratch model rows")
  (:f temperatureOverride (Option Float64))
  ; (:m :ref GW-SPREAD-20261017 :do "beside :chain, never instead of it: (ALIAS WEIGHT) pairs over aliases also present in :models, tried by smooth weighted round-robin before the plain chain; absent :spread is the empty list, unchanged behaviour")
  (:f spread (List (Pair String Int64)))
  (:f cooldownSec Int64))

; (:m :ref GW-MODES :do "a judge-mode profile's static reply checks: an empty answer (message content, before any reasoning salvage, with no tool calls), a truncated one (finish_reason length), and for the intents in stepIntents an answer holding none of stepHeads; a failed check moves to the next member")
(schema JudgeRules
  (:f empty Bool)
  (:f truncated Bool)
  (:f stepIntents (List String))
  (:f stepHeads (List String)))

fn judgeDefault -> JudgeRules
  (JudgeRules :empty true :truncated true :stepIntents (list) :stepHeads (list "(:step"))

(schema GatewayProfile
  (:f id String)
  (:f routes (List GatewayRoute))
  (:f fallback (Option String))
  ; (:m :ref GW-MODES :do "pin: the route's first member only, its failure relayed as is; route (default): chain, spread, limits, breakers; judge: route plus the judge checks")
  (:f mode String)
  (:f judge JudgeRules)
  ; (:m :ref CTX-ROUTE :do "prompt estimate in tokens above which the members are tried largest contextBudget first; 0 keeps the chain order")
  (:f budgetFirstAbove Int64))

(schema GatewayModel
  (:f id String)
  (:f provider String)
  (:f name String)
  (:f calibration (Option String))
  (:f params GatewayParams)
  (:f shown (List (Pair String String)))
  (:f gone Bool))

(schema GatewayProvider
  (:f id String)
  (:f kind String)
  (:f base String)
  (:f keyEnv String)
  (:f secret String)
  (:f promptCacheKey Bool)
  (:f sessionHeader String)
  (:f timeoutSec Float64)
  (:f firstByteSec Float64)
  (:f rpm Float64)
  ; (:m :ref GW-PROVIDER-BUCKET :do "provider :rpmShared true makes :rpm the provider's own budget: every model of the provider draws from one rate bucket keyed on the provider, whatever rpm a model names")
  (:f rpmShared Bool)
  ; (:m :ref GW-IFM-EMPTY-TOOLS :do "provider :dropEmptyTools true :assistantReasoning false removes an empty tools array from the body sent to the provider, which some free upstreams reject")
  (:f dropEmptyTools Bool)
  ; (:m :ref IFM-4XX-20261031 :do "provider :assistantReasoning true adds reasoning_content \"\" to assistant messages that carry no thinking field, which ifm requires in multi-turn history")
  (:f assistantReasoning Bool)
  (:f pool (Option GatewayPool))
  (:f retry (Option RetryPolicy)))

(schema GatewayPool
  (:f config bp/PoolConfig)
  (:f batch Bool)
  (:f scaleDownPath String))

; (:m :tags (retry) :do "a transient upstream failure (429 rate-limit text, 502/503/504, a cheap transport timeout or reset) retries the same model maxAttempts times with exponential backoff before any cascade or circuit-breaker trip; absent on both provider and model, maxAttempts is 0 so nothing changes for a config that never names :retry")
(schema RetryPolicy
  (:f maxAttempts Int64)
  (:f baseMs Int64)
  (:f capMs Int64))

fn noRetryPolicy -> RetryPolicy
  (RetryPolicy :maxAttempts 0 :baseMs 1000 :capMs 20000)

(schema GatewayUpstream
  (:f provider String)
  (:f url String)
  (:f key String))

(schema GatewayEntry
  (:f alias String)
  (:f provider String)
  (:f kind String)
  (:f name String)
  (:f dispatch String)
  (:f params GatewayParams)
  (:f upstream GatewayUpstream)
  (:f timeoutSec Float64)
  (:f firstByteSec Float64)
  (:f rpm (Option Float64))
  (:f rpmKey String)
  (:f dropEmptyTools Bool)
  ; (:m :ref IFM-4XX-20261031 :do "provider :assistantReasoning true adds reasoning_content \"\" to assistant messages that carry no thinking field, which ifm requires in multi-turn history")
  (:f assistantReasoning Bool)
  (:f pool (Option GatewayPool))
  (:f retry (Option RetryPolicy)))

(enum GatewayResolvedEntry
  (:c entryResolved [(entry GatewayEntry)])
  (:c entryUnresolved [(alias String)]))

(schema GatewayV1Config
  (:f defaultProfile String)
  (:f profiles (Map String (List GatewayRoute))))

(schema GatewayTable
  (:f version Int64)
  (:f defaultProfile String)
  (:f profiles (Map String GatewayProfile))
  (:f profileOrder (List String))
  (:f models (Map String GatewayModel))
  (:f modelOrder (List String))
  (:f providers (Map String GatewayProvider))
  (:f intents (Map String (Option String)))
  (:f uses (Map String String))
  (:f useOrder (List String))
  (:f source String)
  (:f registry String)
  (:f registryError (Option String))
  (:f warnings (List String))
  (:f undeclaredIntents (Map String Int64))
  (:f keyFiles (List String))
  (:f limits (List GatewayLimit))
  (:f bucketWaitSec Float64)
  (:f queueBudgetSec Float64))

; (:m :ref GW-KEYSTORE-20261019 :do "a provider's :keyEnv is resolved against (:gateway :keyFiles (path ...)) before the process environment, never the other way: a key file is this workspace's own secret store, checked into no repo, and should win over a stray inherited env var from the caller's shell. ~ expands against HOME; each path is read as dotenv-style NAME=value lines (export prefix and quotes stripped, # comments skipped -- aslGateway/usage's zshLine/loadZshEnvText already implements exactly that grammar for ~/.zshenv, reused here instead of a second parser) and searched in listed order, first match wins; a file that is missing, unreadable or lacks the name is silently skipped, not an error -- only exhausting every file and the environment is")
fn expandUserPath p: String -> String
  (cond
    ((= p "~") (optionOr (envGet "HOME") p))
    ((stringStartsWith? p "~/") (str (rstripSlash (optionOr (envGet "HOME") "")) (optionOr (stringSlice p 1 (stringLength p)) "")))
    (else p))

fn ! keyFileLookup! paths: (List String) keyEnv: String -> (Option String)
  (match (listHead paths)
    ((none) none)
    ((some p)
     (let [(rest (optionOr (listTail paths) (list)))]
       (match (fileReadString (expandUserPath p))
         ((err _) (keyFileLookup! rest keyEnv))
         ((ok raw)
          (match (ug/loadZshEnvText (mapEmpty) raw)
            ((err _) (keyFileLookup! rest keyEnv))
            ((ok envMap)
             (match (mapGet envMap keyEnv)
               ((some v) (if (stringEmpty? v) (keyFileLookup! rest keyEnv) (some v)))
               ((none) (keyFileLookup! rest keyEnv))))))))))

fn ! resolveProviderKey! keyFiles: (List String) keyEnv: String -> (Option String)
  (if (stringEmpty? keyEnv)
    none
    (match (keyFileLookup! keyFiles keyEnv)
      ((some v) (some v))
      ((none) (envGet keyEnv))))

fn providerPromptCacheKey? table: GatewayTable provider: String -> Bool
  (match (mapGet table.providers provider)
    ((some p) p.promptCacheKey)
    ((none) false))

fn isValidSecretId? s: String -> Bool
  (and (not (stringEmpty? s))
       (listAll? (fn [(c String)] -> Bool (not (or (= c " ") (or (= c "\"") (or (= c "(") (or (= c ")") (or (= c ";") (or (= c "\n") (= c "\\")))))))))
                 (stringChars s)))

fn gatewaySecretsPathFromProps g: (Map String rd/SExpr) -> String
  (match (mapGet g "secretsFile")
    ((none) (sc/secretsDefaultPath))
    ((some value) (match (asnScalar value) ((scalarStr s) (if (stringEmpty? s) (sc/secretsDefaultPath) (expandUserPath s))) (_ (sc/secretsDefaultPath)))))

; (:m :ref GW-SECRETS-FILE-20261027 :do "a provider's :secret names a row in the secrets file and wins over :keyEnv; no :secret falls back to :keyEnv with the key files; a secret absent from the file is an ERR_SECRET_MISSING receipt naming the id, never a value, and it does not fall back to the environment")
fn ! resolveProviderCredential! secretsPath: String keyFiles: (List String) secret: String keyEnv: String -> (Result (Option String) String)
  (if (stringEmpty? secret)
    (ok (resolveProviderKey! keyFiles keyEnv))
    (match (sc/secretsLoad! secretsPath)
      ((err e) (err e))
      ((ok store) (match (sc/secretsGet store secret) ((ok v) (ok (some v))) ((err e) (err e)))))) 

; (:m :ref GW-KEYSTORE-20261019 :do "a missing key names what was searched -- the env var always, the key files too when any were configured -- never the value")
fn keyFilesSuffix keyFiles: (List String) -> String
  (if (listEmpty? keyFiles) "" (str " (also checked " (stringJoin keyFiles ", ") ")"))

fn gatewayKeyFilesFromProps g: (Map String rd/SExpr) -> (List String)
  (match (mapGet g "keyFiles")
    ((none) (list))
    ((some value)
     (let [(items (match value ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
       (filter (fn [(s String)] -> Bool (not (stringEmpty? s)))
         (map (fn [(it rd/SExpr)] -> String (match (asnScalar it) ((scalarStr s) s) (_ "")))
           items)))))

; (:m :ref GW-LIMIT-SCOPES :do "one provider limit from (:gateway :limits ((:limit :scope account|group|model|endpoint ...) ...)): account counts every alias of :provider, model one alias of :provider (:model M), group the aliases of a (:group :id G :provider P :models (...)) row (:group G), endpoint every provider whose :base is :endpoint; the units are :calls, :tokens (in plus out), :tokensIn, :tokensOut, :tokensCached over a :window, :usd over a :window priced by the models' :priceInPerM and :priceOutPerM, and :concurrency (calls in flight, no window); 0 or absent means that unit is not limited; method, verified, date and note are documentation and are read past")
(schema GatewayLimit
  (:f provider String)
  (:f scope String)
  (:f model String)
  (:f window String)
  (:f calls Int64)
  (:f tokens Int64)
  (:f group String :default "")
  (:f endpoint String :default "")
  (:f tokensIn Int64 :default 0)
  (:f tokensOut Int64 :default 0)
  (:f tokensCached Int64 :default 0)
  (:f usd Float64 :default 0.0)
  (:f concurrency Int64 :default 0)
  ; (:m :ref GW-ADAPTIVE-ADMISSION :do "upper bound the learned concurrency cap may rise to; 0 or absent means twice :concurrency")
  (:f max Int64 :default 0)
  (:f resetDay Int64 :default 1)
  (:f pace String :default "even"))

; (:m :ref GW-LIMIT-SCOPES :do "a (:group :id G :provider P :models (ALIAS ...)) row under (:gateway :groups (...)): the listed aliases of provider P share every limit row that names the group, so one budget spans several models (a plan quota shared across its models, a free-tier daily count across all free models)")
(schema GatewayGroup
  (:f id String)
  (:f provider String)
  (:f models (List String)))

; (:m :ref GW-LIMIT-SCOPES :do "what a limit row needs beyond the usage rows to say whether a call is inside its scope and what it cost: the groups, each provider's :base (endpoint scope) and each model's :priceInPerM and :priceOutPerM (usd units)")
(schema LimitScope
  (:f groups (List GatewayGroup))
  (:f bases (List (Pair String String)))
  (:f prices (List (Pair String (Pair Float64 Float64)))))

fn emptyLimitScope -> LimitScope
  (LimitScope :groups (list) :bases (list) :prices (list))

; (:m :ref GW-LIMIT-SCOPES :do "(:gateway :concurrencyLeaseSec N): a call holding a concurrency slot longer than this is treated as lost and frees it, so a dropped connection never keeps a slot; 10..86400, default 600 adopted")
fn defaultConcurrencyLeaseSec -> Int64
  600

; (:m :ref GW-LIMIT-SCOPES :do "(:gateway :concurrencyPollMs N): how often a call parked behind a full :concurrency limit asks again, up to the call's queue budget; 10..5000, default 250 adopted")
fn defaultConcurrencyPollMs -> Int64
  250

; (:m :ref GW-BUCKET-SHORTWAIT :do "how long a chain member before the last waits for its own rpm bucket to refill before the cascade moves on (the last member keeps its 30 s); (:gateway :bucketWaitSec N), default 5 s adopted")
fn defaultBucketWaitSec -> Float64
  5.0

fn bucketWaitValue props: (Map String rd/SExpr) -> (Option Float64)
  (match (mapGet props "bucketWaitSec")
    ((none) none)
    ((some v) (match (asnScalar v) ((scalarInt n) (some (int64ToFloat64 n))) ((scalarFloat f) (some f)) (_ (some -1.0)))))

fn gatewayBucketWaitSecFromProps g: (Map String rd/SExpr) -> Float64
  (match (bucketWaitValue g)
    ((some f) (if (> f 0.0) f (defaultBucketWaitSec)))
    ((none) (defaultBucketWaitSec)))

fn gatewayBucketWaitWarnings g: (Map String rd/SExpr) -> (List String)
  (match (bucketWaitValue g)
    ((some f) (if (> f 0.0) (list) (list ":bucketWaitSec must be a positive number; using the default")))
    ((none) (list)))

; (:m :ref GW-ALL-DOWN-RETRY-AFTER :do "how long the last chain member waits for its rpm bucket when the caller gave no queue budget (X-ASL-Queue-Ms, X-ASL-Queue-Timeout, body queue_timeout); (:gateway :queueBudgetSec N), default 30 s adopted, a non-positive value warns and keeps the default")
fn defaultQueueBudgetSec -> Float64
  30.0

fn queueBudgetValue props: (Map String rd/SExpr) -> (Option Float64)
  (match (mapGet props "queueBudgetSec")
    ((none) none)
    ((some v) (match (asnScalar v) ((scalarInt n) (some (int64ToFloat64 n))) ((scalarFloat f) (some f)) (_ (some -1.0)))))

; (:m :ref GW-LIMIT-LEFTOVERS :do "(:gateway :queueBudgetSec N) is 1..3600 seconds (3600 adopted as the upper bound, a longer wait outlives any client): above it config check is an error and the runtime load warns and keeps the default 30")
fn queueBudgetMaxSec -> Float64
  3600.0

; (:m :ref GW-LIMIT-LEFTOVERS :do "(:gateway :busyRetrySec N): the Retry-After the gateway puts on a 503 it makes itself when a retry soon is the right answer (an endpoint that went away or did not warm in time, no endpoint admitted); 1..3600, default 1 adopted, the wait Leon applies to a 503 without the header")
fn defaultBusyRetrySec -> Int64
  1

fn gatewayQueueBudgetSecFromProps g: (Map String rd/SExpr) -> Float64
  (match (queueBudgetValue g)
    ((some f) (if (and (> f 0.0) (<= f (queueBudgetMaxSec))) f (defaultQueueBudgetSec)))
    ((none) (defaultQueueBudgetSec)))

fn gatewayQueueBudgetWarnings g: (Map String rd/SExpr) -> (List String)
  (match (queueBudgetValue g)
    ((some f) (if (and (> f 0.0) (<= f (queueBudgetMaxSec))) (list) (list ":queueBudgetSec must be a positive number of at most 3600 seconds; using the default")))
    ((none) (list)))

fn queueBudgetRangeErrors g: (Map String rd/SExpr) -> (List String)
  (match (queueBudgetValue g)
    ((some f) (if (> f (queueBudgetMaxSec)) (list ":queueBudgetSec must be at most 3600 seconds") (list)))
    ((none) (list)))

; (:m :ref GW-ALL-DOWN-RETRY-AFTER :do "config check is strict where the runtime load only warns: a non-positive :bucketWaitSec or :queueBudgetSec is an error in the check receipt, while serve keeps the default so a live hub never dies on it")
fn waitErrorOf key: String value: (Option Float64) -> (List String)
  (match value
    ((some f) (if (> f 0.0) (list) (list (str ":" key " must be a positive number of seconds"))))
    ((none) (list)))

fn topIntOf g: (Map String rd/SExpr) key: String -> (Option Int64)
  (match (mapGet g key)
    ((none) none)
    ((some value) (match (asnScalar value) ((scalarInt n) (some n)) (_ none))))

; (:m :ref GW-429-WINDOW-WAIT :do "config check ranges for the 429 cooldown rows: :cooldown429Sec 1..3600, :cooldown429MaxSec 1..90000 and not under :cooldown429Sec, :cooldownSlackSec 0..30; a present value that is not an integer is an error too, while serve falls back to the default")
fn cooldownErrorOf g: (Map String rd/SExpr) key: String lo: Int64 hi: Int64 -> (List String)
  (rangeErrorOf g key lo hi "seconds")

fn rangeErrorOf g: (Map String rd/SExpr) key: String lo: Int64 hi: Int64 unit: String -> (List String)
  (match (mapGet g key)
    ((none) (list))
    ((some _)
      (match (topIntOf g key)
        ((some n) (if (and (>= n lo) (<= n hi)) (list) (list (str ":" key " must be an integer from " lo " to " hi " " unit))))
        ((none) (list (str ":" key " must be an integer number of " unit))))))

fn gatewayCooldownErrors g: (Map String rd/SExpr) -> (List String)
  (let [(base (topIntOf g "cooldown429Sec"))
        (top (topIntOf g "cooldown429MaxSec"))
        (order (match base
                 ((some b) (match top ((some m) (if (< m b) (list ":cooldown429MaxSec must not be under :cooldown429Sec") (list))) ((none) (list))))
                 ((none) (list))))]
    (listAppend (listAppend (cooldownErrorOf g "cooldown429Sec" 1 3600) (cooldownErrorOf g "cooldown429MaxSec" 1 90000))
                (listAppend (listAppend (cooldownErrorOf g "cooldownSlackSec" 0 30) (cooldownErrorOf g "parkMaxSec" 60 2764800))
                            (listAppend (listAppend (rangeErrorOf g "ledgerMaxBytes" 65536 1073741824 "bytes") (rangeErrorOf g "ledgerKeep" 1 64 "files"))
                                        (listAppend (rangeErrorOf g "contextCap" 1 10000000 "tokens") order)))))

; (:m :ref GW-SESSION-AFFINITY :do "config check for the affinity rows: :affinity is true or false, :affinityStickSec 1..86400, :affinityForgetSec 1..604800 and not under :affinityStickSec, :affinitySwitch dropReasoning or keep")
fn gatewayAffinityErrors g: (Map String rd/SExpr) -> (List String)
  (let [(on (match (mapGet g "affinity")
              ((none) (list))
              ((some v) (match (asnScalar v) ((scalarBool _) (list)) (_ (list ":affinity must be true or false"))))))
        (switch (match (mapGet g "affinitySwitch")
                  ((none) (list))
                  ((some v) (match (asnScalar v)
                              ((scalarStr s) (if (listContains? (list "dropReasoning" "keep") s) (list) (list ":affinitySwitch must be dropReasoning or keep")))
                              (_ (list ":affinitySwitch must be dropReasoning or keep"))))))
        (order (match (topIntOf g "affinityStickSec")
                 ((some s) (match (topIntOf g "affinityForgetSec") ((some f) (if (< f s) (list ":affinityForgetSec must not be under :affinityStickSec") (list))) ((none) (list))))
                 ((none) (list))))]
    (listAppend (listAppend on switch)
                (listAppend (listAppend (cooldownErrorOf g "affinityStickSec" 1 86400) (cooldownErrorOf g "affinityForgetSec" 1 604800)) order)))

; (:m :ref GW-LIMIT-LEARN :do "the learn settings, range checked in config check and kept at their defaults at runtime: :learnRamp true|false (default false), :learnRampPct 5..100 (default 25), :learnWindows a string of window names from minute hour fiveHour day week")
fn learnWindowErrors s: String -> (List String)
  (let [(bad (filter (fn [(w String)] -> Bool (not (listContains? (list "minute" "hour" "fiveHour" "day" "week") w))) (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit s " "))))]
    (if (listEmpty? bad) (list) (list (str ":learnWindows names unknown windows: " (stringJoin bad " ")))))

fn learnConfigErrors g: (Map String rd/SExpr) -> (List String)
  (let [(ramp (match (mapGet g "learnRamp")
                ((none) (list))
                ((some v) (match (asnScalar v) ((scalarBool _) (list)) (_ (list ":learnRamp must be true or false"))))))
        (windows (match (mapGet g "learnWindows")
                   ((none) (list))
                   ((some v) (match (asnScalar v) ((scalarStr s) (learnWindowErrors s)) (_ (list ":learnWindows must be a string of window names"))))))]
    (listAppend (listAppend ramp windows) (rangeErrorOf g "learnRampPct" 5 100 "percent")))

fn gatewayWaitErrors g: (Map String rd/SExpr) -> (List String)
  (listAppend (listAppend (listAppend (listAppend (listAppend (waitErrorOf "bucketWaitSec" (bucketWaitValue g)) (waitErrorOf "queueBudgetSec" (queueBudgetValue g))) (gatewayCooldownErrors g))
              (gatewayAffinityErrors g))
              (gatewayLimitErrors g))
              (listAppend (listAppend (queueBudgetRangeErrors g) (rangeErrorOf g "busyRetrySec" 1 3600 "seconds")) (learnConfigErrors g)))

fn gatewayLimitWindows -> (List String)
  (list "minute" "hour" "fiveHour" "rollingDay" "day" "week" "month")

fn limitStr props: (Map String rd/SExpr) key: String -> String
  (match (mapGet props key)
    ((none) "")
    ((some v) (resultOr (asn_name_or_string v key) "")))

fn limitInt props: (Map String rd/SExpr) key: String -> Int64
  (match (mapGet props key)
    ((none) 0)
    ((some v) (match (asnScalar v) ((scalarInt n) n) (_ -1))))

fn itemsOf g: (Map String rd/SExpr) key: String -> (List rd/SExpr)
  (match (mapGet g key)
    ((none) (list))
    ((some value) (match value ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list)))))

fn limitItems g: (Map String rd/SExpr) -> (List rd/SExpr)
  (itemsOf g "limits")

fn limitFloat props: (Map String rd/SExpr) key: String -> Float64
  (match (mapGet props key)
    ((none) 0.0)
    ((some v) (match (asnScalar v) ((scalarFloat f) f) ((scalarInt n) (int64ToFloat64 n)) (_ -1.0))))

fn limitScopes -> (List String)
  (list "account" "group" "model" "endpoint")

; (:m :ref GW-LIMIT-LONG-WINDOW :do "even spreads a calendar window's cap over the whole window; remaining spreads what is left of it over the days left, today included; off never paces, so the row stops calls only once its cap is spent")
fn limitPaces -> (List String)
  (list "even" "remaining" "off")

fn limitMaxConcurrency -> Int64
  1024

fn limitWho provider: String group: String endpoint: String -> String
  (cond
    ((not (stringEmpty? provider)) provider)
    ((not (stringEmpty? group)) (str "group " group))
    (else endpoint))

fn limitOfItem item: rd/SExpr -> (Result GatewayLimit String)
  (match (asnProps item (some ":limit"))
    ((err e) (err e))
    ((ok p)
     (let [(provider (limitStr p "provider"))
           (scope (if (stringEmpty? (limitStr p "scope")) "account" (limitStr p "scope")))
           (model (limitStr p "model"))
           (group (limitStr p "group"))
           (endpoint (limitStr p "endpoint"))
           (window (limitStr p "window"))
           (calls (limitInt p "calls"))
           (tokens (limitInt p "tokens"))
           (tIn (limitInt p "tokensIn"))
           (tOut (limitInt p "tokensOut"))
           (tCached (limitInt p "tokensCached"))
           (usd (limitFloat p "usd"))
           (conc (limitInt p "concurrency"))
           (maxCap (limitInt p "max"))
           (reset (if (mapHas? p "resetDay") (limitInt p "resetDay") 1))
           (pace (if (stringEmpty? (limitStr p "pace")) "even" (limitStr p "pace")))
           (windowed (or (> calls 0) (or (> tokens 0) (or (> tIn 0) (or (> tOut 0) (or (> tCached 0) (> usd 0.0)))))))
           (who (limitWho provider group endpoint))]
       (cond
         ((not (listContains? (limitScopes) scope)) (err (str "limit " who ": :scope must be account, group, model or endpoint, found " scope)))
         ((and (or (= scope "account") (= scope "model")) (stringEmpty? provider)) (err "limit row needs :provider"))
         ((and (= scope "group") (stringEmpty? group)) (err "limit row: :scope group needs :group"))
         ((and (= scope "endpoint") (stringEmpty? endpoint)) (err "limit row: :scope endpoint needs :endpoint"))
         ((and (= scope "model") (stringEmpty? model)) (err (str "limit " who ": :scope model needs :model")))
         ((or (< calls 0) (or (< tokens 0) (or (< tIn 0) (or (< tOut 0) (or (< tCached 0) (< usd 0.0)))))) (err (str "limit " who ": :calls :tokens :tokensIn :tokensOut :tokensCached and :usd must be whole numbers or amounts of zero or more")))
         ((or (< conc 0) (> conc (limitMaxConcurrency))) (err (str "limit " who ": :concurrency must be a whole number from 1 to 1024")))
         ((and windowed (not (listContains? (gatewayLimitWindows) window))) (err (str "limit " who ": :window must be one of minute hour fiveHour rollingDay day week month, found " window)))
         ((and (not windowed) (= conc 0)) (err (str "limit " who " " window ": needs :calls, :tokens, :tokensIn, :tokensOut, :tokensCached, :usd or :concurrency")))
         ((or (< reset 1) (> reset 31)) (err (str "limit " who ": :resetDay must be a day of the month from 1 to 31, found " (stringFromInt64 reset))))
         ((and (!= reset 1) (!= window "month")) (err (str "limit " who " " window ": :resetDay applies only to a month window")))
         ((not (listContains? (limitPaces) pace)) (err (str "limit " who ": :pace must be even, remaining or off, found " pace)))
         ((and (= pace "remaining") (not (listContains? (list "day" "week" "month") window))) (err (str "limit " who " " window ": :pace remaining needs a day, week or month window")))
         (else (ok (GatewayLimit :provider provider :scope scope :model model :window window :calls calls :tokens tokens
                                 :group group :endpoint endpoint :tokensIn tIn :tokensOut tOut :tokensCached tCached :usd usd :concurrency conc :max maxCap :resetDay reset :pace pace)))))))

; (:m :ref GW-DAILY-SHORTHAND :do "a provider row (:provider :id P ... :dailyCalls N) is the account limit row (:limit :provider P :scope account :window day :calls N); a missing, zero or invalid N makes no row")
fn dailyCallsLimit p: (Map String rd/SExpr) -> (List GatewayLimit)
  (let [(n (limitInt p "dailyCalls"))]
    (if (> n 0)
      (list (GatewayLimit :provider (limitStr p "id") :scope "account" :model "" :window "day" :calls n :tokens 0
                          :group "" :endpoint "" :tokensIn 0 :tokensOut 0 :tokensCached 0 :usd 0.0 :concurrency 0))
      (list)))

fn gatewayLimitsFromProps g: (Map String rd/SExpr) -> (List GatewayLimit)
  (listAppend
    (fold (fn [(acc (List GatewayLimit)) (it rd/SExpr)] -> (List GatewayLimit)
            (match (limitOfItem it) ((ok l) (listAppend acc (list l))) ((err _) acc)))
      (list) (limitItems g))
    (listFlatMap (fn [(it rd/SExpr)] -> (List GatewayLimit) (match (asnProps it (some ":provider")) ((ok p) (dailyCallsLimit p)) ((err _) (list)))) (itemsOf g "providers")))

fn gatewayLimitsFromText text: String -> (List GatewayLimit)
  (match (ast/readForms (lx/tokenize text))
    ((err _) (list))
    ((ok forms)
     (if (!= (listLength forms) 1)
       (list)
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (asnProps top (some ":gateway"))
           ((err _) (list))
           ((ok g) (gatewayLimitsFromProps g)))))))

; (:m :ref GW-LIMIT-WINDOWS :do "a malformed limit row is dropped from the table and named here, never silently")
fn gatewayLimitWarnings g: (Map String rd/SExpr) -> (List String)
  (fold (fn [(acc (List String)) (it rd/SExpr)] -> (List String)
          (match (limitOfItem it) ((ok _) acc) ((err e) (listAppend acc (list (str "limits: " e))))))
    (fold (fn [(acc (List String)) (it rd/SExpr)] -> (List String)
            (match (asnProps it (some ":provider"))
              ((err _) acc)
              ((ok p) (if (and (some? (mapGet p "dailyCalls")) (<= (limitInt p "dailyCalls") 0))
                        (listAppend acc (list (str "limits: provider " (limitStr p "id") ": :dailyCalls must be a whole number of 1 or more")))
                        acc))))
      (list) (itemsOf g "providers"))
    (limitItems g))

fn rowProps g: (Map String rd/SExpr) key: String tag: String -> (List (Map String rd/SExpr))
  (fold (fn [(acc (List (Map String rd/SExpr))) (it rd/SExpr)] -> (List (Map String rd/SExpr))
          (match (asnProps it (some tag)) ((ok p) (listAppend acc (list p))) ((err _) acc)))
    (list) (itemsOf g key))

fn namesOf v: rd/SExpr -> (List String)
  (let [(items (match v ((rd/sexprList l) l) ((rd/sexprVect vv) vv) (_ (list))))]
    (filter (fn [(s String)] -> Bool (not (stringEmpty? s)))
      (map (fn [(it rd/SExpr)] -> String (match (asnScalar it) ((scalarStr s) s) (_ ""))) items)))

fn groupOfProps p: (Map String rd/SExpr) -> GatewayGroup
  (GatewayGroup :id (limitStr p "id") :provider (limitStr p "provider")
                :models (match (mapGet p "models") ((none) (list)) ((some v) (namesOf v))))

fn gatewayGroupsFromProps g: (Map String rd/SExpr) -> (List GatewayGroup)
  (map groupOfProps (rowProps g "groups" ":group"))

fn priceOfProps p: (Map String rd/SExpr) -> (Pair String (Pair Float64 Float64))
  (pair (limitStr p "id") (pair (limitFloat p "priceInPerM") (limitFloat p "priceOutPerM")))

; (:m :ref GW-LIMIT-SCOPES :do "the group rows, each provider's :base and each model's price per million tokens, read from the config text the server already holds")
fn gatewayLimitScopeFromProps g: (Map String rd/SExpr) -> LimitScope
  (LimitScope :groups (gatewayGroupsFromProps g)
              :bases (map (fn [(p (Map String rd/SExpr))] -> (Pair String String) (pair (limitStr p "id") (limitStr p "base"))) (rowProps g "providers" ":provider"))
              :prices (map priceOfProps (rowProps g "models" ":model")))

fn gatewayLimitScopeFromText text: String -> LimitScope
  (match (ast/readForms (lx/tokenize text))
    ((err _) (emptyLimitScope))
    ((ok forms)
     (if (!= (listLength forms) 1)
       (emptyLimitScope)
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (asnProps top (some ":gateway"))
           ((err _) (emptyLimitScope))
           ((ok g) (gatewayLimitScopeFromProps g)))))))

fn groupErrors g: (Map String rd/SExpr) -> (List String)
  (let [(groups (gatewayGroupsFromProps g))
        (models (map (fn [(p (Map String rd/SExpr))] -> (Pair String String) (pair (limitStr p "id") (limitStr p "provider"))) (rowProps g "models" ":model")))]
    (fold (fn [(acc (List String)) (gr GatewayGroup)] -> (List String)
            (let [(dup (> (listLength (filter (fn [(o GatewayGroup)] -> Bool (= o.id gr.id)) groups)) 1))
                  (bad (filter (fn [(m String)] -> Bool (not (listAny? (fn [(mp (Pair String String))] -> Bool (and (= (pairFirst mp) m) (= (pairSecond mp) gr.provider))) models))) gr.models))]
              (cond
                ((stringEmpty? gr.id) (listAppend acc (list "groups: a group row needs :id")))
                (dup (listAppend acc (list (str "groups: group " gr.id " is declared twice"))))
                ((stringEmpty? gr.provider) (listAppend acc (list (str "groups: group " gr.id " needs :provider"))))
                ((listEmpty? gr.models) (listAppend acc (list (str "groups: group " gr.id " needs :models"))))
                ((not (listEmpty? bad)) (listAppend acc (list (str "groups: group " gr.id " names " (stringJoin bad " ") " that is not a model of provider " gr.provider))))
                (else acc))))
      (list) groups))

fn limitGroupErrors g: (Map String rd/SExpr) -> (List String)
  (let [(groups (gatewayGroupsFromProps g))]
    (fold (fn [(acc (List String)) (it rd/SExpr)] -> (List String)
            (match (limitOfItem it)
              ((err _) acc)
              ((ok l) (if (and (= l.scope "group") (not (listAny? (fn [(gr GatewayGroup)] -> Bool (= gr.id l.group)) groups)))
                        (listAppend acc (list (str "limits: group " l.group " is not declared under :groups")))
                        acc))))
      (list) (limitItems g)))

; (:m :ref GW-LIMIT-SCOPES :do "config check is strict where the runtime load drops or warns: a malformed limit row, a group that names an unknown model or is declared twice, a limit naming an undeclared group and an out-of-range :concurrencyLeaseSec or :concurrencyPollMs are errors")
fn gatewayLimitErrors g: (Map String rd/SExpr) -> (List String)
  (listAppend (listAppend (gatewayLimitWarnings g) (listAppend (groupErrors g) (limitGroupErrors g)))
              (listAppend (listAppend (rangeErrorOf g "concurrencyLeaseSec" 10 86400 "seconds") (listAppend (rangeErrorOf g "concurrencyPollMs" 10 5000 "milliseconds") (listAppend (rangeErrorOf g "requestDeadlineSec" 1 86400 "seconds") (listAppend (rangeErrorOf g "healthKeep" 1 10000 "files") (rangeErrorOf g "requestKeepRows" 100 10000000 "rows")))))
                          (listAppend (rangeErrorOf g "ledgerRollupKeepDays" 62 3660 "days") (rollupPathErrors g))))

; (:m :ref GW-LIMIT-LONG-WINDOW :do "an optional (:gateway ... :ledgerRollupPath \"...\") names the day-rollup file of the shared ledger; present, it is a non-empty string")
fn rollupPathErrors g: (Map String rd/SExpr) -> (List String)
  (match (mapGet g "ledgerRollupPath")
    ((none) (list))
    ((some v) (match (asnScalar v) ((scalarStr s) (if (stringEmpty? s) (list ":ledgerRollupPath must be a non-empty path") (list))) (_ (list ":ledgerRollupPath must be a quoted path")))))

fn listAppendOne xs: (List T) x: T -> (List T)
  (listAppend xs (list x))

fn isStringLiteral? expr: rd/SExpr -> Bool
  (match expr
    ((rd/sexprAtom v) (and (>= (stringLength v) 2) (stringStartsWith? v "\"") (stringEndsWith? v "\"")))
    (_ false))

fn isKeyword? expr: rd/SExpr -> Bool
  (match expr
    ((rd/sexprAtom v) (and (> (stringLength v) 1) (stringStartsWith? v ":") (not (stringStartsWith? v "\""))))
    (_ false))

fn isBareAtom? expr: rd/SExpr -> Bool
  (match expr
    ((rd/sexprAtom v) (and (not (stringEmpty? v)) (not (stringStartsWith? v ":")) (not (stringStartsWith? v "\""))))
    (_ false))

fn sexprRawText expr: rd/SExpr -> String
  (match expr
    ((rd/sexprAtom v) v)
    (_ ""))

fn unescapeLoop s: String i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (and (= c "\\") (< (+ i 1) n))
        (let [(nextC (optionOr (stringSlice s (+ i 1) (+ i 2)) ""))]
          (cond
            ((= nextC "\"") (unescapeLoop s (+ i 2) n (cons "\"" acc)))
            ((= nextC "\\") (unescapeLoop s (+ i 2) n (cons "\\" acc)))
            ((= nextC "n") (unescapeLoop s (+ i 2) n (cons "\n" acc)))
            ((= nextC "t") (unescapeLoop s (+ i 2) n (cons "\t" acc)))
            ((= nextC "r") (unescapeLoop s (+ i 2) n (cons "\r" acc)))
            (else (unescapeLoop s (+ i 2) n (cons nextC acc)))))
        (unescapeLoop s (+ i 1) n (cons c acc)))))

fn stripQuotesAndUnescape s: String -> String
  (let [(n (stringLength s))]
    (if (and (>= n 2) (stringStartsWith? s "\"") (stringEndsWith? s "\""))
      (let [(inner (optionOr (stringSlice s 1 (- n 1)) ""))]
        (if (stringContains? inner "\\")
          (unescapeLoop inner 0 (stringLength inner) (list))
          inner))
      s))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":")
    (lstripColons (optionOr (stringSlice s 1 (stringLength s)) ""))
    s)

fn isDigitChar c: String -> Bool
  (and (>= (charCode c) 48) (<= (charCode c) 57))

fn allDigits? s: String i: Int64 n: Int64 -> Bool
  (if (>= i n)
    (> n 0)
    (if (isDigitChar (optionOr (stringSlice s i (+ i 1)) ""))
      (allDigits? s (+ i 1) n)
      false))

fn isIntString? s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0) false
      (if (stringStartsWith? s "-")
        (and (> n 1) (allDigits? s 1 n))
        (allDigits? s 0 n))))

fn isFloatString? s: String -> Bool
  (let [(n (stringLength s))
        (dot (stringIndexOf s "."))]
    (match dot
      ((none) false)
      ((some dotIdx)
        (let [(prefix (optionOr (stringSlice s 0 dotIdx) ""))
              (suffix (optionOr (stringSlice s (+ dotIdx 1) n) ""))]
          (and (isIntString? prefix) (> (stringLength suffix) 0) (allDigits? suffix 0 (stringLength suffix)))))))

fn isEnvNameChar c: String -> Bool
  (let [(code (charCode c))]
    (or (= c "_")
        (and (>= code 65) (<= code 90))
        (and (>= code 97) (<= code 122))
        (and (>= code 48) (<= code 57))))

fn isEnvStartChar c: String -> Bool
  (let [(code (charCode c))]
    (or (= c "_")
        (and (>= code 65) (<= code 90))
        (and (>= code 97) (<= code 122))))

fn checkEnvChars s: String i: Int64 n: Int64 -> Bool
  (if (>= i n) true
    (if (isEnvNameChar (optionOr (stringSlice s i (+ i 1)) ""))
      (checkEnvChars s (+ i 1) n)
      false))

fn isValidEnvName? s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0) false
      (if (isEnvStartChar (optionOr (stringSlice s 0 1) ""))
        (checkEnvChars s 1 n)
        false)))

fn isHeaderNameChar c: String -> Bool
  (let [(code (charCode c))]
    (or (= c "-")
        (and (>= code 65) (<= code 90))
        (and (>= code 97) (<= code 122))
        (and (>= code 48) (<= code 57))))

fn checkHeaderNameChars s: String i: Int64 n: Int64 -> Bool
  (if (>= i n) true
    (if (isHeaderNameChar (optionOr (stringSlice s i (+ i 1)) ""))
      (checkHeaderNameChars s (+ i 1) n)
      false))

fn isValidHeaderName? s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0) false
      (checkHeaderNameChars s 0 n)))

fn rstripSlash s: String -> String
  (if (stringEndsWith? s "/")
    (rstripSlash (optionOr (stringSlice s 0 (- (stringLength s) 1)) ""))
    s)


fn asnName v: rd/SExpr what: String -> (Result String String)
  (match v
    ((rd/sexprAtom s)
      (if (or (stringEmpty? s) (stringStartsWith? s ":") (stringStartsWith? s "\""))
        (err (str what " must be a bare atom, found " s))
        (ok s)))
    (_ (err (str what " must be a bare atom, found compound"))))

; (:m :do "a bare atom names most things (:id plan), but a composite key like a role:lens pair (auditor:logic) cannot lex as one atom since ':' always breaks a symbol run; a quoted string carries it instead, so :id/:as/:intent accept either form")
fn asn_name_or_string v: rd/SExpr what: String -> (Result String String)
  (match (asnScalar v)
    ((scalarStr s) (if (stringEmpty? s) (err (str what " must be a bare atom or string, found " (sexprRawText v))) (ok s)))
    (_ (err (str what " must be a bare atom or string, found " (sexprRawText v)))))

fn asnScalar expr: rd/SExpr -> AsnScalar
  (match expr
    ((rd/sexprAtom raw)
      (if (isStringLiteral? expr)
        (scalarStr (stripQuotesAndUnescape raw))
        (cond
          ((= raw "true") (scalarBool true))
          ((= raw "false") (scalarBool false))
          ((isIntString? raw) (scalarInt (optionOr (stringToInt64 raw) 0)))
          ((isFloatString? raw) (match (stringToFloat64 raw) ((some f) (scalarFloat f)) ((none) (scalarStr (lstripColons raw)))))
          (else (scalarStr (lstripColons raw))))))
    ((rd/sexprList _) (scalarStr ""))
    ((rd/sexprVect _) (scalarStr "")))

fn parsePropsPairs items: (List rd/SExpr) what: String acc: (Map String rd/SExpr) -> (Result (Map String rd/SExpr) String)
  (match (listHead items)
    ((none) (ok acc))
    ((some kExpr)
      (let [(tail (optionOr (listTail items) (list)))]
        (match (listHead tail)
          ((none) (err (str what " has an odd number of items")))
          ((some vExpr)
            (let [(rest (optionOr (listTail tail) (list)))]
              (if (not (isKeyword? kExpr))
                (err (str what ": " (sexprRawText kExpr) " is not a :keyword"))
                (let [(key (lstripColons (sexprRawText kExpr)))]
                  (parsePropsPairs rest what (mapSet acc key vExpr))))))))))

fn asnProps form: rd/SExpr head: (Option String) -> (Result (Map String rd/SExpr) String)
  (let [(what (match head ((some h) (str "(" h " ...)")) ((none) "a property list")))]
    (match form
      ((rd/sexprList items)
        (match head
          ((some h)
            (match (listHead items)
              ((none) (err (str "expected " what ", found ()")))
              ((some first)
                (if (!= (sexprRawText first) h)
                  (err (str "expected " what ", found (" (sexprRawText first) " ...)"))
                  (let [(rest (optionOr (listTail items) (list)))]
                    (if (!= (mod (listLength rest) 2) 0)
                      (err (str what " has an odd number of items"))
                      (parsePropsPairs rest what (mapEmpty))))))))
          ((none)
            (if (!= (mod (listLength items) 2) 0)
              (err (str what " has an odd number of items"))
              (parsePropsPairs items what (mapEmpty))))))
      (_ (err (str "expected " what ", found compound")))))

fn asnFigure expr: rd/SExpr -> AsnScalar
  (match expr
    ((rd/sexprList items)
      (match (asnProps expr (none))
        ((ok props)
          (match (mapGet props "v")
            ((some vExpr) (asnScalar vExpr))
            ((none) (asnScalar expr))))
        ((err _) (asnScalar expr))))
    (_ (asnScalar expr)))


fn checkTopP props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "topP")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarFloat f)
            (if (and (not (< f 0.0)) (not (> f 1.0)))
              (pair (with cur :topP (some f)) errs)
              (pair cur (cons (str what ": :topP must be a number in 0..1") errs))))
          ((scalarInt n)
            (if (and (not (< n 0)) (not (> n 1)))
              (pair (with cur :topP (some (int64ToFloat64 n))) errs)
              (pair cur (cons (str what ": :topP must be a number in 0..1") errs))))
          (_ (pair cur (cons (str what ": :topP must be a number in 0..1") errs)))))))

fn checkTemperature props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "temperature")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarFloat f) (pair (with cur :temperature (some f)) errs))
          ((scalarInt n) (pair (with cur :temperature (some (int64ToFloat64 n))) errs))
          (_ (pair cur (cons (str what ": :temperature must be a number") errs)))))))

fn checkTemperatureFixed props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "temperatureFixed")
    ((none) (pair cur errs))
    ((some expr)
      (let [(clash (if (mapHas? props "temperature") (list (str what ": :temperatureFixed and :temperature are exclusive on one row")) (list)))]
        (match (asnFigure expr)
          ((scalarFloat f) (pair (with cur :temperatureFixed (some f)) (listAppend clash errs)))
          ((scalarInt n) (pair (with cur :temperatureFixed (some (int64ToFloat64 n))) (listAppend clash errs)))
          (_ (pair cur (cons (str what ": :temperatureFixed must be a number") (listAppend clash errs))))))))

fn checkEffort props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "effort")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarStr s)
            (if (or (= s "low") (or (= s "medium") (or (= s "high") (or (= s "xhigh") (= s "none")))))
              (pair (with cur :effort (some s)) errs)
              (pair cur (cons (str what ": :effort must be low, medium, high, xhigh or none") errs))))
          (_ (pair cur (cons (str what ": :effort must be low, medium, high, xhigh or none") errs)))))))

; (:m :ref GWREASON :do "a model row's :effortDialect names how its :effort reaches the provider; absent means the provider's built-in default")
fn effortDialects -> (List String)
  (list "reasoningEffort" "openrouter" "chatTemplateThinking" "glmThinking" "gemini" "off")

fn checkEffortDialect props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "effortDialect")
    ((none) (pair cur errs))
    ((some expr)
      (match (asnFigure expr)
        ((scalarStr s)
          (if (listContains? (effortDialects) s)
            (pair (with cur :effortDialect (some s)) errs)
            (pair cur (cons (str what ": :effortDialect must be one of reasoningEffort, openrouter, chatTemplateThinking, glmThinking, gemini, off") errs))))
        (_ (pair cur (cons (str what ": :effortDialect must be one of reasoningEffort, openrouter, chatTemplateThinking, glmThinking, gemini, off") errs))))))

fn checkMaxTokens props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "maxTokens")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :maxTokens (some n)) errs)
              (pair cur (cons (str what ": :maxTokens must be a positive number") errs))))
          ((scalarFloat f)
            (if (and (> f 0.0) (some? (float64ToInt64 f)))
              (pair (with cur :maxTokens (float64ToInt64 f)) errs)
              (pair cur (cons (str what ": :maxTokens must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :maxTokens must be a positive number") errs)))))))

fn checkContextBudget props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (let [(key (if (mapHas? props "contextBudget") "contextBudget" "contextTokens"))
        (found (match (mapGet props "contextBudget") ((some e) (some e)) ((none) (mapGet props "contextTokens"))))]
    (match found
      ((none) (pair cur errs))
      ((some expr)
        (let [(sc (asnFigure expr))]
          (match sc
            ((scalarInt n)
              (if (> n 0)
                (pair (with cur :contextBudget (some n)) errs)
                (pair cur (cons (str what ": :" key " must be a positive number") errs))))
            ((scalarFloat f)
              (if (and (> f 0.0) (some? (float64ToInt64 f)))
                (pair (with cur :contextBudget (float64ToInt64 f)) errs)
                (pair cur (cons (str what ": :" key " must be a positive number") errs))))
            (_ (pair cur (cons (str what ": :" key " must be a positive number") errs))))))))

fn checkTimeoutSec props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "timeoutSec")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarFloat f)
            (if (> f 0.0)
              (pair (with cur :timeoutSec (some f)) errs)
              (pair cur (cons (str what ": :timeoutSec must be a positive number") errs))))
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :timeoutSec (some (int64ToFloat64 n))) errs)
              (pair cur (cons (str what ": :timeoutSec must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :timeoutSec must be a positive number") errs)))))))

fn checkFirstByteSec props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "firstByteSec")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarFloat f)
            (if (> f 0.0)
              (pair (with cur :firstByteSec (some f)) errs)
              (pair cur (cons (str what ": :firstByteSec must be a positive number") errs))))
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :firstByteSec (some (int64ToFloat64 n))) errs)
              (pair cur (cons (str what ": :firstByteSec must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :firstByteSec must be a positive number") errs)))))))

; (:m :ref NATIVE-TOOLS-DEFAULT :do "a model row's :nativeTools false marks a route that rejects or mishandles native tools: the gateway strips tools and tool_choice from the body it sends there, so the caller's text contract carries the turn; absent means tools pass through")
fn checkNativeTools props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "nativeTools")
    ((none) (pair cur errs))
    ((some expr)
      (match (asnFigure expr)
        ((scalarBool b) (pair (with cur :nativeTools (some b)) errs))
        (_ (pair cur (cons (str what ": :nativeTools must be true or false") errs))))))

fn checkStream props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "stream")
    ((none) (pair cur errs))
    ((some expr)
      (match (asnFigure expr)
        ((scalarBool b) (pair (with cur :stream (some b)) errs))
        (_ (pair cur (cons (str what ": :stream must be true or false") errs))))))

fn checkReasoning props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "reasoning")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarBool b) (pair (with cur :reasoning (some b)) errs))
          (_ (pair cur (cons (str what ": :reasoning must be true or false") errs)))))))

fn checkRpm props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "rpm")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarFloat f)
            (if (> f 0.0)
              (pair (with cur :rpm (some f)) errs)
              (pair cur (cons (str what ": :rpm must be a positive number") errs))))
          ((scalarInt n)
            (if (> n 0)
              (pair (with cur :rpm (some (int64ToFloat64 n))) errs)
              (pair cur (cons (str what ": :rpm must be a positive number") errs))))
          (_ (pair cur (cons (str what ": :rpm must be a positive number") errs)))))))

fn gatewayParams props: (Map String rd/SExpr) what: String -> (Pair GatewayParams (List String))
  (let [(s0 (pair (emptyGatewayParams) (list)))
        (s0b (checkTopP props what (pairFirst s0) (pairSecond s0)))
        (s1 (checkTemperature props what (pairFirst s0b) (pairSecond s0b)))
        (s2 (checkEffort props what (pairFirst s1) (pairSecond s1)))
        (s3 (checkMaxTokens props what (pairFirst s2) (pairSecond s2)))
        (s4 (checkContextBudget props what (pairFirst s3) (pairSecond s3)))
        (s5 (checkTimeoutSec props what (pairFirst s4) (pairSecond s4)))
        (s5b (checkFirstByteSec props what (pairFirst s5) (pairSecond s5)))
        (s6 (checkReasoning props what (pairFirst s5b) (pairSecond s5b)))
        (s7 (checkRpm props what (pairFirst s6) (pairSecond s6)))
        (s8 (checkApi props what (pairFirst s7) (pairSecond s7)))
        (s8b (checkEffortDialect props what (pairFirst s8) (pairSecond s8)))
        (s8c (checkPrefill props what (pairFirst s8b) (pairSecond s8b)))
        (s9 (checkRetry props what (pairFirst s8c) (pairSecond s8c)))
        (s9b (checkNativeTools props what (pairFirst s9) (pairSecond s9)))
        (s9c (checkTemperatureFixed props what (pairFirst s9b) (pairSecond s9b)))
        (s9d (checkStream props what (pairFirst s9c) (pairSecond s9c)))]
    (pair (pairFirst s9d) (listReverse (pairSecond s9d))))

fn checkApi props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "api")
    ((none) (pair cur errs))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarStr s)
            (if (or (= s "chat") (= s "responses"))
              (pair (with cur :api (some s)) errs)
              (pair cur (cons (str what ": :api must be chat or responses") errs))))
          (_ (pair cur (cons (str what ": :api must be chat or responses") errs)))))))

; (:m :ref PREFILL-OFF :do ":prefill false: the model rejects a trailing assistant message (vercel beam 400 missing reasoning_content, gemini flash-lite, ifm), so the gateway drops Leon's attractor prefill for it; Leon's continueReply already takes a whole reply when no prefill was honoured")
fn checkPrefill props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "prefill")
    ((none) (pair cur errs))
    ((some expr)
      (match (asnFigure expr)
        ((scalarBool b) (pair (with cur :prefill (some b)) errs))
        (_ (pair cur (cons (str what ": :prefill must be true or false") errs))))))

fn checkRetry props: (Map String rd/SExpr) what: String cur: GatewayParams errs: (List String) -> (Pair GatewayParams (List String))
  (match (mapGet props "retry")
    ((none) (pair cur errs))
    ((some expr)
      (match (parseRetryPolicy expr what)
        ((err e) (pair cur (cons e errs)))
        ((ok policy) (pair (with cur :retry (some policy)) errs)))))

fn paramPresent? params: GatewayParams k: String -> Bool
  (cond
    ((= k "temperature") (some? params.temperature))
    ((= k "topP") (some? params.topP))
    ((= k "effort") (some? params.effort))
    ((= k "effortDialect") (some? params.effortDialect))
    ((= k "maxTokens") (some? params.maxTokens))
    ((= k "contextBudget") (some? params.contextBudget))
    ((= k "timeoutSec") (some? params.timeoutSec))
    ((= k "firstByteSec") (some? params.firstByteSec))
    ((= k "reasoning") (some? params.reasoning))
    ((= k "rpm") (some? params.rpm))
    ((= k "api") (some? params.api))
    ((= k "prefill") (some? params.prefill))
    ((= k "nativeTools") (some? params.nativeTools))
    ((= k "temperatureFixed") (some? params.temperatureFixed))
    ((= k "stream") (some? params.stream))
    (else false))

fn scalarAsnValue sc: AsnScalar -> String
  (match sc
    ((scalarBool b) (if b "true" "false"))
    ((scalarInt n) (stringFromInt64 n))
    ((scalarFloat f) (stringFromFloat64 f))
    ((scalarStr s) (str "\"" (wire/asnEscape s) "\"")))

fn paramsShown props: (Map String rd/SExpr) params: GatewayParams -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (k String)] -> (List (Pair String String))
          (match (mapGet props k)
            ((none) acc)
            ((some expr)
              (if (paramPresent? params k)
                (listAppend acc (list (pair k (scalarAsnValue (asnFigure expr)))))
                acc))))
        (list)
        (list "temperature" "topP" "effort" "effortDialect" "maxTokens" "contextBudget" "timeoutSec" "firstByteSec" "reasoning" "rpm" "api" "prefill" "nativeTools" "temperatureFixed" "stream"))

fn shownHasKey? shown: (List (Pair String String)) k: String -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) k)) shown)

fn mergeShown base: (List (Pair String String)) own: (List (Pair String String)) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (o (Pair String String))] -> (List (Pair String String))
          (if (shownHasKey? acc (pairFirst o))
            (map (fn [(p (Pair String String))] -> (Pair String String) (if (= (pairFirst p) (pairFirst o)) o p)) acc)
            (listAppend acc (list o))))
        base
        own)

fn asnReadCheck text: String -> (Option String)
  (asnScan (stringChars text) 0 0)

fn asnScan cs: (List String) i: Int64 depth: Int64 -> (Option String)
  (match (listHead cs)
    ((none) (if (> depth 0) (some (str (stringFromInt64 depth) " unclosed ( at end of text")) (none)))
    ((some c)
      (let [(rest (optionOr (listTail cs) (list)))]
        (cond
          ((= c ";") (asnSkipLine rest (+ i 1) depth))
          ((= c "(") (asnScan rest (+ i 1) (+ depth 1)))
          ((= c ")") (if (= depth 0) (some (str "unbalanced ) at offset " (stringFromInt64 i))) (asnScan rest (+ i 1) (- depth 1))))
          ((= c "\"") (asnString rest (+ i 1) i depth))
          (else (asnScan rest (+ i 1) depth))))))

fn asnSkipLine cs: (List String) i: Int64 depth: Int64 -> (Option String)
  (match (listHead cs)
    ((none) (asnScan (list) i depth))
    ((some c) (if (= c "\n") (asnScan (optionOr (listTail cs) (list)) (+ i 1) depth) (asnSkipLine (optionOr (listTail cs) (list)) (+ i 1) depth))))

fn asnString cs: (List String) j: Int64 start: Int64 depth: Int64 -> (Option String)
  (match (listHead cs)
    ((none) (some (str "unterminated string at offset " (stringFromInt64 start))))
    ((some ch)
      (let [(rest (optionOr (listTail cs) (list)))
            (badEscape (some (str "bad string escape at offset " (stringFromInt64 j))))]
        (cond
          ((= ch "\"") (asnScan rest (+ j 1) depth))
          ((= ch "\\")
            (match (listHead rest)
              ((some e) (if (listContains? (list "\\" "\"" "n" "t") e) (asnString (optionOr (listTail rest) (list)) (+ j 2) start depth) badEscape))
              ((none) badEscape)))
          (else (asnString rest (+ j 1) start depth))))))


fn calibrationRowId idExpr: rd/SExpr -> (Result String String)
  (if (isStringLiteral? idExpr)
    (let [(id (stripQuotesAndUnescape (sexprRawText idExpr)))]
      (if (stringEmpty? id) (err "calibration row :id must be a string, found ''") (ok id)))
    (err (str "calibration row :id must be a string, found '" (sexprRawText idExpr) "'")))

fn parseCalibrationModel mForm: rd/SExpr -> (Result (Pair String (Pair GatewayParams (List (Pair String String)))) String)
  (match (asnProps mForm (some ":model"))
    ((err e) (err e))
    ((ok props)
      (match (match (mapGet props "id") ((none) (err "calibration row :id must be a string, found None")) ((some idExpr) (calibrationRowId idExpr)))
        ((err e) (err e))
        ((ok id)
          (let [(pRes (match (mapGet props "params")
                        ((none) (ok (mapEmpty)))
                        ((some pExpr) (match pExpr
                                        ((rd/sexprList _) (asnProps pExpr (none)))
                                        (_ (ok (mapEmpty)))))))]
            (match pRes
              ((err e) (err e))
              ((ok pProps)
                (let [(checked (gatewayParams pProps (str "calibration " id)))]
                  (if (listEmpty? (pairSecond checked))
                    (ok (pair id (pair (pairFirst checked) (paramsShown pProps (pairFirst checked)))))
                    (err (stringJoin (pairSecond checked) "; ")))))))))))

fn parseCalibrationModels modelsList: (List rd/SExpr) acc: (Map String (Pair GatewayParams (List (Pair String String)))) -> (Result (Map String (Pair GatewayParams (List (Pair String String)))) String)
  (match (listHead modelsList)
    ((none) (ok acc))
    ((some mForm)
      (let [(tail (optionOr (listTail modelsList) (list)))]
        (match (parseCalibrationModel mForm)
          ((err e) (err e))
          ((ok p) (parseCalibrationModels tail (mapSet acc (pairFirst p) (pairSecond p))))))))

fn calibrationRowsLoad! path: String -> (Result (Map String (Pair GatewayParams (List (Pair String String)))) String)
  (if (stringEmpty? path)
    (err "calibration registry not found")
    (match (fileReadString path)
      ((err e) (err (str "calibration registry " path " not found")))
      ((ok text)
        (let [(toks (lx/tokenize text))]
          (match (match (asnReadCheck text) ((some e) (err (ast/ParseError :msg e :line 0 :col 0))) ((none) (ast/readForms toks)))
            ((err e) (err (str "calibration registry " path ": " e.msg)))
            ((ok forms)
              (if (!= (listLength forms) 1)
                (err (str "calibration registry " path ": expected one (:calibrationIndex ...) form, found " (stringFromInt64 (listLength forms))))
                (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
                  (match (asnProps top (some ":calibrationIndex"))
                    ((err e) (err (str "calibration registry " path ": " e)))
                    ((ok props)
                      (match (mapGet props "models")
                        ((none) (ok (mapEmpty)))
                        ((some modelsExpr)
                          (match modelsExpr
                            ((rd/sexprList mList) (match (parseCalibrationModels mList (mapEmpty)) ((ok rows) (ok rows)) ((err e) (err (str "calibration registry " path ": " e)))))
                            ((rd/sexprVect mList) (match (parseCalibrationModels mList (mapEmpty)) ((ok rows) (ok rows)) ((err e) (err (str "calibration registry " path ": " e)))))
                            (_ (ok (mapEmpty))))))))))))))))

fn calibrationRegistryLoad! path: String -> (Result (Map String GatewayParams) String)
  (match (calibrationRowsLoad! path)
    ((err e) (err e))
    ((ok rows) (ok (mapFromPairs (map (fn [(p (Pair String (Pair GatewayParams (List (Pair String String)))))] -> (Pair String GatewayParams) (pair (pairFirst p) (pairFirst (pairSecond p)))) (mapPairs rows))))))


fn parseV1Route rf: rd/SExpr pid: String -> (Result GatewayRoute String)
  (match (asnProps rf (none))
    ((err e) (err e))
    ((ok props)
      (match (mapGet props "intent")
        ((none) (err (str "profile " pid " route :intent must be a bare atom, found ()")))
        ((some intentExpr)
          (match (asnName intentExpr (str "profile " pid " route :intent"))
            ((err e) (err e))
            ((ok rawIntent)
              (let [(intent (stringLower rawIntent))]
                (match (mapGet props "models")
                  ((none) (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings")))
                  ((some modelsExpr)
                    (match modelsExpr
                      ((rd/sexprList mItems)
                        (if (listEmpty? mItems)
                          (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                          (let [(allStr (listAll? (fn [(m rd/SExpr)] -> Bool (and (isStringLiteral? m) (not (stringEmpty? (stripQuotesAndUnescape (sexprRawText m)))))) mItems))]
                            (if (not allStr)
                              (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                              (ok (GatewayRoute :intent intent :chain (list) :models (map (fn [(m rd/SExpr)] -> String (stripQuotesAndUnescape (sexprRawText m))) mItems) :temperature none :temperatureOverride none :spread (list) :cooldownSec 60))))))
                      ((rd/sexprVect mItems)
                        (if (listEmpty? mItems)
                          (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                          (let [(allStr (listAll? (fn [(m rd/SExpr)] -> Bool (and (isStringLiteral? m) (not (stringEmpty? (stripQuotesAndUnescape (sexprRawText m)))))) mItems))]
                            (if (not allStr)
                              (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings"))
                              (ok (GatewayRoute :intent intent :chain (list) :models (map (fn [(m rd/SExpr)] -> String (stripQuotesAndUnescape (sexprRawText m))) mItems) :temperature none :temperatureOverride none :spread (list) :cooldownSec 60))))))
                      (_ (err (str "profile " pid " route " intent ": :models must be a non-empty list of strings")))))))))))))

fn parseV1Routes rItems: (List rd/SExpr) pid: String acc: (List GatewayRoute) -> (Result (List GatewayRoute) String)
  (match (listHead rItems)
    ((none) (ok (listReverse acc)))
    ((some rf)
      (let [(tail (optionOr (listTail rItems) (list)))]
        (match (parseV1Route rf pid)
          ((err e) (err e))
          ((ok route) (parseV1Routes tail pid (cons route acc)))))))

fn parseV1Profile pf: rd/SExpr profiles: (Map String (List GatewayRoute)) -> (Result (Pair String (List GatewayRoute)) String)
  (match (asnProps pf (some ":profile"))
    ((err e) (err e))
    ((ok pProps)
      (match (mapGet pProps "id")
        ((none) (err "(:profile :id ...) must be a bare atom, found ()"))
        ((some idExpr)
          (match (asnName idExpr "(:profile :id ...)")
            ((err e) (err e))
            ((ok pid)
              (if (mapHas? profiles pid)
                (err (str "profile " pid " is defined twice"))
                (match (mapGet pProps "routes")
                  ((none) (err (str "profile " pid ": :routes must be a non-empty list")))
                  ((some routesExpr)
                    (match routesExpr
                      ((rd/sexprList rItems)
                        (if (listEmpty? rItems)
                          (err (str "profile " pid ": :routes must be a non-empty list"))
                          (match (parseV1Routes rItems pid (list))
                            ((err e) (err e))
                            ((ok routes) (ok (pair pid routes))))))
                      ((rd/sexprVect rItems)
                        (if (listEmpty? rItems)
                          (err (str "profile " pid ": :routes must be a non-empty list"))
                          (match (parseV1Routes rItems pid (list))
                            ((err e) (err e))
                            ((ok routes) (ok (pair pid routes))))))
                      (_ (err (str "profile " pid ": :routes must be a non-empty list")))))))))))))

fn parseV1ProfilesList pfList: (List rd/SExpr) profiles: (Map String (List GatewayRoute)) -> (Result (Map String (List GatewayRoute)) String)
  (match (listHead pfList)
    ((none) (ok profiles))
    ((some pf)
      (let [(tail (optionOr (listTail pfList) (list)))]
        (match (parseV1Profile pf profiles)
          ((err e) (err e))
          ((ok pPair) (parseV1ProfilesList tail (mapSet profiles (pairFirst pPair) (pairSecond pPair))))))))

fn gatewayProfilesParse text: String -> (Result GatewayV1Config String)
  (let [(toks (lx/tokenize text))]
    (match (match (asnReadCheck text) ((some e) (err (ast/ParseError :msg e :line 0 :col 0))) ((none) (ast/readForms toks)))
      ((err e) (err (str e.msg)))
      ((ok forms)
        (if (!= (listLength forms) 1)
          (err (str "expected one (:gateway ...) form, found " (stringFromInt64 (listLength forms))))
          (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
            (match (asnProps top (some ":gateway"))
              ((err e) (err e))
              ((ok g)
                (match (mapGet g "profiles")
                  ((none) (err ":profiles must be a non-empty list of (:profile ...)"))
                  ((some pExpr)
                    (let [(pList (match pExpr ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
                      (if (listEmpty? pList)
                        (err ":profiles must be a non-empty list of (:profile ...)")
                        (match (parseV1ProfilesList pList (mapEmpty))
                          ((err e) (err e))
                          ((ok profiles)
                            (let [(defaultName (match (mapGet g "profile")
                                                 ((none) "default")
                                                 ((some defExpr) (resultOr (asnName defExpr "(:gateway :profile ...)") "default"))))]
                              (if (not (mapHas? profiles defaultName))
                                (err (str ":profile " defaultName " names no defined profile"))
                                (ok (GatewayV1Config :defaultProfile defaultName :profiles profiles)))))))))))))))))


fn defaultProviders! -> (Map String GatewayProvider)
  (let [(geminiBase "https://generativelanguage.googleapis.com/v1beta/openai")
        (groqBase (rstripSlash (optionOr (envGet "GROQ_BASE_URL") "https://api.groq.com/openai/v1")))
        (openrouterBase (rstripSlash (optionOr (envGet "OPENROUTER_BASE_URL") "https://openrouter.ai/api/v1")))
        (ollamaBase (str (rstripSlash (optionOr (envGet "OLLAMA_BASE_URL") "https://ollama.com")) "/v1"))
        (ollamaTimeout (optionOr (match (envGet "OLLAMA_TIMEOUT_SEC")
                                   ((none) (none))
                                   ((some s) (if (isFloatString? s) (stringToFloat64 s) (match (stringToInt64 s) ((some n) (some (int64ToFloat64 n)) ((none) (none)))))))
                                 300.0))
        (p1 (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "agy" :kind "cli" :base "" :keyEnv "" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none)))
        (p2 (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "codex" :kind "cli" :base "" :keyEnv "" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none)))
        (p3 (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "claude" :kind "cli" :base "" :keyEnv "" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none)))
        (p4 (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "gemini" :kind "openai" :base geminiBase :keyEnv "GEMINI_API_KEY" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 45.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none)))
        (p5 (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "groq" :kind "openai" :base groqBase :keyEnv "GROQ_API_KEY" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 45.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none)))
        (p6 (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "openrouter" :kind "openai" :base openrouterBase :keyEnv "OPENROUTER_API_KEY" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 45.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none)))
        (p7 (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "ollama" :kind "openai" :base ollamaBase :keyEnv "OLLAMA_API_KEY" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec ollamaTimeout :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none)))]
    (mapFromPairs (list (pair "agy" p1) (pair "codex" p2) (pair "claude" p3) (pair "gemini" p4) (pair "groq" p5) (pair "openrouter" p6) (pair "ollama" p7))))

fn extractPropList items: (List rd/SExpr) head: String accForms: (List (Map String rd/SExpr)) accErrs: (List String) -> (Pair (List (Map String rd/SExpr)) (List String))
  (match (listHead items)
    ((none) (pair (listReverse accForms) (listReverse accErrs)))
    ((some f)
      (let [(tail (optionOr (listTail items) (list)))]
        (match (asnProps f (some head))
          ((ok props) (extractPropList tail head (cons props accForms) accErrs))
          ((err e) (extractPropList tail head accForms (cons e accErrs)))))))

fn getSubForms g: (Map String rd/SExpr) key: String head: String -> (Pair (List (Map String rd/SExpr)) (List String))
  (match (mapGet g key)
    ((none) (pair (list) (list)))
    ((some expr)
      (match expr
        ((rd/sexprList items) (extractPropList items head (list) (list)))
        ((rd/sexprVect items) (extractPropList items head (list) (list)))
        (_ (pair (list) (list (str ":" key " must be a list of (" head " ...)")))))))

fn poolPositiveInt props: (Map String rd/SExpr) key: String -> (Result Int64 String)
  (match (mapGet props key)
    ((none) (err (str "pool requires :" key)))
    ((some expr)
      (match (asnScalar expr)
        ((scalarInt n) (if (> n 0) (ok n) (err (str "pool :" key " must be a positive integer"))))
        (_ (err (str "pool :" key " must be a positive integer"))))))

fn poolBool props: (Map String rd/SExpr) key: String -> (Result Bool String)
  (match (mapGet props key)
    ((none) (err (str "pool requires :" key)))
    ((some expr)
      (match (asnScalar expr)
        ((scalarBool b) (ok b))
        (_ (err (str "pool :" key " must be true or false"))))))

fn poolOptionalBool props: (Map String rd/SExpr) key: String -> (Result Bool String)
  (if (mapHas? props key) (poolBool props key) (ok false))

fn poolOptionalPath props: (Map String rd/SExpr) key: String -> (Result String String)
  (match (mapGet props key)
    ((none) (ok ""))
    ((some expr)
      (match (asnScalar expr)
        ((scalarStr text) (if (stringStartsWith? text "/") (ok text) (err (str "pool :" key " must be a path starting with /"))))
        (_ (err (str "pool :" key " must be a string path"))))))

fn parsePoolConfig expr: rd/SExpr -> (Result GatewayPool String)
  (match (asnProps expr (none))
    ((err e) (err (str "invalid :pool: " e)))
    ((ok props)
      (match (poolPositiveInt props "windowMs")
        ((err e) (err e))
        ((ok windowMs)
          (match (poolPositiveInt props "peakCount")
            ((err e) (err e))
            ((ok peakCount)
              (match (poolBool props "bypassWhileBusy")
                ((err e) (err e))
                ((ok bypassWhileBusy)
                  (match (poolPositiveInt props "requestTimeoutMs")
                    ((err e) (err e))
                    ((ok requestTimeoutMs)
                      (match (poolOptionalBool props "batch")
                        ((err e) (err e))
                        ((ok batch)
                          (match (poolOptionalPath props "scaleDownPath")
                            ((err e) (err e))
                            ((ok scaleDownPath)
                              (ok (GatewayPool :config (bp/makePoolConfig windowMs peakCount bypassWhileBusy requestTimeoutMs)
                                    :batch batch :scaleDownPath scaleDownPath))))))))))))))))

fn retryRequiredNonNegInt props: (Map String rd/SExpr) key: String what: String -> (Result Int64 String)
  (match (mapGet props key)
    ((none) (err (str what ": :retry requires :" key)))
    ((some expr)
      (match (asnScalar expr)
        ((scalarInt n) (if (>= n 0) (ok n) (err (str what ": :retry :" key " must be a nonnegative integer"))))
        (_ (err (str what ": :retry :" key " must be a nonnegative integer"))))))

fn retryOptionalPosInt props: (Map String rd/SExpr) key: String fallback: Int64 what: String -> (Result Int64 String)
  (match (mapGet props key)
    ((none) (ok fallback))
    ((some expr)
      (match (asnScalar expr)
        ((scalarInt n) (if (> n 0) (ok n) (err (str what ": :retry :" key " must be a positive integer"))))
        (_ (err (str what ": :retry :" key " must be a positive integer"))))))

; (:m :tags (retry) :do "(:retry (:max N :baseMs N :capMs N)): :max is the extra attempts after the first (0 keeps today's no-retry behaviour); :baseMs/:capMs default to 1000/20000 and bound the exponential backoff")
fn parseRetryPolicy expr: rd/SExpr what: String -> (Result RetryPolicy String)
  (match (asnProps expr (none))
    ((err e) (err (str what ": invalid :retry: " e)))
    ((ok props)
      (match (retryRequiredNonNegInt props "max" what)
        ((err e) (err e))
        ((ok maxN)
          (match (retryOptionalPosInt props "baseMs" 1000 what)
            ((err e) (err e))
            ((ok baseMs)
              (match (retryOptionalPosInt props "capMs" 20000 what)
                ((err e) (err e))
                ((ok capMs)
                  (if (< capMs baseMs)
                    (err (str what ": :retry :capMs must be >= :baseMs"))
                    (ok (RetryPolicy :maxAttempts maxN :baseMs baseMs :capMs capMs)))))))))))

fn applyOneProvider provs: (Map String GatewayProvider) curErrs: (List String) p: (Map String rd/SExpr) -> (Pair (Map String GatewayProvider) (List String))
  (match (mapGet p "id")
    ((none) (pair provs curErrs))
    ((some idExpr)
      (match (asnName idExpr "(:provider :id ...)")
        ((err e) (pair provs (listAppendOne curErrs e)))
        ((ok pid)
          (let [(withKeyErr (if (mapHas? p "key") (listAppendOne curErrs (str "provider " pid ": keys are named by :keyEnv, never stored in the file")) curErrs))
                (existing (optionOr (mapGet provs pid) (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id pid :kind "" :base "" :keyEnv "" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none))))
                (kind (match (mapGet p "kind")
                        ((some kExpr) (scalarToString (asnScalar kExpr)))
                        ((none) existing.kind)))
                (kindErr (if (and (!= kind "openai") (and (!= kind "cli") (and (!= kind "anthropic") (and (!= kind "gemini") (!= kind "gateway")))))
                           (listAppendOne withKeyErr (str "provider " pid ": :kind must be openai, anthropic, gemini, cli or gateway"))
                           (if (and (= kind "cli") (not (or (= pid "agy") (or (= pid "codex") (= pid "claude")))))
                             (listAppendOne withKeyErr (str "provider " pid ": a cli provider is one of agy, codex, claude"))
                             withKeyErr)))
                (baseRes (match (mapGet p "base")
                           ((none) (pair existing.base kindErr))
                           ((some bExpr)
                             (if (not (isStringLiteral? bExpr))
                               (pair existing.base (listAppendOne kindErr (str "provider " pid ": :base must be an http(s) URL string")))
                               (let [(bStr (stripQuotesAndUnescape (sexprRawText bExpr)))]
                                 (if (not (or (stringStartsWith? bStr "http://") (stringStartsWith? bStr "https://")))
                                   (pair existing.base (listAppendOne kindErr (str "provider " pid ": :base must be an http(s) URL string")))
                                   (pair (rstripSlash bStr) kindErr)))))))
                (base (pairFirst baseRes))
                (withBaseErr (pairSecond baseRes))
                (keyEnvRes (match (mapGet p "keyEnv")
                             ((none) (pair existing.keyEnv withBaseErr))
                             ((some keExpr)
                               (let [(ke (scalarToString (asnScalar keExpr)))]
                                 (if (not (isValidEnvName? ke))
                                   (pair existing.keyEnv (listAppendOne withBaseErr (str "provider " pid ": :keyEnv must name an environment variable")))
                                   (pair ke withBaseErr))))))
                (keyEnv (pairFirst keyEnvRes))
                (withKeErr (pairSecond keyEnvRes))
                (secretRes (match (mapGet p "secret")
                             ((none) (pair existing.secret withKeErr))
                             ((some sExpr)
                               (let [(sid (scalarToString (asnScalar sExpr)))]
                                 (if (isValidSecretId? sid)
                                   (pair sid withKeErr)
                                   (pair existing.secret (listAppendOne withKeErr (str "provider " pid ": :secret must name a secrets-file id"))))))))
                (secret (pairFirst secretRes))
                (withSecretErr (pairSecond secretRes))
                (pckRes (match (mapGet p "promptCacheKey")
                          ((none) (pair existing.promptCacheKey withSecretErr))
                          ((some pExpr)
                            (match (asnScalar pExpr)
                              ((scalarBool b) (pair b withSecretErr))
                              (_ (pair existing.promptCacheKey (listAppendOne withSecretErr (str "provider " pid ": :promptCacheKey must be true or false"))))))))
                (promptCacheKey (pairFirst pckRes))
                (withPckErr0 (pairSecond pckRes))
                (rsRes (match (mapGet p "rpmShared")
                         ((none) (pair existing.rpmShared withPckErr0))
                         ((some rsExpr)
                           (match (asnScalar rsExpr)
                             ((scalarBool b) (pair b withPckErr0))
                             (_ (pair existing.rpmShared (listAppendOne withPckErr0 (str "provider " pid ": :rpmShared must be true or false"))))))))
                (rpmShared (pairFirst rsRes))
                (dtRes (match (mapGet p "dropEmptyTools")
                         ((none) (pair existing.dropEmptyTools (pairSecond rsRes)))
                         ((some dtExpr)
                           (match (asnScalar dtExpr)
                             ((scalarBool b) (pair b (pairSecond rsRes)))
                             (_ (pair existing.dropEmptyTools (listAppendOne (pairSecond rsRes) (str "provider " pid ": :dropEmptyTools must be true or false"))))))))
                (dropEmptyTools (pairFirst dtRes))
                (arRes (match (mapGet p "assistantReasoning")
                         ((none) (pair existing.assistantReasoning (pairSecond dtRes)))
                         ((some arExpr)
                           (match (asnScalar arExpr)
                             ((scalarBool b) (pair b (pairSecond dtRes)))
                             (_ (pair existing.assistantReasoning (listAppendOne (pairSecond dtRes) (str "provider " pid ": :assistantReasoning must be true or false"))))))))
                (assistantReasoning (pairFirst arRes))
                (withPckErr (pairSecond arRes))
                (sessionHeaderRes (match (mapGet p "sessionHeader")
                                    ((none) (pair existing.sessionHeader withPckErr))
                                    ((some shExpr)
                                      (let [(sh (scalarToString (asnScalar shExpr)))]
                                        (if (not (isValidHeaderName? sh))
                                          (pair existing.sessionHeader (listAppendOne withPckErr (str "provider " pid ": :sessionHeader must name an http header")))
                                          (pair sh withPckErr))))))
                (sessionHeader (pairFirst sessionHeaderRes))
                (withShErr (pairSecond sessionHeaderRes))
                (timeoutRes (match (mapGet p "timeoutSec")
                              ((none) (pair existing.timeoutSec withShErr))
                              ((some tExpr)
                                (let [(sc (asnScalar tExpr))]
                                  (match sc
                                    ((scalarFloat f) (if (> f 0.0) (pair f withShErr) (pair existing.timeoutSec (listAppendOne withShErr (str "provider " pid ": :timeoutSec must be a positive number")))))
                                    ((scalarInt n) (if (> n 0) (pair (int64ToFloat64 n) withShErr) (pair existing.timeoutSec (listAppendOne withShErr (str "provider " pid ": :timeoutSec must be a positive number")))))
                                    (_ (pair existing.timeoutSec (listAppendOne withShErr (str "provider " pid ": :timeoutSec must be a positive number")))))))))
                (timeoutSec (pairFirst timeoutRes))
                (withToErr (pairSecond timeoutRes))
                (firstByteSecRes (match (mapGet p "firstByteSec")
                              ((none) (pair existing.firstByteSec withToErr))
                              ((some fbExpr)
                                (let [(sc (asnScalar fbExpr))]
                                  (match sc
                                    ((scalarFloat f) (if (> f 0.0) (pair f withToErr) (pair existing.firstByteSec (listAppendOne withToErr (str "provider " pid ": :firstByteSec must be a positive number")))))
                                    ((scalarInt n) (if (> n 0) (pair (int64ToFloat64 n) withToErr) (pair existing.firstByteSec (listAppendOne withToErr (str "provider " pid ": :firstByteSec must be a positive number")))))
                                    (_ (pair existing.firstByteSec (listAppendOne withToErr (str "provider " pid ": :firstByteSec must be a positive number")))))))))
                (firstByteSec (pairFirst firstByteSecRes))
                (withFbErr (pairSecond firstByteSecRes))
                (rpmRes (match (mapGet p "rpm")
                          ((none) (pair existing.rpm withFbErr))
                          ((some rExpr)
                            (let [(sc (asnScalar rExpr))]
                              (match sc
                                ((scalarFloat f) (if (> f 0.0) (pair f withFbErr) (pair existing.rpm (listAppendOne withFbErr (str "provider " pid ": :rpm must be a positive number")))))
                                ((scalarInt n) (if (> n 0) (pair (int64ToFloat64 n) withFbErr) (pair existing.rpm (listAppendOne withFbErr (str "provider " pid ": :rpm must be a positive number")))))
                                (_ (pair existing.rpm (listAppendOne withFbErr (str "provider " pid ": :rpm must be a positive number")))))))))
                (rpm (pairFirst rpmRes))
                (withRpmErr (pairSecond rpmRes))
                (poolRes (match (mapGet p "pool")
                            ((none) (pair existing.pool withRpmErr))
                            ((some poolExpr)
                              (match (parsePoolConfig poolExpr)
                                ((err e) (pair existing.pool (listAppendOne withRpmErr (str "provider " pid ": " e))))
                                ((ok poolValue) (pair (some poolValue) withRpmErr))))))
                (poolValue (pairFirst poolRes))
                (withPoolErr (pairSecond poolRes))
                (retryRes (match (mapGet p "retry")
                            ((none) (pair existing.retry withPoolErr))
                            ((some retryExpr)
                              (match (parseRetryPolicy retryExpr (str "provider " pid))
                                ((err e) (pair existing.retry (listAppendOne withPoolErr e)))
                                ((ok retryValue) (pair (some retryValue) withPoolErr))))))
                (retryValue (pairFirst retryRes))
                (withRetryErr (pairSecond retryRes))
                (baseErrs (if (and (or (= kind "openai") (or (= kind "anthropic") (or (= kind "gemini") (= kind "gateway")))) (stringEmpty? base))
                             (listAppendOne withRetryErr (str "provider " pid ": an " kind " provider needs :base"))
                             withRetryErr))
                (finalErrs (if (and (= kind "gateway") (stringEmpty? secret))
                             (listAppendOne baseErrs (str "provider " pid ": a gateway provider needs :secret naming its bearer token in the secrets file"))
                             baseErrs))
                (updated (GatewayProvider :rpmShared rpmShared :dropEmptyTools dropEmptyTools :assistantReasoning assistantReasoning :id pid :kind kind :base base :keyEnv (if (stringEmpty? secret) keyEnv (sc/secretEnvName secret)) :secret secret :promptCacheKey promptCacheKey :sessionHeader sessionHeader :timeoutSec timeoutSec :firstByteSec firstByteSec :rpm rpm :pool poolValue :retry retryValue))]
            (pair (mapSet provs pid updated) finalErrs))))))

fn loopProviders pForms: (List (Map String rd/SExpr)) provs: (Map String GatewayProvider) errs: (List String) -> (Pair (Map String GatewayProvider) (List String))
  (match (listHead pForms)
    ((none) (pair provs errs))
    ((some p)
      (let [(tail (optionOr (listTail pForms) (list)))
            (stepRes (applyOneProvider provs errs p))]
        (loopProviders tail (pairFirst stepRes) (pairSecond stepRes)))))

fn providerOrderLoop pForms: (List (Map String rd/SExpr)) provs: (Map String GatewayProvider) order: (List String) -> (List String)
  (match (listHead pForms)
    ((none) order)
    ((some p)
      (let [(tail (optionOr (listTail pForms) (list)))
            (next (pairFirst (applyOneProvider provs (list) p)))
            (added (filter (fn [(k String)] -> Bool (not (mapHas? provs k))) (mapKeys next)))]
        (providerOrderLoop tail next (listAppend order added)))))

fn providerOrder! providerForms: (List (Map String rd/SExpr)) -> (List String)
  (providerOrderLoop providerForms (defaultProviders!) (list "agy" "codex" "claude" "gemini" "groq" "openrouter" "ollama"))

fn buildProviders providerForms: (List (Map String rd/SExpr)) initial: (Map String GatewayProvider) errs: (List String) -> (Pair (Map String GatewayProvider) (List String))
  (loopProviders providerForms initial errs)

(schema ModelAccumulator
  (:f models (Map String GatewayModel))
  (:f order (List String))
  (:f errs (List String))
  (:f warns (List String)))

; (:m :ref GW-GEMINI-400 :do "Google's generativelanguage host answers HTTP 400 \"Requests ending with a model turn are not supported\" to a body whose last message is the assistant's, which is what Leon's attractor prefill is; a model on that host without its own :prefill therefore defaults to :prefill false, an explicit :prefill true still wins")
fn providerPrefillDefault providers: (Map String GatewayProvider) pid: String params: GatewayParams -> GatewayParams
  (if (some? params.prefill) params
    (match (mapGet providers pid)
      ((some p) (if (stringContains? p.base "generativelanguage.googleapis.com") (with params :prefill (some false)) params))
      ((none) params)))

fn applyOneModel acc: ModelAccumulator m: (Map String rd/SExpr) providers: (Map String GatewayProvider) registry: (Map String (Pair GatewayParams (List (Pair String String)))) regError: (Option String) -> ModelAccumulator
  (match (mapGet m "id")
    ((none) acc)
    ((some idExpr)
      (match (asnName idExpr "(:model :id ...)")
        ((err e) (with acc :errs (listAppendOne acc.errs e)))
        ((ok mid)
          (let [(dupErr (if (mapHas? acc.models mid) (listAppendOne acc.errs (str "model alias " mid " is defined twice")) acc.errs))
                (pidRes (match (mapGet m "provider")
                          ((none) (err (str "model " mid " :provider must be a bare atom, found ()")))
                          ((some pExpr) (asnName pExpr (str "model " mid " :provider")))))
                (nameRes (match (mapGet m "name")
                           ((none) (err (str "model " mid ": :name must be a non-empty string")))
                           ((some nExpr)
                             (if (not (isStringLiteral? nExpr))
                               (err (str "model " mid ": :name must be a non-empty string"))
                               (let [(ns (stripQuotesAndUnescape (sexprRawText nExpr)))]
                                 (if (stringEmpty? ns)
                                   (err (str "model " mid ": :name must be a non-empty string"))
                                   (ok ns)))))))
                (errs1 (match pidRes ((err e) (listAppendOne dupErr e)) ((ok _) dupErr)))
                (pid (resultOr pidRes ""))
                (errs2 (if (and (not (stringEmpty? pid)) (not (mapHas? providers pid)))
                         (listAppendOne errs1 (str "model " mid ": unknown provider " pid))
                         errs1))
                (errs3 (match nameRes ((err e) (listAppendOne errs2 e)) ((ok _) errs2)))
                (name (resultOr nameRes ""))
                (ownParamsRes (gatewayParams m (str "model " mid)))
                (ownParams (pairFirst ownParamsRes))
                (ownShown (paramsShown m ownParams))
                (paramErrs (pairSecond ownParamsRes))
                (errs4 (listAppend errs3 paramErrs))
                (providerKnown (or (stringEmpty? pid) (mapHas? providers pid)))
                (calRes (if (not providerKnown)
                          (pair (none) (pair (pair ownParams ownShown) acc.warns))
                          (match (mapGet m "calibration")
                          ((none) (pair (none) (pair (pair ownParams ownShown) acc.warns)))
                          ((some cExpr)
                            (let [(calStr (if (isStringLiteral? cExpr) (stripQuotesAndUnescape (sexprRawText cExpr)) (sexprRawText cExpr)))]
                              (match (mapGet registry calStr)
                                ((some regRow) (pair (some calStr) (pair (pair (mergeParams (pairFirst regRow) ownParams) (mergeShown (pairSecond regRow) ownShown)) acc.warns)))
                                ((none)
                                  (let [(suffix (match regError ((some re) (str " (" re ")")) ((none) "")))
                                        (w (str "model " mid ": calibration " calStr " is not in the registry" suffix))]
                                    (pair (some calStr) (pair (pair ownParams ownShown) (listAppendOne acc.warns w)))))))))))
                (cal (pairFirst calRes))
                (finalParams (pairFirst (pairFirst (pairSecond calRes))))
                (finalShown (pairSecond (pairFirst (pairSecond calRes))))
                (finalWarns (pairSecond (pairSecond calRes)))
                (statusRes (modelStatusGone m mid))
                (model (GatewayModel :id mid :provider pid :name name :calibration cal :params (providerPrefillDefault providers pid finalParams) :shown finalShown :gone (resultOr statusRes false)))]
            (ModelAccumulator
              :models (if providerKnown (mapSet acc.models mid model) acc.models)
              :order (if providerKnown (listAppendOne acc.order mid) acc.order)
              :errs (match statusRes ((err e) (listAppendOne errs4 e)) ((ok _) errs4))
              :warns finalWarns))))))

; (:m :ref GATEWAY-GONE-MODEL-ROWS :do "a model row's :status: absent or active is live, gone marks a model the provider no longer serves; any other value is a config error")
fn modelStatusGone m: (Map String rd/SExpr) mid: String -> (Result Bool String)
  (match (mapGet m "status")
    ((none) (ok false))
    ((some e)
      (let [(s (resultOr (asnName e (str "model " mid " :status")) ""))]
        (if (= s "active") (ok false)
          (if (= s "gone") (ok true)
            (err (str "model " mid ": :status must be active or gone")))))))

; (:m :ref GATEWAY-GONE-MODEL-ROWS :do "the one predicate config check and the runtime share: an alias whose model row is :status gone")
fn gone? models: (Map String GatewayModel) alias: String -> Bool
  (match (mapGet models alias) ((some md) md.gone) ((none) false))

fn goneTag -> String
  "gone: "

; (:m :ref GONE-QUOTED-CHAIN :do "the gone model a quoted chain entry names: the entry read as an alias id or as provider/name; the model's alias id, none when no gone model matches")
fn goneByString models: (Map String GatewayModel) s: String -> (Option String)
  (let [(hits (filter (fn [(md GatewayModel)] -> Bool (and md.gone (or (= md.id s) (= (str md.provider "/" md.name) s)))) (map pairSecond (mapPairs models))))]
    (match (listHead hits) ((some md) (some md.id)) ((none) (none))))

; (:m :ref GATEWAY-GONE-MODEL-ROWS :do "a skipped gone alias travels as a tagged note through the route errors; gatewayConfigV2Build! moves the notes out of the errors into one warning per alias, and config check turns those warnings back into errors")
fn goneNote alias: String pid: String intent: String -> String
  (str (goneTag) alias " " pid "/" intent)

fn loopModels mForms: (List (Map String rd/SExpr)) acc: ModelAccumulator providers: (Map String GatewayProvider) registry: (Map String (Pair GatewayParams (List (Pair String String)))) regError: (Option String) -> ModelAccumulator
  (match (listHead mForms)
    ((none) acc)
    ((some m)
      (let [(tail (optionOr (listTail mForms) (list)))
            (nextAcc (applyOneModel acc m providers registry regError))]
        (loopModels tail nextAcc providers registry regError))))

fn buildModels modelForms: (List (Map String rd/SExpr)) providers: (Map String GatewayProvider) registry: (Map String (Pair GatewayParams (List (Pair String String)))) regError: (Option String) -> ModelAccumulator
  (loopModels modelForms (ModelAccumulator :models (mapEmpty) :order (list) :errs (list) :warns (list)) providers registry regError)

fn intentCycleStep intents: (Map String (Option String)) cur: String seen: (List String) -> (Option (List String))
  (if (listContains? seen cur)
    (some (listAppendOne seen cur))
    (match (mapGet intents cur)
      ((none) (none))
      ((some parentOpt)
        (match parentOpt
          ((none) (none))
          ((some parent) (intentCycleStep intents parent (listAppendOne seen cur)))))))

fn detectIntentCycles intents: (Map String (Option String)) keys: (List String) -> (Option String)
  (match (listHead keys)
    ((none) (none))
    ((some iid)
      (let [(cycle (intentCycleStep intents iid (list)))]
        (match cycle
          ((some path) (some (str "intent cycle: " (stringJoin path " -> "))))
          ((none) (detectIntentCycles intents (optionOr (listTail keys) (list))))))))

fn loopIntents iForms: (List (Map String rd/SExpr)) ints: (Map String (Option String)) errs: (List String) -> (Pair (Map String (Option String)) (List String))
  (match (listHead iForms)
    ((none) (pair ints errs))
    ((some i)
      (let [(tail (optionOr (listTail iForms) (list)))]
        (match (mapGet i "id")
          ((none) (loopIntents tail ints errs))
          ((some idExpr)
            (match (asn_name_or_string idExpr "(:intent :id ...)")
              ((err e) (loopIntents tail ints (listAppendOne errs e)))
              ((ok rawIid)
                (let [(iid (stringLower rawIid))
                      (parentRes (match (mapGet i "as")
                                   ((none) (ok (none)))
                                   ((some asExpr)
                                     (match (asn_name_or_string asExpr (str "intent " iid " :as"))
                                       ((err e) (err e))
                                       ((ok p) (ok (some (stringLower p))))))))]
                  (match parentRes
                    ((err e) (loopIntents tail ints (listAppendOne errs e)))
                    ((ok pOpt) (loopIntents tail (mapSet ints iid pOpt) errs)))))))))))

fn buildIntents intentForms: (List (Map String rd/SExpr)) -> (Pair (Map String (Option String)) (List String))
  (let [(parsed (loopIntents intentForms (mapEmpty) (list)))
        (initialIntents (pairFirst parsed))
        (parseErrs (pairSecond parsed))
        (allIntents (fold (fn [(acc (Map String (Option String))) (pairEntry (Pair String (Option String)))] -> (Map String (Option String))
                            (match (pairSecond pairEntry)
                              ((none) acc)
                              ((some p) (if (mapHas? acc p) acc (mapSet acc p (none))))))
                          initialIntents
                          (mapPairs initialIntents)))
        (cycleOpt (detectIntentCycles allIntents (mapKeys allIntents)))
        (finalErrs (match cycleOpt ((some msg) (listAppendOne parseErrs msg)) ((none) parseErrs)))]
    (pair allIntents finalErrs))

fn parseChainItem a: rd/SExpr models: (Map String GatewayModel) pid: String intent: String st: (Pair (List String) (List String)) -> (Pair (List String) (List String))
  (let [(cList (pairFirst st))
        (cErrs (pairSecond st))]
    (if (isStringLiteral? a)
      (let [(s (stripQuotesAndUnescape (sexprRawText a)))]
        (if (stringEmpty? s)
          (pair cList (listAppendOne cErrs (str "profile " pid " route " intent ": chain entry \"\" is neither an alias nor a model string")))
          (match (goneByString models s)
            ((some gid) (pair cList (listAppendOne cErrs (goneNote gid pid intent))))
            ((none) (pair (listAppendOne cList s) cErrs)))))
      (match a
        ((rd/sexprAtom rawA)
          (if (not (mapHas? models rawA))
            (pair (listAppendOne cList rawA) (listAppendOne cErrs (str "profile " pid " route " intent ": unknown alias " rawA)))
            (if (gone? models rawA)
              (pair cList (listAppendOne cErrs (goneNote rawA pid intent)))
              (pair (listAppendOne cList rawA) cErrs))))
        (_ (pair cList (listAppendOne cErrs (str "profile " pid " route " intent ": chain entry compound is neither an alias nor a model string")))))))

fn parseRouteTemperature props: (Map String rd/SExpr) pid: String intent: String -> (Pair (Option Float64) (List String))
  (parseRouteTemperatureKey props "temperature" pid intent)

fn parseRouteTemperatureKey props: (Map String rd/SExpr) key: String pid: String intent: String -> (Pair (Option Float64) (List String))
  (match (mapGet props key)
    ((none) (pair (none) (list)))
    ((some expr)
      (let [(sc (asnFigure expr))]
        (match sc
          ((scalarFloat f) (pair (some f) (list)))
          ((scalarInt n) (pair (some (int64ToFloat64 n)) (list)))
          (_ (pair (none) (list (str "profile " pid " route " intent ": :" key " must be a number"))))))))

; (:m :ref GW-SPREAD-20261017 :do "one (ALIAS WEIGHT) pair: ALIAS is a bare atom checked against :models the same way parseChainItem checks a chain entry (never a string, never the raw model name); WEIGHT must be a positive integer, so 0, negative or a non-integer each name the offending alias rather than being silently dropped")
fn parseSpreadItem item: rd/SExpr models: (Map String GatewayModel) pid: String intent: String st: (Pair (List (Pair String Int64)) (List String)) -> (Pair (List (Pair String Int64)) (List String))
  (let [(acc (pairFirst st))
        (errs (pairSecond st))
        (parts (match item ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
    (if (!= (listLength parts) 2)
      (pair acc (listAppendOne errs (str "profile " pid " route " intent ": :spread entry must be (ALIAS WEIGHT)")))
      (let [(aExpr (optionOr (listGet parts 0) (rd/makeAtom "")))
            (wExpr (optionOr (listGet parts 1) (rd/makeAtom "")))]
        (match (asnName aExpr (str "profile " pid " route " intent " :spread alias"))
          ((err e) (pair acc (listAppendOne errs e)))
          ((ok alias)
            (if (not (mapHas? models alias))
              (pair acc (listAppendOne errs (str "profile " pid " route " intent ": :spread unknown alias " alias)))
              (if (gone? models alias)
                (pair acc (listAppendOne errs (goneNote alias pid (str intent " :spread"))))
                (match (asnScalar wExpr)
                  ((scalarInt w)
                    (if (<= w 0)
                      (pair acc (listAppendOne errs (str "profile " pid " route " intent ": :spread weight for " alias " must be a positive integer")))
                      (pair (listAppendOne acc (pair alias w)) errs)))
                  (_ (pair acc (listAppendOne errs (str "profile " pid " route " intent ": :spread weight for " alias " must be a positive integer"))))))))))))

fn parseSpread expr: rd/SExpr models: (Map String GatewayModel) pid: String intent: String -> (Pair (List (Pair String Int64)) (List String))
  (let [(items (match expr ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
    (fold (fn [(st (Pair (List (Pair String Int64)) (List String))) (it rd/SExpr)] -> (Pair (List (Pair String Int64)) (List String))
            (parseSpreadItem it models pid intent st))
      (pair (list) (list)) items))

; (:m :ref GW-SPREAD-20261017 :do "default 60 when absent, as the plan names; present but non-positive is a parse error rather than a silently-ignored value")
fn parseCooldownSec props: (Map String rd/SExpr) pid: String intent: String -> (Pair Int64 (List String))
  (match (mapGet props "cooldownSec")
    ((none) (pair 60 (list)))
    ((some expr)
      (match (asnScalar expr)
        ((scalarInt n) (if (> n 0) (pair n (list)) (pair 60 (list (str "profile " pid " route " intent ": :cooldownSec must be a positive integer")))))
        (_ (pair 60 (list (str "profile " pid " route " intent ": :cooldownSec must be a positive integer")))))))

; (:m :ref GW-CAP-ORDER :do "optional :order measured on a route (with :explore 0..50, :refreshS >= 60, :minSamples >= 1, :staleS >= 60, :orderOff (ALIAS ..) of known aliases, :orderAt >= 0): opt-in to measured chain order written back by `gateway order`; any of the options without :order, a value other than measured, an out-of-range number or an unknown alias in :orderOff is an error, and a route without :order is read exactly as before")
fn orderIntOk props: (Map String rd/SExpr) key: String lo: Int64 hi: Int64 -> Bool
  (match (mapGet props key)
    ((none) true)
    ((some v) (match (asnScalar v) ((scalarInt n) (and (>= n lo) (<= n hi))) (_ false))))

fn parseRouteOrder props: (Map String rd/SExpr) models: (Map String GatewayModel) pid: String intent: String -> (List String)
  (let [(where (str "profile " pid " route " intent ": "))
        (opts (list "explore" "refreshS" "minSamples" "staleS" "orderOff" "orderAt"))]
    (match (mapGet props "order")
      ((none) (map (fn [(k String)] -> String (str where ":" k " needs :order measured")) (filter (fn [(k String)] -> Bool (mapHas? props k)) opts)))
      ((some v)
        (listAppend
          (match (asnScalar v) ((scalarStr s) (if (= s "measured") (list) (list (str where ":order must be measured")))) (_ (list (str where ":order must be measured"))))
          (listAppend
            (filter (fn [(e String)] -> Bool (not (stringEmpty? e)))
              (list (if (orderIntOk props "explore" 0 50) "" (str where ":explore must be an integer 0..50"))
                    (if (orderIntOk props "refreshS" 60 31536000) "" (str where ":refreshS must be an integer >= 60"))
                    (if (orderIntOk props "minSamples" 1 1000000) "" (str where ":minSamples must be an integer >= 1"))
                    (if (orderIntOk props "staleS" 60 31536000) "" (str where ":staleS must be an integer >= 60"))
                    (if (orderIntOk props "orderAt" 0 9007199254740991) "" (str where ":orderAt must be an integer >= 0"))))
            (match (mapGet props "orderOff")
              ((none) (list))
              ((some e)
                (let [(items (match e ((rd/sexprList l) l) ((rd/sexprVect vv) vv) (_ (list))))]
                  (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
                    (map (fn [(it rd/SExpr)] -> String
                           (match it
                             ((rd/sexprAtom a) (if (mapHas? models a) "" (str where ":orderOff unknown alias " a)))
                             (_ (str where ":orderOff entries must be aliases"))))
                         items)))))))))) 

fn parseProfileRoute rf: rd/SExpr pid: String intents: (Map String (Option String)) models: (Map String GatewayModel) -> (Pair (Option GatewayRoute) (List String))
  (match (asnProps rf (none))
    ((err e) (pair (none) (list (str "profile " pid ": " e))))
    ((ok props)
      (let [(intentRes (match (mapGet props "intent")
                         ((none) (err (str "profile " pid " route :intent must be a bare atom or string, found ()")))
                         ((some iExpr) (asn_name_or_string iExpr (str "profile " pid " route :intent")))))
            (intent (stringLower (resultOr intentRes "")))
            (errs1 (match intentRes ((err e) (list (str "profile " pid ": " e))) ((ok _) (list))))
            (errs2 (if (and (not (stringEmpty? intent)) (and (!= intent "any") (not (mapHas? intents intent))))
                     (listAppendOne errs1 (str "profile " pid ": route intent " intent " is not in :intents"))
                     errs1))
            (chainExprOpt (mapGet props "chain"))]
        (match chainExprOpt
          ((none) (pair (none) (listAppendOne errs2 (str "profile " pid " route " intent ": :chain must be a non-empty list of aliases"))))
          ((some chainExpr)
            (let [(cItems (match chainExpr ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
              (if (listEmpty? cItems)
                (pair (none) (listAppendOne errs2 (str "profile " pid " route " intent ": :chain must be a non-empty list of aliases")))
                (let [(chainRes (fold (fn [(st (Pair (List String) (List String))) (a rd/SExpr)] -> (Pair (List String) (List String))
                                        (parseChainItem a models pid intent st))
                                      (pair (list) (list))
                                      cItems))
                      (chain (pairFirst chainRes))
                      (chainErrs (pairSecond chainRes))
                      (tempRes (parseRouteTemperature props pid intent))
                      (temperature (pairFirst tempRes))
                      (tempErrs (pairSecond tempRes))
                      (overRes (parseRouteTemperatureKey props "temperatureOverride" pid intent))
                      (tempOverride (pairFirst overRes))
                      (overErrs (pairSecond overRes))
                      (spreadRes (match (mapGet props "spread") ((none) (pair (list) (list))) ((some sExpr) (parseSpread sExpr models pid intent))))
                      (spread (pairFirst spreadRes))
                      (spreadErrs (pairSecond spreadRes))
                      (cooldownRes (parseCooldownSec props pid intent))
                      (cooldownSec (pairFirst cooldownRes))
                      (cooldownErrs (pairSecond cooldownRes))
                      (orderErrs (parseRouteOrder props models pid intent))
                      (finalErrs (listAppend (listAppend (listAppend (listAppend (listAppend (listAppend errs2 chainErrs) tempErrs) overErrs) spreadErrs) cooldownErrs) orderErrs))]
                  (pair (some (GatewayRoute :intent intent :chain chain :models (list) :temperature temperature :temperatureOverride tempOverride :spread spread :cooldownSec cooldownSec)) finalErrs)))))))))

fn profileFallbackStep profiles: (Map String GatewayProfile) cur: String seen: (List String) -> (Option (List String))
  (if (listContains? seen cur)
    (some (listAppendOne seen cur))
    (match (mapGet profiles cur)
      ((none) (none))
      ((some pr)
        (match pr.fallback
          ((none) (none))
          ((some fb)
            (if (mapHas? profiles fb)
              (profileFallbackStep profiles fb (listAppendOne seen cur))
              (none)))))))

fn detectProfileFallbackCycles profiles: (Map String GatewayProfile) keys: (List String) -> (Option String)
  (match (listHead keys)
    ((none) (none))
    ((some pid)
      (let [(cycle (profileFallbackStep profiles pid (list)))]
        (match cycle
          ((some path) (some (str "profile fallback cycle: " (stringJoin path " -> "))))
          ((none) (detectProfileFallbackCycles profiles (optionOr (listTail keys) (list))))))))

fn profileModes -> (List String)
  (list "pin" "route" "judge")

; (:m :ref GW-MODES :do "a profile's :mode, route when absent; any other word than pin, route or judge is a config error")
fn profileModeOf p: (Map String rd/SExpr) pid: String -> (Pair String (List String))
  (match (mapGet p "mode")
    ((none) (pair "route" (list)))
    ((some e)
      (match (asnScalar e)
        ((scalarStr s) (if (listContains? (profileModes) s) (pair s (list)) (pair "route" (list (str "profile " pid ": :mode must be pin, route or judge")))))
        (_ (pair "route" (list (str "profile " pid ": :mode must be pin, route or judge")))))))

fn stringItems e: rd/SExpr -> (Option (List String))
  (match e
    ((rd/sexprList xs) (some (map (fn [(x rd/SExpr)] -> String (scalarToString (asnScalar x))) xs)))
    ((rd/sexprVect xs) (some (map (fn [(x rd/SExpr)] -> String (scalarToString (asnScalar x))) xs)))
    (_ none))

fn judgeBool props: (Map String rd/SExpr) key: String d: Bool pid: String -> (Pair Bool (List String))
  (match (mapGet props key)
    ((none) (pair d (list)))
    ((some e) (match (asnScalar e)
                ((scalarBool b) (pair b (list)))
                (_ (pair d (list (str "profile " pid ": :judge :" key " must be true or false")))))))

fn judgeList props: (Map String rd/SExpr) key: String d: (List String) pid: String -> (Pair (List String) (List String))
  (match (mapGet props key)
    ((none) (pair d (list)))
    ((some e) (match (stringItems e)
                ((some xs) (pair xs (list)))
                ((none) (pair d (list (str "profile " pid ": :judge :" key " must be a list")))))))

; (:m :ref GW-MODES :do "a profile's (:judge :empty B :truncated B :stepIntents (INTENT ...) :stepHeads (\"TEXT\" ...)) rows over judgeDefault; an unknown key or a wrong type is a config error")
fn profileJudgeOf p: (Map String rd/SExpr) pid: String -> (Pair JudgeRules (List String))
  (let [(d (judgeDefault))]
    (match (mapGet p "judge")
      ((none) (pair d (list)))
      ((some e)
        (match (asnProps e (none))
          ((err msg) (pair d (list (str "profile " pid " :judge: " msg))))
          ((ok props)
            (let [(unknown (filter (fn [(k String)] -> Bool (not (listContains? (list "empty" "truncated" "stepIntents" "stepHeads") k))) (mapKeys props)))
                  (em (judgeBool props "empty" d.empty pid))
                  (tr (judgeBool props "truncated" d.truncated pid))
                  (si (judgeList props "stepIntents" d.stepIntents pid))
                  (sh (judgeList props "stepHeads" d.stepHeads pid))]
              (pair (JudgeRules :empty (pairFirst em) :truncated (pairFirst tr) :stepIntents (map stringLower (pairFirst si)) :stepHeads (pairFirst sh))
                    (listAppend (map (fn [(k String)] -> String (str "profile " pid ": unknown :judge key :" k)) unknown)
                                (listAppend (listAppend (pairSecond em) (pairSecond tr)) (listAppend (pairSecond si) (pairSecond sh)))))))))))

; (:m :ref GW-MODES :do "the mode and judge rules of a named profile; an unknown profile is route with the default rules")
fn gatewayProfileMode table: GatewayTable name: String -> String
  (match (mapGet table.profiles name) ((some p) p.mode) ((none) "route"))

fn gatewayProfileJudge table: GatewayTable name: String -> JudgeRules
  (match (mapGet table.profiles name) ((some p) p.judge) ((none) (judgeDefault)))

; (:m :ref CTX-ROUTE :do "a named profile's :budgetFirstAbove, 0 for an unknown profile or none set")
fn gatewayProfileBudgetFirst table: GatewayTable name: String -> Int64
  (match (mapGet table.profiles name) ((some p) p.budgetFirstAbove) ((none) 0))

; (:m :ref CTX-ROUTE :do "a profile's :budgetFirstAbove N, a positive integer of tokens; absent is 0, anything else a config error")
fn profileBudgetFirstOf p: (Map String rd/SExpr) pid: String -> (Pair Int64 (List String))
  (match (mapGet p "budgetFirstAbove")
    ((none) (pair 0 (list)))
    ((some e)
      (match (asnScalar e)
        ((scalarInt n) (if (> n 0) (pair n (list)) (pair 0 (list (str "profile " pid ": :budgetFirstAbove must be a positive integer")))))
        (_ (pair 0 (list (str "profile " pid ": :budgetFirstAbove must be a positive integer")))))))

(schema ProfileAccumulator
  (:f profiles (Map String GatewayProfile))
  (:f order (List String))
  (:f errs (List String)))

fn applyOneProfile acc: ProfileAccumulator p: (Map String rd/SExpr) intents: (Map String (Option String)) models: (Map String GatewayModel) -> ProfileAccumulator
  (match (mapGet p "id")
    ((none) acc)
    ((some idExpr)
      (match (asnName idExpr "(:profile :id ...)")
        ((err e) (with acc :errs (listAppendOne acc.errs e)))
        ((ok pid)
          (let [(dupErr (if (mapHas? acc.profiles pid) (listAppendOne acc.errs (str "profile " pid " is defined twice")) acc.errs))
                (routesExprOpt (mapGet p "routes"))
                (routesList (match routesExprOpt
                              ((none) (list))
                              ((some re) (match re ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))))
                (routesEmptyErr (if (listEmpty? routesList) (listAppendOne dupErr (str "profile " pid ": :routes must be a non-empty list")) dupErr))
                (routesParsed (fold (fn [(st (Pair (List GatewayRoute) (List String))) (rf rd/SExpr)] -> (Pair (List GatewayRoute) (List String))
                                      (let [(rRes (parseProfileRoute rf pid intents models))]
                                        (match (pairFirst rRes)
                                          ((none) (pair (pairFirst st) (listAppend (pairSecond st) (pairSecond rRes))))
                                          ((some route) (pair (listAppendOne (pairFirst st) route) (listAppend (pairSecond st) (pairSecond rRes)))))))
                                    (pair (list) (list))
                                    routesList))
                (routes (pairFirst routesParsed))
                (routeErrs (pairSecond routesParsed))
                (errs1 (listAppend routesEmptyErr routeErrs))
                (fbRes (match (mapGet p "fallback")
                         ((none) (ok (none)))
                         ((some fbExpr)
                           (match (asnName fbExpr (str "profile " pid " :fallback"))
                             ((err e) (err e))
                             ((ok fb) (ok (some fb)))))))
                (errs2a (match fbRes ((err e) (listAppendOne errs1 e)) ((ok _) errs1)))
                (fallback (resultOr fbRes (none)))
                (modeRes (profileModeOf p pid))
                (judgeRes (profileJudgeOf p pid))
                (bfRes (profileBudgetFirstOf p pid))
                (errs2 (listAppend errs2a (listAppend (pairSecond modeRes) (listAppend (pairSecond judgeRes) (pairSecond bfRes)))))
                (profile (GatewayProfile :id pid :routes routes :fallback fallback :mode (pairFirst modeRes) :judge (pairFirst judgeRes) :budgetFirstAbove (pairFirst bfRes)))]
            (ProfileAccumulator
              :profiles (mapSet acc.profiles pid profile)
              :order (listAppendOne acc.order pid)
              :errs errs2))))))

fn loopProfiles pForms: (List (Map String rd/SExpr)) acc: ProfileAccumulator intents: (Map String (Option String)) models: (Map String GatewayModel) -> ProfileAccumulator
  (match (listHead pForms)
    ((none) acc)
    ((some p)
      (let [(tail (optionOr (listTail pForms) (list)))
            (nextAcc (applyOneProfile acc p intents models))]
        (loopProfiles tail nextAcc intents models))))

fn buildProfiles profileForms: (List (Map String rd/SExpr)) intents: (Map String (Option String)) models: (Map String GatewayModel) -> (Pair (Pair (Map String GatewayProfile) (List String)) (List String))
  (let [(parsed (loopProfiles profileForms (ProfileAccumulator :profiles (mapEmpty) :order (list) :errs (list)) intents models))
        (profiles parsed.profiles)
        (order parsed.order)
        (errs0 parsed.errs)
        (fbUnknownErrs (fold (fn [(acc (List String)) (pid String)] -> (List String)
                               (match (mapGet profiles pid)
                                 ((none) acc)
                                 ((some pr)
                                   (match pr.fallback
                                     ((none) acc)
                                     ((some fb) (if (not (mapHas? profiles fb)) (listAppendOne acc (str "profile " pid ": unknown fallback profile " fb)) acc))))))
                             (list)
                             order))
        (errs1 (listAppend errs0 fbUnknownErrs))
        (cycleOpt (detectProfileFallbackCycles profiles order))
        (finalErrs (match cycleOpt ((some msg) (listAppendOne errs1 msg)) ((none) errs1)))]
    (pair (pair profiles order) finalErrs))

fn useOrderAdd order: (List String) uses: (Map String String) uf: String -> (List String)
  (if (mapHas? uses uf) order (listAppendOne order uf))

fn applyOneUse uses: (Pair (Map String String) (List String)) errs: (List String) u: (Map String rd/SExpr) profiles: (Map String GatewayProfile) -> (Pair (Pair (Map String String) (List String)) (List String))
  (match (mapGet u "for")
    ((none) (pair uses errs))
    ((some forExpr)
      (match (asnName forExpr "(:use :for ...)")
        ((err e) (pair uses (listAppendOne errs e)))
        ((ok uf)
          (match (mapGet u "profile")
            ((none) (pair uses (listAppendOne errs (str "use " uf " :profile must be a bare atom, found ()"))))
            ((some pExpr)
              (match (asnName pExpr (str "use " uf " :profile"))
                ((err e) (pair uses (listAppendOne errs e)))
                ((ok up)
                  (let [(upErr (if (not (mapHas? profiles up)) (listAppendOne errs (str "use " uf ": unknown profile " up)) errs))
                        (useMap (pairFirst uses))]
                    (pair (pair (mapSet useMap uf up) (useOrderAdd (pairSecond uses) useMap uf)) upErr))))))))))

fn loopUses uForms: (List (Map String rd/SExpr)) uses: (Pair (Map String String) (List String)) errs: (List String) profiles: (Map String GatewayProfile) -> (Pair (Pair (Map String String) (List String)) (List String))
  (match (listHead uForms)
    ((none) (pair uses errs))
    ((some u)
      (let [(tail (optionOr (listTail uForms) (list)))
            (stepRes (applyOneUse uses errs u profiles))]
        (loopUses tail (pairFirst stepRes) (pairSecond stepRes) profiles))))

fn buildUses useForms: (List (Map String rd/SExpr)) profiles: (Map String GatewayProfile) -> (Pair (Pair (Map String String) (List String)) (List String))
  (loopUses useForms (pair (mapEmpty) (list)) (list) profiles)

fn gatewayConfigV2Build! g: (Map String rd/SExpr) source: String registryPath: String -> (Pair GatewayTable (List String))
  (let [(provForms (getSubForms g "providers" ":provider"))
        (modelForms (getSubForms g "models" ":model"))
        (intentForms (getSubForms g "intents" ":intent"))
        (profileForms (getSubForms g "profiles" ":profile"))
        (useForms (getSubForms g "uses" ":use"))
        (listErrors (listAppend (pairSecond provForms) (listAppend (pairSecond modelForms) (listAppend (pairSecond intentForms) (listAppend (pairSecond profileForms) (pairSecond useForms))))))
        (provRes (buildProviders (pairFirst provForms) (defaultProviders!) listErrors))
        (providers (pairFirst provRes))
        (provErrs (pairSecond provRes))
        (regRes (calibrationRowsLoad! registryPath))
        (reg (match regRes ((ok r) r) ((err _) (mapEmpty))))
        (regErr (match regRes ((err e) (some e)) ((ok _) (none))))
        (modRes (buildModels (pairFirst modelForms) providers reg regErr))
        (models modRes.models)
        (modelOrder modRes.order)
        (modErrs modRes.errs)
        (warnings modRes.warns)
        (intRes (buildIntents (pairFirst intentForms)))
        (intents (pairFirst intRes))
        (intErrs (pairSecond intRes))
        (profRes (buildProfiles (pairFirst profileForms) intents models))
        (profiles (pairFirst (pairFirst profRes)))
        (profileOrder (pairSecond (pairFirst profRes)))
        (profErrs (pairSecond profRes))
        (useRes (buildUses (pairFirst useForms) profiles))
        (uses (pairFirst (pairFirst useRes)))
        (useOrder (pairSecond (pairFirst useRes)))
        (useErrs (pairSecond useRes))
        (allErrs0 (listAppend provErrs (listAppend modErrs (listAppend intErrs (listAppend profErrs useErrs)))))
        (defaultFromUse (mapGet uses "default"))
        (defaultRes (match defaultFromUse
                      ((some dp) (pair (some dp) allErrs0))
                      ((none)
                        (match (mapGet g "profile")
                          ((none) (pair (none) (listAppendOne allErrs0 "no default profile: add (:use :for default :profile ID)")))
                          ((some pExpr)
                            (match (asnName pExpr "(:gateway :profile ...)")
                              ((err e) (pair (none) (listAppendOne allErrs0 e)))
                              ((ok defName)
                                (if (not (mapHas? profiles defName))
                                  (pair (none) (listAppendOne allErrs0 (str ":profile " defName " names no defined profile")))
                                  (pair (some defName) allErrs0)))))))))
        (defaultProf (optionOr (pairFirst defaultRes) ""))
        (allErrs1 (pairSecond defaultRes))
        (allErrs2 (if (listEmpty? profileOrder)
                    (listAppendOne allErrs1 ":profiles must define at least one (:profile ...)")
                    allErrs1))
        (keyFilesList (gatewayKeyFilesFromProps g))
        (envWarns (fold (fn [(acc (List String)) (pid String)] -> (List String)
                          (let [(pv (optionOr (mapGet providers pid) (GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id pid :kind "" :base "" :keyEnv "" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none))))]
                            (if (and (not (stringEmpty? pv.keyEnv)) (and (stringEmpty? pv.secret) (listAny? (fn [(m GatewayModel)] -> Bool (= m.provider pid)) (mapValues models))))
                              (match (resolveProviderKey! keyFilesList pv.keyEnv)
                                ((none) (listAppendOne acc (str "provider " pid ": key env " pv.keyEnv " is not set" (keyFilesSuffix keyFilesList))))
                                ((some val) (if (stringEmpty? val) (listAppendOne acc (str "provider " pid ": key env " pv.keyEnv " is not set" (keyFilesSuffix keyFilesList))) acc)))
                              (if (and (not (stringEmpty? pv.secret)) (listAny? (fn [(m GatewayModel)] -> Bool (= m.provider pid)) (mapValues models)))
                                (match (resolveProviderCredential! (gatewaySecretsPathFromProps g) keyFilesList pv.secret "")
                                  ((err e) (listAppendOne acc (str "provider " pid ": " e)))
                                  ((ok _) acc))
                                acc))))
                        (list)
                        (providerOrder! (pairFirst provForms))))
        (goneNotes (filter (fn [(e String)] -> Bool (stringStartsWith? e (goneTag))) allErrs2))
        (errs (filter (fn [(e String)] -> Bool (not (stringStartsWith? e (goneTag)))) allErrs2))
        (allWarns (listAppend (listAppend (listAppend warnings envWarns) (listAppend (gatewayLimitWarnings g) (listAppend (gatewayBucketWaitWarnings g) (gatewayQueueBudgetWarnings g)))) (goneWarnings goneNotes)))
        (table (GatewayTable
                 :version 2
                 :defaultProfile defaultProf
                 :profiles profiles
                 :profileOrder profileOrder
                 :models models
                 :modelOrder modelOrder
                 :providers providers
                 :intents intents
                 :uses uses
                 :useOrder useOrder
                 :source source
                 :registry registryPath
                 :registryError regErr
                 :warnings allWarns
                 :undeclaredIntents (mapEmpty)
                 :keyFiles keyFilesList
                 :limits (gatewayLimitsFromProps g)
                 :bucketWaitSec (gatewayBucketWaitSecFromProps g)
                 :queueBudgetSec (gatewayQueueBudgetSecFromProps g)))]
    (pair table errs))


; (:m :ref GATEWAY-GONE-MODEL-ROWS :do "one warning per gone alias, naming every route it was skipped in; each starts with goneTag so config check can raise them")
fn goneNoteAlias n: String -> String
  (optionOr (listHead (stringSplit (optionOr (stringSlice n (stringLength (goneTag)) (stringLength n)) "") " ")) "")

fn goneWarnings notes: (List String) -> (List String)
  (let [(aliases (orderedUnique (map goneNoteAlias notes)))]
    (map (fn [(a String)] -> String
           (str (goneTag) "model " a " is :status gone, skipped in "
                (stringJoin (map (fn [(n String)] -> String (optionOr (stringSlice n (+ (stringLength (goneTag)) (+ (stringLength a) 1)) (stringLength n)) "")) (filter (fn [(n String)] -> Bool (= (goneNoteAlias n) a)) notes)) ", ")))
         aliases))

fn convertV1ToTable! v1: GatewayV1Config source: String keyFiles: (List String) -> GatewayTable
  (let [(profilesMap (fold (fn [(acc (Map String GatewayProfile)) (pairEntry (Pair String (List GatewayRoute)))] -> (Map String GatewayProfile)
                             (mapSet acc (pairFirst pairEntry) (GatewayProfile :id (pairFirst pairEntry) :routes (pairSecond pairEntry) :fallback (none) :mode "route" :judge (judgeDefault) :budgetFirstAbove 0)))
                           (mapEmpty)
                           (mapPairs v1.profiles)))
        (profileOrder (mapKeys v1.profiles))]
    (GatewayTable
      :version 1
      :defaultProfile v1.defaultProfile
      :profiles profilesMap
      :profileOrder profileOrder
      :models (mapEmpty)
      :modelOrder (list)
      :providers (defaultProviders!)
      :intents (mapEmpty)
      :uses (mapSet (mapEmpty) "default" v1.defaultProfile)
      :useOrder (list "default")
      :source source
      :registry ""
      :registryError (none)
      :warnings (list)
      :undeclaredIntents (mapEmpty)
      :keyFiles keyFiles
      :limits (list)
      :bucketWaitSec (defaultBucketWaitSec)
      :queueBudgetSec (defaultQueueBudgetSec)))

fn gatewayConfigParse! text: String source: String registryPath: String -> (Result GatewayTable String)
  (let [(toks (lx/tokenize text))]
    (match (match (asnReadCheck text) ((some e) (err (ast/ParseError :msg e :line 0 :col 0))) ((none) (ast/readForms toks)))
      ((err e) (err (str e.msg)))
      ((ok forms)
        (if (!= (listLength forms) 1)
          (err (str "expected one (:gateway ...) form, found " (stringFromInt64 (listLength forms))))
          (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
            (match (asnProps top (some ":gateway"))
              ((err e) (err e))
              ((ok g)
                (let [(v (match (mapGet g "v")
                           ((none) 1)
                           ((some vExpr)
                             (match (asnScalar vExpr)
                               ((scalarInt n) n)
                               (_ 1)))))]
                  (if (= v 2)
                    (let [(built (gatewayConfigV2Build! g source registryPath))
                          (tbl (pairFirst built))
                          (errs (pairSecond built))]
                      (if (not (listEmpty? errs))
                        (err (stringJoin errs "; "))
                        (ok tbl)))
                    (match (gatewayProfilesParse text)
                      ((err e) (err e))
                      ((ok v1) (ok (convertV1ToTable! v1 source (gatewayKeyFilesFromProps g))))))))))))))


fn intentLineLoop intents: (Map String (Option String)) cur: String acc: (List String) -> (List String)
  (if (or (stringEmpty? cur) (listContains? acc cur))
    (listReverse acc)
    (let [(nextAcc (cons cur acc))]
      (match (mapGet intents cur)
        ((none) (listReverse nextAcc))
        ((some parentOpt)
          (match parentOpt
            ((none) (listReverse nextAcc))
            ((some parent) (intentLineLoop intents parent nextAcc)))))))

fn gatewayIntentLine table: GatewayTable intent: String -> (List String)
  (let [(cur (stringLower (lstripColons intent)))]
    (intentLineLoop table.intents cur (list)))

fn routeFindIntent routes: (List GatewayRoute) targetIntent: String -> (Option GatewayRoute)
  (match (listHead routes)
    ((none) (none))
    ((some r)
      (if (= r.intent targetIntent)
        (some r)
        (routeFindIntent (optionOr (listTail routes) (list)) targetIntent))))

fn routeFindLine routes: (List GatewayRoute) line: (List String) -> (Option GatewayRoute)
  (match (listHead line)
    ((none) (none))
    ((some i)
      (match (routeFindIntent routes i)
        ((some r) (some r))
        ((none) (routeFindLine routes (optionOr (listTail line) (list)))))))

fn routeFindLineOrAny routes: (List GatewayRoute) line: (List String) -> (Option GatewayRoute)
  (match (routeFindLine routes line)
    ((some r) (some r))
    ((none) (routeFindIntent routes "any")))

fn gatewayV2Route profile: GatewayProfile line: (List String) -> (List String)
  (match (routeFindLineOrAny profile.routes line)
    ((some r) r.chain)
    ((none) (list)))

; (:m :do "the per-route :temperature default, for the same route resolution gateway_v2_route uses, so a role/intent's calibrated sampling temperature comes from config instead of a hardcoded table")
fn gatewayV2RouteTemperature profile: GatewayProfile line: (List String) -> (Option Float64)
  (match (routeFindLineOrAny profile.routes line)
    ((some r) r.temperature)
    ((none) none))

fn gatewayV2Entry! table: GatewayTable alias: String -> GatewayResolvedEntry
  (match (mapGet table.models alias)
    ((none) (entryUnresolved alias))
    ((some m)
      (match (mapGet table.providers m.provider)
        ((none) (entryUnresolved alias))
        ((some pv)
          (if (= pv.kind "cli")
            (entryResolved (GatewayEntry
                             :alias alias
                             :provider m.provider
                             :kind "cli"
                             :name m.name
                             :dispatch (str m.provider "/" m.name)
                             :params m.params
                             :upstream (GatewayUpstream :provider (str m.provider "-cli") :url (str "cli://" m.provider) :key "")
                             :timeoutSec 0.0
                             :firstByteSec 0.0
                             :rpm (none)
                             :rpmKey ""
                             :dropEmptyTools false :assistantReasoning false
                             :pool none
                             :retry (none)))
            (let [(key (optionOr (resolveProviderKey! table.keyFiles pv.keyEnv) ""))
                  (tSec (match m.params.timeoutSec
                          ((some ts) ts)
                          ((none) pv.timeoutSec)))
                  ; (:m :ref FREEPOOL-GATEWAY-FIRSTBYTE-20261017 :do "a model's own :firstByteSec wins over its provider's; 0.0 (neither set one) is firstByteCapSec's own unconfigured sentinel, never a second 60.0 literal resolved here")
                  (fbSec (match m.params.firstByteSec
                          ((some fb) fb)
                          ((none) pv.firstByteSec)))
                  (rpmVal (if (and pv.rpmShared (> pv.rpm 0.0))
                            (some pv.rpm)
                            (match m.params.rpm
                              ((some r) (some r))
                              ((none) (if (> pv.rpm 0.0) (some pv.rpm) (none))))))
                  (retryVal (match m.params.retry
                              ((some r) (some r))
                              ((none) pv.retry)))]
              (entryResolved (GatewayEntry
                               :alias alias
                               :provider m.provider
                               :kind pv.kind
                               :name m.name
                               :dispatch m.name
                               :params m.params
                               :upstream (GatewayUpstream :provider m.provider :url pv.base :key key)
                               :timeoutSec tSec
                               :firstByteSec fbSec
                               :rpm rpmVal
                               :rpmKey (if (and pv.rpmShared (> pv.rpm 0.0)) (str "provider:" pv.id) "")
                               :dropEmptyTools pv.dropEmptyTools :assistantReasoning pv.assistantReasoning
                               :pool pv.pool
                               :retry retryVal))))))))

fn entriesStep! pairState: (Pair (List String) (List GatewayResolvedEntry)) a: String table: GatewayTable -> (Pair (List String) (List GatewayResolvedEntry))
  (if (listContains? (pairFirst pairState) a)
    pairState
    (pair (cons a (pairFirst pairState)) (cons (gatewayV2Entry! table a) (pairSecond pairState))))

fn entriesLoop! table: GatewayTable cur: String line: (List String) seen: (List String) tried: (List String) acc: (List GatewayResolvedEntry) -> (List GatewayResolvedEntry)
  (if (or (stringEmpty? cur) (listContains? seen cur))
    (listReverse acc)
    (match (mapGet table.profiles cur)
      ((none) (listReverse acc))
      ((some prof)
        (let [(chain (gatewayV2Route prof line))
              (res (fold (fn [(st (Pair (List String) (List GatewayResolvedEntry))) (a String)] -> (Pair (List String) (List GatewayResolvedEntry))
                           (entriesStep! st a table))
                         (pair tried acc)
                         chain))
              (nextTried (pairFirst res))
              (nextAcc (withTemperatureOverride (pairSecond res) (- (listLength (pairSecond res)) (listLength acc)) (routeTemperatureOverrideOf (routeFindLineOrAny prof.routes line))))
              (nextSeen (cons cur seen))]
          (match prof.fallback
            ((none) (listReverse nextAcc))
            ((some fb) (entriesLoop! table fb line nextSeen nextTried nextAcc)))))))

fn routeTemperatureOverrideOf r: (Option GatewayRoute) -> (Option Float64)
  (match r ((some x) x.temperatureOverride) ((none) none))

; (:m :ref GW-ROUTE-TEMPERATURE :do "acc is newest-first (reversed at the end), so the first n entries are the ones the current route just added; only those take the route's override, entries from an earlier profile in the fallback walk keep their own route's")
fn paramsWithTemperature p: GatewayParams t: Float64 -> GatewayParams
  (with p :temperature (some t))

fn entryWithTemperature en: GatewayEntry t: Float64 -> GatewayEntry
  (with en :params (paramsWithTemperature en.params t))

fn withTemperatureOverride acc: (List GatewayResolvedEntry) n: Int64 t: (Option Float64) -> (List GatewayResolvedEntry)
  (match t
    ((none) acc)
    ((some temp)
      (listAppend
        (map (fn [(e GatewayResolvedEntry)] -> GatewayResolvedEntry
               (match e
                 ((entryResolved en) (entryResolved (entryWithTemperature en temp)))
                 ((entryUnresolved a) (entryUnresolved a))))
             (listTake acc n))
        (listDrop acc n))))

fn gatewayV2Entries! table: GatewayTable name: String intent: String -> (List GatewayResolvedEntry)
  (let [(line (gatewayIntentLine table intent))]
    (entriesLoop! table name line (list) (list) (list)))

; (:m :do "the exact-match sibling of entriesLoop!: a profile fallback chain is still honored, but there is no silent substitution of the profile's :intent any catch-all route when the requested intent has no route of its own -- used where a caller is testing several candidate keys in turn (role, then a role:lens composite, then a bare role) and must tell a real miss from the generic default, rather than have every candidate succeed via the same any route")
fn entriesLoopExact! table: GatewayTable cur: String line: (List String) seen: (List String) tried: (List String) acc: (List GatewayResolvedEntry) -> (List GatewayResolvedEntry)
  (if (or (stringEmpty? cur) (listContains? seen cur))
    (listReverse acc)
    (match (mapGet table.profiles cur)
      ((none) (listReverse acc))
      ((some prof)
        (let [(chain (match (routeFindLine prof.routes line) ((some r) r.chain) ((none) (list))))
              (res (fold (fn [(st (Pair (List String) (List GatewayResolvedEntry))) (a String)] -> (Pair (List String) (List GatewayResolvedEntry))
                           (entriesStep! st a table))
                         (pair tried acc)
                         chain))
              (nextTried (pairFirst res))
              (nextAcc (withTemperatureOverride (pairSecond res) (- (listLength (pairSecond res)) (listLength acc)) (routeTemperatureOverrideOf (routeFindLine prof.routes line))))
              (nextSeen (cons cur seen))]
          (match prof.fallback
            ((none) (listReverse nextAcc))
            ((some fb) (entriesLoopExact! table fb line nextSeen nextTried nextAcc)))))))

fn gatewayV2EntriesExact! table: GatewayTable name: String intent: String -> (List GatewayResolvedEntry)
  (let [(line (gatewayIntentLine table intent))]
    (entriesLoopExact! table name line (list) (list) (list)))

fn findModelByProviderAndName models: (List GatewayModel) target: String -> (Option GatewayModel)
  (match (listHead models)
    ((none) (none))
    ((some m)
      (if (= (str m.provider "/" m.name) target)
        (some m)
        (findModelByProviderAndName (optionOr (listTail models) (list)) target))))

fn gatewayV2AliasEntry! table: GatewayTable model: String -> (Option GatewayResolvedEntry)
  (if (!= table.version 2)
    (none)
    (match (mapGet table.models model)
      ((some _) (some (gatewayV2Entry! table model)))
      ((none)
        (match (findModelByProviderAndName (mapValues table.models) model)
          ((some m) (some (gatewayV2Entry! table m.id)))
          ((none) (none))))))

fn gatewayEntryLabel e: GatewayResolvedEntry -> String
  (match e
    ((entryResolved entry) entry.alias)
    ((entryUnresolved alias) alias))

; (:m :tags (retry) :do "a model's own :retry wins; absent, it falls back to its provider's :retry; absent on both, noRetryPolicy (maxAttempts 0) keeps today's behaviour unchanged")
fn providerRetryOf table: (Option GatewayTable) providerId: String -> (Option RetryPolicy)
  (match table
    ((none) (none))
    ((some tbl) (match (mapGet tbl.providers providerId) ((some pv) pv.retry) ((none) (none)))))

fn mergedRetryPolicy table: (Option GatewayTable) providerId: String entry: (Option GatewayEntry) -> RetryPolicy
  (let [(entryRetry (match entry ((some e) e.retry) ((none) (none))))]
    (optionOr entryRetry (optionOr (providerRetryOf table providerId) (noRetryPolicy))))

fn anyOnlyForProfile table: GatewayTable pid: String pr: GatewayProfile -> (List String)
  (let [(namedRoutes (filter (fn [(r GatewayRoute)] -> Bool (!= r.intent "any")) pr.routes))
        (named (map (fn [(r GatewayRoute)] -> String r.intent) namedRoutes))
        (leonIntents (list "auto" "code" "plan" "research" "reinforce"))]
    (fold (fn [(acc (List String)) (i String)] -> (List String)
            (let [(line (gatewayIntentLine table i))
                  (hasMatch (listAny? (fn [(l String)] -> Bool (listContains? named l)) line))]
              (if hasMatch
                acc
                (listAppendOne acc (str "profile " pid ": Leon intent " i " resolves only to any")))))
          (list)
          leonIntents))

fn gatewayAnyOnlyIntents table: GatewayTable -> (List String)
  (fold (fn [(acc (List String)) (pid String)] -> (List String)
          (match (mapGet table.profiles pid)
            ((none) acc)
            ((some pr) (listAppend acc (anyOnlyForProfile table pid pr)))))
        (list)
        table.profileOrder)

fn gatewayNoteIntent table: GatewayTable intent: String -> GatewayTable
  (if (and (= table.version 2) (and (not (stringEmpty? intent)) (not (mapHas? table.intents intent))))
    (let [(curCount (optionOr (mapGet table.undeclaredIntents intent) 0))
          (nextMap (mapSet table.undeclaredIntents intent (+ curCount 1)))]
      (with table :undeclaredIntents nextMap))
    table)

fn gatewayUndeclaredIntents table: GatewayTable -> (Map String Int64)
  table.undeclaredIntents


(enum ConfigKey
  (:c keyBuiltin [])
  (:c keyFiles [(parts (List (Pair String (Option (Pair Int64 Int64)))))]))

(schema ProfilesCache
  (:f key (Option ConfigKey))
  (:f result (Result GatewayTable String)))

(schema ProfileSelection
  (:f name String)
  (:f profile GatewayProfile)
  (:f source String))

(schema RouteEntries
  (:f name String)
  (:f entries (List GatewayResolvedEntry))
  (:f table GatewayTable)
  (:f temperature (Option Float64))
  ; (:m :ref GW-SPREAD-LIVE-20261018 :do "the matched route's own :spread/:cooldownSec, carried the same way :temperature already is, so cascadeChosen can order its Loop.models without re-resolving the route itself")
  (:f spread (List (Pair String Int64)))
  (:f cooldownSec Int64))

(enum ProfileHealth
  (:c healthError [(error String) (source String)])
  (:c healthV1 [(name String) (routes (List GatewayRoute)) (source String)])
  (:c healthV2 [(name String) (routes (List GatewayRoute)) (fallback (Option String)) (source String)]))

(schema ConfigHealth
  (:f source String)
  (:f uses (List (Pair String String)))
  (:f profiles (List GatewayProfile))
  (:f models (List GatewayModel))
  (:f registry String)
  (:f registryError (Option String))
  (:f warnings (List String)))

fn gatewayProfilesPath home: String -> String
  (str (rstripSlash home) "/.asl/gateway.asn")

; (:m :ref GW-SECRETS-FILE-OVERRIDE :do "an optional top-level (:gateway ... :secretsFile \"path\") names the secrets file the server and config check both read; ~ expands against HOME, absent or unparseable text is none so the default ~/.asl/secrets.asn applies")
fn gatewaySecretsFileOverride text: String -> (Option String)
  (match (ast/readForms (lx/tokenize text))
    ((err _) none)
    ((ok forms)
     (if (!= (listLength forms) 1)
       none
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (asnProps top (some ":gateway"))
           ((err _) none)
           ((ok g)
            (match (mapGet g "secretsFile")
              ((none) none)
              ((some value)
               (match (asnScalar value)
                 ((scalarStr s) (if (stringEmpty? s) none (some (expandUserPath s))))
                 (_ none))))))))))

; (:m :ref GW-SERVE-KEYFILES :do "serve and link read provider keys from the process env only, so a key kept in a (:gateway :keyFiles) file never reached a request; this overlays each provider keyEnv with the value those files hold (the file wins, as GW-KEYSTORE-20261019 orders it), and never prints a value")
fn ! keyFilesEnvOverlay! text: String env: (Map String String) -> (Map String String)
  (match (ast/readForms (lx/tokenize text))
    ((err _) env)
    ((ok forms)
     (match (asnProps (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr (some ":gateway"))
       ((err _) env)
       ((ok g)
        (let [(files (gatewayKeyFilesFromProps g))
              (rows (match (mapGet g "providers") ((some (rd/sexprList l)) l) (_ (list))))
              (keyEnvs (map (fn [(row rd/SExpr)] -> String
                              (match (asnProps row (some ":provider"))
                                ((ok p) (match (mapGet p "keyEnv") ((some v) (scalarToString (asnScalar v))) ((none) "")))
                                ((err _) "")))
                         rows))]
          (if (listEmpty? files) env
            (fold (fn [(acc (Map String String)) (name String)] -> (Map String String)
                    (if (stringEmpty? name) acc
                      (match (resolveProviderKey! files name) ((some v) (if (stringEmpty? v) acc (mapSet acc name v))) ((none) acc))))
              env keyEnvs)))))))

; (:m :ref AUDIT12-B6 :do "the strict form of gatewaySecretsFileOverride for serve: unparseable non-empty text or a :secretsFile that is not a non-empty string is an error instead of none, so serve auth cannot fail open on a config it could not read; absent key is ok none")
fn gatewaySecretsFileChoice text: String -> (Result (Option String) String)
  (if (stringEmpty? (stringTrim text)) (ok none)
    (match (ast/readForms (lx/tokenize text))
      ((err e) (err (str "ERR_SECRETS_CONFIG: gateway config does not parse: " e)))
      ((ok forms)
       (if (!= (listLength forms) 1)
         (err "ERR_SECRETS_CONFIG: gateway config is not exactly one form")
         (match (asnProps (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr (some ":gateway"))
           ((err e) (err (str "ERR_SECRETS_CONFIG: " e)))
           ((ok g)
            (match (mapGet g "secretsFile")
              ((none) (ok none))
              ((some value)
               (match (asnScalar value)
                 ((scalarStr s) (if (stringEmpty? s) (err "ERR_SECRETS_CONFIG: :secretsFile is empty") (ok (some (expandUserPath s)))))
                 (_ (err "ERR_SECRETS_CONFIG: :secretsFile must be a string path")))))))))))

; (:m an optional top-level (:gateway ... :ledgerPath "...") string overrides ul/defaultLedgerPath's home/.asl/run/gatewayCalls.asn; absent, unparseable or non-string text is none, never guessed)
fn gatewayLedgerPathOverride text: String -> (Option String)
  (match (ast/readForms (lx/tokenize text))
    ((err _) none)
    ((ok forms)
     (if (!= (listLength forms) 1)
       none
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (asnProps top (some ":gateway"))
           ((err _) none)
           ((ok g)
            (match (mapGet g "ledgerPath")
              ((none) none)
              ((some value)
               (match (asnScalar value)
                 ((scalarStr s) (some s))
                 (_ none))))))))))

; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "an optional top-level (:gateway ... :sharedUsagePath \"...\") string, same shape as :ledgerPath above but for the shared accounting ledger every gateway process (any HOME, any scratch slot) appends every call to; absent, unparseable or non-string text is none, same default-to-home fallback as :ledgerPath. A scratch-HOME gateway only reaches the real, shared, non-deleted path when its own copy of this config carries this key as an ABSOLUTE string (fp/writeGatewayConfig!-style copy preserves it verbatim, since it is a literal string in the file, not derived from $HOME at read time) -- the operator sets this once in the real ~/.asl/gateway.asn after merge, same deliver step as GW-SPREAD-20261017's :spread rows")
fn gatewaySharedUsagePathOverride text: String -> (Option String)
  (match (ast/readForms (lx/tokenize text))
    ((err _) none)
    ((ok forms)
     (if (!= (listLength forms) 1)
       none
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (asnProps top (some ":gateway"))
           ((err _) none)
           ((ok g)
            (match (mapGet g "sharedUsagePath")
              ((none) none)
              ((some value)
               (match (asnScalar value)
                 ((scalarStr s) (some s))
                 (_ none))))))))))

; (:m :ref GW-BREAKER-STALE-20261018 :do "an optional top-level (:gateway ... :breakerCooldownSec N), same shape as :ledgerPath above; absent, unparseable or non-int text is none, so a config that never sets this keeps the 600s default -- GW-BREAKER-STALE-20261018's own incident was a cooldown fixed at 600s outlasting an entire sweep with no way to shorten it")
fn gatewayBreakerCooldownSecOverride text: String -> (Option Int64)
  (gatewayTopIntOverride text "breakerCooldownSec")

; (:m :ref GW-429-WINDOW-WAIT :do "an optional top-level (:gateway ... :KEY N) int, read the way :breakerCooldownSec always was; absent, unparseable or non-int is none")
; (:m :ref CTX-ROUTE :do "the top-level (:gateway :contextCap N) row, the ceiling gateway models sync and apply put on a model's :contextBudget; adopted default 200000 when absent or not an integer; config check accepts 1 to 10000000")
fn gatewayContextCap text: String -> Int64
  (optionOr (gatewayTopIntOverride text "contextCap") 200000)

fn gatewayTopIntOverride text: String key: String -> (Option Int64)
  (match (gatewayTopScalarOverride text key)
    ((some (scalarInt n)) (some n))
    (_ none))

; (:m :ref GW-SESSION-AFFINITY :do "an optional top-level (:gateway ... :KEY V) scalar; absent or unparseable text is none")
fn gatewayTopScalarOverride text: String key: String -> (Option AsnScalar)
  (match (ast/readForms (lx/tokenize text))
    ((err _) none)
    ((ok forms)
     (if (!= (listLength forms) 1)
       none
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (asnProps top (some ":gateway"))
           ((err _) none)
           ((ok g) (optionMap asnScalar (mapGet g key))))))))

; (:m :ref GW-USAGE-ACCOUNTING-20261017 :do "walks (:dailyTokenBudgets ((profileId N) ...)) looking for one row naming profile; a profile absent from the list has no budget (none), never guessed, so an operator who sets no budget for a profile keeps today's unlimited behaviour")
fn gatewayDailyTokenBudgetItems items: (List rd/SExpr) profile: String -> (Option Int64)
  (match (listHead items)
    ((none) none)
    ((some entry)
     (let [(parts (match entry ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))
           (name (match (listHead parts) ((none) "") ((some n) (resultOr (asn_name_or_string n "dailyTokenBudgets entry") ""))))
           (budget (match (asnScalar (optionOr (listGet parts 1) (rd/makeAtom ""))) ((scalarInt n) (some n)) (_ none)))]
       (if (= name profile) budget (gatewayDailyTokenBudgetItems (optionOr (listTail items) (list)) profile)))))

fn gatewayDailyTokenBudget text: String profile: String -> (Option Int64)
  (match (ast/readForms (lx/tokenize text))
    ((err _) none)
    ((ok forms)
     (if (!= (listLength forms) 1)
       none
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (asnProps top (some ":gateway"))
           ((err _) none)
           ((ok g)
            (match (mapGet g "dailyTokenBudgets")
              ((none) none)
              ((some value)
               (let [(items (match value ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
                 (gatewayDailyTokenBudgetItems items profile))))))))))

; (:m :ref PROFILE-PIN-NAME-20261018 :do "a per-worktree/per-rootDir pin naming which gateway profile this run should use, written by tools/fleet/freePool.asl and tools/orch/main.asl's Leon lane, read by asl/packages/asl-agent/src/providers.asl's providerEnv! and asl-forms/delegate.asl's (:research ...) op -- previously each of those four call sites duplicated its own profilePinPath string and its own ad-hoc parse (a byte tokenizer in one, a stringIndexOf/split in another); this is the one shared path, reader and writer all four now call. .asl.config.asn already has several unrelated :profile rows of its own (FREEPOOL-PROFILE-COLLISION), so the pin keeps its own dedicated file rather than folding into that surface; renamed from freePoolProfile.asn since the pin is not free-pool-specific -- orch's own non-freePool Leon lane and :research read it too")
fn profilePinPath rootDir: String -> String
  (str rootDir "/.asl/gatewayProfilePin.asn")

fn profilePinFromText text: String -> (Option String)
  (match (ast/readForms (lx/tokenize text))
    ((err _) none)
    ((ok forms)
     (if (!= (listLength forms) 1)
       none
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match top
           ((rd/sexprList items)
            (match (listHead items)
              ((none) none)
              ((some head)
               (if (!= (sexprRawText head) ":profile")
                 none
                 (match (listGet items 1)
                   ((none) none)
                   ((some valueExpr)
                    (match (asnScalar valueExpr)
                      ((scalarStr s) (if (stringEmpty? s) none (some s)))
                      (_ none))))))))
           (_ none))))))

fn ! profilePinRead! rootDir: String -> (Option String)
  (match (fileReadString (profilePinPath rootDir))
    ((err _) none)
    ((ok text) (profilePinFromText text)))

fn ! writeProfilePin! rootDir: String profile: String -> Bool
  (and (ok? (dirCreate (str rootDir "/.asl")))
    (ok? (fileWrite (profilePinPath rootDir) (str "(:profile " (asnQuoted profile) ")\n"))))

fn configKeyPart! path: String -> (Pair String (Option (Pair Int64 Int64)))
  (match (fileStat path)
    ((ok st) (pair path (some (pair st.mtime st.size))))
    ((err _) (pair path (none))))

fn gatewayConfigKey! path: String registryPath: String -> ConfigKey
  (keyFiles (list (configKeyPart! path) (configKeyPart! registryPath)))

fn statEqual? a: (Option (Pair Int64 Int64)) b: (Option (Pair Int64 Int64)) -> Bool
  (match a
    ((none) (none? b))
    ((some x)
      (match b
        ((none) false)
        ((some y) (and (= (pairFirst x) (pairFirst y)) (= (pairSecond x) (pairSecond y)))))))

fn keyPartsEqual? a: (List (Pair String (Option (Pair Int64 Int64)))) b: (List (Pair String (Option (Pair Int64 Int64)))) -> Bool
  (match (listHead a)
    ((none) (listEmpty? b))
    ((some x)
      (match (listHead b)
        ((none) false)
        ((some y)
          (and (= (pairFirst x) (pairFirst y))
               (statEqual? (pairSecond x) (pairSecond y))
               (keyPartsEqual? (optionOr (listTail a) (list)) (optionOr (listTail b) (list))))))))

fn configKeyEqual? a: ConfigKey b: ConfigKey -> Bool
  (match a
    ((keyBuiltin) (match b ((keyBuiltin) true) (_ false)))
    ((keyFiles pa) (match b ((keyFiles pb) (keyPartsEqual? pa pb)) (_ false))))

fn gatewayProfileHasRoutes? table: GatewayTable -> Bool
  (listAny? (fn [(name String)] -> Bool
              (match (mapGet table.profiles name)
                ((some p) (not (listEmpty? p.routes)))
                ((none) false)))
            table.profileOrder)

fn gatewayNoRoutesError? message: String -> Bool
  (or (stringContains? message "routes must be a non-empty list")
      (or (stringContains? message "profiles must be a non-empty list")
          (stringContains? message "profiles must define at least one")))

fn gatewayProfilesLoadText! path: String exists: Bool text: (Result String String) registryPath: String -> (Result GatewayTable String)
  (if (not exists)
    (err (str "ERR_GATEWAY_NO_CONFIG: " path))
    (match text
      ((err e) (err (str path ": " e)))
      ((ok t)
        (match (gatewayConfigParse! t path registryPath)
          ((err e) (if (gatewayNoRoutesError? e) (err (str "ERR_GATEWAY_NO_CONFIG: " path)) (err (str path ": " e))))
          ((ok tbl) (if (gatewayProfileHasRoutes? tbl) (ok tbl) (err (str "ERR_GATEWAY_NO_CONFIG: " path))))))))

fn gatewayLoadWarningLines path: String table: GatewayTable -> (List String)
  (map (fn [(w String)] -> String (str "[Gateway Config] " path ": " w)) table.warnings)

fn emptyProfilesCache -> ProfilesCache
  (ProfilesCache :key (none) :result (err "gateway profiles not loaded"))

fn cacheHit? cache: ProfilesCache key: ConfigKey -> Bool
  (match cache.key
    ((none) false)
    ((some k) (configKeyEqual? k key)))

fn gatewayProfilesLoad! cache: ProfilesCache home: String registryPath: String -> (Pair ProfilesCache (Result GatewayTable String))
  (let [(path (gatewayProfilesPath home))
        (exists (fileExists? path))
        (key (if exists (gatewayConfigKey! path registryPath) (keyBuiltin)))]
    (if (cacheHit? cache key)
      (pair cache cache.result)
      (let [(text (if exists (fileReadString path) (err "not read")))
            (result (gatewayProfilesLoadText! path exists text registryPath))]
        (do
          (match result
            ((ok tbl)
              (let [(lines (gatewayLoadWarningLines path tbl))]
                (if (and exists (not (listEmpty? lines))) (eprintln (stringJoin lines "\n")) ())))
            ((err _) ()))
          (pair (ProfilesCache :key (some key) :result result) result)))))

; (:m :ref HRN-DECISION-LAYER :do "a decision point is switched per row (:gateway ... :decides ((:decide :point P :mode off|static|model|shadow :model M :threshold T))); a point with no valid row of its own runs static (no outward call); shadow and model, the modes that send error lines to a provider, come only from an explicit valid row for that point, and a malformed row of another point never changes this one; keyFiles ride along so a caller resolves the provider key through keyFileLookup! and not the environment first")
(schema DecidePoint
  (:f point String)
  (:f mode String)
  (:f model String)
  (:f threshold Float64)
  (:f keyFiles (List String)))

fn decideModes -> (List String)
  (list "off" "static" "model" "shadow")

fn defaultDecidePoint point: String -> DecidePoint
  (DecidePoint :point point :mode "static" :model "" :threshold 0.5 :keyFiles (list))

fn decideThreshold props: (Map String rd/SExpr) what: String -> (Result Float64 String)
  (match (mapGet props "threshold")
    ((none) (ok 0.5))
    ((some expr)
      (let [(v (match (asnScalar expr) ((scalarFloat f) (some f)) ((scalarInt n) (some (int64ToFloat64 n))) (_ (none))))]
        (match v
          ((none) (err (str what " :threshold must be a number")))
          ((some f) (if (or (< f 0.0) (> f 1.0)) (err (str what " :threshold must be within 0..1")) (ok f)))))))

fn decideOne props: (Map String rd/SExpr) -> (Result DecidePoint String)
  (match (mapGet props "point")
    ((none) (err "(:decide ...) needs :point"))
    ((some pExpr)
      (match (asnName pExpr "(:decide :point ...)")
        ((err e) (err e))
        ((ok point)
          (let [(what (str "decide " point))
                (modeRes (match (mapGet props "mode")
                           ((none) (err (str what " needs :mode off, static, model or shadow")))
                           ((some m) (match (asnName m (str what " :mode"))
                                       ((err e) (err e))
                                       ((ok mode) (if (listContains? (decideModes) mode) (ok mode) (err (str what " :mode must be one of off static model shadow, found " mode))))))))
                (modelRes (match (mapGet props "model")
                            ((none) (ok ""))
                            ((some m) (asn_name_or_string m (str what " :model")))))]
            (match modeRes
              ((err e) (err e))
              ((ok mode)
                (match modelRes
                  ((err e) (err e))
                  ((ok model)
                    (match (decideThreshold props what)
                      ((err e) (err e))
                      ((ok t) (ok (DecidePoint :point point :mode mode :model model :threshold t :keyFiles (list))))))))))))))

fn gatewayDecideRows g: (Map String rd/SExpr) -> (Pair (Map String DecidePoint) (List String))
  (let [(forms (getSubForms g "decides" ":decide"))
        (keyFiles (gatewayKeyFilesFromProps g))
        (named (map (fn [(props (Map String rd/SExpr))] -> String
                      (match (mapGet props "point") ((some p) (match (asnName p "point") ((ok s) s) ((err _) ""))) ((none) "")))
                    (pairFirst forms)))
        (twice (fn [(p String)] -> Bool (> (listCount (fn [(s String)] -> Bool (= s p)) named) 1)))]
    (fold (fn [(acc (Pair (Map String DecidePoint) (List String))) (props (Map String rd/SExpr))] -> (Pair (Map String DecidePoint) (List String))
            (match (decideOne props)
              ((err e) (pair (pairFirst acc) (listAppendOne (pairSecond acc) e)))
              ((ok d) (cond
                        ((twice d.point)
                          (if (listContains? (pairSecond acc) (str "decide " d.point " is declared twice"))
                            acc
                            (pair (pairFirst acc) (listAppendOne (pairSecond acc) (str "decide " d.point " is declared twice")))))
                        (else (pair (mapSet (pairFirst acc) d.point (DecidePoint :point d.point :mode d.mode :model d.model :threshold d.threshold :keyFiles keyFiles)) (pairSecond acc)))))))
          (pair (mapEmpty) (pairSecond forms))
          (pairFirst forms)))

; (:m :do "text is a whole gateway.asn; an unreadable or non-(:gateway ...) text, or a point with no row, yields defaultDecidePoint (static) plus the reason; valid rows of other points stay in force")
fn gatewayDecidePoint text: String point: String -> (Pair DecidePoint (List String))
  (match (ast/readForms (lx/tokenize text))
    ((err e) (pair (defaultDecidePoint point) (list (str "gateway config unreadable: " e))))
    ((ok forms)
      (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
        (match (asnProps top (some ":gateway"))
          ((err e) (pair (defaultDecidePoint point) (list e)))
          ((ok g)
            (let [(rows (gatewayDecideRows g))
                  (base (DecidePoint :point point :mode "static" :model "" :threshold 0.5 :keyFiles (gatewayKeyFilesFromProps g)))]
              (pair (optionOr (mapGet (pairFirst rows) point) base) (pairSecond rows))))))))

fn ! gatewayDecideLoad! path: String point: String -> (Pair DecidePoint (List String))
  (match (fileReadString path)
    ((err _) (pair (defaultDecidePoint point) (list (str "no gateway config at " path))))
    ((ok text) (gatewayDecidePoint text point)))

; (:m :ref CODE-ROUTE-20261028 :do "a code route is declared per row (:gateway ... :codeRoutes ((:codeRoute :id ID :writer ALIAS :retries N :escalate ALIAS :escalateTimeoutSec S :escalateRetries N :escalateRetryStatuses (CODE ...)))); writer and escalate name :models aliases of the same config, never an upstream model id; the temperature is the alias row's own; :retries defaults 2 and may not exceed 2")
(schema CodeRoute
  (:f id String)
  (:f writer String)
  (:f retries Int64)
  (:f escalate String)
  (:f retryWriter String)
  (:f escalateTimeoutSec Float64)
  (:f escalateRetries Int64)
  (:f escalateRetryStatuses (List Int64)))

fn codeRouteAlias props: (Map String rd/SExpr) key: String what: String table: GatewayTable -> (Result String String)
  (match (mapGet props key)
    ((none) (err (str what " needs :" key)))
    ((some e)
      (match (asnName e (str what " :" key))
        ((err m) (err m))
        ((ok a) (if (mapHas? table.models a) (ok a) (err (str what " :" key ": unknown alias " a)))))))

fn codeRouteOptAlias props: (Map String rd/SExpr) key: String what: String table: GatewayTable -> (Result String String)
  (match (mapGet props key)
    ((none) (ok ""))
    ((some _) (codeRouteAlias props key what table)))

fn codeRouteInt props: (Map String rd/SExpr) key: String fallback: Int64 lo: Int64 hi: Int64 what: String -> (Result Int64 String)
  (match (mapGet props key)
    ((none) (ok fallback))
    ((some e)
      (match (asnScalar e)
        ((scalarInt n) (if (or (< n lo) (> n hi)) (err (str what " :" key " must be within " (stringFromInt64 lo) ".." (stringFromInt64 hi))) (ok n)))
        (_ (err (str what " :" key " must be an integer"))))))

fn codeRouteStatuses props: (Map String rd/SExpr) what: String -> (Result (List Int64) String)
  (match (mapGet props "escalateRetryStatuses")
    ((none) (ok (list 502)))
    ((some e)
      (let [(items (match e ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))
            (codes (map (fn [(x rd/SExpr)] -> (Option Int64) (match (asnScalar x) ((scalarInt n) (some n)) (_ (none)))) items))]
        (if (or (listEmpty? items) (listAny? (fn [(c (Option Int64))] -> Bool (= (optionOr c -1) -1)) codes))
          (err (str what " :escalateRetryStatuses must be a non-empty list of integers"))
          (ok (map (fn [(c (Option Int64))] -> Int64 (optionOr c 0)) codes))))))

fn codeRouteOne props: (Map String rd/SExpr) table: GatewayTable -> (Result CodeRoute String)
  (match (mapGet props "id")
    ((none) (err "(:codeRoute ...) needs :id"))
    ((some iExpr)
      (match (asnName iExpr "(:codeRoute :id ...)")
        ((err e) (err e))
        ((ok id)
          (let [(what (str "codeRoute " id))]
            (match (codeRouteAlias props "writer" what table)
              ((err e) (err e))
              ((ok writer)
                (match (codeRouteAlias props "escalate" what table)
                  ((err e) (err e))
                  ((ok escalate)
                    (match (codeRouteOptAlias props "retryWriter" what table)
                      ((err e) (err e))
                      ((ok retryWriter)
                    (match (codeRouteInt props "retries" 2 0 2 what)
                      ((err e) (err e))
                      ((ok retries)
                        (match (codeRouteInt props "escalateTimeoutSec" 240 1 3600 what)
                          ((err e) (err e))
                          ((ok timeout)
                            (match (codeRouteInt props "escalateRetries" 2 0 5 what)
                              ((err e) (err e))
                              ((ok escRetries)
                                (match (codeRouteStatuses props what)
                                  ((err e) (err e))
                                  ((ok statuses)
                                    (ok (CodeRoute :id id :writer writer :retries retries :escalate escalate :retryWriter retryWriter :escalateTimeoutSec (int64ToFloat64 timeout) :escalateRetries escRetries :escalateRetryStatuses statuses)))))))))))))))))))))

; (:m :do "text is a whole gateway.asn; the row named id is parsed and its aliases checked against the same config's :models; an unreadable config, a missing row or a malformed row is an error naming the cause, never a default route")
fn ! gatewayCodeRoute! text: String id: String registryPath: String -> (Result CodeRoute String)
  (match (gatewayConfigParse! text "codeRoute" registryPath)
    ((err e) (err e))
    ((ok table)
      (match (ast/readForms (lx/tokenize text))
        ((err e) (err (str "gateway config unreadable: " e)))
        ((ok forms)
          (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
            (match (asnProps top (some ":gateway"))
              ((err e) (err e))
              ((ok g)
                (let [(rows (getSubForms g "codeRoutes" ":codeRoute"))
                      (named (filter (fn [(p (Map String rd/SExpr))] -> Bool
                                       (match (mapGet p "id") ((some x) (match (asnName x "id") ((ok s) (= s id)) ((err _) false))) ((none) false)))
                                     (pairFirst rows)))]
                  (match (listHead named)
                    ((none) (err (str "no codeRoute " id " in the gateway config")))
                    ((some p) (if (> (listLength named) 1) (err (str "codeRoute " id " is declared twice")) (codeRouteOne p table))))))))))))

fn headerGet headers: (List (Pair String String)) name: String -> String
  (match (listHead headers)
    ((none) "")
    ((some h)
      (if (= (stringLower (pairFirst h)) (stringLower name))
        (pairSecond h)
        (headerGet (optionOr (listTail headers) (list)) name))))

fn gatewayProfileName table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) -> (Result String String)
  (let [(fromHeader (stringTrim (headerGet headers "X-ASL-Profile")))
        (use (stringTrim (headerGet headers "X-ASL-Use")))
        (uses (if (= (mapSize table.uses) 0) (mapSet (mapEmpty) "default" table.defaultProfile) table.uses))
        (viaUse (if (and (stringEmpty? fromHeader) (not (stringEmpty? use)))
                  (match (mapGet uses use)
                    ((none) (err (str "unknown use " use)))
                    ((some p) (ok p)))
                  (ok fromHeader)))]
    (match viaUse
      ((err e) (err e))
      ((ok picked)
        (let [(fromEnv (stringTrim (optionOr envProfile "")))
              (name (cond
                      ((not (stringEmpty? picked)) picked)
                      ((not (stringEmpty? fromEnv)) fromEnv)
                      (else table.defaultProfile)))]
          (if (mapHas? table.profiles name)
            (ok name)
            (err (str "unknown profile " name)))))))

fn gatewayProfileSelect table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) -> (Result ProfileSelection String)
  (match (gatewayProfileName table headers envProfile)
    ((err e) (err e))
    ((ok name)
      (match (mapGet table.profiles name)
        ((none) (err (str "unknown profile " name)))
        ((some pr) (ok (ProfileSelection :name name :profile pr :source table.source))))))

fn isPlanIntent? i: String -> Bool
  (or (= i "plan") (= i "design") (= i "research"))

fn routeModelsNamed routes: (List GatewayRoute) i: String -> (Option (List String))
  (match (listHead routes)
    ((none) (none))
    ((some r)
      (if (and (!= r.intent "any") (or (= r.intent i) (and (= r.intent "plan") (isPlanIntent? i))))
        (some r.models)
        (routeModelsNamed (optionOr (listTail routes) (list)) i))))

fn routeModelsAny routes: (List GatewayRoute) -> (Option (List String))
  (match (listHead routes)
    ((none) (none))
    ((some r)
      (if (= r.intent "any")
        (some r.models)
        (routeModelsAny (optionOr (listTail routes) (list))))))

fn gatewayProfileModels routes: (List GatewayRoute) intent: String -> (Option (List String))
  (let [(i (stringLower (lstripColons intent)))]
    (match (routeModelsNamed routes i)
      ((some ms) (some ms))
      ((none) (routeModelsAny routes))))

fn routeTemperatureFor table: GatewayTable name: String intent: String -> (Option Float64)
  (match (mapGet table.profiles name)
    ((none) (none))
    ((some prof) (gatewayV2RouteTemperature prof (gatewayIntentLine table intent))))

; (:m :do "the exact-match sibling of routeTemperatureFor: walks the same profile fallback chain as entriesLoopExact! (so a profile that falls back to another one inherits its temperature, not just its models) but never substitutes the :intent any catch-all for a specific miss")
fn routeTemperatureForExactLoop table: GatewayTable cur: String line: (List String) seen: (List String) -> (Option Float64)
  (if (or (stringEmpty? cur) (listContains? seen cur))
    none
    (match (mapGet table.profiles cur)
      ((none) none)
      ((some prof)
       (match (routeFindLine prof.routes line)
         ((some r) r.temperature)
         ((none) (match prof.fallback ((none) none) ((some fb) (routeTemperatureForExactLoop table fb line (cons cur seen)))))))))

fn routeTemperatureForExact table: GatewayTable name: String intent: String -> (Option Float64)
  (routeTemperatureForExactLoop table name (gatewayIntentLine table intent) (list))

; (:m :ref GW-SPREAD-LIVE-20261018 :do "routeTemperatureFor's sibling for :spread/:cooldownSec: same single-profile, :intent any-substituting lookup, never a fallback walk")
fn routeSpreadFor table: GatewayTable name: String intent: String -> (List (Pair String Int64))
  (match (mapGet table.profiles name)
    ((none) (list))
    ((some prof) (match (routeFindLineOrAny prof.routes (gatewayIntentLine table intent)) ((some r) r.spread) ((none) (list)))))

fn routeCooldownSecFor table: GatewayTable name: String intent: String -> Int64
  (match (mapGet table.profiles name)
    ((none) 60)
    ((some prof) (match (routeFindLineOrAny prof.routes (gatewayIntentLine table intent)) ((some r) r.cooldownSec) ((none) 60))))

; (:m :do "the exact-match sibling of routeSpreadFor/routeCooldownSecFor: walks the profile fallback chain exactly like routeTemperatureForExactLoop, no :intent any substitution")
fn routeSpreadForExactLoop table: GatewayTable cur: String line: (List String) seen: (List String) -> (List (Pair String Int64))
  (if (or (stringEmpty? cur) (listContains? seen cur))
    (list)
    (match (mapGet table.profiles cur)
      ((none) (list))
      ((some prof)
       (match (routeFindLine prof.routes line)
         ((some r) r.spread)
         ((none) (match prof.fallback ((none) (list)) ((some fb) (routeSpreadForExactLoop table fb line (cons cur seen)))))))))

fn routeSpreadForExact table: GatewayTable name: String intent: String -> (List (Pair String Int64))
  (routeSpreadForExactLoop table name (gatewayIntentLine table intent) (list))

fn routeCooldownSecForExactLoop table: GatewayTable cur: String line: (List String) seen: (List String) -> Int64
  (if (or (stringEmpty? cur) (listContains? seen cur))
    60
    (match (mapGet table.profiles cur)
      ((none) 60)
      ((some prof)
       (match (routeFindLine prof.routes line)
         ((some r) r.cooldownSec)
         ((none) (match prof.fallback ((none) 60) ((some fb) (routeCooldownSecForExactLoop table fb line (cons cur seen)))))))))

fn routeCooldownSecForExact table: GatewayTable name: String intent: String -> Int64
  (routeCooldownSecForExactLoop table name (gatewayIntentLine table intent) (list))

; (:m :ref GATEWAY-GONE-MODEL-ROWS :do "a route whose every chain alias was skipped as gone has an empty chain (the parse refuses an empty one otherwise): asking for it is an error for that route only, never a silent fall to another route")
fn goneRouteCheck table: GatewayTable name: String intent: String exact: Bool re: RouteEntries -> (Result RouteEntries String)
  (if (not (listEmpty? re.entries)) (ok re)
    (match (mapGet table.profiles name)
      ((none) (ok re))
      ((some prof)
        (let [(line (gatewayIntentLine table intent))
              (r (if exact (routeFindLine prof.routes line) (routeFindLineOrAny prof.routes line)))]
          (match r
            ((some x) (if (listEmpty? x.chain) (err (str "profile " name " route " x.intent ": every chain alias is :status gone")) (ok re)))
            ((none) (ok re)))))))

fn gatewayRouteEntries! table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) intent: String -> (Result RouteEntries String)
  (match (gatewayProfileName table headers envProfile)
    ((err e) (err e))
    ((ok name)
      (if (= table.version 2)
        (let [(noted (gatewayNoteIntent table (stringLower (lstripColons intent))))]
          (goneRouteCheck noted name intent false (RouteEntries :name name :entries (gatewayV2Entries! noted name intent) :table noted :temperature (routeTemperatureFor noted name intent)
                :spread (routeSpreadFor noted name intent) :cooldownSec (routeCooldownSecFor noted name intent))))
        (let [(routes (match (mapGet table.profiles name) ((some pr) pr.routes) ((none) (list))))
              (models (optionOr (gatewayProfileModels routes intent) (list)))]
          (ok (RouteEntries :name name :entries (map (fn [(m String)] -> GatewayResolvedEntry (entryUnresolved m)) models) :table table :temperature none :spread (list) :cooldownSec 60))))))

; (:m :do "the exact-match sibling of gatewayRouteEntries!: no :intent any substitution, so an empty entries list genuinely means this key has no route of its own; used by aliasRoute! to try role, role:lens composite and bare role in turn without the active profile's generic any route masking every miss")
fn gatewayRouteEntriesExact! table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) intent: String -> (Result RouteEntries String)
  (match (gatewayProfileName table headers envProfile)
    ((err e) (err e))
    ((ok name)
      (if (= table.version 2)
        (let [(noted (gatewayNoteIntent table (stringLower (lstripColons intent))))]
          (goneRouteCheck noted name intent true (RouteEntries :name name :entries (gatewayV2EntriesExact! noted name intent) :table noted :temperature (routeTemperatureForExact noted name intent)
                :spread (routeSpreadForExact noted name intent) :cooldownSec (routeCooldownSecForExact noted name intent))))
        (let [(routes (match (mapGet table.profiles name) ((some pr) pr.routes) ((none) (list))))
              (models (optionOr (routeModelsNamed routes (stringLower (lstripColons intent))) (list)))]
          (ok (RouteEntries :name name :entries (map (fn [(m String)] -> GatewayResolvedEntry (entryUnresolved m)) models) :table table :temperature none :spread (list) :cooldownSec 60))))))

; (:m :do "a reverse lookup: does the active profile's own chain for ANY intent already list this raw model string; used when the caller's model field names a dispatch target directly rather than an alias or a role/intent, so a dead model still gets a cascade of configured siblings to retry instead of a single dead end")
fn routeChainContaining routes: (List GatewayRoute) model: String -> (Option (List String))
  (match (listHead (filter (fn [(r GatewayRoute)] -> Bool (listContains? r.chain model)) routes))
    ((none) none)
    ((some r) (some r.chain)))

fn gatewayChainContainingModel! table: GatewayTable headers: (List (Pair String String)) envProfile: (Option String) model: String -> (Option (List String))
  (match (gatewayProfileName table headers envProfile)
    ((err _) none)
    ((ok name)
      (match (mapGet table.profiles name)
        ((none) none)
        ((some prof) (routeChainContaining prof.routes model)))))

fn gatewayProfileHealth loaded: (Result GatewayTable String) headers: (List (Pair String String)) envProfile: (Option String) path: String exists: Bool -> ProfileHealth
  (let [(errSource (if exists path "builtin"))]
    (match loaded
      ((err e) (healthError e errSource))
      ((ok table)
        (match (gatewayProfileSelect table headers envProfile)
          ((err e) (healthError e errSource))
          ((ok sel)
            (if (= table.version 2)
              (healthV2 sel.name sel.profile.routes sel.profile.fallback table.source)
              (healthV1 sel.name sel.profile.routes table.source)))))))

fn orderedUnique order: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (k String)] -> (List String) (if (listContains? acc k) acc (cons k acc))) (list) order))

fn gatewayConfigHealth loaded: (Result GatewayTable String) -> (Option ConfigHealth)
  (match loaded
    ((err _) (none))
    ((ok table)
      (if (!= table.version 2)
        (none)
        (some (ConfigHealth
                :source table.source
                :uses (fold (fn [(acc (List (Pair String String))) (k String)] -> (List (Pair String String))
                              (match (mapGet table.uses k) ((some p) (listAppend acc (list (pair k p)))) ((none) acc)))
                            (list)
                            (orderedUnique table.useOrder))
                :profiles (fold (fn [(acc (List GatewayProfile)) (k String)] -> (List GatewayProfile)
                                  (match (mapGet table.profiles k) ((some p) (listAppend acc (list p))) ((none) acc)))
                                (list)
                                (orderedUnique table.profileOrder))
                :models (fold (fn [(acc (List GatewayModel)) (k String)] -> (List GatewayModel)
                                (match (mapGet table.models k) ((some m) (listAppend acc (list m))) ((none) acc)))
                              (list)
                              (orderedUnique table.modelOrder))
                :registry table.registry
                :registryError table.registryError
                :warnings table.warnings)))))

fn asnQuoted s: String -> String
  (str "\"" (wire/asnEscape s) "\"")

fn fallbackAsn fallback: (Option String) -> String
  (match fallback
    ((none) "")
    ((some fb) (if (stringEmpty? fb) "" (str " :fallback " fb))))

fn gatewayProfileAsn info: ProfileHealth -> String
  (match info
    ((healthError e source) (str "(:error " (asnQuoted e) " :source " (asnQuoted source) ")"))
    ((healthV2 name routes fallback source)
      (let [(rs (stringJoin (map (fn [(r GatewayRoute)] -> String (str "(:intent " r.intent " :chain (" (stringJoin r.chain " ") "))")) routes) " "))]
        (str "(:name " name " :v 2 :source " (asnQuoted source) " :routes (" rs ")" (fallbackAsn fallback) ")")))
    ((healthV1 name routes source)
      (let [(rs (stringJoin (map (fn [(r GatewayRoute)] -> String (str "(:intent " r.intent " :models (" (stringJoin (map asnQuoted r.models) " ") "))")) routes) " "))]
        (str "(:name " name " :source " (asnQuoted source) " :routes (" rs "))"))))

fn modelAsn m: GatewayModel -> String
  (let [(cal (match m.calibration
               ((none) "")
               ((some c) (if (stringEmpty? c) "" (str " :calibration " (asnQuoted c))))))
        (params (stringJoin (map (fn [(p (Pair String String))] -> String (str " :" (pairFirst p) " " (pairSecond p))) m.shown) ""))]
    (str "(:model :id " m.id " :provider " m.provider " :name " (asnQuoted m.name) cal params (if m.gone " :status gone" "") ")"))

fn gatewayConfigAsn cfg: (Option ConfigHealth) -> String
  (match cfg
    ((none) "")
    ((some c)
      (let [(uses (stringJoin (map (fn [(u (Pair String String))] -> String (str "(:use :for " (pairFirst u) " :profile " (pairSecond u) ")")) c.uses) " "))
            (profiles (stringJoin (map (fn [(p GatewayProfile)] -> String (gatewayProfileAsn (healthV2 p.id p.routes p.fallback c.source))) c.profiles) " "))
            (models (stringJoin (map modelAsn c.models) " "))]
        (str " :gateway (:v 2 :source " (asnQuoted c.source) " :registry " (asnQuoted c.registry)
             " :uses (" uses ") :profiles (" profiles ") :models (" models "))"))))

fn gatewayConfigReceipt path: String registry: String status: String v: Int64 errors: (List String) warnings: (List String) extra: String -> String
  (str "(:configCheck :file " (asnQuoted path) " :v " (stringFromInt64 v) " :registry " (asnQuoted registry) " :status :" status
       " :errors (" (stringJoin (map asnQuoted errors) " ") ") :warnings (" (stringJoin (map asnQuoted warnings) " ") ")" extra ")")

; (:m :ref CONFIG-CHECK-CODEROUTE :do "configCheck parses every (:codeRoute ...) row with the same codeRouteOne the runtime uses, so a missing or unknown writer, retryWriter or escalate alias, or an out-of-range number, is a config error naming the route and the field instead of a failure at the first code run")
fn codeRouteErrors g: (Map String rd/SExpr) table: GatewayTable -> (List String)
  (fold (fn [(acc (List String)) (p (Map String rd/SExpr))] -> (List String)
          (match (codeRouteOne p table) ((err e) (listAppend acc (list e))) ((ok _) acc)))
        (list) (pairFirst (getSubForms g "codeRoutes" ":codeRoute")))

fn gatewayConfigCheckText! text: String source: String registry: String -> (Pair String Int64)
  (let [(tokens (lx/tokenize text))
        (checked (match (asnReadCheck text)
                   ((some e) (err e))
                   ((none)
                     (match (ast/readForms tokens)
                       ((err e) (err e.msg))
                       ((ok forms) (ok forms))))))]
    (match checked
      ((err e) (pair (gatewayConfigReceipt source registry "error" 0 (list e) (list) "") 1))
      ((ok forms)
        (if (!= (listLength forms) 1)
          (pair (gatewayConfigReceipt source registry "error" 0
                    (list (str "expected one (:gateway ...) form, found " (stringFromInt64 (listLength forms)))) (list) "") 1)
          (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
            (match (asnProps top (some ":gateway"))
              ((err e)
                (let [(message (if (isStringLiteral? top)
                                 (str "expected (:gateway ...), found '" (stripQuotesAndUnescape (sexprRawText top)) "'")
                                 e))]
                  (pair (gatewayConfigReceipt source registry "error" 0 (list message) (list) "") 1)))
              ((ok g)
                (let [(version (match (mapGet g "v")
                                ((none) 1)
                                ((some value)
                                  (match (asnScalar value)
                                    ((scalarInt n) n)
                                    (_ 1)))))]
                  (if (!= version 2)
                    (match (gatewayProfilesParse text)
                      ((err e) (pair (gatewayConfigReceipt source registry "error" 1 (list e) (list) "") 1))
                      ((ok parsed)
                        (pair
                          (gatewayConfigReceipt source registry "ok" 1 (list) (list)
                            (str " :profiles " (stringFromInt64 (listLength (mapKeys parsed.profiles)))))
                          0)))
                    (let [(built (gatewayConfigV2Build! g source registry))
                          (table (pairFirst built))
                          (goneErrs (filter (fn [(w String)] -> Bool (stringStartsWith? w (goneTag))) table.warnings))
                          (liveWarns (filter (fn [(w String)] -> Bool (not (stringStartsWith? w (goneTag)))) table.warnings))
                          (errors0 (listAppend (pairSecond built) goneErrs))
                          (errors (listAppend (if (listEmpty? errors0) (codeRouteErrors g table) errors0) (gatewayWaitErrors g)))
                          (warnings (if (listEmpty? errors) (listAppend liveWarns (gatewayAnyOnlyIntents table)) liveWarns))
                          (extra (str " :profiles " (stringFromInt64 (listLength (mapKeys table.profiles)))
                                      " :models " (stringFromInt64 (listLength (mapKeys table.models)))
                                      " :uses " (stringFromInt64 (listLength (mapKeys table.uses)))))
                          (status (if (listEmpty? errors) "ok" "error"))]
                      (pair (gatewayConfigReceipt source registry status 2 errors warnings extra)
                            (if (listEmpty? errors) 0 1))))))))))))
