(module ws/asl/tools/observe/hmap
  :x [HMap OMap hashKey hmEmpty hmGet hmHas? hmPut hmPairs hmValues hmSize omEmpty omGet omHas? omPut omPairs omValues omSize]
  :i [])

enum HMap
  (hmNil)
  (hmNode h: Int64 k: String v: V l: (HMap V) r: (HMap V))

enum OMap
  (omOf seq: (HMap (Pair Int64 V)) n: Int64)

fn hashLoop bs: Bytes i: Int64 n: Int64 h: Int64 -> Int64
  (if (>= i n) h (hashLoop bs (+ i 1) n (mod (+ (* h 131) (bytesGet bs i) 7) 2147483629)))

fn hashKey k: String -> Int64
  (let [(bs (stringToBytes k))] (hashLoop bs 0 (bytesLength bs) 5381))

fn hmEmpty -> (HMap V)
  (hmNil)

fn hmFind m: (HMap V) h: Int64 k: String -> (Option V)
  (mt m
    ((hmNil) (none))
    ((hmNode h2 k2 v l r)
      (cond
        ((and (= h h2) (= k k2)) (some v))
        ((or (< h h2) (and (= h h2) (< k k2))) (hmFind l h k))
        (else (hmFind r h k)))))

fn hmGet m: (HMap V) k: String -> (Option V)
  (hmFind m (hashKey k) k)

fn hmHas? m: (HMap V) k: String -> Bool
  (some? (hmGet m k))

fn hmIns m: (HMap V) h: Int64 k: String v: V -> (HMap V)
  (mt m
    ((hmNil) (hmNode h k v (hmNil) (hmNil)))
    ((hmNode h2 k2 v2 l r)
      (cond
        ((and (= h h2) (= k k2)) (hmNode h k v l r))
        ((or (< h h2) (and (= h h2) (< k k2))) (hmNode h2 k2 v2 (hmIns l h k v) r))
        (else (hmNode h2 k2 v2 l (hmIns r h k v))))))

fn hmPut m: (HMap V) k: String v: V -> (HMap V)
  (hmIns m (hashKey k) k v)

fn hmCollect m: (HMap V) acc: (List (Pair String V)) -> (List (Pair String V))
  (mt m
    ((hmNil) acc)
    ((hmNode h k v l r) (hmCollect l (cons (pair k v) (hmCollect r acc)))))

fn hmPairs m: (HMap V) -> (List (Pair String V))
  (hmCollect m (list))

fn hmValues m: (HMap V) -> (List V)
  (map (fn [(p (Pair String V))] -> V (pairSecond p)) (hmPairs m))

fn hmSize m: (HMap V) -> Int64
  (mt m ((hmNil) 0) ((hmNode h k v l r) (+ 1 (hmSize l) (hmSize r))))

fn omEmpty -> (OMap V)
  (omOf (hmNil) 0)

fn omGet m: (OMap V) k: String -> (Option V)
  (mt m ((omOf t n) (optionMap (fn [(p (Pair Int64 V))] -> V (pairSecond p)) (hmGet t k))))

fn omHas? m: (OMap V) k: String -> Bool
  (some? (omGet m k))

fn omPut m: (OMap V) k: String v: V -> (OMap V)
  (mt m
    ((omOf t n)
      (mt (hmGet t k)
        ((some p) (omOf (hmPut t k (pair (pairFirst p) v)) n))
        ((none) (omOf (hmPut t k (pair n v)) (+ n 1))))))

fn omPairs m: (OMap V) -> (List (Pair String V))
  (mt m
    ((omOf t n)
      (map (fn [(p (Pair String (Pair Int64 V)))] -> (Pair String V) (pair (pairFirst p) (pairSecond (pairSecond p))))
           (listSortBy (fn [(p (Pair String (Pair Int64 V)))] -> Int64 (pairFirst (pairSecond p))) (hmPairs t)))))

fn omValues m: (OMap V) -> (List V)
  (map (fn [(p (Pair String V))] -> V (pairSecond p)) (omPairs m))

fn omSize m: (OMap V) -> Int64
  (mt m ((omOf t n) (hmSize t)))
