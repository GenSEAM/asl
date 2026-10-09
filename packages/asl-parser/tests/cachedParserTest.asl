(module asl-parser/tests/cachedParserTest
  :x [testCachedParserHashAndSymbol testCachedParserIncrementalParsing testCachedParserHitAndTelemetry testCachedParserEvictionAndClear runTests RunTests]
  :i [(cachedParser :a cp) (reader :a rd)])

fn testCachedParserHashAndSymbol -> Bool
  (let [(code "(fn add [x Int] -> Int x)")
        (h (cp/computeFormHash code))
        (symPair (cp/extractFormSymbol code))
        (k (pairFirst symPair))
        (n (pairSecond symPair))]
    (assert (stringStartsWith? h "cas-") "Form hash must start with cas- prefix")
    (assert (= k "fn") "Extracted kind must be fn")
    (assert (= n "add") "Extracted name must be add")
    true)

fn testCachedParserIncrementalParsing -> Bool
  (let [(cache (cp/newAstCache))
        (code "(fn foo [] a)\n(fn bar [] b)")
        (res (cp/parseIncrementalWithTelemetry cache code))
        (telemetry (pairFirst res))
        (nextCache (pairSecond res))
        (stats (cp/getCacheStats nextCache))]
    (assert (= telemetry.totalForms 2) "Total forms must be 2")
    (assert (= telemetry.hits 0) "First run hits must be 0")
    (assert (= telemetry.misses 2) "First run misses must be 2")
    (assert (= telemetry.cacheHitRate 0.0) "Hit rate must be 0.0")
    (assert (stringContains? stats ":entries 2") "Cache stats must report 2 entries")
    (assert (stringContains? stats ":misses 2") "Cache stats must report 2 misses")
    true)

fn testCachedParserHitAndTelemetry -> Bool
  (let [(cache0 (cp/newAstCache))
        (res1 (cp/parseIncrementalWithTelemetry cache0 "(fn foo [] a)\n(fn bar [] b)"))
        (cache1 (pairSecond res1))
        (res2 (cp/parseIncrementalWithTelemetry cache1 "(fn foo [] a)\n(fn baz [] c)"))
        (telemetry (pairFirst res2))
        (cache2 (pairSecond res2))
        (stats (cp/getCacheStats cache2))]
    (assert (= telemetry.totalForms 2) "Second run total forms must be 2")
    (assert (= telemetry.hits 1) "foo must be a cache hit")
    (assert (= telemetry.misses 1) "baz must be a cache miss")
    (assert (= telemetry.cacheHitRate 0.5) "Hit rate must be 0.5")
    (assert (stringContains? stats ":hits 1") "Cache stats must report 1 hit")
    (assert (stringContains? stats ":misses 3") "Cumulative misses must be 3")
    (assert (stringContains? stats ":entries 3") "Total cached entries must be 3")
    true)

fn testCachedParserEvictionAndClear -> Bool
  (let [(cache0 (cp/newAstCache))
        (res (cp/parseIncrementalWithTelemetry cache0 "(fn foo [] a)"))
        (cache1 (pairSecond res))
        (cleared (cp/clearCache cache1))
        (clearedStats (cp/getCacheStats cleared))
        (boundedCache (cp/newBoundedAstCache 20))
        (resBounded1 (cp/parseIncrementalWithTelemetry boundedCache "(fn veryLongFunctionNameOne [] a)"))
        (resBounded2 (cp/parseIncrementalWithTelemetry (pairSecond resBounded1) "(fn veryLongFunctionNameTwo [] b)"))
        (boundedStats (cp/getCacheStats (pairSecond resBounded2)))]
    (assert (stringContains? clearedStats ":entries 0") "Cleared cache entries must be 0")
    (assert (stringContains? boundedStats ":entries 1 :hits 0 :misses 2 :evictions 1 :bytes") "Bounded cache of 20 bytes must evict the first entry when the second arrives")
    true)

fn testCachedParserNoArrowFnDropsSentinel -> Bool
  (let [(cache (cp/newAstCache))
        (code "fn f x: Int64\n  (+ x 1)")
        (res (cp/parseCachedForm code cache))
        (entry (pairFirst res))
        (rendered (rd/renderSexpr entry.ast))]
    (do
      (assert (not (stringContains? rendered ":inferredUnit"))
              (str "cached no-arrow fn AST must not leak the :inferredUnit sentinel: " rendered))
      (assert (= rendered "(fn f [(x Int64)] (+ x 1))")
              (str "no-arrow fn header round-trips with no arrow at all: " rendered))
      true))

fn testCachedParserArrowedFnBodyNotCorrupted -> Bool
  (let [(cache (cp/newAstCache))
        (code "fn f x: Int64 -> Int64\n  (-> x)\n  (:inferredUnit 1)")
        (res (cp/parseCachedForm code cache))
        (entry (pairFirst res))
        (rendered (rd/renderSexpr entry.ast))]
    (do
      (assert (= rendered "(fn f [(x Int64)] -> Int64 (-> x) (:inferredUnit 1))")
              (str "both body forms, shaped like the sentinel pair, survive untouched: " rendered))
      true))

fn testCachedParserParenFnWithNoArrowKeepsListShapedBody -> Bool
  (let [(cache (cp/newAstCache))
        (code "(fn f [(x Int64)] (-> x) (:inferredUnit 1))")
        (res (cp/parseCachedForm code cache))
        (entry (pairFirst res))
        (rendered (rd/renderSexpr entry.ast))]
    (do
      (assert (= rendered "(fn f (list (x Int64)) (-> x) (:inferredUnit 1))")
              (str "both body forms, list-shaped like the sentinel pair, survive untouched: " rendered))
      true))

fn testCachedParserArrowedFnBareSentinelAtomsInBodySurvive -> Bool
  (let [(cache (cp/newAstCache))
        (code "fn f x: Int64 -> Int64\n  (+ x 1)\n  ->\n  :inferredUnit")
        (res (cp/parseCachedForm code cache))
        (entry (pairFirst res))
        (rendered (rd/renderSexpr entry.ast))]
    (do
      (assert (= rendered "(fn f [(x Int64)] -> Int64 (+ x 1) -> :inferredUnit)")
              (str "the real header and both bare body atoms survive untouched: " rendered))
      true))

fn runTests -> Bool
  (do
    (assert (testCachedParserHashAndSymbol) "testCachedParserHashAndSymbol passed")
    (assert (testCachedParserIncrementalParsing) "testCachedParserIncrementalParsing passed")
    (assert (testCachedParserHitAndTelemetry) "testCachedParserHitAndTelemetry passed")
    (assert (testCachedParserEvictionAndClear) "testCachedParserEvictionAndClear passed")
    (assert (testCachedParserNoArrowFnDropsSentinel) "testCachedParserNoArrowFnDropsSentinel passed")
    (assert (testCachedParserArrowedFnBodyNotCorrupted) "testCachedParserArrowedFnBodyNotCorrupted passed")
    (assert (testCachedParserParenFnWithNoArrowKeepsListShapedBody) "testCachedParserParenFnWithNoArrowKeepsListShapedBody passed")
    (assert (testCachedParserArrowedFnBareSentinelAtomsInBodySurvive) "testCachedParserArrowedFnBareSentinelAtomsInBodySurvive passed")
    true)

fn RunTests -> Bool
  (runTests)
