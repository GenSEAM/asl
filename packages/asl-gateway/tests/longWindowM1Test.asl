(module asl-gateway/tests/longWindowM1Test
  :x [runTests]
  :i [(config :a c)
      (usageLedger :a ul)
      (limits :a lim)])

; (:m :ref GW-LIMIT-LONG-WINDOW :do "M1 handoff: the config check refuses :pace remaining on a window that cannot pace (hour, rollingDay) with exactly one error, and a rollingDay row at exactly 24 h, the window end, is outside the trailing window")

fn nowMs -> Int64
  1793300400000

fn row at: Int64 provider: String alias: String outcome: String -> ul/CallRow
  (ul/CallRow :atMs at :profile "" :intent "" :alias alias :provider provider :model alias
              :inTokens 10 :cachedTokens 0 :outTokens 10 :reasoningTokens 0 :ttftMs none :ms none
              :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none
              :effort none :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn okAt at: Int64 -> ul/CallRow
  (row at "nim" "a1" "ok")

fn okRows n: Int64 from: Int64 -> (List ul/CallRow)
  (map (fn [(i Int64)] -> ul/CallRow (okAt (- from (* i 60000)))) (range 0 n))

fn capped window: String calls: Int64 tokens: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "nim" :scope "account" :model "" :window window :calls calls :tokens tokens)

fn verdict ls: (List c/GatewayLimit) rows: (List ul/CallRow) days: (List ul/DayRow) at: Int64 -> String
  (match (lim/decideWith (c/emptyLimitScope) ls rows days "nim" "a1" at) ((some v) v.outcome) ((none) "none"))

fn ! checked limits: String extra: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)) :limits (" limits "))\n") "src" ".asl/mem/calibration/index.asn")

fn ! refusedOnce limits: String extra: String name: String -> Bool
  (let [(r (checked limits extra))]
    (and (= (pairSecond r) 1) (stringContains? (pairFirst r) name)))

fn paceChecks! -> Bool
  (do
    (assert (refusedOnce "(:limit :provider fp :window hour :calls 10 :pace remaining)" "" "pace") "config check refuses :pace remaining on an hour window with exactly one error")
    (assert (refusedOnce "(:limit :provider fp :window rollingDay :calls 10 :pace remaining)" "" "pace") "config check refuses :pace remaining on rollingDay with exactly one error")
    (assert (= (pairSecond (checked "(:limit :provider fp :window day :calls 10 :pace remaining)" "")) 0) "the same :pace remaining on a day window checks clean")
    true)

fn rollingEdgeChecks -> Bool
  (let [(hour 3600000)
        (clock (nowMs))
        (edge (listAppend (okRows 2 (- clock 60000)) (list (okAt (- clock (* 24 hour))))))
        (inside (listAppend (okRows 2 (- clock 60000)) (list (okAt (+ (- clock (* 24 hour)) 1)))))]
    (do
      (assert (= (verdict (list (capped "rollingDay" 3 0)) edge (list) clock) "none") "a call at exactly 24 h is outside the trailing window: 2 of 3 counted")
      (assert (= (verdict (list (capped "rollingDay" 3 0)) inside (list) clock) "limit:rollingDay") "a call 1 ms inside the trailing window counts: 3 of 3")
      true))

fn ! runTests -> Bool
  (and (paceChecks!) (rollingEdgeChecks))
