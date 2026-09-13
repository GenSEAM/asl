(module aslBench/launchStability
  :d "Launch prefix stability measurement, provider cache use, and token budget tracking."
  :x [PrefixRecord ModelPricing CacheReceipt
      makePrefixRecord comparePrefixStability
      makeModelPricing computeCacheReceipt
      estimateSessionCost isCacheEligible?]
  :i [])

(dfs PrefixRecord
  (:f prefix Str "Prompt prefix text")
  (:f byteCount I64 "Length of prefix in bytes")
  (:f tokenCount I64 "Estimated or tokenizer count of prefix tokens"))

(dfs ModelPricing
  (:f promptRate Float "Dollars per million uncached prompt tokens")
  (:f cachedRate Float "Dollars per million cached prompt tokens")
  (:f completionRate Float "Dollars per million completion tokens"))

(dfs CacheReceipt
  (:f provider Str "Provider or model identifier")
  (:f promptTokens I64 "Total prompt tokens in session")
  (:f cachedTokens I64 "Tokens served from provider prefix cache")
  (:f completionTokens I64 "Tokens generated in completion")
  (:f hitRatio Float "Ratio of cached tokens to total prompt tokens")
  (:f costUsd Float "Actual computed dollar cost")
  (:f latencyMs I64 "Observed response latency in milliseconds")
  (:f hasReceipt Bool "True if backed by provider receipt"))

(df makePrefixRecord [(prefix Str) (tokens I64)] -> PrefixRecord
  :d "Constructs a prefix record with byte and token counts."
  (PrefixRecord
    :prefix prefix
    :byteCount (string-length prefix)
    :tokenCount tokens))

(df comparePrefixStability [(r1 PrefixRecord) (r2 PrefixRecord)] -> Bool
  :d "Compares two prefix records for byte-exact and token stability."
  (and (= (.-prefix r1) (.-prefix r2))
       (and (= (.-byteCount r1) (.-byteCount r2))
            (= (.-tokenCount r1) (.-tokenCount r2)))))

(df makeModelPricing [(promptRate Float) (cachedRate Float) (completionRate Float)] -> ModelPricing
  :d "Creates a model pricing specification with per-million rates."
  (ModelPricing
    :promptRate promptRate
    :cachedRate cachedRate
    :completionRate completionRate))

(df estimateSessionCost [(promptTokens I64) (cachedTokens I64) (completionTokens I64) (pricing ModelPricing)] -> Float
  :d "Calculates explicit dollar cost based on per-million token pricing."
  (let [(uncachedPrompt (- promptTokens cachedTokens))
        (uncachedCost (/ (* (* 1.0 uncachedPrompt) (.-promptRate pricing)) 1000000.0))
        (cachedCost (/ (* (* 1.0 cachedTokens) (.-cachedRate pricing)) 1000000.0))
        (compCost (/ (* (* 1.0 completionTokens) (.-completionRate pricing)) 1000000.0))]
    (+ uncachedCost (+ cachedCost compCost))))

(df computeCacheReceipt [(provider Str) (promptTokens I64) (cachedTokens I64) (completionTokens I64) (pricing ModelPricing) (latencyMs I64) (hasReceipt Bool)] -> CacheReceipt
  :d "Computes a cache receipt with explicit hit ratio and cost calculation."
  (let [(hitRatio (if (> promptTokens 0)
                     (/ (* 1.0 cachedTokens) (* 1.0 promptTokens))
                     0.0))
        (cost (estimateSessionCost promptTokens cachedTokens completionTokens pricing))]
    (CacheReceipt
      :provider provider
      :promptTokens promptTokens
      :cachedTokens cachedTokens
      :completionTokens completionTokens
      :hitRatio hitRatio
      :costUsd cost
      :latencyMs latencyMs
      :hasReceipt hasReceipt)))

(df isCacheEligible? [(tokens I64) (threshold I64)] -> Bool
  :d "Determines whether prompt tokens meet provider cache eligibility threshold."
  (>= tokens threshold))
