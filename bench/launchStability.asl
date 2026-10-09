(module aslBench/launchStability :x [PrefixRecord ModelPricing CacheReceipt makePrefixRecord comparePrefixStability makeModelPricing computeCacheReceipt estimateSessionCost isCacheEligible? runTests] :i [])

(schema PrefixRecord (:f prefix Str) (:f byteCount I64) (:f tokenCount I64))

(schema ModelPricing (:f promptRate Float) (:f cachedRate Float) (:f completionRate Float))

(schema CacheReceipt (:f provider Str) (:f promptTokens I64) (:f cachedTokens I64) (:f completionTokens I64) (:f hitRatio Float) (:f costUsd Float) (:f latencyMs I64) (:f hasReceipt Bool))

fn makePrefixRecord prefix: Str tokens: I64 -> PrefixRecord
  (PrefixRecord :prefix prefix :byteCount (stringLength prefix) :tokenCount tokens)

fn comparePrefixStability r1: PrefixRecord r2: PrefixRecord -> Bool
  (and (= r1.prefix r2.prefix) (and (= r1.byteCount r2.byteCount) (= r1.tokenCount r2.tokenCount)))

fn makeModelPricing promptRate: Float cachedRate: Float completionRate: Float -> ModelPricing
  (ModelPricing :promptRate promptRate :cachedRate cachedRate :completionRate completionRate)

fn estimateSessionCost promptTokens: I64 cachedTokens: I64 completionTokens: I64 pricing: ModelPricing -> Float
  (let [(uncachedPrompt (- promptTokens cachedTokens)) (uncachedCost (/ (* (int64ToFloat64 uncachedPrompt) pricing.promptRate) 1000000.0)) (cachedCost (/ (* (int64ToFloat64 cachedTokens) pricing.cachedRate) 1000000.0)) (compCost (/ (* (int64ToFloat64 completionTokens) pricing.completionRate) 1000000.0))] (+ uncachedCost (+ cachedCost compCost)))

fn computeCacheReceipt provider: Str promptTokens: I64 cachedTokens: I64 completionTokens: I64 pricing: ModelPricing latencyMs: I64 hasReceipt: Bool -> CacheReceipt
  (let [(hitRatio (if (> promptTokens 0) (/ (int64ToFloat64 cachedTokens) (int64ToFloat64 promptTokens)) 0.0)) (cost (estimateSessionCost promptTokens cachedTokens completionTokens pricing))] (CacheReceipt :provider provider :promptTokens promptTokens :cachedTokens cachedTokens :completionTokens completionTokens :hitRatio hitRatio :costUsd cost :latencyMs latencyMs :hasReceipt hasReceipt))

fn isCacheEligible? tokens: I64 threshold: I64 -> Bool
  (>= tokens threshold)

fn runTests -> Bool
  (let [(p1 (makePrefixRecord "prefix-one" 10))
        (p2 (makePrefixRecord "prefix-one" 10))
        (p3 (makePrefixRecord "prefix-two" 12))
        (pricing (makeModelPricing 3.0 0.30 15.0))]
    (do
      (assert (comparePrefixStability p1 p2) "identical prefix records are stable")
      (refute (comparePrefixStability p1 p3) "differing prefix records are not stable")
      (assert (isCacheEligible? 1024 1024) "exact threshold is eligible")
      (assert (isCacheEligible? 2048 1024) "above threshold is eligible")
      (refute (isCacheEligible? 512 1024) "below threshold is not eligible")
      (let [(cost (estimateSessionCost 1000 500 200 pricing))]
        (assert (> cost 0.0) "session cost is positive"))
      (let [(receipt (computeCacheReceipt "provider-a" 1000 500 200 pricing 120 true))]
        (assert (= receipt.hitRatio 0.5) "hit ratio is 50 percent"))
      true))
