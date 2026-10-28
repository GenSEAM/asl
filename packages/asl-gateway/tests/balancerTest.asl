(module aslGateway/tests/balancerTest
  :x [runTests]
  :i [(aslGateway/balancer :a bl)
      (aslGateway/usageLedger :a ul)
      (aslGateway/config :a c)
      (asl-parser/reader :a rd)])

fn dayMs -> Int64 86400000

fn fiveHMs -> Int64 18000000

fn budget id: String window: Int64 unit: String size: Int64 soft: Int64 useOrLose: Bool -> bl/Budget
  (bl/Budget :id id :windowMs window :anchorMs 0 :headerWindowMs 0 :unit unit :size size :softPct soft :hardPct 100 :useOrLose useOrLose :source "declared")

fn model id: String tier: bl/Tier budgets: (List String) cost: Int64 -> bl/PoolModel
  (bl/PoolModel :id id :provider id :tier tier :why "fixture" :budgets budgets :costMicros cost :declaredQuality (none))

fn cal id: String pass: Int64 total: Int64 -> bl/CalScore
  (bl/CalScore :model id :intent "any" :pass pass :total total :source "cal:fixture")

fn dayBudgets -> (List bl/Budget)
  (list (budget "orDay" (dayMs) "req" 160 90 true)
        (budget "groqDay" (dayMs) "req" 160 90 true)
        (budget "claude5h" (fiveHMs) "req" 40 80 true)
        (budget "codexWeek" (* 7 (dayMs)) "req" 1400 80 true)
        (budget "paidDay" (dayMs) "usd" 400000 80 false)
        (budget "newDay" (dayMs) "req" 100 90 true))

fn dayModels -> (List bl/PoolModel)
  (list (model "orQwen" (bl/tierFree) (list "orDay") 0)
        (model "groqLlama" (bl/tierFree) (list "groqDay") 0)
        (model "claudeOpus" (bl/tierSub) (list "claude5h") 0)
        (model "codexAstra" (bl/tierSub) (list "codexWeek") 0)
        (model "dsFlash" (bl/tierPaid) (list "paidDay") 2000)
        (model "newFree" (bl/tierFree) (list "newDay") 0))

fn dayCals -> (List bl/CalScore)
  (list (cal "orQwen" 8 10) (cal "groqLlama" 7 10) (cal "claudeOpus" 9 10) (cal "codexAstra" 8 10) (cal "dsFlash" 8 10))

fn dayBalancer mode: bl/Mode -> bl/Balancer
  (bl/makeBalancer (dayModels) (dayBudgets) (dayCals) (bl/Policy :mode mode :exploreEvery 20 :softFactor 100))

fn requests n: Int64 spanMs: Int64 -> (List bl/Request)
  (map (fn [(i Int64)] -> bl/Request
         (bl/Request :seq (+ i 1) :atMs (+ (/ (* i spanMs) n) (/ spanMs (* 2 n))) :intent "code" :tokens 1000))
       (range 0 n))

fn pickedId p: bl/Pick -> String
  (match p
    ((bl/picked m _ _ _) m)
    ((bl/refused _) ""))

fn countModel r: bl/Replay id: String -> Int64
  (listLength (filter (fn [(p bl/Pick)] -> Bool (= (pickedId p) id)) r.picks))

fn countRefused r: bl/Replay -> Int64
  (countModel r "")

fn countTier r: bl/Replay bal: bl/Balancer tier: String -> Int64
  (listLength (filter (fn [(p bl/Pick)] -> Bool
                        (listAny? (fn [(m bl/PoolModel)] -> Bool (and (= m.id (pickedId p)) (= (bl/tierName m.tier) tier))) bal.models))
                      r.picks))

fn percentOf used: Int64 capacity: Int64 -> Int64
  (/ (* 100 used) (max 1 capacity))

; (:m :do "day capacity of each use-or-lose pool: daily quotas whole, claude 40 per 5h over 24h is 192, codex 1400 per week pro-rata is 200, demand 720 is 88 percent of the 812 they hold together")
fn poolShares r: bl/Replay -> (List Int64)
  (list (percentOf (countModel r "orQwen") 160)
        (percentOf (countModel r "groqLlama") 160)
        (percentOf (countModel r "claudeOpus") 192)
        (percentOf (countModel r "codexAstra") 200)
        (percentOf (countModel r "newFree") 100))

; (:m :do "walks the day request by request and records whether any use-or-lose quota reached its hard cap before three quarters of its window had passed")
fn exhaustedEarly? bal: bl/Balancer reqs: (List bl/Request) -> Bool
  (let [(st (fold (fn [(acc (Pair (Map String bl/Window) Bool)) (req bl/Request)] -> (Pair (Map String bl/Window) Bool)
                    (let [(use (pairFirst acc))
                          (use2 (match (bl/pick bal use req) ((bl/picked id _ _ _) (bl/chargeUse bal use id req.atMs req.tokens)) ((bl/refused _) use)))
                          (early (listAny? (fn [(b bl/Budget)] -> Bool
                                             (and b.useOrLose
                                                  (>= (bl/budgetUsed use2 b req.atMs) (bl/hardCap b))
                                                  (< (* 4 (- req.atMs (bl/windowStart b req.atMs))) (* 3 b.windowMs))))
                                           (mapValues bal.budgets)))]
                      (pair use2 (or (pairSecond acc) early))))
                  (pair (bl/emptyUse) false)
                  reqs))]
    (pairSecond st))

fn testDayBalanced -> Bool
  (let [(bal (dayBalancer (bl/modeBalanced)))
        (reqs (requests 720 (dayMs)))
        (r (bl/replay bal (bl/emptyUse) reqs))
        (shares (poolShares r))
        (mean (/ (* 100 720) 812))]
    (do
      (assert (= (countRefused r) 0) "balanced day serves every request while quotas have room")
      (assert (= r.overHard 0) "no budget passes its hard cap at any step of the day")
      (assert (= (countModel r "dsFlash") 0) "paid stays idle while free and subscription quotas still have room")
      (assert (listAll? (fn [(s Int64)] -> Bool (and (>= s (- mean 12)) (<= s (+ mean 12)))) shares) (str "each use-or-lose pool lands within 12 points of the 88 percent mean: " (stringJoin (map (fn [(s Int64)] -> String (str s)) shares) " ")))
      (assert (>= (countModel r "orQwen") 144) "openrouter daily free quota is at least 90 percent used by its reset")
      (assert (>= (countModel r "groqLlama") 144) "groq daily free quota is at least 90 percent used by its reset")
      (assert (not (exhaustedEarly? bal reqs)) "pacing keeps every subscription and free quota from running dry before three quarters of its window")
      true))

fn testOverloadUsesPaidUnderCap -> Bool
  (let [(bal (dayBalancer (bl/modeBalanced)))
        (r (bl/replay bal (bl/emptyUse) (requests 1100 (dayMs))))
        (paid (countModel r "dsFlash"))]
    (do
      (assert (> paid 0) "when demand passes the free and subscription quotas, paid takes the overflow")
      (assert (<= (* paid 2000) 400000) "paid spend stays within its daily usd hard cap")
      (assert (= r.overHard 0) "overload passes no hard cap")
      true))

fn twoFree softA: Int64 -> bl/Balancer
  (bl/makeBalancer (list (model "a" (bl/tierFree) (list "aDay") 0) (model "b" (bl/tierFree) (list "bDay") 0))
                   (list (budget "aDay" (dayMs) "req" 100 softA false) (budget "bDay" (dayMs) "req" 100 100 false))
                   (list (cal "a" 9 10) (cal "b" 7 10))
                   (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100))

fn testSoftShifts -> Bool
  (let [(half (/ (dayMs) 2))
        (req (bl/Request :seq 1 :atMs half :intent "code" :tokens 10))
        (soft (twoFree 40))
        (loose (twoFree 100))
        (useA (bl/chargeUse loose (bl/emptyUse) "a" half 10))
        (use40 (fold (fn [(u (Map String bl/Window)) (i Int64)] -> (Map String bl/Window) (bl/chargeUse loose u "a" half 10)) (bl/emptyUse) (range 0 40)))
        (rSoft (bl/replay soft (bl/emptyUse) (requests 150 (dayMs))))
        (rLoose (bl/replay loose (bl/emptyUse) (requests 150 (dayMs))))]
    (do
      (assert (= (pickedId (bl/pick loose useA req)) "a") "below every soft line the stronger model a wins")
      (assert (= (pickedId (bl/pick loose use40 req)) "a") "at 40 of 100 with a soft line of 100, a still wins")
      (assert (= (pickedId (bl/pick soft use40 req)) "b") "at its 40 percent soft line a sheds the request to b")
      (assert (< (countModel rSoft "a") (countModel rLoose "a")) (str "over a day the soft line moves traffic off a: " (countModel rSoft "a") " vs " (countModel rLoose "a")))
      (assert (= (+ (countModel rSoft "a") (countModel rSoft "b")) 150) "shifted traffic is served, not dropped")
      true))

fn testHardRefuses -> Bool
  (let [(bal (dayBalancer (bl/modeFree)))
        (req (bl/Request :seq 1 :atMs 1000 :intent "code" :tokens 10))
        (full (fold (fn [(u (Map String bl/Window)) (i Int64)] -> (Map String bl/Window) (bl/chargeUse bal u "orQwen" 500 10)) (bl/emptyUse) (range 0 160)))
        (r (bl/replay bal (bl/emptyUse) (requests 720 (dayMs))))
        (last (bl/pick bal r.use (bl/Request :seq 2 :atMs (- (dayMs) 1) :intent "code" :tokens 10)))]
    (do
      (assert (!= (pickedId (bl/pick bal full req)) "orQwen") "a model at its hard cap is never picked")
      (assert (!= (pickedId (bl/pick bal full req)) "") "another free model serves while one is at its hard cap")
      (assert (= (countRefused r) (- 720 420)) "free mode serves exactly the 420 free requests of the day and refuses the rest")
      (assert (= r.overHard 0) "refusal keeps every budget at or under its hard cap")
      (assert (match last ((bl/refused why) (stringContains? why "hard cap")) (_ false)) "with every free quota spent the pick is a refusal that names the hard cap")
      true))

fn testModesFilter -> Bool
  (let [(reqs (requests 720 (dayMs)))
        (freeBal (dayBalancer (bl/modeFree)))
        (subBal (dayBalancer (bl/modeSub)))
        (paidBal (dayBalancer (bl/modePaid)))
        (rFree (bl/replay freeBal (bl/emptyUse) reqs))
        (rSub (bl/replay subBal (bl/emptyUse) reqs))
        (rPaid (bl/replay paidBal (bl/emptyUse) reqs))
        (exploreBal (dayBalancer (bl/modeExplore)))
        (lonePaid (bl/makeBalancer (list (model "x" (bl/tierPaid) (list) 0)) (list) (list) (bl/Policy :mode (bl/modeFree) :exploreEvery 0 :softFactor 100)))]
    (do
      (assert (= (countTier rFree freeBal "free") 420) "free mode routes only free models")
      (assert (= (+ (countTier rFree freeBal "sub") (countTier rFree freeBal "paid")) 0) "free mode routes zero sub or paid calls")
      (assert (> (countTier rSub subBal "sub") 0) "sub mode routes subscription models")
      (assert (= (+ (countTier rSub subBal "free") (countTier rSub subBal "paid")) 0) "sub mode routes zero free or paid calls")
      (assert (= (countModel rPaid "dsFlash") 200) "paid mode routes only paid until the 400000 microusd daily cap")
      (assert (= (+ (countTier rPaid paidBal "free") (countTier rPaid paidBal "sub")) 0) "paid mode routes zero free or sub calls")
      (assert (= (pickedId (bl/pick exploreBal (bl/emptyUse) (bl/Request :seq 1 :atMs 1000 :intent "code" :tokens 10))) "newFree") "explore mode prefers the least calibrated model")
      (assert (match (bl/pick lonePaid (bl/emptyUse) (bl/Request :seq 1 :atMs 1 :intent "code" :tokens 1)) ((bl/refused why) (stringContains? why "admits no model")) (_ false)) "a mode with no admitted model refuses and says so")
      true))

fn testUncalibratedRoutable -> Bool
  (let [(bal (dayBalancer (bl/modeBalanced)))
        (newM (model "newFree" (bl/tierFree) (list "newDay") 0))
        (orM (model "orQwen" (bl/tierFree) (list "orDay") 0))
        (qNew (bl/qualityFor bal newM "code"))
        (qOr (bl/qualityFor bal orM "code"))
        (declared (bl/qualityFor bal (bl/PoolModel :id "d" :provider "p" :tier (bl/tierPaid) :why "" :budgets (list) :costMicros 0 :declaredQuality (some 700)) "code"))
        (r (bl/replay bal (bl/emptyUse) (requests 720 (dayMs))))
        (alone (bl/makeBalancer (list newM) (dayBudgets) (list) (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100)))]
    (do
      (assert (= qNew.source "prior") "an uncalibrated model takes the tier prior")
      (assert (= qNew.score (bl/tierPrior (bl/tierFree))) "the prior score is the free tier prior")
      (assert (< qNew.confidence qOr.confidence) "the prior carries a lower confidence than a calibrated row")
      (assert (= qOr.source "cal:fixture") "a calibrated model names its CAL source")
      (assert (and (= declared.source "declared") (= declared.score 700) (< qNew.confidence declared.confidence) (< declared.confidence qOr.confidence)) "a declared quality sits between prior and CAL in confidence")
      (assert (> (countModel r "newFree") 0) "the uncalibrated model gets an exploration share of the day")
      (assert (< (countModel r "newFree") (countModel r "orQwen")) "its share stays below a calibrated model of the same tier")
      (assert (= (pickedId (bl/pick alone (bl/emptyUse) (bl/Request :seq 1 :atMs 1000 :intent "code" :tokens 10))) "newFree") "an uncalibrated model alone in the pool is routed, not blocked")
      true))

fn testCalReuse -> Bool
  (let [(text "(:cal :id LAGUNA1-B3 :date \"2026-10-17\" :scores ((ccMimoPro 4 5) (groqQwen 2 5 :noisy \"429\") (ocBeam 0 5 :why \"x\") (broken)))\n(:obs :at 2026-10-11 :worker w)\n(:cal :id C2 :intent code :scores ((ccMimoPro 9 10)))")
        (cals (bl/parseCalScores text))
        (bal (bl/makeBalancer (list) (list) cals (bl/defaultPolicy)))
        (mimo (model "ccMimoPro" (bl/tierFree) (list) 0))
        (qCode (bl/qualityFor bal mimo "code"))
        (qAny (bl/qualityFor bal mimo "research"))]
    (do
      (assert (= (listLength cals) 4) "saved CAL rows parse, the unreadable score row and non-cal rows are skipped")
      (assert (= qCode.source "cal:C2") "an intent-specific CAL row wins for its intent")
      (assert (= qAny.source "cal:LAGUNA1-B3 cal:C2") "without an intent row every CAL row of the model counts")
      (assert (> qCode.score qAny.score) "the stronger code row lifts the code score")
      (assert (> qAny.confidence qCode.confidence) "more runs give more confidence")
      true))

fn gatewayText balancerSection: String modelExtra: String -> String
  (str "(:gateway :v 2 :models ((:model :id orQwen :provider openrouter :name \"qwen\" :tier free :why \"bulk drafts\" :budgets (orDay)) (:model :id dsFlash :provider deepseek :name \"ds\" :costMicros 2000" modelExtra ")) :balancer " balancerSection ")")

fn testConfigParse -> Bool
  (let [(sec "(:balancer :mode free :exploreEvery 10 :budgets ((:budget :id orDay :window day :unit req :size 200 :soft 80 :useOrLose true :source header)))")
        (ok1 (bl/parseBalancer (rd/parseSexpr (gatewayText sec "")) (list)))
        (noSec (bl/parseBalancer (rd/parseSexpr "(:gateway :v 2 :models ((:model :id m :provider p :name \"n\")))") (list)))
        (badRef (bl/parseBalancer (rd/parseSexpr (gatewayText sec " :budgets (nope)")) (list)))
        (badTier (bl/parseBalancer (rd/parseSexpr (gatewayText sec " :tier gold")) (list)))
        (badWindow (bl/parseBalancer (rd/parseSexpr (gatewayText "(:balancer :budgets ((:budget :id x :window fortnight :size 1)))" "")) (list)))]
    (do
      (assert (match ok1
                ((ok b) (and (= (bl/modeName b.policy.mode) "free") (= b.policy.exploreEvery 10) (= (listLength b.models) 2)
                             (match (mapGet b.budgets "orDay") ((some x) (and (= x.size 200) (= x.softPct 80) (= x.hardPct 100) x.useOrLose (= x.windowMs (dayMs)))) ((none) false))))
                ((err _) false))
              "a balancer section and model why, tier and budgets parse from the gateway form")
      (assert (match ok1
                ((ok b) (listAny? (fn [(m bl/PoolModel)] -> Bool (and (= m.id "dsFlash") (= (bl/tierName m.tier) "paid") (= m.costMicros 2000))) b.models))
                ((err _) false))
              "a model row without a tier defaults to paid")
      (assert (match ok1 ((ok b) (listAny? (fn [(m bl/PoolModel)] -> Bool (= m.why "bulk drafts")) b.models)) ((err _) false)) "the model row keeps why it is in the pool")
      (assert (match noSec ((ok b) (= (bl/modeName b.policy.mode) "balanced")) ((err _) false)) "without a balancer section the mode is balanced")
      (assert (match badRef ((err e) (stringContains? e "unknown budget")) ((ok _) false)) "a model naming an unknown budget is a config error")
      (assert (match badTier ((err e) (stringContains? e "unknown tier")) ((ok _) false)) "an unknown tier is a config error")
      (assert (match badWindow ((err e) (stringContains? e "unknown window")) ((ok _) false)) "an unknown window is a config error")
      true))

; (:m :do "the balancer extensions ride inside a config the gateway itself loads: config.asl must accept model rows with tier why budgets and a top-level balancer section")
fn testCoexistsWithConfig -> Bool
  (let [(text "(:gateway :v 2 :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\")) :models ((:model :id m :provider test :name \"model-m\" :tier free :why \"drafts\" :budgets (mDay))) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)) :balancer (:balancer :mode sub :budgets ((:budget :id mDay :window day :size 10))))")
        (table (c/gatewayProfilesLoadText! "/test" true (ok text) ""))
        (bal (bl/parseBalancer (rd/parseSexpr text) (list)))]
    (do
      (assert (match table ((ok t) (mapHas? t.models "m")) ((err _) false)) (str "config.asl loads a gateway file that carries balancer extensions: " (match table ((err e) e) ((ok _) "ok"))))
      (assert (match bal ((ok b) (and (= (bl/modeName b.policy.mode) "sub") (listAny? (fn [(m bl/PoolModel)] -> Bool (and (= m.id "m") (= m.why "drafts") (= m.budgets (list "mDay")))) b.models))) ((err _) false)) "the same text yields the balancer pool")
      true))

fn callLine atMs: Int64 alias: String -> String
  (str "(:call :at " atMs " :profile work :intent code :alias " alias " :provider p :model m :in 100 :cached 0 :out 50 :reasoning 0 :ttftMs absent :ms absent :outcome ok :charge 300 :tag absent :temperature absent :topP absent :maxTokens absent :effort absent :api chat :stream false :toolCount 0 :promptBytes 0 :sysHash h)")

fn testLedgerWindows -> Bool
  (let [(tokBudget (budget "orTok" (dayMs) "tok" 1000 80 true))
        (bal (bl/makeBalancer (list (model "orQwen" (bl/tierFree) (list "orDay" "orTok") 0)) (list (budget "orDay" (dayMs) "req" 160 90 true) tokBudget) (list) (bl/defaultPolicy)))
        (rows (fold (fn [(acc (List ul/CallRow)) (line String)] -> (List ul/CallRow) (match (ul/callRowParse line) ((ok r) (listAppend acc (list r))) ((err _) acc)))
                    (list)
                    (list (callLine 1000 "orQwen") (callLine 2000 "orQwen") (callLine (+ (dayMs) 5) "orQwen") (callLine (+ (dayMs) 6) "other"))))
        (use (bl/usageFromCalls bal rows))
        (now (+ (dayMs) 10))
        (lines (map bl/budgetRowLine (bl/budgetRows bal use now)))]
    (do
      (assert (= (listLength rows) 4) "recorded call rows parse")
      (assert (= (bl/budgetUsed use tokBudget now) 150) "only the current day window counts, tokens in plus out")
      (assert (= (bl/budgetUsed use tokBudget 1500) 0) "a query outside the stored window reads zero, never the stale count")
      (assert (= (bl/windowStart (budget "c" (fiveHMs) "req" 1 1 false) (+ (* 2 (fiveHMs)) 7)) (* 2 (fiveHMs))) "a 5h window starts on its anchor grid")
      (assert (listAny? (fn [(l String)] -> Bool (and (stringContains? l ":id orDay :used 1 ") (stringContains? l ":cap 160"))) lines) (str "a report row per budget carries used and cap: " (stringJoin lines " ")))
      (assert (listAny? (fn [(l String)] -> Bool (and (stringContains? l ":id orDay") (stringContains? l ":flag over"))) lines) "one request in the first 10 ms projects past the daily cap and is flagged over")
      true))

; (:m :do "GW-BALANCER-SMALL-QUOTA-PACING: a 10-request daily quota at 15 percent of the day has a pro-rata target of 1.5; with one request used it is behind and must score up, as a 1000-request quota at 150 of 150 stays neutral; an integer target of 1 called it on pace")
fn testSmallQuotaPacing -> Bool
  (let [(at (/ (* 15 (dayMs)) 100))
        (small (budget "small" (dayMs) "req" 10 100 true))
        (large (budget "large" (dayMs) "req" 1000 100 true))
        (both (bl/makeBalancer (list (model "big" (bl/tierFree) (list "large") 0) (model "tiny" (bl/tierFree) (list "small") 0))
                               (list small large) (list (cal "big" 8 10) (cal "tiny" 8 10))
                               (bl/Policy :mode (bl/modeBalanced) :exploreEvery 0 :softFactor 100)))
        (use (bl/chargeUse both (fold (fn [(u (Map String bl/Window)) (i Int64)] -> (Map String bl/Window) (bl/chargeUse both u "big" at 10)) (bl/emptyUse) (range 0 150)) "tiny" at 10))]
    (do
      (assert (> (bl/pacingFactor small 1 at 100) 1000) (str "one of 10 used against a target of 1.5 scores up: " (bl/pacingFactor small 1 at 100)))
      (assert (= (bl/pacingFactor large 150 at 100) 1000) "a quota exactly on its pro-rata pace stays neutral")
      (assert (= (match (bl/pick both use (bl/Request :seq 1 :atMs at :intent "code" :tokens 10)) ((bl/picked m _ _ _) m) (_ "")) "tiny") "the small quota that is behind its pace wins the tie")
      true))

; (:m :do "GW-BALANCER-WORKERSTATS: three graded runs of one model in workerStats shape (two passes, one reject) plus a pending and an ungraded run that must be skipped")
fn testWorkerStatsReuse -> Bool
  (let [(text "(:workerStats :id SH :v 1 :form \"(:run ...)\" :runs ((:run :unit H1 :worker agy :model flashHigh :grade accept) (:run :unit H2 :worker agy :model flashHigh :grade acceptWithFixes :note \"x\") (:run :unit H3 :worker agy :model flashHigh :grade reject) (:run :unit H4 :worker agy :model flashHigh :grade pending) (:run :unit H5 :worker agy :model flashHigh :outcome partial) (:run :unit H6 :odd)))\n(:run :unit H7 :worker leon :model other :grade accept)")
        (cals (bl/parseCalScores text))
        (bal (bl/makeBalancer (list) (list) cals (bl/defaultPolicy)))
        (none0 (bl/makeBalancer (list) (list) (list) (bl/defaultPolicy)))
        (flash (model "flashHigh" (bl/tierFree) (list) 0))
        (q (bl/qualityFor bal flash "code"))
        (q0 (bl/qualityFor none0 flash "code"))]
    (do
      (assert (= (listLength (filter (fn [(c bl/CalScore)] -> Bool (= c.model "flashHigh")) cals)) 3) "three graded runs become three trials, pending and ungraded runs are skipped")
      (assert (listAny? (fn [(c bl/CalScore)] -> Bool (and (= c.model "other") (= c.source "workerStats:H7"))) cals) "a bare top-level run row is read too")
      (assert (> q.confidence q0.confidence) "graded runs raise the model's confidence above the tier prior")
      (assert (stringContains? q.source "workerStats:H1") "the quality names the workerStats runs it came from")
      (assert (= q.score (/ (+ 2000 (* 2 (bl/tierPrior (bl/tierFree)))) 5)) "two of three passes shrink toward the prior by two pseudo-runs")
      true))

; (:m :do "GW-BALANCER-CALAS: worker runs graded under gemini-3.8-flash-high score the gateway alias flash only through its calAs list")
fn testCalAs -> Bool
  (let [(runs (bl/parseCalScores "(:workerStats :id SH :runs ((:run :unit H1 :model gemini-3.8-flash-high :grade accept) (:run :unit H2 :model gemini-3.8-flash-high :grade accept) (:run :unit H3 :model gemini-3.8-flash-high :grade reject)))"))
        (withAs (bl/parseBalancer (rd/parseSexpr "(:gateway :v 2 :models ((:model :id flash :provider agy :name \"gemini-3.8-flash\" :tier free :calAs (gemini-3.8-flash-high \"gemini-3.8-flash:high\")) (:model :id plain :provider agy :name \"gemini-3.8-flash\" :tier free)))") runs))]
    (match withAs
      ((err e) (do (assert false (str "calAs config parses: " e)) false))
      ((ok bal)
        (let [(flash (optionOr (listFind (fn [(m bl/PoolModel)] -> Bool (= m.id "flash")) bal.models) (model "missing" (bl/tierFree) (list) 0)))
              (plain (optionOr (listFind (fn [(m bl/PoolModel)] -> Bool (= m.id "plain")) bal.models) (model "missing" (bl/tierFree) (list) 0)))
              (qf (bl/qualityFor bal flash "code"))
              (qp (bl/qualityFor bal plain "code"))]
          (do
            (assert (= (mapGetOr bal.calAs "flash" (list)) (list "gemini-3.8-flash-high" "gemini-3.8-flash:high")) "calAs names parse from the model row, bare and quoted")
            (assert (stringContains? qf.source "workerStats:H1") (str "runs under a calAs name score the alias: " qf.source))
            (assert (> qf.confidence qp.confidence) "the alias with calAs gains confidence from three runs, the alias without stays at the prior")
            (assert (= qp.source "prior") "a model without calAs does not borrow runs filed under another name")
            true)))))

; (:m :do "the shape the real SH/workerStats.asn grew by appends, with synthetic runs: one :runs list, then further run groups and an :external list after it, so the head's props are odd and a key-value read sees nothing; every graded run must still become a trial")
fn testAppendedRunGroups -> Bool
  (let [(text "(:workerStats :id SH :v 1 :form \"f\" :runs ((:run :unit A1 :model wA :grade accept) (:run :unit A2 :model wA :grade reject)) ((:run :unit B1 :model wB :grade acceptWithFixes)) ((:run :unit C1 :model wA :grade pending) (:run :unit C2 :model wC :grade accept)) :external ((:run :unit E1 :model wB :grade reject)))")
        (trials (bl/parseCalScores text))
        (ids (map (fn [(c bl/CalScore)] -> String c.source) trials))]
    (do
      (assert (= (listLength trials) 5) (str "five graded runs across :runs, the trailing groups and :external become trials: " (stringJoin ids " ")))
      (assert (listContains? ids "workerStats:B1") "a run in a trailing group after :runs is read")
      (assert (listContains? ids "workerStats:E1") "a run under :external is read")
      (assert (not (listContains? ids "workerStats:C1")) "a pending run is still skipped")
      (assert (= (listLength (filter (fn [(c bl/CalScore)] -> Bool (and (= c.model "wA") (= c.pass 1))) trials)) 1) "wA has one pass and one fail")
      true))

; (:m :do "AUDIT10-A3: a month usd budget of 5e9 microUSD (5000 USD) at 90 percent of its window with 4.5e9 used is exactly on pace; hardCap x elapsed ms would be 1.17e19 and wrap Int64, so the factor must be computed from the permille window fraction")
fn testLargeBudgets -> Bool
  (let [(month (* 30 (dayMs)))
        (big (bl/Budget :id "monthUsd" :windowMs month :anchorMs 0 :headerWindowMs 0 :unit "usd" :size 5000000000 :softPct 100 :hardPct 100 :useOrLose false :source "declared"))
        (at (/ (* 9 month) 10))
        (bal (bl/makeBalancer (list (model "p" (bl/tierPaid) (list "monthUsd") 1000)) (list big) (list) (bl/defaultPolicy)))
        (rows (bl/budgetRows bal (mapSet (bl/emptyUse) "monthUsd" (bl/Window :start 0 :used 4500000000)) at))
        (row (optionOr (listHead rows) (bl/BudgetRow :id "" :used 0 :target 0 :cap 0 :projected 0 :flag "")))
        (tooBig (bl/parseBalancer (rd/parseSexpr "(:gateway :v 2 :models () :balancer (:balancer :budgets ((:budget :id huge :window month :unit usd :size 2000000000000))))") (list)))]
    (do
      (assert (= (bl/pacingFactor big 4500000000 at 100) 1000) (str "an on-pace 5000 USD month budget is neutral, not shifted by an overflow: " (bl/pacingFactor big 4500000000 at 100)))
      (assert (< (bl/pacingFactor big 4900000000 at 100) 1000) "running ahead of the same budget still scores down")
      (assert (= row.target 4500000000) (str "the report target is size x window fraction: " row.target))
      (assert (= row.projected 5000000000) (str "the projection to window end stays in range: " row.projected))
      (assert (= row.flag "ok") "the on-pace month budget is flagged ok")
      (assert (match tooBig ((err e) (stringContains? e "needs a :size from 0 to 1000000000000")) ((ok _) false)) "a size above 1e12 is a config error")
      true))

fn runTests -> Bool
  (do
    (assert (testLargeBudgets) "large budgets")
    (assert (testDayBalanced) "day balanced")
    (assert (testOverloadUsesPaidUnderCap) "overload")
    (assert (testSoftShifts) "soft shifts")
    (assert (testHardRefuses) "hard refuses")
    (assert (testModesFilter) "modes filter")
    (assert (testUncalibratedRoutable) "uncalibrated routable")
    (assert (testCalReuse) "cal reuse")
    (assert (testConfigParse) "config parse")
    (assert (testLedgerWindows) "ledger windows")
    (assert (testSmallQuotaPacing) "small quota pacing")
    (assert (testWorkerStatsReuse) "workerStats reuse")
    (assert (testCalAs) "calAs")
    (assert (testAppendedRunGroups) "appended run groups")
    (assert (testCoexistsWithConfig) "coexists with config")
    true)
