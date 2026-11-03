(module aslGateway/capOrder
  :x [AliasStat OrderOpts Ranked defaultOrderOpts untestedStat aliasScore exploring? rankChain refreshDue? orderOptsOfProps spreadWeights]
  :i [(aslGateway/config :a c)
      (asl-parser/reader :a rd)])

; (:m :ref GW-CAP-ORDER :do "capability-ordered chains: a pure ranking of a route's aliases from measured stats, no model call and no clock beyond the nowMs it is handed; the stats come from the conductor journal and the gateway call ledger (capOrderStats), the result is written back into the route's :chain and :spread by `gateway order`, so a request never ranks anything")
(schema AliasStat
  (:f alias String)
  ; (:m :do "write attempts attributed to this alias and the ones whose unit merged (green and graded), from the conductor journal; 0 0 when the journal never named the alias")
  (:f attempts Int64)
  (:f green Int64)
  ; (:m :do "upstream calls that reached the provider, those that answered ok, and those that hit a limit or a 429, from the gateway call ledger")
  (:f calls Int64)
  (:f callsOk Int64)
  (:f limitHits Int64)
  ; (:m :do "share of the cap still free in permille, -1 when unknown (counted as fully free)")
  (:f capPermille Int64)
  ; (:m :do "newest evidence time in epoch ms over journal and ledger, 0 when the alias has none")
  (:f lastMs Int64))

; (:m :ref GW-CAP-ORDER :do "per route options from the route row :order measured :explore PCT :refreshS S [:minSamples N] [:staleS S] [:orderOff (ALIAS ..)] [:orderAt MS]; explore is the share of spread weight in percent given to untested or stale aliases, off lists aliases kept out of the ranking, at is the time of the last write-back")
(schema OrderOpts
  (:f explore Int64)
  (:f refreshS Int64)
  (:f minSamples Int64)
  (:f staleS Int64)
  (:f off (List String))
  (:f at Int64))

; (:m :do "chain is every live alias, best first, explored ones last in their original order; weights give every chain alias a non-negative integer (a score of 0 or an exploit alias with no measured score gets 0); explored names the aliases that drew the exploration share, excluded the ones the route row turned off")
(schema Ranked
  (:f chain (List String))
  (:f weights (List (Pair String Int64)))
  (:f explored (List String))
  (:f excluded (List String)))

fn defaultOrderOpts -> OrderOpts
  (OrderOpts :explore 12 :refreshS 86400 :minSamples 5 :staleS 604800 :off (list) :at 0)

fn untestedStat alias: String -> AliasStat
  (AliasStat :alias alias :attempts 0 :green 0 :calls 0 :callsOk 0 :limitHits 0 :capPermille -1 :lastMs 0)

fn statFor stats: (List AliasStat) alias: String -> AliasStat
  (optionOr (listHead (filter (fn [(s AliasStat)] -> Bool (= s.alias alias)) stats)) (untestedStat alias))

fn clampPermille v: Int64 -> Int64
  (if (< v 0) 0 (if (> v 1000) 1000 v))

; (:m :do "permille score: unit yield (green per attempt, or the call success rate when the journal has no attempts, 500 when neither) times call success times the cap still free after limit hits; integer arithmetic only so ties are exact")
fn aliasScore s: AliasStat -> Int64
  (let [(okPm (if (> s.calls 0) (/ (* s.callsOk 1000) s.calls) 1000))
        (base (cond ((> s.attempts 0) (/ (* s.green 1000) s.attempts))
                    ((> s.calls 0) okPm)
                    (else 500)))
        (limitPm (/ (* s.limitHits 1000) (+ 1 (+ s.calls s.limitHits))))
        (capPm (clampPermille (- (if (< s.capPermille 0) 1000 s.capPermille) limitPm)))]
    (/ (* (/ (* base okPm) 1000) capPm) 1000))

; (:m :do "an alias is explored while it has fewer samples (attempts plus calls) than minSamples or its newest evidence is older than staleS")
fn exploring? s: AliasStat opts: OrderOpts nowMs: Int64 -> Bool
  (or (< (+ s.attempts s.calls) opts.minSamples)
      (or (= s.lastMs 0) (> (- nowMs s.lastMs) (* opts.staleS 1000))))

; (:m :do "descending score with the chain position as the tie break, as one integer sort key so the prelude sort order never decides a tie")
fn rankKey stats: (List AliasStat) chain: (List String) a: String -> Int64
  (+ (* (- 1000001 (aliasScore (statFor stats a))) 1000) (optionOr (listIndexOf chain a) 0))

fn exploitWeight score: Int64 sumScore: Int64 total: Int64 -> Int64
  (if (or (<= sumScore 0) (<= score 0)) 0 (let [(w (/ (* score total) sumScore))] (if (< w 1) 1 w)))

fn rankChain chain: (List String) stats: (List AliasStat) opts: OrderOpts nowMs: Int64 -> Ranked
  (let [(live (filter (fn [(a String)] -> Bool (not (listContains? opts.off a))) chain))
        (excluded (filter (fn [(a String)] -> Bool (listContains? opts.off a)) chain))
        (explored (filter (fn [(a String)] -> Bool (exploring? (statFor stats a) opts nowMs)) live))
        (exploit (listSortBy (fn [(a String)] -> Int64 (rankKey stats live a))
                   (filter (fn [(a String)] -> Bool (not (listContains? explored a))) live)))
        (sumScore (listSum (map (fn [(a String)] -> Int64 (aliasScore (statFor stats a))) exploit)))
        (exploreTotal (cond ((listEmpty? explored) 0)
                            ((listEmpty? exploit) 100)
                            (else (if (< opts.explore 0) 0 (if (> opts.explore 100) 100 opts.explore)))))
        (exploitTotal (- 100 exploreTotal))
        (exploreEach (if (<= exploreTotal 0) 0 (let [(w (/ exploreTotal (listLength explored)))] (if (< w 1) 1 w))))
        (newChain (listAppend exploit explored))
        (weights (map (fn [(a String)] -> (Pair String Int64)
                        (if (listContains? explored a)
                          (pair a exploreEach)
                          (pair a (exploitWeight (aliasScore (statFor stats a)) sumScore exploitTotal))))
                   newChain))]
    (Ranked :chain newChain :weights weights :explored explored :excluded excluded))

; (:m :do "the positive weights only, as the config :spread wants them: a zero weight stays in the chain but never enters the spread")
fn spreadWeights r: Ranked -> (List (Pair String Int64))
  (filter (fn [(p (Pair String Int64))] -> Bool (> (pairSecond p) 0)) r.weights)

; (:m :do "a route is due when its last write-back is at least refreshS old; a route never written (at 0) is due")
fn refreshDue? opts: OrderOpts nowMs: Int64 -> Bool
  (>= (- nowMs opts.at) (* opts.refreshS 1000))

fn propInt props: (Map String rd/SExpr) key: String d: Int64 -> Int64
  (match (mapGet props key)
    ((none) d)
    ((some v) (match (c/asnScalar v) ((c/scalarInt n) n) (_ -1))))

fn atomsOf expr: rd/SExpr -> (List String)
  (let [(items (match expr ((rd/sexprList l) l) ((rd/sexprVect v) v) (_ (list))))]
    (map (fn [(e rd/SExpr)] -> String (match e ((rd/sexprAtom s) s) (_ ""))) items))

; (:m :do "none when the route has no :order key (today's behaviour); an error text for any other value than measured or an out-of-range number; the same bounds config check enforces")
fn orderOptsOfProps props: (Map String rd/SExpr) -> (Result (Option OrderOpts) String)
  (match (mapGet props "order")
    ((none) (ok (none)))
    ((some v)
      (match (c/asnScalar v)
        ((c/scalarStr s)
          (if (!= s "measured")
            (err (str ":order must be measured, found " s))
            (let [(d (defaultOrderOpts))
                  (o (OrderOpts :explore (propInt props "explore" d.explore) :refreshS (propInt props "refreshS" d.refreshS)
                       :minSamples (propInt props "minSamples" d.minSamples) :staleS (propInt props "staleS" d.staleS)
                       :off (match (mapGet props "orderOff") ((some e) (atomsOf e)) ((none) (list)))
                       :at (propInt props "orderAt" 0)))]
              (if (or (< o.explore 0) (or (> o.explore 50) (or (< o.refreshS 60) (or (< o.minSamples 1) (or (< o.staleS 60) (< o.at 0))))))
                (err ":order options out of range: explore 0..50, refreshS >= 60, minSamples >= 1, staleS >= 60, orderAt >= 0")
                (ok (some o))))))
        (_ (err ":order must be measured")))))
