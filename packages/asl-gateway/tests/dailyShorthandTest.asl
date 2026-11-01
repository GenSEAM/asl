(module aslGateway/tests/dailyShorthandTest
  :x [runTests]
  :i [(aslGateway/config :a c)
      (aslGateway/usageLedger :a ul)
      (aslGateway/limits :a lim)])

; (:m :ref GW-DAILY-SHORTHAND :do "a provider's :dailyCalls N is the account limit row for the day window: it is in the parsed table and in the text read, it blocks the provider once N calls were sent, a missing, zero or invalid N makes no row (zero and invalid also warn), and an explicit :limits row stays beside it")
fn nowMs -> Int64
  (/ (nowNs) 1000000)

fn rowAt at: Int64 -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias "m1" :provider "fp" :model "m1"
              :inTokens 10 :cachedTokens 0 :outTokens 10 :reasoningTokens 0 :ttftMs none :ms none
              :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn sent n: Int64 -> (List ul/CallRow)
  (if (<= n 0) (list) (cons (rowAt (- (nowMs) (* n 1000))) (sent (- n 1))))

fn cfgOf pExtra: String extra: String -> String
  (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY" pExtra ")) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))")

fn ! parsed! pExtra: String extra: String -> (Result c/GatewayTable String)
  (c/gatewayConfigParse! (cfgOf pExtra extra) "default" ".asl/mem/calibration/index.asn")

fn limitsOf r: (Result c/GatewayTable String) -> (List c/GatewayLimit)
  (match r ((ok t) t.limits) ((err _) (list)))

fn warnsDaily r: (Result c/GatewayTable String) -> Bool
  (match r ((ok t) (listAny? (fn [(w String)] -> Bool (stringContains? w "dailyCalls")) t.warnings)) ((err _) false))

fn scope -> c/LimitScope
  (c/LimitScope :groups (list) :bases (list (pair "fp" "http://127.0.0.1:1")) :prices (list))

fn verdict ls: (List c/GatewayLimit) rows: (List ul/CallRow) -> String
  (match (lim/decideIn (scope) ls rows "fp" "m1" (nowMs)) ((some v) v.outcome) ((none) "none"))

fn ! runTests -> Bool
  (let [(five (parsed! " :dailyCalls 5" ""))
        (fiveLimits (limitsOf five))
        (row (optionOr (listHead fiveLimits) (c/GatewayLimit :provider "" :scope "" :model "" :window "" :calls -1 :tokens 0)))
        (viaText (c/gatewayLimitsFromText (cfgOf " :dailyCalls 5" "")))
        (none (parsed! "" ""))
        (zero (parsed! " :dailyCalls 0" ""))
        (neg (parsed! " :dailyCalls -3" ""))
        (both (parsed! " :dailyCalls 5" " :limits ((:limit :provider fp :scope account :window hour :calls 2))"))]
    (do
      (assert (= (listLength fiveLimits) 1) (str "one shorthand row in the table: " (stringFromInt64 (listLength fiveLimits))))
      (assert (and (= row.provider "fp") (= row.scope "account") (= row.window "day") (= row.calls 5)) "it is the account day row of the provider with the calls")
      (assert (= (listLength viaText) 1) "the text read the server uses sees it too")
      (assert (= (verdict fiveLimits (sent 4)) "none") "four of five calls leave the provider open")
      (assert (= (verdict fiveLimits (sent 5)) "limit:day") (str "the fifth call spends it: " (verdict fiveLimits (sent 5))))
      (assert (and (listEmpty? (limitsOf none)) (not (warnsDaily none))) "without :dailyCalls no row and no warning")
      (assert (and (listEmpty? (limitsOf zero)) (warnsDaily zero)) "zero makes no row and warns")
      (assert (and (listEmpty? (limitsOf neg)) (warnsDaily neg)) "a negative number makes no row and warns")
      (assert (= (listLength (limitsOf both)) 2) "an explicit :limits row stays beside the shorthand")
      true))
