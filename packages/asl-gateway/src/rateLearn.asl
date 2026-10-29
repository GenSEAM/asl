(module aslGateway/rateLearn
  :x [Spec Counts countsOf nextRpm clampTotal learnAll storeText parseStore readStore! writeStore! stepShare backoffFactor hiShare]
  :i [(aslGateway/subPace :a sp)])

; (:m :ref GW-RPM-AIMD :do "pure learner for the gateway's own per-alias :rpm bucket: the configured :rpm is the start, a window of usage-ledger calls that were throttled by our bucket and drew no 429 raises the rate by stepShare of the start, a 429 share above hiShare multiplies it by backoffFactor, the result stays within start/4 and :rpmMax, and one provider :rpmTotal bounds the sum over its aliases; no clock, the store file is read and written through explicit paths")

(schema Spec
  (:f alias String) (:f provider String) (:f start Float64) (:f max Float64))

(schema Counts
  (:f calls Int64) (:f throttled Int64) (:f real429 Int64))

; (:m :do "adopted: additive step 20 percent of the start, multiplicative back-off 0.7, a 429 share above 2 percent of the alias calls is a limit hit")
fn stepShare -> Float64
  0.2

fn backoffFactor -> Float64
  0.7

fn hiShare -> Float64
  0.02

fn quoted line: String key: String -> String
  (sp/quotedAfter line key)

; (:m :ref GW-RPM-AIMD :do "same rule as asl/tools/coord/sched.asl notSent?: a row the gateway answered itself without a request (open breaker, skipped member, daily cap) is not a call; kept here so the gateway package does not import the tools tree")
fn notSent? o: String -> Bool
  (or (stringStartsWith? o "breaker") (or (stringStartsWith? o "skipped") (stringStartsWith? o "daily")))

fn rowAt line: String -> Int64
  (optionOr (stringToInt64 (sp/tokAfter line ":at")) -1)

; (:m :ref GW-RPM-AIMD :do "calls of one alias with fromMs <= at < toMs: all sent calls, those our bucket throttled and those the provider answered 429")
fn countsOf lines: (List String) alias: String fromMs: Int64 toMs: Int64 -> Counts
  (fold (fn [(c Counts) (l String)] -> Counts
          (let [(at (rowAt l))
                (o (quoted l ":outcome"))]
            (if (and (stringStartsWith? l "(:call ") (and (>= at fromMs) (and (< at toMs) (and (= (quoted l ":alias") alias) (not (notSent? o))))))
              (Counts :calls (+ c.calls 1) :throttled (+ c.throttled (if (= o "throttled") 1 0)) :real429 (+ c.real429 (if (= o "429") 1 0)))
              c)))
        (Counts :calls 0 :throttled 0 :real429 0) lines)

fn clampF x: Float64 lo: Float64 hi: Float64 -> Float64
  (if (< x lo) lo (if (> x hi) hi x))

; (:m :ref GW-RPM-AIMD :do "max 0.0 means no :rpmMax; a window with a 429 share above hiShare decreases, one with throttled rows and no 429 increases, anything else holds; always within start/4 and max")
fn nextRpm cur: Float64 start: Float64 max: Float64 c: Counts -> Float64
  (let [(hi (if (> max 0.0) max (floatInf)))
        (lo (/ start 4.0))
        (share (if (> c.calls 0) (/ (int64ToFloat64 c.real429) (int64ToFloat64 c.calls)) 0.0))
        (raw (cond
               ((and (> c.real429 0) (> share (hiShare))) (* cur (backoffFactor)))
               ((and (= c.real429 0) (> c.throttled 0)) (+ cur (* start (stepShare))))
               (else cur)))]
    (clampF raw lo hi))

fn specProvider p: (Pair Spec Float64) -> String
  (let [(s (pairFirst p))] s.provider)

fn specAlias p: (Pair Spec Float64) -> String
  (let [(s (pairFirst p))] s.alias)

; (:m :ref GW-RPM-AIMD :do "a provider :rpmTotal scales the learned rates of its aliases down together when their sum exceeds it, each keeping its start/4 floor; total 0.0 means no total")
fn clampTotal rates: (List (Pair Spec Float64)) total: Float64 -> (List (Pair Spec Float64))
  (let [(sum (fold (fn [(s Float64) (p (Pair Spec Float64))] -> Float64 (+ s (pairSecond p))) 0.0 rates))]
    (if (or (<= total 0.0) (<= sum total))
      rates
      (map (fn [(p (Pair Spec Float64))] -> (Pair Spec Float64)
             (let [(sp1 (pairFirst p))]
               (pair sp1 (max (/ sp1.start 4.0) (* (pairSecond p) (/ total sum))))))
           rates)))

; (:m :ref GW-RPM-AIMD :do "one learning step over every spec: cur holds the stored rates (absent means the start), totals maps a provider to its :rpmTotal; returns the new rate per alias")
fn learnAll specs: (List Spec) cur: (Map String Float64) lines: (List String) fromMs: Int64 toMs: Int64 totals: (Map String Float64) -> (Map String Float64)
  (let [(stepped (map (fn [(s Spec)] -> (Pair Spec Float64)
                        (pair s (nextRpm (mapGetOr cur s.alias s.start) s.start s.max (countsOf lines s.alias fromMs toMs))))
                      specs))
        (providers (mapKeys (mapFromPairs (map (fn [(s Spec)] -> (Pair String Bool) (pair s.provider true)) specs))))
        (clamped (listFlatMap (fn [(prov String)] -> (List (Pair Spec Float64))
                            (clampTotal (filter (fn [(p (Pair Spec Float64))] -> Bool (= (specProvider p) prov)) stepped) (mapGetOr totals prov 0.0)))
                          providers))]
    (mapFromPairs (map (fn [(p (Pair Spec Float64))] -> (Pair String Float64) (pair (specAlias p) (pairSecond p))) clamped)))

fn storeText rates: (Map String Float64) -> String
  (stringJoin (map (fn [(p (Pair String Float64))] -> String
                     (str "(:rate :alias \"" (pairFirst p) "\" :rpm " (stringFromFloat64 (pairSecond p)) ")\n"))
                   (mapPairs rates)) "")

fn parseStore text: String -> (Map String Float64)
  (mapFromPairs
    (listFlatMap (fn [(l String)] -> (List (Pair String Float64))
               (if (stringStartsWith? l "(:rate ")
                 (match (stringToFloat64 (sp/tokAfter l ":rpm"))
                   ((some r) (list (pair (quoted l ":alias") r)))
                   ((none) (list)))
                 (list)))
             (stringSplit text "\n")))

; (:m :ref GW-RPM-AIMD :do "a missing or unreadable store is no learning yet: the caller keeps the configured starts")
fn dirOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! readStore! path: String -> (Map String Float64)
  (parseStore (resultOr (fileReadString path) ""))

fn ! writeStore! path: String rates: (Map String Float64) -> (Result Bool String)
  (match (dirCreate (dirOf path))
    ((err e) (err e))
    ((ok _) (match (fileWrite path (storeText rates))
              ((ok _) (ok true))
              ((err e) (err e)))))
