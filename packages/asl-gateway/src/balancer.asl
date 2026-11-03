(module aslGateway/balancer
  :x [Tier Mode Budget PoolModel CalScore Quality Window Policy Balancer Request Pick Replay BudgetRow Scored
      tierFree tierSub tierPaid modeFree modeSub modePaid modeBalanced modeExplore picked refused
      parseTier parseMode tierName modeName windowMsOf tierAdmitted? defaultPolicy makeBalancer
      windowStart budgetUsed hardCap softCap pacingFactor modelPacing qualityFor tierPrior
      parseCalScores parseBalancer emptyUse chargeUse usageFromCalls scoreOf pick replay
      budgetRows budgetRowLine blockingBudgets Pool loadPool! poolFromParts poolRequest poolPick poolCharge poolTarget pickWhy refusalText poolFailed Observed RateObs parseDurationMs parseRfc3339Ms parseRateHeaders retryAfterMs poolObserve poolObserveEndpoint effectiveUse poolPickLanes laneOf laneFor ledgerSinceMs Poll pollsDue poolPolled poolPollReply parseHttpDateMs urlHost deriveInstance Hold poolReserve poolRelease poolAliasesFor poolHonour modelKey poolReleaseAt deriveInstanceWithRoles]
  :i [(asl-parser/reader :a rd)
      (aslGateway/config :a cfg)
      (aslGateway/usageLedger :a ul)
      (asl-json/json :a j)])

; (:m :ref GW-BUDGET-BALANCER-20261027 :do "pure model-pool balancer: every model is routable with a quality from the best source (own CAL, declared, tier prior) and a confidence, modes filter tiers, pacing spreads each budget window evenly, soft caps shift load, hard caps refuse, costs are Int64 microUSD")

(enum Tier
  (:c tierFree [])
  (:c tierSub [])
  (:c tierPaid []))

(enum Mode
  (:c modeFree [])
  (:c modeSub [])
  (:c modePaid [])
  (:c modeBalanced [])
  (:c modeExplore []))

; (:m :do "a quota window: unit req counts calls, tok counts tokens, usd counts microUSD, soft and hard are percent of size, useOrLose quotas reset unused, so they get a bonus near the window end")
(schema Budget
  (:f id String)
  (:f windowMs Int64)
  (:f anchorMs Int64)
  (:f unit String)
  (:f size Int64)
  (:f softPct Int64)
  (:f hardPct Int64)
  (:f useOrLose Bool)
  (:f source String)
  ; (:m :ref GW-BALANCER-HEADER-WINDOW :do "the window the provider rate-limit headers count, 0 when the row names none; a header whose reset lies beyond it counts another window and is ignored, one shorter than the budget window can only exhaust the budget until its reset")
  (:f headerWindowMs Int64))

(schema PoolModel
  (:f id String)
  (:f provider String)
  (:f tier Tier)
  (:f why String)
  (:f budgets (List String))
  (:f costMicros Int64)
  (:f declaredQuality (Option Int64)))

(schema CalScore
  (:f model String)
  (:f intent String)
  (:f pass Int64)
  (:f total Int64)
  (:f source String))

; (:m :do "score and confidence are permille, source names where the score came from: a CAL id, declared or prior")
(schema Quality
  (:f score Int64)
  (:f confidence Int64)
  (:f source String))

(schema Window
  (:f start Int64)
  (:f used Int64))

(schema Policy
  (:f mode Mode)
  (:f exploreEvery Int64)
  (:f softFactor Int64))

(schema Balancer
  (:f models (List PoolModel))
  (:f budgets (Map String Budget))
  (:f cals (List CalScore))
  (:f policy Policy)
  ; (:m :ref GW-BALANCER-CALAS :do "per pool alias, the other names its calibration rows carry (worker model names in workerStats, CAL ids), from the model row calAs list")
  (:f calAs (Map String (List String))))

(schema Request
  (:f seq Int64)
  (:f atMs Int64)
  (:f intent String)
  (:f tokens Int64))

(enum Pick
  (:c picked [(model String) (score Int64) (quality Quality) (explore Bool)])
  (:c refused [(reason String)]))

(schema Replay
  (:f use (Map String Window))
  (:f picks (List Pick))
  (:f overHard Int64))

(schema BudgetRow
  (:f id String)
  (:f used Int64)
  (:f target Int64)
  (:f cap Int64)
  (:f projected Int64)
  (:f flag String))

(schema Scored
  (:f model PoolModel)
  (:f score Int64)
  (:f quality Quality))

fn hourMs -> Int64 3600000

fn dayMs -> Int64 86400000

fn parseTier name: String -> (Result Tier String)
  (cond
    ((= name "free") (ok (tierFree)))
    ((= name "sub") (ok (tierSub)))
    ((= name "paid") (ok (tierPaid)))
    (else (err (str "balancer: unknown tier " name))))

fn tierName tier: Tier -> String
  (match tier
    ((tierFree) "free")
    ((tierSub) "sub")
    ((tierPaid) "paid"))

fn parseMode name: String -> (Result Mode String)
  (cond
    ((= name "free") (ok (modeFree)))
    ((= name "sub") (ok (modeSub)))
    ((= name "paid") (ok (modePaid)))
    ((= name "balanced") (ok (modeBalanced)))
    ((= name "explore") (ok (modeExplore)))
    (else (err (str "balancer: unknown mode " name))))

fn modeName mode: Mode -> String
  (match mode
    ((modeFree) "free")
    ((modeSub) "sub")
    ((modePaid) "paid")
    ((modeBalanced) "balanced")
    ((modeExplore) "explore"))

fn windowMsOf name: String -> (Result Int64 String)
  (cond
    ((= name "minute") (ok 60000))
    ((= name "hour") (ok (hourMs)))
    ((= name "5h") (ok (* 5 (hourMs))))
    ((= name "day") (ok (dayMs)))
    ((= name "week") (ok (* 7 (dayMs))))
    ((= name "month") (ok (* 30 (dayMs))))
    (else (err (str "balancer: unknown window " name))))

fn tierAdmitted? mode: Mode tier: Tier -> Bool
  (match mode
    ((modeFree) (= (tierName tier) "free"))
    ((modeSub) (= (tierName tier) "sub"))
    ((modePaid) (= (tierName tier) "paid"))
    ((modeBalanced) true)
    ((modeExplore) true))

fn defaultPolicy -> Policy
  (Policy :mode (modeBalanced) :exploreEvery 20 :softFactor 100)

fn makeBalancer models: (List PoolModel) budgets: (List Budget) cals: (List CalScore) policy: Policy -> Balancer
  (Balancer :models models
            :budgets (fold (fn [(acc (Map String Budget)) (b Budget)] -> (Map String Budget) (mapSet acc b.id b)) (mapEmpty) budgets)
            :cals cals
            :policy policy
            :calAs (mapEmpty))

fn emptyUse -> (Map String Window)
  (mapEmpty)

fn windowStart b: Budget nowMs: Int64 -> Int64
  (if (<= b.windowMs 0)
    b.anchorMs
    (- nowMs (mod (+ (mod (- nowMs b.anchorMs) b.windowMs) b.windowMs) b.windowMs)))

fn budgetUsed use: (Map String Window) b: Budget nowMs: Int64 -> Int64
  (match (mapGet use b.id)
    ((some w) (if (= w.start (windowStart b nowMs)) w.used 0))
    ((none) 0))

fn hardCap b: Budget -> Int64
  (/ (* b.size b.hardPct) 100)

fn softCap b: Budget -> Int64
  (/ (* b.size b.softPct) 100)

fn chargeAmount b: Budget m: PoolModel tokens: Int64 -> Int64
  (cond
    ((= b.unit "req") 1)
    ((= b.unit "tok") (max 0 tokens))
    (else (max 0 m.costMicros)))

; (:m :do "permille factor: behind the pro-rata target scores up (the window fraction is taken in permille before it multiplies a size, AUDIT10-A3) (target and use compared in thousandths of a unit, so a quota of a few requests is paced by its fractional target) (use-or-lose quotas only, a spend cap is never pushed to spend), ahead scores down, squared so a pool cannot run far ahead, the soft line is the absolute soft cap or running ahead of the hard cap pro-rata, past it the factor is scaled by softFactor, a use-or-lose quota in the last quarter of its window ignores the soft line and below 90% gets x1.5 so it drains before reset")
fn pacingFactor b: Budget used: Int64 nowMs: Int64 softFactor: Int64 -> Int64
  (let [(elapsed (- nowMs (windowStart b nowMs)))
        (span (max 1 b.windowMs))
        (fracP (/ (* 1000 (min elapsed span)) span))
        (targetP (* b.size fracP))
        (slack (max 1 (/ b.size 20)))
        (slackP (* 1000 slack))
        (ratio (min (if b.useOrLose 4000 1000) (max 100 (/ (* 1000 (+ targetP slackP)) (+ (* 1000 used) slackP)))))
        (paced (min 8000 (max 10 (/ (* ratio ratio) 1000))))
        (lateWindow (< (* 4 (- span elapsed)) span))
        (ahead (> used (+ (/ (* (hardCap b) fracP) 1000) slack)))
        (pastSoft (and (or (>= used (softCap b)) ahead) (not (and b.useOrLose lateWindow))))
        (soft (if pastSoft (/ (* paced softFactor) 1000) paced))
        (bonus (and b.useOrLose lateWindow (< (* 10 used) (* 9 b.size))))]
    (max 1 (if bonus (/ (* soft 3) 2) soft)))

fn modelBudgets bal: Balancer m: PoolModel -> (List Budget)
  (fold (fn [(acc (List Budget)) (id String)] -> (List Budget)
          (match (mapGet bal.budgets id)
            ((some b) (listAppend acc (list b)))
            ((none) acc)))
        (list)
        m.budgets)

; (:m :do "a model drawing on several budgets is paced by its tightest one, a model with no budget is neutral 1000")
fn modelPacing bal: Balancer use: (Map String Window) m: PoolModel nowMs: Int64 -> Int64
  (let [(factors (map (fn [(b Budget)] -> Int64 (pacingFactor b (budgetUsed use b nowMs) nowMs bal.policy.softFactor)) (modelBudgets bal m)))]
    (if (listEmpty? factors) 1000 (fold (fn [(acc Int64) (f Int64)] -> Int64 (min acc f)) 1000000 factors)))

fn fits? bal: Balancer use: (Map String Window) m: PoolModel req: Request -> Bool
  (listAll? (fn [(b Budget)] -> Bool (<= (+ (budgetUsed use b req.atMs) (chargeAmount b m req.tokens)) (hardCap b)))
            (modelBudgets bal m))

fn tierPrior tier: Tier -> Int64
  (match tier
    ((tierFree) 450)
    ((tierSub) 600)
    ((tierPaid) 600))

fn tierWeight tier: Tier -> Int64
  (match tier
    ((tierFree) 1000)
    ((tierSub) 1000)
    ((tierPaid) 600))

; (:m :do "best source wins: CAL rows for the intent, else CAL rows for any intent, else a declared quality, else the tier prior, CAL scores shrink toward the prior by two pseudo-runs and confidence grows with n, so one lucky run cannot outrank a measured model")
fn qualityFor bal: Balancer m: PoolModel intent: String -> Quality
  (let [(names (listAppend (list m.id) (mapGetOr bal.calAs m.id (list))))
        (own (filter (fn [(c CalScore)] -> Bool (listContains? names c.model)) bal.cals))
        (exact (filter (fn [(c CalScore)] -> Bool (= c.intent intent)) own))
        (rows (if (listEmpty? exact) own exact))
        (pass (listSum (map (fn [(c CalScore)] -> Int64 c.pass) rows)))
        (total (listSum (map (fn [(c CalScore)] -> Int64 c.total) rows)))
        (prior (tierPrior m.tier))]
    (if (> total 0)
      (Quality :score (/ (+ (* (min pass total) 1000) (* prior 2)) (+ total 2))
               :confidence (/ (* 1000 total) (+ total 4))
               :source (stringJoin (map (fn [(c CalScore)] -> String c.source) rows) " "))
      (match m.declaredQuality
        ((some q) (Quality :score (min 1000 (max 0 q)) :confidence 250 :source "declared"))
        ((none) (Quality :score prior :confidence 100 :source "prior")))))

fn costFloorMicros -> Int64 1000

; (:m :do "score = pacing x tier weight / cost per green unit, where cost per green is (cost + floor) / quality, a stronger model that needs fewer retries wins even when pricier")
fn scoreOf bal: Balancer use: (Map String Window) m: PoolModel req: Request -> Scored
  (let [(q (qualityFor bal m req.intent))
        (quality (if (= (modeName bal.policy.mode) "explore") (- 1000 q.confidence) q.score))
        (perGreen (max 1 (/ (* (+ (max 0 m.costMicros) (costFloorMicros)) 1000) (max 1 quality))))
        (pace (modelPacing bal use m req.atMs))
        (s (/ (* (/ (* pace (tierWeight m.tier)) 1000) 1000000) perGreen))]
    (Scored :model m :score s :quality q))

fn bestBy better: (fn [Scored Scored] -> Bool) xs: (List Scored) -> (Option Scored)
  (fold (fn [(acc (Option Scored)) (x Scored)] -> (Option Scored)
          (match acc
            ((none) (some x))
            ((some y) (if (better x y) (some x) acc))))
        (none)
        xs)

; (:m :do "ids of the budgets that keep the admitted models of the mode from fitting, each once, in model order")
fn blockingBudgets bal: Balancer use: (Map String Window) req: Request -> (List String)
  (fold (fn [(acc (List String)) (m PoolModel)] -> (List String)
          (fold (fn [(acc2 (List String)) (b Budget)] -> (List String)
                  (if (and (> (+ (budgetUsed use b req.atMs) (chargeAmount b m req.tokens)) (hardCap b)) (not (listContains? acc2 b.id)))
                    (listAppend acc2 (list b.id))
                    acc2))
                acc
                (modelBudgets bal m)))
        (list)
        (filter (fn [(m PoolModel)] -> Bool (tierAdmitted? bal.policy.mode m.tier)) bal.models))

fn pick bal: Balancer use: (Map String Window) req: Request -> Pick
  (let [(admitted (filter (fn [(m PoolModel)] -> Bool (tierAdmitted? bal.policy.mode m.tier)) bal.models))
        (open (filter (fn [(m PoolModel)] -> Bool (fits? bal use m req)) admitted))
        (scored (map (fn [(m PoolModel)] -> Scored (scoreOf bal use m req)) open))
        (every bal.policy.exploreEvery)
        (explore (and (> every 0) (= (mod req.seq every) 0) (> (listLength scored) 1)))
        (choice (if explore
                  (bestBy (fn [(x Scored) (y Scored)] -> Bool (or (< x.quality.confidence y.quality.confidence) (and (= x.quality.confidence y.quality.confidence) (> x.score y.score)))) scored)
                  (bestBy (fn [(x Scored) (y Scored)] -> Bool (> x.score y.score)) scored)))]
    (match choice
      ((some s) (picked s.model.id s.score s.quality explore))
      ((none)
        (refused (if (listEmpty? admitted)
                   (str "mode " (modeName bal.policy.mode) " admits no model")
                   (str "every model in mode " (modeName bal.policy.mode) " is at its hard cap: " (stringJoin (blockingBudgets bal use req) " ")))))))

fn chargeUse bal: Balancer use: (Map String Window) modelId: String atMs: Int64 tokens: Int64 -> (Map String Window)
  (match (listFind (fn [(m PoolModel)] -> Bool (= m.id modelId)) bal.models)
    ((none) use)
    ((some m)
      (fold (fn [(acc (Map String Window)) (b Budget)] -> (Map String Window)
              (let [(start (windowStart b atMs))
                    (prev (budgetUsed acc b atMs))]
                (mapSet acc b.id (Window :start start :used (+ prev (chargeAmount b m tokens))))))
            use
            (modelBudgets bal m))))

; (:m :do "rebuild window usage from recorded gateway calls: each row charges the budgets of its alias at its own time, tokens in+out, cost from the row charge, rows outside the current window drop out by windowStart")
fn usageFromCalls bal: Balancer rows: (List ul/CallRow) -> (Map String Window)
  (fold (fn [(acc (Map String Window)) (r ul/CallRow)] -> (Map String Window)
          (match (listFind (fn [(m PoolModel)] -> Bool (= m.id r.alias)) bal.models)
            ((none) acc)
            ((some m)
              (fold (fn [(acc2 (Map String Window)) (b Budget)] -> (Map String Window)
                      (let [(amount (cond ((= b.unit "req") 1) ((= b.unit "tok") (+ r.inTokens r.outTokens)) (else (max 0 r.charge))))]
                        (mapSet acc2 b.id (Window :start (windowStart b r.atMs) :used (+ (budgetUsed acc2 b r.atMs) amount)))))
                    acc
                    (modelBudgets bal m)))))
        (emptyUse)
        rows)

fn overHardCount bal: Balancer use: (Map String Window) nowMs: Int64 -> Int64
  (listLength (filter (fn [(b Budget)] -> Bool (> (budgetUsed use b nowMs) (hardCap b))) (mapValues bal.budgets)))

fn replay bal: Balancer use: (Map String Window) reqs: (List Request) -> Replay
  (fold (fn [(st Replay) (req Request)] -> Replay
          (let [(p (pick bal st.use req))
                (use2 (match p ((picked id _ _ _) (chargeUse bal st.use id req.atMs req.tokens)) ((refused _) st.use)))]
            (Replay :use use2 :picks (listAppend st.picks (list p)) :overHard (+ st.overHard (overHardCount bal use2 req.atMs)))))
        (Replay :use use :picks (list) :overHard 0)
        reqs)

fn budgetRows bal: Balancer use: (Map String Window) nowMs: Int64 -> (List BudgetRow)
  (map (fn [(b Budget)] -> BudgetRow
         (let [(used (budgetUsed use b nowMs))
               (elapsed (max 1 (- nowMs (windowStart b nowMs))))
               (fracP (max 1 (/ (* 1000 (min elapsed (max 1 b.windowMs))) (max 1 b.windowMs))))
               (target (/ (* b.size fracP) 1000))
               (projected (/ (* used 1000) fracP))
               (flag (cond
                       ((> projected (hardCap b)) "over")
                       ((and b.useOrLose (< (* 10 projected) (* 9 b.size))) "under")
                       (else "ok")))]
           (BudgetRow :id b.id :used used :target target :cap (hardCap b) :projected projected :flag flag)))
       (mapValues bal.budgets))

fn budgetRowLine r: BudgetRow -> String
  (str "(:budgetRow :id " r.id " :used " r.used " :target " r.target " :cap " r.cap " :projected " r.projected " :flag " r.flag ")")

fn listOf expr: rd/SExpr -> (List rd/SExpr)
  (match expr
    ((rd/sexprList items) items)
    ((rd/sexprVect items) items)
    (_ (list)))

fn propStr props: (Map String rd/SExpr) key: String fallback: String -> String
  (match (mapGet props key)
    ((some e) (cfg/scalarToString (cfg/asnScalar e)))
    ((none) fallback))

fn propInt props: (Map String rd/SExpr) key: String fallback: Int64 -> (Result Int64 String)
  (match (mapGet props key)
    ((none) (ok fallback))
    ((some e)
      (match (cfg/asnScalar e)
        ((cfg/scalarInt v) (ok v))
        (_ (err (str "balancer: :" key " must be an integer"))))))

fn propIntOpt props: (Map String rd/SExpr) key: String -> (Result (Option Int64) String)
  (match (mapGet props key)
    ((none) (ok (none)))
    ((some _) (match (propInt props key 0) ((ok v) (ok (some v))) ((err e) (err e)))))

fn propBool props: (Map String rd/SExpr) key: String fallback: Bool -> Bool
  (match (mapGet props key)
    ((some e) (match (cfg/asnScalar e) ((cfg/scalarBool v) v) (_ fallback)))
    ((none) fallback))

; (:m :ref AUDIT10-A3 :do "pacing multiplies a size by at most 1e6 (permille fraction, then permille ratio), so sizes up to 1e12 keep every product under Int64 9.2e18")
fn maxBudgetSize -> Int64 1000000000000

fn parseBudget form: rd/SExpr -> (Result Budget String)
  (match (cfg/asnProps form (some ":budget"))
    ((err e) (err e))
    ((ok p)
      (let [(id (propStr p "id" ""))]
        (if (stringEmpty? id)
          (err "balancer: budget row has no :id")
          (match (windowMsOf (propStr p "window" "day"))
            ((err e) (err (str e " in budget " id)))
            ((ok windowMs)
              (let [(unit (propStr p "unit" "req"))]
                (if (not (listContains? (list "req" "tok" "usd") unit))
                  (err (str "balancer: budget " id " unit must be req, tok or usd"))
                  (match (propInt p "size" -1)
                    ((err e) (err e))
                    ((ok size)
                      (if (or (< size 0) (> size (maxBudgetSize)))
                        (err (str "balancer: budget " id " needs a :size from 0 to " (maxBudgetSize) " (1e12, a million USD in microUSD), so pacing arithmetic stays inside Int64"))
                        (match (propInt p "soft" 80)
                          ((err e) (err e))
                          ((ok soft)
                            (match (propInt p "hard" 100)
                              ((err e) (err e))
                              ((ok hard)
                                (match (propInt p "anchorMs" 0)
                                  ((err e) (err e))
                                  ((ok anchor)
                                    (if (or (< soft 0) (< hard soft))
                                      (err (str "balancer: budget " id " needs 0 <= soft <= hard"))
                                      (match (match (mapGet p "headerWindow") ((some e) (windowMsOf (cfg/scalarToString (cfg/asnScalar e)))) ((none) (ok 0)))
                                        ((err e) (err (str e " in budget " id " :headerWindow")))
                                        ((ok headerWindow)
                                          (ok (Budget :id id :windowMs windowMs :anchorMs anchor :unit unit :size size
                                                      :softPct soft :hardPct hard
                                                      :useOrLose (propBool p "useOrLose" false)
                                                      :source (propStr p "source" "declared")
                                                      :headerWindowMs headerWindow))))))))))))))))))))))

fn parseBudgets forms: (List rd/SExpr) -> (Result (List Budget) String)
  (fold (fn [(acc (Result (List Budget) String)) (f rd/SExpr)] -> (Result (List Budget) String)
          (match acc
            ((err e) (err e))
            ((ok xs) (match (parseBudget f) ((ok x) (ok (listAppend xs (list x)))) ((err e) (err e))))))
        (ok (list))
        forms)

; (:m :do "model rows keep their gateway keys and may add why, tier, budgets, costMicros and quality, a row without a tier is paid, so a free-only or sub-only mode never spends on it by accident")
fn parsePoolModel form: rd/SExpr budgets: (Map String Budget) -> (Result PoolModel String)
  (match (cfg/asnProps form (some ":model"))
    ((err e) (err e))
    ((ok p)
      (let [(id (propStr p "id" ""))
            (refs (match (mapGet p "budgets") ((some e) (map (fn [(x rd/SExpr)] -> String (cfg/scalarToString (cfg/asnScalar x))) (listOf e))) ((none) (list))))
            (missing (filter (fn [(r String)] -> Bool (not (mapHas? budgets r))) refs))]
        (cond
          ((stringEmpty? id) (err "balancer: model row has no :id"))
          ((not (listEmpty? missing)) (err (str "balancer: model " id " names unknown budget " (stringJoin missing " "))))
          (else
            (match (parseTier (propStr p "tier" "paid"))
              ((err e) (err (str e " in model " id)))
              ((ok tier)
                (match (propInt p "costMicros" 0)
                  ((err e) (err e))
                  ((ok cost)
                    (match (propIntOpt p "quality")
                      ((err e) (err e))
                      ((ok q)
                        (ok (PoolModel :id id :provider (propStr p "provider" "") :tier tier :why (propStr p "why" "")
                                       :budgets refs :costMicros cost :declaredQuality q)))))))))))))

fn calAsOf forms: (List rd/SExpr) -> (Map String (List String))
  (fold (fn [(acc (Map String (List String))) (f rd/SExpr)] -> (Map String (List String))
          (match (cfg/asnProps f (some ":model"))
            ((err _) acc)
            ((ok p) (match (mapGet p "calAs") ((some e) (mapSet acc (propStr p "id" "") (stringsOf e))) ((none) acc)))))
        (mapEmpty)
        forms)

fn parsePoolModels budgets: (Map String Budget) forms: (List rd/SExpr) -> (Result (List PoolModel) String)
  (fold (fn [(acc (Result (List PoolModel) String)) (f rd/SExpr)] -> (Result (List PoolModel) String)
          (match acc
            ((err e) (err e))
            ((ok xs) (match (parsePoolModel f budgets) ((ok x) (ok (listAppend xs (list x)))) ((err e) (err e))))))
        (ok (list))
        forms)

; (:m :do "reads the (:gateway ...) form already loaded by config: :models rows plus an optional (:balancer :mode :exploreEvery :softFactor :budgets (...)) section, config.asl ignores both extensions")
fn parseBalancer form: rd/SExpr cals: (List CalScore) -> (Result Balancer String)
  (match (cfg/asnProps form (some ":gateway"))
    ((err e) (err e))
    ((ok top)
      (let [(sec (match (mapGet top "balancer") ((some e) (cfg/asnProps e (some ":balancer"))) ((none) (ok (mapEmpty)))))]
        (match sec
          ((err e) (err e))
          ((ok b)
            (match (parseMode (propStr b "mode" "balanced"))
              ((err e) (err e))
              ((ok mode)
                (match (propInt b "exploreEvery" 20)
                  ((err e) (err e))
                  ((ok every)
                    (match (propInt b "softFactor" 100)
                      ((err e) (err e))
                      ((ok softFactor)
                        (match (parseBudgets (match (mapGet b "budgets") ((some e) (listOf e)) ((none) (list))))
                          ((err e) (err e))
                          ((ok budgetList)
                            (let [(bal0 (makeBalancer (list) budgetList cals (Policy :mode mode :exploreEvery (max 0 every) :softFactor (max 1 softFactor))))]
                              (match (parsePoolModels bal0.budgets (match (mapGet top "models") ((some e) (listOf e)) ((none) (list))))
                                ((err e) (err e))
                                ((ok models) (ok (with (with bal0 :models models) :calAs (calAsOf (match (mapGet top "models") ((some e) (listOf e)) ((none) (list))))))))))))))))))))))

fn calScoreOf calId: String intent: String item: rd/SExpr -> (List CalScore)
  (let [(items (listOf item))
        (at (fn [(i Int64)] -> Int64
              (match (listGet items i)
                ((some e) (match (cfg/asnScalar e) ((cfg/scalarInt v) v) (_ -1)))
                ((none) -1))))
        (pass (at 1))
        (total (at 2))
        (model (match (listGet items 0) ((some e) (cfg/scalarToString (cfg/asnScalar e))) ((none) "")))]
    (if (and (not (stringEmpty? model)) (>= pass 0) (> total 0))
      (list (CalScore :model model :intent intent :pass pass :total total :source (str "cal:" calId)))
      (list)))

; (:m :ref GW-BALANCER-WORKERSTATS :do "a graded worker run is one calibration trial of its model: accept and acceptWithFixes pass, reject fails, pending or ungraded runs and unreadable rows are skipped")
fn runScore form: rd/SExpr -> (List CalScore)
  (match (cfg/asnProps form (some ":run"))
    ((err _) (list))
    ((ok p)
      (let [(m (propStr p "model" ""))
            (grade (propStr p "grade" ""))
            (pass (cond ((or (= grade "accept") (= grade "acceptWithFixes")) 1) ((= grade "reject") 0) (else -1)))]
        (if (or (stringEmpty? m) (< pass 0))
          (list)
          (list (CalScore :model m :intent "any" :pass pass :total 1 :source (str "workerStats:" (propStr p "unit" "?"))))))))

; (:m :do "SH/workerStats.asn holds (:workerStats ... :runs ((:run ...) ...)) and, as appended in practice, further run groups after :runs that break its key-value shape; so every (:run ...) form at any depth under the head is read, and a bare top-level (:run ...) row reads the same")
fn runForms expr: rd/SExpr -> (List rd/SExpr)
  (match expr
    ((rd/sexprList items)
      (match (listHead items)
        ((some (rd/sexprAtom h)) (if (= h ":run") (list expr) (fold (fn [(acc (List rd/SExpr)) (x rd/SExpr)] -> (List rd/SExpr) (listAppend acc (runForms x))) (list) items)))
        (_ (fold (fn [(acc (List rd/SExpr)) (x rd/SExpr)] -> (List rd/SExpr) (listAppend acc (runForms x))) (list) items))))
    (_ (list)))

fn workerStatsScores form: rd/SExpr -> (List CalScore)
  (match (listHead (listOf form))
    ((some (rd/sexprAtom h))
      (if (or (= h ":workerStats") (= h ":run"))
        (fold (fn [(acc (List CalScore)) (r rd/SExpr)] -> (List CalScore) (listAppend acc (runScore r))) (list) (runForms form))
        (list)))
    (_ (list)))

; (:m :do "reuses saved calibration ledgers such as CAL/freeModels.asn: every (:cal :id :scores ((model pass total ...) ...)) row becomes CalScore rows, :intent defaults to any, rows it cannot read are skipped, never an error")
fn parseCalScores text: String -> (List CalScore)
  (fold (fn [(acc (List CalScore)) (form rd/SExpr)] -> (List CalScore)
          (match (cfg/asnProps form (some ":cal"))
            ((err _) (listAppend acc (workerStatsScores form)))
            ((ok p)
              (let [(id (propStr p "id" "?"))
                    (intent (propStr p "intent" "any"))]
                (listAppend acc (fold (fn [(a (List CalScore)) (it rd/SExpr)] -> (List CalScore) (listAppend a (calScoreOf id intent it)))
                                      (list)
                                      (match (mapGet p "scores") ((some e) (listOf e)) ((none) (list)))))))))
        (list)
        (listOf (rd/parseSexpr (str "(" text "\n)"))))

; (:m :ref GW-BALANCER-WIRE :do "the balancer as the dispatch layer holds it: pool, window usage rebuilt from the shared call ledger, alias to provider and upstream model name, and a count of charged requests that numbers the next request for exploration")
(schema Pool
  (:f bal Balancer)
  (:f use (Map String Window))
  (:f targets (Map String (Pair String String)))
  (:f seq Int64)
  ; (:m :ref GW-BALANCER-CASCADE :do "a pool alias whose last call failed sits out until failedUntil, so the chat cascade retry after a failure reaches another model; when every model sits out the exclusion lifts")
  (:f failedUntil (Map String Int64))
  (:f cooldownMs Int64)
  ; (:m :ref GW-BALANCER-LIVE-QUOTA :do "what providers reported per budget id: remaining from rate-limit headers or a status endpoint, or exhausted after an upstream 429")
  (:f observed (Map String Observed))
  ; (:m :ref GW-BALANCER-CLI-LANES :do "per pool alias the lane that serves it: http for a provider dispatch sends to, cli for a vendor CLI on this machine, gateway for a federation row; an alias with no entry is http")
  (:f lanes (Map String String))
  (:f instance String)
  (:f notes (List String))
  ; (:m :ref GW-BALANCER-STATUS-POLL :do "status endpoints to poll and, per budget id, when the last poll was sent or, after a rate-limited reply, the instant the backoff counts from")
  (:f polls (List Poll))
  (:f polledAt (Map String Int64))
  ; (:m :ref AUDIT11-A3 :do "requests picked and sent but not yet settled, each holding its estimated charge so a concurrent pick sees it")
  (:f holds (List Hold)))

(schema Hold
  (:f alias String)
  (:f atMs Int64)
  (:f tokens Int64))

; (:m :ref GW-BALANCER-STATUS-POLL :do "a status endpoint that refreshes an endpoint usd budget: url is the provider base plus path, the provider names whose key the request carries")
(schema Poll
  (:f budget String)
  (:f provider String)
  (:f url String)
  (:f everyMs Int64))

fn poolFromParts bal: Balancer use: (Map String Window) targets: (Map String (Pair String String)) -> Pool
  (Pool :bal (with bal :models (filter (fn [(m PoolModel)] -> Bool (mapHas? targets m.id)) bal.models)) :use use :targets targets :seq 0 :failedUntil (mapEmpty) :cooldownMs 60000 :observed (mapEmpty) :lanes (mapEmpty) :instance "local" :notes (list) :polls (list) :polledAt (mapEmpty) :holds (list))

fn laneOf pool: Pool alias: String -> String
  (mapGetOr pool.lanes alias "http")

; (:m :ref GW-BALANCER-CLI-LANES :do "the lane of a provider kind: a vendor CLI is a local login, so it is a lane only on a local instance and a remote one reaches it only through a gateway federation row; a provider dispatch cannot send to and that is no federation row is no lane")
fn laneFor kind: String routable: Bool instance: String -> (Option String)
  (cond
    ((= kind "cli") (if (= instance "local") (some "cli") (none)))
    ((= kind "gateway") (some "gateway"))
    (routable (some "http"))
    (else (none)))

fn laneBal pool: Pool lanes: (List String) -> Balancer
  (with pool.bal :models (filter (fn [(m PoolModel)] -> Bool (listContains? lanes (laneOf pool m.id))) pool.bal.models))

fn stringsOf expr: rd/SExpr -> (List String)
  (map (fn [(x rd/SExpr)] -> String (cfg/scalarToString (cfg/asnScalar x))) (listOf expr))

; (:m :do "a ledger row is charged to its alias when that is a pool model (the server writes the pool alias after a balancer dispatch, GW-BALANCER-ALIAS), else, for legacy rows written under a chat alias, to the first pool model whose upstream name it served, else left as it is")
fn resolveAliases targets: (Map String (Pair String String)) rows: (List ul/CallRow) -> (List ul/CallRow)
  (map (fn [(r ul/CallRow)] -> ul/CallRow
         (if (mapHas? targets r.alias)
           r
           (match (listFind (fn [(id String)] -> Bool (match (mapGet targets id) ((some t) (= (pairSecond t) r.model)) ((none) false))) (mapKeys targets))
             ((some id) (with r :alias id))
             ((none) r))))
       rows)

fn poolRequest pool: Pool intent: String atMs: Int64 tokens: Int64 -> Request
  (Request :seq (+ pool.seq 1) :atMs atMs :intent (if (stringEmpty? intent) "any" intent) :tokens (max 0 tokens))

; (:m :ref AUDIT10-A4 :do "a model with a budget a live 429 exhausted does not fit at any charge, a zero-cost request included, until that reset; failure rest only orders the rest and lifts when every model rests, exhaustion never lifts early")
fn exhaustedIds pool: Pool nowMs: Int64 -> (List String)
  (filter (fn [(id String)] -> Bool (match (mapGet pool.observed id) ((some o) (and o.exhausted (< nowMs o.resetAtMs))) ((none) false)))
          (mapKeys pool.observed))

; (:m :ref GW-BALANCER-CLI-LANES :do "picks among the models of the given lanes only; budgets stay shared across lanes, so a CLI call and an HTTP call drawing on one subscription pace each other")
fn poolPickLanes pool: Pool req: Request lanes: (List String) -> Pick
  (let [(bal (laneBal pool lanes))
        (dead (exhaustedIds pool req.atMs))
        (open (filter (fn [(m PoolModel)] -> Bool (not (listAny? (fn [(id String)] -> Bool (listContains? dead id)) m.budgets))) bal.models))
        (resting (fn [(m PoolModel)] -> Bool (> (mapGetOr pool.failedUntil m.id 0) req.atMs)))
        (awake (filter (fn [(m PoolModel)] -> Bool (not (resting m))) open))
        (admitted (filter (fn [(m PoolModel)] -> Bool (tierAdmitted? bal.policy.mode m.tier)) bal.models))
        (openAdmitted (filter (fn [(m PoolModel)] -> Bool (tierAdmitted? bal.policy.mode m.tier)) open))]
    (if (and (listEmpty? openAdmitted) (not (listEmpty? admitted)))
      (refused (str "every model in mode " (modeName bal.policy.mode) " is at its hard cap: " (stringJoin dead " ")))
      (pick (with bal :models (if (listEmpty? awake) open awake)) (effectiveUse pool req.atMs) req)))

fn effortSuffixes -> (List String)
  (list ":minimal" ":low" ":medium" ":high" ":xhigh")

; (:m :ref GW-HONOUR-NAME-MATCH :do "a model name without a trailing reasoning-effort suffix (gemini-3.8-flash:low is gemini-3.8-flash); other suffixes such as OpenRouter :free are part of the name and stay")
fn modelKey name: String -> String
  (match (listFind (fn [(s String)] -> Bool (and (stringEndsWith? name s) (> (stringLength name) (stringLength s)))) (effortSuffixes))
    ((some s) (optionOr (stringSlice name 0 (- (stringLength name) (stringLength s))) name))
    ((none) name))

; (:m :ref GW-MODEL-SUBSTITUTION :do "the http pool aliases a request already naming a model asks for: an alias whose id is the name, or whose target is that provider and :name exactly; failing those (GW-HONOUR-NAME-MATCH), the aliases on that provider whose :name equals it once an effort suffix is dropped from both")
fn poolAliasesFor pool: Pool provider: String model: String -> (List String)
  (let [(http (filter (fn [(m PoolModel)] -> Bool (= (laneOf pool m.id) "http")) pool.bal.models))
        (targetIs (fn [(m PoolModel) (same (fn [String] -> Bool))] -> Bool
                    (match (mapGet pool.targets m.id) ((some t) (and (= (pairFirst t) provider) (same (pairSecond t)))) ((none) false))))
        (exact (filter (fn [(m PoolModel)] -> Bool (or (= m.id model) (targetIs m (fn [(n String)] -> Bool (= n model))))) http))
        (loose (filter (fn [(m PoolModel)] -> Bool (targetIs m (fn [(n String)] -> Bool (= (modelKey n) (modelKey model))))) http))]
    (map (fn [(m PoolModel)] -> String m.id) (if (listEmpty? exact) loose exact)))

; (:m :ref GW-MODEL-SUBSTITUTION :do "honours a named model: picks among the asked aliases only, refused when every one is exhausted by a provider, resting after a failure, outside the mode or at its hard cap, so the caller may substitute and say so")
fn poolHonour pool: Pool req: Request ids: (List String) -> Pick
  (let [(dead (exhaustedIds pool req.atMs))
        (asked (filter (fn [(m PoolModel)] -> Bool (listContains? ids m.id)) (laneBal pool (list "http")).models))
        (live (filter (fn [(m PoolModel)] -> Bool (not (listAny? (fn [(id String)] -> Bool (listContains? dead id)) m.budgets))) asked))
        (awake (filter (fn [(m PoolModel)] -> Bool (<= (mapGetOr pool.failedUntil m.id 0) req.atMs)) live))
        (admitted (filter (fn [(m PoolModel)] -> Bool (tierAdmitted? pool.bal.policy.mode m.tier)) awake))]
    (cond
      ((listEmpty? asked) (refused "the asked model is no pool model"))
      ((listEmpty? live) (refused (str "the asked model " (stringJoin ids " ") " is exhausted by its provider: " (stringJoin dead " "))))
      ((listEmpty? awake) (refused (str "the asked model " (stringJoin ids " ") " rests after a failure")))
      ((listEmpty? admitted) (refused (str "mode " (modeName pool.bal.policy.mode) " does not admit the asked model " (stringJoin ids " "))))
      (else
        (match (pick (with pool.bal :models admitted) (effectiveUse pool req.atMs) req)
          ((refused _) (refused (str "the asked model " (stringJoin ids " ") " is at its hard cap: " (stringJoin (blockingBudgets (with pool.bal :models admitted) (effectiveUse pool req.atMs) req) " "))))
          (p p)))))

; (:m :ref GW-BALANCER-CLI-LANES :do "the dispatch pick: http lanes only, so an HTTP dispatch never retargets to a CLI or federation alias")
fn poolPick pool: Pool req: Request -> Pick
  (poolPickLanes pool req (list "http"))

fn poolFailed pool: Pool alias: String nowMs: Int64 -> Pool
  (if (mapHas? pool.targets alias)
    (with pool :failedUntil (mapSet pool.failedUntil alias (+ nowMs pool.cooldownMs)))
    pool)

fn poolTarget pool: Pool alias: String -> (Option (Pair String String))
  (mapGet pool.targets alias)

fn poolCharge pool: Pool alias: String atMs: Int64 tokens: Int64 -> Pool
  (if (listAny? (fn [(m PoolModel)] -> Bool (= m.id alias)) pool.bal.models)
    (with (with pool :use (chargeUse pool.bal pool.use alias atMs tokens)) :seq (+ pool.seq 1))
    pool)

; (:m :do "the score parts of a pick as one ASN form for the route receipt: pacing, tier weight, quality and its confidence and source, expected cost, score, and whether it was an exploration pick")
fn pickWhy pool: Pool req: Request p: Pick -> String
  (match p
    ((refused reason) (str "(:balancer :mode " (modeName pool.bal.policy.mode) " :refused \"" reason "\")"))
    ((picked id score q explore)
      (match (listFind (fn [(m PoolModel)] -> Bool (= m.id id)) pool.bal.models)
        ((none) (str "(:balancer :pick " id ")"))
        ((some m)
          (str "(:balancer :mode " (modeName pool.bal.policy.mode) " :pick " id " :tier " (tierName m.tier)
               " :pacing " (modelPacing pool.bal (effectiveUse pool req.atMs) m req.atMs) " :tierWeight " (tierWeight m.tier)
               " :quality " q.score " :confidence " q.confidence " :source \"" q.source "\""
               " :costMicros " m.costMicros " :score " score " :explore " (if explore "true" "false") ")")))))

; (:m :do "the 429 reply body: one ASN form naming the mode and every budget at its hard cap")
fn refusalText pool: Pool req: Request reason: String -> String
  (str "(:balancer :refused :mode " (modeName pool.bal.policy.mode) " :budgets (" (stringJoin (blockingBudgets (laneBal pool (list "http")) (effectiveUse pool req.atMs) req) " ") ") :reason \"" reason "\")")

fn ! readCals! paths: (List String) -> (Result (List CalScore) String)
  (fold (fn [(acc (Result (List CalScore) String)) (p String)] -> (Result (List CalScore) String)
          (match acc
            ((err e) (err e))
            ((ok xs)
              (if (not (fileExists? p))
                (ok xs)
                (match (fileReadString p)
                  ((err e) (err (str "cal " p ": " e)))
                  ((ok text) (ok (listAppend xs (parseCalScores text)))))))))
        (ok (list))
        paths)

(schema Lanes
  (:f targets (Map String (Pair String String)))
  (:f lanes (Map String String))
  (:f notes (List String)))

fn providerKind tbl: cfg/GatewayTable pid: String -> String
  (match (mapGet tbl.providers pid) ((some pv) pv.kind) ((none) ""))

; (:m :ref GW-BALANCER-CLI-LANES :do "every gateway model with a lane becomes a pool target; a CLI model on a remote instance leaves the pool with a note")
fn poolLanes table: (Option cfg/GatewayTable) routable: (fn [String] -> Bool) instance: String -> Lanes
  (match table
    ((none) (Lanes :targets (mapEmpty) :lanes (mapEmpty) :notes (list)))
    ((some tbl)
      (fold (fn [(acc Lanes) (id String)] -> Lanes
              (match (mapGet tbl.models id)
                ((none) acc)
                ((some gm)
                  (let [(kind (providerKind tbl gm.provider))]
                    (match (laneFor kind (routable gm.provider) instance)
                      ((some lane) (with (with acc :targets (mapSet acc.targets id (pair gm.provider gm.name))) :lanes (mapSet acc.lanes id lane)))
                      ((none) (if (= kind "cli") (with acc :notes (listAppend acc.notes (list (str id ": cli lane is local only, left out on instance " instance)))) acc)))))))
            (Lanes :targets (mapEmpty) :lanes (mapEmpty) :notes (list))
            tbl.modelOrder)))

fn subscriptionPaced? bal: Balancer m: PoolModel -> Bool
  (listAny? (fn [(b Budget)] -> Bool b.useOrLose) (modelBudgets bal m))

; (:m :ref GW-BALANCER-CLI-LANES :do "a vendor CLI runs on a subscription login, so its lane is tier sub whatever the row says and must draw on a use-or-lose budget; a CLI model with none would be unpaced and leaves the pool with a note")
fn withLanes pool: Pool ln: Lanes instance: String -> Pool
  (let [(lanePool (with (with (with pool :lanes ln.lanes) :instance instance) :notes ln.notes))
        (isCli (fn [(m PoolModel)] -> Bool (= (laneOf lanePool m.id) "cli")))
        (unpaced (filter (fn [(m PoolModel)] -> Bool (and (isCli m) (not (subscriptionPaced? pool.bal m)))) pool.bal.models))
        (kept (filter (fn [(m PoolModel)] -> Bool (not (and (isCli m) (not (subscriptionPaced? pool.bal m))))) pool.bal.models))
        (subbed (map (fn [(m PoolModel)] -> PoolModel (if (isCli m) (with m :tier tierSub) m)) kept))]
    (with (with lanePool :bal (with pool.bal :models subbed))
          :notes (listAppend ln.notes (map (fn [(m PoolModel)] -> String (str m.id ": cli lane names no use-or-lose budget, left out unpaced")) unpaced))))

; (:m :do "none when the gateway form has no balancer section, so dispatch keeps its old routing; CAL files default to the workspace freeModels ledger and a missing file only lowers confidence; routable says which providers dispatch can send to, other models leave the pool; :instance local (the default) or remote decides whether vendor CLI rows are cli lanes, GW-BALANCER-CLI-LANES")
fn prependNote pool: Pool note: String -> Pool
  (with pool :notes (listAppend (list note) pool.notes))

fn lastOf xs: (List String) -> String
  (optionOr (listGet xs (- (listLength xs) 1)) "")

; (:m :ref GW-BALANCER-INSTANCE-DETECT :do "the host of a provider base url: scheme, userinfo, path and port dropped, an IPv6 literal without its brackets")
fn urlHost url: String -> String
  (let [(rest (cond
                ((stringStartsWith? url "https://") (optionOr (stringSlice url 8 (stringLength url)) ""))
                ((stringStartsWith? url "http://") (optionOr (stringSlice url 7 (stringLength url)) ""))
                (else url)))
        (authority (lastOf (stringSplit (optionOr (listGet (stringSplit rest "/") 0) "") "@")))]
    (if (stringStartsWith? authority "[")
      (optionOr (listGet (stringSplit (optionOr (stringSlice authority 1 (stringLength authority)) "") "]") 0) "")
      (optionOr (listGet (stringSplit authority ":") 0) "")))

; (:m :ref GW-BALANCER-INSTANCE-DETECT :do "the instance and the rule that decided it: an explicit :instance wins; a gateway row means this instance forwards to a host gateway (often through a loopback tunnel, so its url host proves nothing), which keeps the vendor CLI lanes; a gateway with no HOME runs as no local user whose vendor CLI logins could serve; otherwise local")
fn deriveInstance sec: (Map String rd/SExpr) table: (Option cfg/GatewayTable) home: String -> (Pair String String)
  (deriveInstanceWithRoles sec table home (mapEmpty))

; (:m :ref GW-INSTANCE-DIRECTION :do "the :role of each gateway provider row in the raw gateway form, read here because config.asl keeps no such field: satellite says this instance forwards to that row's host gateway, outward says this host federates out to that row")
fn gatewayRoles top: (Map String rd/SExpr) -> (Map String String)
  (fold (fn [(acc (Map String String)) (f rd/SExpr)] -> (Map String String)
          (match (cfg/asnProps f (some ":provider"))
            ((err _) acc)
            ((ok p) (if (mapHas? p "role") (mapSet acc (propStr p "id" "") (propStr p "role" "")) acc))))
        (mapEmpty)
        (match (mapGet top "providers") ((some e) (listOf e)) ((none) (list))))

; (:m :ref GW-INSTANCE-DIRECTION :do "an explicit :instance wins; a gateway row marked :role outward points from this host to a satellite or peer and leaves the instance local; a row marked :role satellite, or unmarked (the safe reading for a config copied to a VPS), makes it remote; no HOME is remote; otherwise local")
fn deriveInstanceWithRoles sec: (Map String rd/SExpr) table: (Option cfg/GatewayTable) home: String roles: (Map String String) -> (Pair String String)
  (match (mapGet sec "instance")
    ((some e)
      (let [(v (cfg/scalarToString (cfg/asnScalar e)))]
        (pair v (str "instance " v ": declared by :instance"))))
    ((none)
      (let [(remoteRows (match table
                          ((none) (list))
                          ((some tbl) (filter (fn [(pv cfg/GatewayProvider)] -> Bool (and (= pv.kind "gateway") (!= (mapGetOr roles pv.id "") "outward")))
                                              (map (fn [(id String)] -> cfg/GatewayProvider (optionOr (mapGet tbl.providers id) (cfg/GatewayProvider :rpmShared false :dropEmptyTools false :assistantReasoning false :id "" :kind "" :base "" :keyEnv "" :secret "" :promptCacheKey false :sessionHeader "" :timeoutSec 0.0 :firstByteSec 0.0 :rpm 0.0 :pool (none) :retry (none))))
                                                   (mapKeys tbl.providers))))))]
        (match (listGet remoteRows 0)
          ((some pv) (pair "remote" (str "instance remote: provider " pv.id " is a gateway row to " (urlHost pv.base)
                                         (if (= (mapGetOr roles pv.id "") "satellite") " marked :role satellite" " with no :role outward")
                                         ", so vendor CLI lanes stay with that host gateway")))
          ((none)
            (if (stringEmpty? home)
              (pair "remote" "instance remote: no HOME, so no local user whose vendor CLI logins could serve a cli lane")
              (pair "local" (if (listEmpty? (mapKeys (filterRoles roles "outward"))) "instance local: no gateway row and a local user HOME" (str "instance local: gateway rows " (stringJoin (mapKeys (filterRoles roles "outward")) " ") " are :role outward and a local user HOME")))))))))

fn filterRoles roles: (Map String String) role: String -> (Map String String)
  (fold (fn [(acc (Map String String)) (id String)] -> (Map String String) (if (= (mapGetOr roles id "") role) (mapSet acc id role) acc)) (mapEmpty) (mapKeys roles))

; (:m :ref GW-LEDGER-READ-COST :do "the earliest call any budget can still count at nowMs: the start of each budget's current window, its anchor for a lifetime budget; loadPool! passes the newest ledger call, since no later request can count a row of an earlier window and the balancer keeps no clock of its own, so older generations stay closed")
fn ledgerSinceMs bal: Balancer nowMs: Int64 -> Int64
  (fold (fn [(acc Int64) (b Budget)] -> Int64 (min acc (windowStart b nowMs))) nowMs (mapValues bal.budgets))

fn ! loadPool! text: String table: (Option cfg/GatewayTable) home: String routable: (fn [String] -> Bool) -> (Result (Option Pool) String)
  (let [(form (rd/parseSexpr text))]
    (match (cfg/asnProps form (some ":gateway"))
      ((err _) (ok none))
      ((ok top)
        (match (mapGet top "balancer")
          ((none) (ok none))
          ((some secExpr)
            (match (cfg/asnProps secExpr (some ":balancer"))
              ((err e) (err e))
              ((ok sec)
                (match (readCals! (match (mapGet sec "cal") ((some e) (stringsOf e)) ((none) (list ".asl/mem/work/CAL/freeModels.asn" ".asl/mem/work/SH/workerStats.asn"))))
                  ((err e) (err e))
                  ((ok cals)
                    (match (parseBalancer form cals)
                      ((err e) (err e))
                      ((ok bal)
                        (let [(decided (deriveInstanceWithRoles sec table home (gatewayRoles top)))
                              (instance (pairFirst decided))
                              (ln (poolLanes table routable instance))
                              (targets ln.targets)
                              (ledger (match (mapGet sec "ledger")
                                        ((some e) (cfg/scalarToString (cfg/asnScalar e)))
                                        ((none) (optionOr (cfg/gatewaySharedUsagePathOverride text) (ul/defaultSharedUsagePath home)))))]
                          (match (match (ul/windowReadNewest! ledger (fn [(newest Int64)] -> Int64 (ledgerSinceMs bal newest))) ((ok got) (ok (pairSecond got))) ((err e) (err e)))
                            ((err e) (err (str "usage ledger " ledger ": " e)))
                            ((ok rows)
                              (match (propInt sec "failCooldownMs" 60000)
                                ((err e) (err e))
                                ((ok cool)
                                  (if (not (listContains? (list "local" "remote") instance))
                                    (err (str "balancer: :instance is local or remote, not " instance))
                                    (match (pollsOf table (match (mapGet sec "budgets") ((some e) (listOf e)) ((none) (list))))
                                      ((err e) (err e))
                                      ((ok polls) (ok (some (prependNote (with (withLanes (with (poolFromParts bal (usageFromCalls bal (resolveAliases targets rows)) targets) :cooldownMs (max 0 cool)) ln instance) :polls polls) (pairSecond decided)))))))))))))))))))))))

; (:m :ref GW-BALANCER-STATUS-POLL :do "adopted values: a poll every 5 minutes unless the row says otherwise, and never more than one a minute per budget, so a short :everyMs cannot hammer a status endpoint")
fn defaultPollMs -> Int64 300000

fn minPollMs -> Int64 60000

fn trimSlash s: String -> String
  (if (stringEndsWith? s "/") (trimSlash (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")) s)

; (:m :ref GW-BALANCER-STATUS-POLL :do "a budget row may carry (:poll :provider P :path \"/key\" :everyMs N); only an endpoint usd budget can be refreshed by a poll, and its provider must be a gateway row with a base")
fn pollOf table: (Option cfg/GatewayTable) form: rd/SExpr -> (Result (List Poll) String)
  (match (cfg/asnProps form (some ":budget"))
    ((err e) (err e))
    ((ok p)
      (match (mapGet p "poll")
        ((none) (ok (list)))
        ((some pe)
          (let [(id (propStr p "id" ""))]
            (match (cfg/asnProps pe (some ":poll"))
              ((err e) (err (str "balancer: budget " id " poll: " e)))
              ((ok q)
                (let [(pid (propStr q "provider" ""))
                      (path (propStr q "path" ""))
                      (base (match table ((some tbl) (match (mapGet tbl.providers pid) ((some pv) pv.base) ((none) ""))) ((none) "")))]
                  (cond
                    ((or (!= (propStr p "source" "declared") "endpoint") (!= (propStr p "unit" "req") "usd"))
                      (err (str "balancer: budget " id " polls a status endpoint, so it needs :source endpoint :unit usd")))
                    ((stringEmpty? base) (err (str "balancer: budget " id " polls provider " pid ", which is no gateway provider with a :base")))
                    ((not (stringStartsWith? path "/")) (err (str "balancer: budget " id " poll :path must start with /")))
                    (else
                      (match (propInt q "everyMs" (defaultPollMs))
                        ((err e) (err e))
                        ((ok every) (ok (list (Poll :budget id :provider pid :url (str (trimSlash base) path) :everyMs (max (minPollMs) every))))))))))))))))

fn pollsOf table: (Option cfg/GatewayTable) forms: (List rd/SExpr) -> (Result (List Poll) String)
  (fold (fn [(acc (Result (List Poll) String)) (f rd/SExpr)] -> (Result (List Poll) String)
          (match acc
            ((err e) (err e))
            ((ok xs) (match (pollOf table f) ((ok ys) (ok (listAppend xs ys))) ((err e) (err e))))))
        (ok (list))
        forms)

; (:m :ref GW-BALANCER-STATUS-POLL :do "the polls to send now: a budget some pool model draws on, whose last poll is at least everyMs ago; the caller sends each through its provider and marks it with poolPolled first, so a slow reply is never polled twice")
fn pollsDue pool: Pool nowMs: Int64 -> (List Poll)
  (filter (fn [(p Poll)] -> Bool
            (and (listAny? (fn [(m PoolModel)] -> Bool (listContains? m.budgets p.budget)) pool.bal.models)
                 (match (mapGet pool.polledAt p.budget) ((some at) (>= nowMs (+ at p.everyMs))) ((none) true))))
          pool.polls)

fn poolPolled pool: Pool budgetId: String nowMs: Int64 -> Pool
  (with pool :polledAt (mapSet pool.polledAt budgetId nowMs))

; (:m :ref GW-BALANCER-STATUS-POLL :do "a status reply: 200 feeds poolObserveEndpoint, 429 backs the next poll off to four intervals, anything else keeps the last observation; the string is empty on success, else why the budget was not refreshed")
fn poolPollReply pool: Pool budgetId: String status: Int64 body: String nowMs: Int64 -> (Pair Pool String)
  (let [(every (match (listFind (fn [(p Poll)] -> Bool (= p.budget budgetId)) pool.polls) ((some p) p.everyMs) ((none) (minPollMs))))
        (marked (with pool :polledAt (mapSet pool.polledAt budgetId (if (= status 429) (+ nowMs (* 3 every)) nowMs))))]
    (cond
      ((= status 200)
        (match (poolObserveEndpoint marked budgetId body nowMs)
          ((ok p) (pair p ""))
          ((err e) (pair marked e))))
      ((= status 429) (pair marked (str "status poll for " budgetId " was rate limited, next in " (* 4 every) " ms")))
      (else (pair marked (str "status poll for " budgetId " answered " status)))))

; (:m :ref GW-BALANCER-LIVE-QUOTA :do "remaining is in the budget unit, resetAtMs 0 means unknown (valid to the end of the budget window), exhausted holds the budget at its hard cap until resetAtMs")
(schema Observed
  (:f remaining Int64)
  (:f resetAtMs Int64)
  (:f atMs Int64)
  (:f exhausted Bool))

(schema RateObs
  (:f unit String)
  (:f remaining Int64)
  (:f resetAtMs Int64))

fn headerGet headers: (List (Pair String String)) name: String -> (Option String)
  (match (listFind (fn [(h (Pair String String))] -> Bool (= (stringLower (stringTrim (pairFirst h))) name)) headers)
    ((some h) (some (stringTrim (pairSecond h))))
    ((none) none))

fn wholeInt s: String -> (Option Int64)
  (match (stringToInt64 s)
    ((some n) (some n))
    ((none) (match (stringToFloat64 s) ((some f) (float64ToInt64 f)) ((none) none))))

fn durationPart s: String unit: String -> (Option Int64)
  (match (stringToFloat64 s)
    ((none) none)
    ((some f)
      (float64ToInt64 (* f (cond ((= unit "h") 3600000.0) ((= unit "m") 60000.0) ((= unit "s") 1000.0) (else 1.0))))))

; (:m :do "reads 1s, 6m0s, 2m59.56s, 120ms, 1h2m3s and a bare number of seconds; anything else is none")
fn parseDurationMs s: String -> (Option Int64)
  (let [(text (stringTrim s))
        (n (stringLength text))
        (step (fn [(st (Pair (Pair Int64 String) Bool)) (i Int64)] -> (Pair (Pair Int64 String) Bool)
                (let [(acc (pairFirst (pairFirst st)))
                      (num (pairSecond (pairFirst st)))
                      (c (optionOr (stringSlice text i (+ i 1)) ""))
                      (next (optionOr (stringSlice text (+ i 1) (+ i 2)) ""))]
                  (cond
                    ((not (pairSecond st)) st)
                    ((or (stringContains? "0123456789." c)) (pair (pair acc (str num c)) true))
                    ((and (= c "m") (= next "s")) (pair (pair acc (str num "#ms")) true))
                    ((= c "s")
                      (if (stringEndsWith? num "#ms")
                        (match (durationPart (stringReplace num "#ms" "") "ms") ((some v) (pair (pair (+ acc v) "") true)) ((none) (pair (pair acc num) false)))
                        (match (durationPart num "s") ((some v) (pair (pair (+ acc v) "") true)) ((none) (pair (pair acc num) false)))))
                    ((or (= c "h") (= c "m"))
                      (match (durationPart num c) ((some v) (pair (pair (+ acc v) "") true)) ((none) (pair (pair acc num) false))))
                    (else (pair (pair acc num) false))))))
        (done (fold step (pair (pair 0 "") true) (range 0 n)))]
    (cond
      ((= n 0) none)
      ((not (pairSecond done)) none)
      ((stringEmpty? (pairSecond (pairFirst done))) (some (pairFirst (pairFirst done))))
      ((= (pairFirst (pairFirst done)) 0) (durationPart (pairSecond (pairFirst done)) "s"))
      (else none)))

fn daysFromCivil y: Int64 m: Int64 d: Int64 -> Int64
  (let [(y1 (if (<= m 2) (- y 1) y))
        (era (/ (if (>= y1 0) y1 (- y1 399)) 400))
        (yoe (- y1 (* era 400)))
        (mp (if (> m 2) (- m 3) (+ m 9)))
        (doy (+ (/ (+ (* 153 mp) 2) 5) (- d 1)))
        (doe (+ (* yoe 365) (/ yoe 4) (- 0 (/ yoe 100)) doy))]
    (+ (* era 146097) doe -719468))

fn sliceInt s: String i: Int64 j: Int64 -> (Option Int64)
  (match (stringSlice s i j) ((some t) (stringToInt64 t)) ((none) none))

; (:m :do "UTC timestamps as anthropic sends them: 2026-10-27T12:00:00Z, with optional fraction and a Z or +00:00 suffix; other offsets are none rather than a wrong instant")
fn parseRfc3339Ms s: String -> (Option Int64)
  (let [(t (stringTrim s))
        (tail (optionOr (stringSlice t 19 (stringLength t)) ""))
        (utc (or (stringEndsWith? tail "Z") (stringEndsWith? tail "+00:00") (stringEmpty? tail)))
        (fracMs (if (stringStartsWith? tail ".")
                  (let [(digits (stringReplace (stringReplace tail "Z" "") "+00:00" ""))]
                    (match (stringToFloat64 (str "0" digits)) ((some f) (optionOr (float64ToInt64 (* f 1000.0)) 0)) ((none) 0)))
                  0))
        (y (optionOr (sliceInt t 0 4) -1)) (mo (optionOr (sliceInt t 5 7) -1)) (d (optionOr (sliceInt t 8 10) -1))
        (h (optionOr (sliceInt t 11 13) -1)) (mi (optionOr (sliceInt t 14 16) -1)) (sec (optionOr (sliceInt t 17 19) -1))]
    (if (and utc (= (optionOr (stringSlice t 10 11) "") "T") (>= y 0) (>= mo 1) (<= mo 12) (>= d 1) (<= d 31) (>= h 0) (<= h 23) (>= mi 0) (<= mi 59) (>= sec 0) (<= sec 60))
      (some (+ (* (+ (* (+ (* (daysFromCivil y mo d) 24) h) 60) mi) 60000) (* sec 1000) fracMs))
      none))

fn resetAt value: (Option String) nowMs: Int64 -> Int64
  (match value
    ((none) 0)
    ((some v)
      (match (parseDurationMs v)
        ((some ms) (+ nowMs ms))
        ((none) (optionOr (parseRfc3339Ms v) 0)))))

fn obsFrom headers: (List (Pair String String)) unit: String remainingName: String resetName: String nowMs: Int64 -> (List RateObs)
  (match (headerGet headers remainingName)
    ((none) (list))
    ((some v)
      (match (wholeInt v)
        ((some n) (list (RateObs :unit unit :remaining (max 0 n) :resetAtMs (resetAt (headerGet headers resetName) nowMs))))
        ((none) (list)))))

; (:m :do "OpenAI and Groq send x-ratelimit-remaining-requests/tokens with x-ratelimit-reset-* durations, Anthropic sends anthropic-ratelimit-requests/tokens-remaining with RFC 3339 resets; the first family present wins per unit")
fn parseRateHeaders headers: (List (Pair String String)) nowMs: Int64 -> (List RateObs)
  (let [(req (obsFrom headers "req" "x-ratelimit-remaining-requests" "x-ratelimit-reset-requests" nowMs))
        (tok (obsFrom headers "tok" "x-ratelimit-remaining-tokens" "x-ratelimit-reset-tokens" nowMs))
        (aReq (obsFrom headers "req" "anthropic-ratelimit-requests-remaining" "anthropic-ratelimit-requests-reset" nowMs))
        (aTok (obsFrom headers "tok" "anthropic-ratelimit-tokens-remaining" "anthropic-ratelimit-tokens-reset" nowMs))]
    (listAppend (if (listEmpty? req) aReq req) (if (listEmpty? tok) aTok tok)))

fn monthNumber name: String -> Int64
  (match (listFind (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) name))
                   (list (pair "Jan" 1) (pair "Feb" 2) (pair "Mar" 3) (pair "Apr" 4) (pair "May" 5) (pair "Jun" 6)
                         (pair "Jul" 7) (pair "Aug" 8) (pair "Sep" 9) (pair "Oct" 10) (pair "Nov" 11) (pair "Dec" 12)))
    ((some p) (pairSecond p))
    ((none) 0))

; (:m :ref GW-BALANCER-RETRYAFTER-DATE :do "the IMF-fixdate form RFC 9110 requires of senders: Wed, 21 Oct 2015 07:28:00 GMT; the obsolete RFC 850 and asctime forms, and any zone but GMT, are none rather than a wrong instant")
fn parseHttpDateMs s: String -> (Option Int64)
  (let [(parts (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit (stringTrim s) " ")))
        (at (fn [(i Int64)] -> String (optionOr (listGet parts i) "")))
        (clock (stringSplit (at 4) ":"))
        (part (fn [(i Int64)] -> Int64 (optionOr (stringToInt64 (optionOr (listGet clock i) "")) -1)))
        (d (optionOr (stringToInt64 (at 1)) -1))
        (mo (monthNumber (at 2)))
        (y (optionOr (stringToInt64 (at 3)) -1))
        (h (part 0)) (mi (part 1)) (sec (part 2))]
    (if (and (= (listLength parts) 6) (stringEndsWith? (at 0) ",") (= (stringLength (at 1)) 2) (= (stringLength (at 3)) 4) (= (listLength clock) 3) (= (at 5) "GMT")
             (>= mo 1) (>= d 1) (<= d 31) (>= y 0) (>= h 0) (<= h 23) (>= mi 0) (<= mi 59) (>= sec 0) (<= sec 60))
      (some (+ (* (+ (* (+ (* (daysFromCivil y mo d) 24) h) 60) mi) 60000) (* sec 1000)))
      none))

; (:m :ref GW-BALANCER-RETRYAFTER-DATE :do "the delay a Retry-After header asks for: delay-seconds, or an HTTP-date taken against nowMs, a date already past being no delay")
fn retryAfterMs headers: (List (Pair String String)) nowMs: Int64 -> (Option Int64)
  (match (headerGet headers "retry-after")
    ((none) none)
    ((some v)
      (match (wholeInt v)
        ((some secs) (some (* 1000 (max 0 secs))))
        ((none) (match (parseHttpDateMs v) ((some at) (some (max 0 (- at nowMs)))) ((none) none))))))

; (:m :ref GW-BALANCER-HEADER-WINDOW :do "a header observation for a header-sourced budget; with a declared :headerWindow its reset must lie within it (a second of slack, adopted), and a header window shorter than the budget window only records exhaustion at zero remaining")
fn headerObserved acc: (Map String Observed) b: Budget o: RateObs nowMs: Int64 -> (Map String Observed)
  (let [(horizon (if (> o.resetAtMs nowMs) (- o.resetAtMs nowMs) 0))
        (declared (> b.headerWindowMs 0))
        (beyond (and declared (> horizon (+ b.headerWindowMs 1000))))
        (shorter (and declared (< b.headerWindowMs b.windowMs)))]
    (cond
      (beyond acc)
      (shorter
        (if (= o.remaining 0)
          (mapSet acc b.id (Observed :remaining 0 :resetAtMs (if (> o.resetAtMs nowMs) o.resetAtMs (+ nowMs b.headerWindowMs)) :atMs nowMs :exhausted true))
          acc))
      (else (mapSet acc b.id (Observed :remaining o.remaining :resetAtMs o.resetAtMs :atMs nowMs :exhausted false)))))

fn modelOf pool: Pool alias: String -> (Option PoolModel)
  (listFind (fn [(m PoolModel)] -> Bool (= m.id alias)) pool.bal.models)

; (:m :do "after an upstream reply: a 429 marks every budget of the model exhausted until retry-after, else the reported reset, else the end of the budget window; any other reply refreshes each header-sourced budget from the header of its unit")
fn poolObserve pool: Pool alias: String status: Int64 headers: (List (Pair String String)) nowMs: Int64 -> Pool
  (match (modelOf pool alias)
    ((none) pool)
    ((some m)
      (let [(obs (parseRateHeaders headers nowMs))
            (retry (retryAfterMs headers nowMs))]
        (with pool :observed
          (fold (fn [(acc (Map String Observed)) (b Budget)] -> (Map String Observed)
                  (let [(mine (listFind (fn [(o RateObs)] -> Bool (= o.unit b.unit)) obs))]
                    (if (= status 429)
                      (let [(windowEnd (+ (windowStart b nowMs) b.windowMs))
                            (until (match retry
                                     ((some ms) (+ nowMs ms))
                                     ((none) (match mine ((some o) (if (> o.resetAtMs nowMs) o.resetAtMs windowEnd)) ((none) windowEnd)))))]
                        (mapSet acc b.id (Observed :remaining 0 :resetAtMs until :atMs nowMs :exhausted true)))
                      (match mine
                        ((some o) (if (= b.source "header") (headerObserved acc b o nowMs) acc))
                        ((none) acc)))))
                pool.observed
                (modelBudgets pool.bal m))))))

fn jsonNumber v: (Option j/Json) -> (Option Float64)
  (match v
    ((some (j/jint n)) (some (int64ToFloat64 n)))
    ((some (j/jfloat f)) (some f))
    ((some (j/jnum f)) (some f))
    ((some (j/jstr t)) (stringToFloat64 (stringTrim t)))
    (_ none))

; (:m :do "a status poll body in OpenRouter shape: /api/v1/key data.limit_remaining or /api/v1/credits data.total_credits - data.total_usage, or in Vercel AI Gateway shape: /v1/credits balance, a number or a decimal string (GW-BALANCER-STATUS-POLL), in USD, applied as microUSD remaining to an endpoint-sourced usd budget; any other body or budget is an error, never a silent zero")
fn poolObserveEndpoint pool: Pool budgetId: String body: String nowMs: Int64 -> (Result Pool String)
  (match (mapGet pool.bal.budgets budgetId)
    ((none) (err (str "balancer: no budget " budgetId)))
    ((some b)
      (if (or (!= b.source "endpoint") (!= b.unit "usd"))
        (err (str "balancer: budget " budgetId " is not an endpoint usd budget"))
        (match (j/jsonParse body)
          ((err e) (err (str "balancer: status body is not JSON: " e)))
          ((ok v)
            (let [(left (match (j/jsonGet v "data")
                          ((none) (jsonNumber (j/jsonGet v "balance")))
                          ((some d)
                            (match (jsonNumber (j/jsonGet d "limit_remaining"))
                              ((some f) (some f))
                              ((none) (match (pair (jsonNumber (j/jsonGet d "total_credits")) (jsonNumber (j/jsonGet d "total_usage")))
                                        ((pair (some c) (some u)) (some (- c u)))
                                        (_ none)))))))]
                  (match left
                    ((none) (err "balancer: status body has none of data.limit_remaining, data.total_credits with data.total_usage, or balance"))
                    ((some usd)
                      (ok (with pool :observed (mapSet pool.observed budgetId
                                                 (Observed :remaining (max 0 (optionOr (float64ToInt64 (* usd 1000000.0)) 0)) :resetAtMs 0 :atMs nowMs :exhausted false))))))))))))

; (:m :do "usage the pick sees: the ledger count raised to what the provider reports, so pacing follows min(ledger remaining, observed remaining); an observation from an earlier budget window or past its reset is ignored, an exhausted budget sits at its hard cap until its reset")
; (:m :ref AUDIT11-A3 :do "adopted: a hold no settle has released lapses after 10 minutes, past the longest provider timeout, so a request whose reply never settles cannot pin a budget for the rest of its window")
fn holdMs -> Int64 600000

fn liveHolds pool: Pool nowMs: Int64 -> (List Hold)
  (filter (fn [(h Hold)] -> Bool (and (<= h.atMs nowMs) (< nowMs (+ h.atMs (holdMs))))) pool.holds)

; (:m :ref AUDIT11-A3 :do "reserves the estimated charge of a pick at plan time; a non-pool alias holds nothing")
fn poolReserve pool: Pool alias: String atMs: Int64 tokens: Int64 -> Pool
  (if (listAny? (fn [(m PoolModel)] -> Bool (= m.id alias)) pool.bal.models)
    (with pool :holds (listAppend (liveHolds pool atMs) (list (Hold :alias alias :atMs atMs :tokens (max 0 tokens)))))
    pool)

; (:m :ref AUDIT11-A3 :do "drops the oldest hold of the alias, done at settle before the actual charge, so settle charges actual minus estimate and a lower actual frees the difference; GW-HOLD-PRUNE: without a clock it takes the newest hold as now, so a hold already lapsed beside it is pruned rather than released in place of the live one")
fn poolRelease pool: Pool alias: String -> Pool
  (poolReleaseAt pool alias (fold (fn [(acc Int64) (h Hold)] -> Int64 (max acc h.atMs)) 0 pool.holds))

; (:m :ref GW-HOLD-PRUNE :do "prunes holds lapsed at nowMs, then drops the oldest live hold of the alias")
fn poolReleaseAt pool: Pool alias: String nowMs: Int64 -> Pool
  (let [(step (fn [(acc (Pair (List Hold) Bool)) (h Hold)] -> (Pair (List Hold) Bool)
                (if (and (not (pairSecond acc)) (= h.alias alias))
                  (pair (pairFirst acc) true)
                  (pair (listAppend (pairFirst acc) (list h)) (pairSecond acc)))))]
    (with pool :holds (pairFirst (fold step (pair (list) false) (liveHolds pool nowMs)))))

; (:m :ref AUDIT11-A3 :do "usage the pick sees: observed usage plus every live hold, so K concurrent picks against one hard budget admit only what fits")
fn effectiveUse pool: Pool nowMs: Int64 -> (Map String Window)
  (fold (fn [(acc (Map String Window)) (h Hold)] -> (Map String Window) (chargeUse pool.bal acc h.alias h.atMs h.tokens))
        (observedUse pool nowMs)
        (liveHolds pool nowMs))

fn observedUse pool: Pool nowMs: Int64 -> (Map String Window)
  (fold (fn [(acc (Map String Window)) (id String)] -> (Map String Window)
          (match (pair (mapGet pool.bal.budgets id) (mapGet pool.observed id))
            ((pair (some b) (some o))
              (let [(live (or (= o.resetAtMs 0) (< nowMs o.resetAtMs)))
                    (sameWindow (= (windowStart b o.atMs) (windowStart b nowMs)))
                    (ledger (budgetUsed acc b nowMs))
                    (used (cond
                            ((and o.exhausted live) (max ledger (hardCap b)))
                            ((and (not o.exhausted) live sameWindow) (max ledger (- b.size o.remaining)))
                            (else ledger)))]
                (mapSet acc id (Window :start (windowStart b nowMs) :used used))))
            (_ acc)))
        pool.use
        (mapKeys pool.observed))
