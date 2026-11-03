(module aslGateway/tests/limitScopeFnsTest
  :x [runTests]
  :i [(config :a c)
      (usageLedger :a ul)
      (limits :a lim)])

; (:m :ref COVERAGE-RATCHET-RED :do "direct cases for the scope-aware limit functions: coversIn and covers? decide membership of a call in a limit row (account, model, group, endpoint; an empty scope resolves no group or endpoint), usedCallsIn usedTokensIn usedUsdIn spentRatioIn count only sent rows inside the window and the scope, limitKey names the row")
fn nowMs -> Int64
  1793300400000

fn rowAt at: Int64 provider: String alias: String inTok: Int64 outTok: Int64 outcome: String -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias alias :provider provider :model alias
              :inTokens inTok :cachedTokens 0 :outTokens outTok :reasoningTokens 0 :ttftMs none :ms none
              :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn sent provider: String alias: String -> ul/CallRow
  (rowAt (- (nowMs) 10000) provider alias 10 20 "ok")

fn scope -> c/LimitScope
  (c/LimitScope :groups (list (c/GatewayGroup :id "G" :provider "nim" :models (list "a1" "a2")))
                :bases (list (pair "nim" "http://x") (pair "groq" "http://x") (pair "other" "http://y"))
                :prices (list (pair "a1" (pair 1.0 2.0))))

fn limitOf scopeName: String provider: String model: String group: String endpoint: String -> c/GatewayLimit
  (c/GatewayLimit :provider provider :scope scopeName :model model :window "hour" :calls 4 :tokens 0 :group group :endpoint endpoint)

fn account -> c/GatewayLimit
  (limitOf "account" "nim" "" "" "")

fn modelA1 -> c/GatewayLimit
  (limitOf "model" "nim" "a1" "" "")

fn groupG -> c/GatewayLimit
  (limitOf "group" "" "" "G" "")

fn endpointX -> c/GatewayLimit
  (limitOf "endpoint" "" "" "" "http://x")

fn rows -> (List ul/CallRow)
  (list (sent "nim" "a1") (sent "nim" "a1") (sent "nim" "a1") (sent "nim" "a2") (sent "nim" "a2") (sent "groq" "g1")
        (rowAt (- (nowMs) 7200000) "nim" "a1" 10 20 "ok")
        (rowAt (- (nowMs) 5000) "nim" "a1" 10 20 "breakerOpen")
        (rowAt (- (nowMs) 5000) "nim" "a1" 10 20 "limit:hour"))

fn testKey -> Bool
  (do (assert (= (lim/limitKey (account)) "account|nim|||") "an account row is keyed by scope and provider")
      (assert (= (lim/limitKey (modelA1)) "model|nim|a1||") "a model row adds the alias")
      (assert (= (lim/limitKey (groupG)) "group|||G|") "a group row names the group")
      (assert (= (lim/limitKey (endpointX)) "endpoint||||http://x") "an endpoint row names the base")
      (assert (not (= (lim/limitKey (account)) (lim/limitKey (modelA1)))) "different rows have different keys")
      true)

fn testCovers -> Bool
  (do (assert (lim/covers? (account) "nim" "a1") "an account row covers every alias of its provider")
      (assert (lim/covers? (account) "nim" "zzz") "an account row covers an alias it has not seen")
      (assert (not (lim/covers? (account) "groq" "a1")) "an account row does not cover another provider")
      (assert (lim/covers? (modelA1) "nim" "a1") "a model row covers its alias")
      (assert (not (lim/covers? (modelA1) "nim" "a2")) "a model row does not cover a sibling alias")
      (assert (not (lim/covers? (modelA1) "groq" "a1")) "a model row does not cover the same alias of another provider")
      (assert (not (lim/covers? (groupG) "nim" "a1")) "an empty scope resolves no group")
      (assert (not (lim/covers? (endpointX) "nim" "a1")) "an empty scope resolves no endpoint")
      (assert (lim/coversIn (scope) (groupG) "nim" "a1") "a group row covers a listed member")
      (assert (lim/coversIn (scope) (groupG) "nim" "a2") "a group row covers every listed member")
      (assert (not (lim/coversIn (scope) (groupG) "nim" "a3")) "a group row does not cover an unlisted alias")
      (assert (not (lim/coversIn (scope) (groupG) "groq" "a1")) "a group row is bound to its provider")
      (assert (lim/coversIn (scope) (endpointX) "nim" "a1") "an endpoint row covers a provider on that base")
      (assert (lim/coversIn (scope) (endpointX) "groq" "g1") "an endpoint row spans the providers sharing the base")
      (assert (not (lim/coversIn (scope) (endpointX) "other" "o1")) "an endpoint row does not cover a provider on another base")
      (assert (not (lim/coversIn (scope) (endpointX) "unknown" "u1")) "a provider with no base is outside every endpoint row")
      (assert (not (lim/coversIn (scope) (limitOf "planet" "nim" "" "" "") "nim" "a1")) "an unknown scope covers nothing")
      true)

fn testUsed -> Bool
  (let [(now (nowMs))]
    (do (assert (= (lim/usedCallsIn (scope) (account) (rows) now) 5) "an account window counts the sent rows of the provider, not the old, breaker or limit rows")
        (assert (= (lim/usedCallsIn (scope) (modelA1) (rows) now) 3) "a model window counts that alias only")
        (assert (= (lim/usedCallsIn (scope) (groupG) (rows) now) 5) "a group window counts every member")
        (assert (= (lim/usedCallsIn (scope) (endpointX) (rows) now) 6) "an endpoint window counts every provider on the base")
        (assert (= (lim/usedCallsIn (scope) (account) (list) now) 0) "no rows is no use")
        (assert (= (lim/usedTokensIn (scope) (account) (rows) now) 150) "tokens are input plus output of the counted rows")
        (assert (= (lim/usedTokensIn (scope) (modelA1) (rows) now) 90) "a model window sums its own tokens")
        (assert (= (lim/usedTokensIn (scope) (endpointX) (rows) now) 180) "an endpoint window sums across providers")
        (let [(priced (list (rowAt (- now 1000) "nim" "a1" 1000000 500000 "ok") (rowAt (- now 1000) "nim" "a2" 1000000 500000 "ok")))]
          (do (assert (= (lim/usedUsdIn (scope) (account) priced now) 2.0) "usd prices input and output per million, an unpriced model costs nothing")
              (assert (= (lim/usedUsdIn (scope) (modelA1) priced now) 2.0) "a model window prices its alias")
              (assert (= (lim/usedUsdIn (scope) (limitOf "model" "nim" "a2" "" "") priced now) 0.0) "an unpriced alias spends no usd")
              (assert (= (lim/usedUsdIn (c/emptyLimitScope) (account) priced now) 0.0) "an empty scope has no prices")))
        true))

fn testSpent -> Bool
  (let [(now (nowMs))
        (calls4 (limitOf "account" "nim" "" "" ""))
        (usd4 (c/GatewayLimit :provider "nim" :scope "model" :model "a1" :window "hour" :calls 0 :tokens 0 :usd 4.0))
        (tokens600 (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "hour" :calls 0 :tokens 600))
        (windowless (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "" :calls 1 :tokens 0))
        (priced (list (rowAt (- now 1000) "nim" "a1" 1000000 500000 "ok")))]
    (do (assert (= (lim/spentRatioIn (scope) calls4 (rows) now) 1.25) "five calls against a cap of four is 1.25")
        (assert (= (lim/spentRatioIn (scope) tokens600 (rows) now) 0.25) "150 tokens against 600 is 0.25")
        (assert (= (lim/spentRatioIn (scope) usd4 priced now) 0.5) "two usd against four is 0.5")
        (assert (= (lim/spentRatioIn (scope) windowless (rows) now) 0.0) "a row without a window is never spent")
        (assert (= (lim/spentRatioIn (scope) calls4 (list) now) 0.0) "no rows spend nothing")
        (let [(both (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "hour" :calls 20 :tokens 600))]
          (assert (= (lim/spentRatioIn (scope) both (rows) now) 0.25) "the most spent unit decides: calls 5/20 and tokens 150/600 are both 0.25"))
        (let [(mixed (c/GatewayLimit :provider "nim" :scope "account" :model "" :window "hour" :calls 10 :tokens 200))]
          (assert (= (lim/spentRatioIn (scope) mixed (rows) now) 0.75) "calls 5/10 = 0.5 loses to tokens 150/200 = 0.75"))
        true))

fn ! runTests -> Bool
  (do (testKey) (testCovers) (testUsed) (testSpent) true)
