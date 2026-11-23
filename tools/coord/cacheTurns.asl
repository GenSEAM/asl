(module asl-tools/coord/cacheTurns
  :x [TurnBucket bucketOf shareOf medianOf cacheByTurn turnBucketLine cacheByTurnText StickyShare SessionSticky stickyShare perSessionSwitches stickyShareText]
  :i [(aslGateway/usageLedger :a ul)])

; (:m :ref CACHE-BY-TURN :do "cache efficiency by position in a long session: every gateway call row that names its session and its turn gets a bucket (turn1, turns2to14, turns15plus) and a cached share (cachedTokens/inTokens); the metric is the median share per provider and bucket, plus the count of rows that cannot be attributed to a turn at all")
(schema TurnBucket
  (:f provider String)
  (:f bucket String)
  (:f calls Int64)
  (:f medianCachedShare Float64))

(schema CallShare
  (:f provider String)
  (:f bucket String)
  (:f share Float64))

fn bucketOf turn: Int64 -> String
  (if (<= turn 1) "turn1" (if (<= turn 14) "turns2to14" "turns15plus"))

fn shareOf row: ul/CallRow -> Float64
  (if (= row.inTokens 0) 0.0 (/ (int64ToFloat64 row.cachedTokens) (int64ToFloat64 row.inTokens)))

fn insertSorted v: Float64 xs: (List Float64) -> (List Float64)
  (match (listHead xs)
    ((none) (list v))
    ((some h) (if (< v h)
                (listAppend (list v) xs)
                (listAppend (list h) (insertSorted v (optionOr (listTail xs) (list)))))))

fn sortFloats xs: (List Float64) -> (List Float64)
  (fold (fn [(acc (List Float64)) (v Float64)] -> (List Float64) (insertSorted v acc)) (list) xs)

; (:m :do "median of the per-call shares: the middle value for an odd count, the mean of the two middle values for an even count, 0.0 for no calls")
fn medianOf xs: (List Float64) -> Float64
  (let [(s (sortFloats xs))
        (n (listLength s))
        (mid (/ n 2))]
    (if (= n 0)
      0.0
      (if (= (mod n 2) 0)
        (/ (+ (optionOr (listGet s (- mid 1)) 0.0) (optionOr (listGet s mid) 0.0)) 2.0)
        (optionOr (listGet s mid) 0.0))))

fn attributed row: ul/CallRow -> (Option CallShare)
  (match row.turn
    ((none) none)
    ((some t) (match row.session
                ((none) none)
                ((some _) (some (CallShare :provider row.provider :bucket (bucketOf t) :share (shareOf row)))))))

fn gather xs: (List ul/CallRow) -> (Pair (List CallShare) Int64)
  (fold (fn [(acc (Pair (List CallShare) Int64)) (r ul/CallRow)] -> (Pair (List CallShare) Int64)
          (match (attributed r)
            ((none) (pair (pairFirst acc) (+ (pairSecond acc) 1)))
            ((some s) (pair (listAppend (pairFirst acc) (list s)) (pairSecond acc)))))
        (pair (list) 0) xs)

fn sameBucketKey a: CallShare b: CallShare -> Bool
  (and (= a.provider b.provider) (= a.bucket b.bucket))

; (:m :do "one key per provider and bucket, in the order the rows under test first name it, so the output needs no ordering on strings or floats")
fn distinctKeys xs: (List CallShare) -> (List CallShare)
  (fold (fn [(acc (List CallShare)) (x CallShare)] -> (List CallShare)
          (if (some? (listHead (filter (fn [(y CallShare)] -> Bool (sameBucketKey y x)) acc)))
            acc
            (listAppend acc (list (CallShare :provider x.provider :bucket x.bucket :share 0.0)))))
        (list) xs)

fn sharesFor xs: (List CallShare) k: CallShare -> (List Float64)
  (map (fn [(y CallShare)] -> Float64 y.share)
       (filter (fn [(y CallShare)] -> Bool (sameBucketKey y k)) xs))

fn bucketRow xs: (List CallShare) k: CallShare -> TurnBucket
  (let [(s (sharesFor xs k))]
    (TurnBucket :provider k.provider :bucket k.bucket :calls (listLength s) :medianCachedShare (medianOf s)))

; (:m :do "the metric over parsed call rows: rows without a session or without a turn are skipped and counted in the second half of the pair")
fn cacheByTurn rows: (List ul/CallRow) -> (Pair (List TurnBucket) Int64)
  (let [(g (gather rows))
        (xs (pairFirst g))
        (ks (distinctKeys xs))]
    (pair (map (fn [(k CallShare)] -> TurnBucket (bucketRow xs k)) ks)
          (pairSecond g)))

fn turnBucketLine r: TurnBucket -> String
  (str "(:provider \"" r.provider "\" :bucket \"" r.bucket "\" :calls " (stringFromInt64 r.calls)
       " :medianCachedShare " (stringFromFloat64 r.medianCachedShare) ")")

; (:m :ref CACHE-STICKY-SHARE :do "route stickiness: for every session that has a turn 1, the turns after the first are counted and the ones served by the same provider and alias as turn 1 are counted as sticky; the metric sums both over sessions and reports the share, and perSessionSwitches names the sessions that switched at least once")
(schema StickyShare
  (:f sessions Int64)
  (:f turnsAfterFirst Int64)
  (:f sameProvider Int64)
  (:f share Float64))

(schema SessionSticky
  (:f session String)
  (:f hasTurn1 Bool)
  (:f turnsAfterFirst Int64)
  (:f sameProvider Int64))

fn stickyRow? r: ul/CallRow -> Bool
  (and (some? r.session) (some? r.turn))

fn sessionName r: ul/CallRow -> String
  (optionOr r.session "")

fn sessionNames xs: (List ul/CallRow) -> (List String)
  (fold (fn [(acc (List String)) (r ul/CallRow)] -> (List String)
          (let [(n (sessionName r))]
            (if (listContains? acc n) acc (listAppend acc (list n)))))
        (list) xs)

fn rowsForSession xs: (List ul/CallRow) s: String -> (List ul/CallRow)
  (filter (fn [(r ul/CallRow)] -> Bool (= (sessionName r) s)) xs)

fn turnSeen? t: Int64 xs: (List (Pair Int64 ul/CallRow)) -> Bool
  (listAny? (fn [(p (Pair Int64 ul/CallRow))] -> Bool (= (pairFirst p) t)) xs)

fn addTurn xs: (List (Pair Int64 ul/CallRow)) r: ul/CallRow -> (List (Pair Int64 ul/CallRow))
  (match r.turn
    ((none) xs)
    ((some t) (if (turnSeen? t xs) xs (listAppend xs (list (pair t r))))))

fn insertTurn p: (Pair Int64 ul/CallRow) xs: (List (Pair Int64 ul/CallRow)) -> (List (Pair Int64 ul/CallRow))
  (match (listHead xs)
    ((none) (list p))
    ((some h) (if (< (pairFirst p) (pairFirst h))
                (cons p xs)
                (cons h (insertTurn p (optionOr (listTail xs) (list)))))))

fn sortTurns xs: (List (Pair Int64 ul/CallRow)) -> (List (Pair Int64 ul/CallRow))
  (fold (fn [(acc (List (Pair Int64 ul/CallRow))) (p (Pair Int64 ul/CallRow))] -> (List (Pair Int64 ul/CallRow))
          (insertTurn p acc))
        (list) xs)

; (:m :do "one row per turn, the first row seen for that turn, ordered by turn number")
fn turnsOf xs: (List ul/CallRow) -> (List (Pair Int64 ul/CallRow))
  (sortTurns (fold (fn [(acc (List (Pair Int64 ul/CallRow))) (r ul/CallRow)] -> (List (Pair Int64 ul/CallRow))
                     (addTurn acc r))
                   (list) xs))

fn sameRoute ref: ul/CallRow r: ul/CallRow -> Bool
  (and (= ref.provider r.provider) (= ref.alias r.alias))

fn sessionSticky xs: (List ul/CallRow) s: String -> SessionSticky
  (let [(ts (turnsOf (rowsForSession xs s)))]
    (match (listHead ts)
      ((none) (SessionSticky :session s :hasTurn1 false :turnsAfterFirst 0 :sameProvider 0))
      ((some f) (if (= (pairFirst f) 1)
                  (let [(ref (pairSecond f))
                        (rest (optionOr (listTail ts) (list)))]
                    (SessionSticky :session s :hasTurn1 true
                      :turnsAfterFirst (listLength rest)
                      :sameProvider (listLength (filter (fn [(p (Pair Int64 ul/CallRow))] -> Bool (sameRoute ref (pairSecond p))) rest))))
                  (SessionSticky :session s :hasTurn1 false :turnsAfterFirst 0 :sameProvider 0)))))

fn stickySessions rows: (List ul/CallRow) -> (List SessionSticky)
  (let [(xs (filter (fn [(r ul/CallRow)] -> Bool (stickyRow? r)) rows))]
    (map (fn [(s String)] -> SessionSticky (sessionSticky xs s)) (sessionNames xs)))

; (:m :do "the metric over parsed call rows: sessions without a turn 1 cannot be attributed and are left out of every total")
fn stickyShare rows: (List ul/CallRow) -> StickyShare
  (let [(ss (filter (fn [(s SessionSticky)] -> Bool s.hasTurn1) (stickySessions rows)))
        (after (fold (fn [(a Int64) (s SessionSticky)] -> Int64 (+ a s.turnsAfterFirst)) 0 ss))
        (same (fold (fn [(a Int64) (s SessionSticky)] -> Int64 (+ a s.sameProvider)) 0 ss))]
    (StickyShare :sessions (listLength ss) :turnsAfterFirst after :sameProvider same
      :share (if (= after 0) 0.0 (/ (int64ToFloat64 same) (int64ToFloat64 after)))))

fn switched? s: SessionSticky -> Bool
  (and s.hasTurn1 (> (- s.turnsAfterFirst s.sameProvider) 0))

fn perSessionSwitches rows: (List ul/CallRow) -> (List String)
  (map (fn [(s SessionSticky)] -> String s.session)
       (filter (fn [(s SessionSticky)] -> Bool (switched? s)) (stickySessions rows)))

fn stickyShareText rows: (List ul/CallRow) -> String
  (let [(s (stickyShare rows))]
    (str "(:sessions " (stringFromInt64 s.sessions)
         " :turnsAfterFirst " (stringFromInt64 s.turnsAfterFirst)
         " :sameProvider " (stringFromInt64 s.sameProvider)
         " :share " (stringFromFloat64 s.share) ")"))

fn cacheByTurnText rows: (List ul/CallRow) -> String

  (let [(r (cacheByTurn rows))]
    (str (stringJoin (map turnBucketLine (pairFirst r)) "\n")
         "\n(:unattributed " (stringFromInt64 (pairSecond r)) ")"
         "\n" (stickyShareText rows)))
