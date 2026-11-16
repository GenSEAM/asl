(module asl-tools/coord/cacheTurns
  :x [TurnBucket bucketOf shareOf medianOf cacheByTurn turnBucketLine cacheByTurnText]
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

fn cacheByTurnText rows: (List ul/CallRow) -> String
  (let [(r (cacheByTurn rows))]
    (str (stringJoin (map turnBucketLine (pairFirst r)) "\n")
         "\n(:unattributed " (stringFromInt64 (pairSecond r)) ")"))
