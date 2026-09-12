(module asl-bench/launch-stability
  :d "Launch prefix stability measurement, provider cache use, and token budget tracking."
  :x [PrefixRecord ModelPricing CacheReceipt
      make-prefix-record compare-prefix-stability
      make-model-pricing compute-cache-receipt
      estimate-session-cost is-cache-eligible?]
  :i [])

(dfs PrefixRecord
  (:f prefix Str "Prompt prefix text")
  (:f byte-count I64 "Length of prefix in bytes")
  (:f token-count I64 "Estimated or tokenizer count of prefix tokens"))

(dfs ModelPricing
  (:f prompt-rate Float "Dollars per million uncached prompt tokens")
  (:f cached-rate Float "Dollars per million cached prompt tokens")
  (:f completion-rate Float "Dollars per million completion tokens"))

(dfs CacheReceipt
  (:f provider Str "Provider or model identifier")
  (:f prompt-tokens I64 "Total prompt tokens in session")
  (:f cached-tokens I64 "Tokens served from provider prefix cache")
  (:f completion-tokens I64 "Tokens generated in completion")
  (:f hit-ratio Float "Ratio of cached tokens to total prompt tokens")
  (:f cost-usd Float "Actual computed dollar cost")
  (:f latency-ms I64 "Observed response latency in milliseconds")
  (:f has-receipt Bool "True if backed by provider receipt"))

(df make-prefix-record [(prefix Str) (tokens I64)] -> PrefixRecord
  :d "Constructs a prefix record with byte and token counts."
  (PrefixRecord
    :prefix prefix
    :byte-count (string-length prefix)
    :token-count tokens))

(df compare-prefix-stability [(r1 PrefixRecord) (r2 PrefixRecord)] -> Bool
  :d "Compares two prefix records for byte-exact and token stability."
  (and (= (.-prefix r1) (.-prefix r2))
       (and (= (.-byte-count r1) (.-byte-count r2))
            (= (.-token-count r1) (.-token-count r2)))))

(df make-model-pricing [(prompt-rate Float) (cached-rate Float) (completion-rate Float)] -> ModelPricing
  :d "Creates a model pricing specification with per-million rates."
  (ModelPricing
    :prompt-rate prompt-rate
    :cached-rate cached-rate
    :completion-rate completion-rate))

(df estimate-session-cost [(prompt-tokens I64) (cached-tokens I64) (completion-tokens I64) (pricing ModelPricing)] -> Float
  :d "Calculates explicit dollar cost based on per-million token pricing."
  (let [(uncached-prompt (- prompt-tokens cached-tokens))
        (uncached-cost (/ (* (* 1.0 uncached-prompt) (.-prompt-rate pricing)) 1000000.0))
        (cached-cost (/ (* (* 1.0 cached-tokens) (.-cached-rate pricing)) 1000000.0))
        (comp-cost (/ (* (* 1.0 completion-tokens) (.-completion-rate pricing)) 1000000.0))]
    (+ uncached-cost (+ cached-cost comp-cost))))

(df compute-cache-receipt [(provider Str) (prompt-tokens I64) (cached-tokens I64) (completion-tokens I64) (pricing ModelPricing) (latency-ms I64) (has-receipt Bool)] -> CacheReceipt
  :d "Computes a cache receipt with explicit hit ratio and cost calculation."
  (let [(hit-ratio (if (> prompt-tokens 0)
                     (/ (* 1.0 cached-tokens) (* 1.0 prompt-tokens))
                     0.0))
        (cost (estimate-session-cost prompt-tokens cached-tokens completion-tokens pricing))]
    (CacheReceipt
      :provider provider
      :prompt-tokens prompt-tokens
      :cached-tokens cached-tokens
      :completion-tokens completion-tokens
      :hit-ratio hit-ratio
      :cost-usd cost
      :latency-ms latency-ms
      :has-receipt has-receipt)))

(df is-cache-eligible? [(tokens I64) (threshold I64)] -> Bool
  :d "Determines whether prompt tokens meet provider cache eligibility threshold."
  (>= tokens threshold))
