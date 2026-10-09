(module asl-intel/tab
  :x [Strtab strtabNew intern! lookup internStr! lookupStr strtabCount ivNew ivGet ivSet! ivAdd! sortWith sortPairsByInt]
  :i [])

(schema Strtab
  (:f slots Bytes)
  (:f cap Int64)
  (:f keys Bytes)
  (:f keyCap Int64)
  (:f used Int64)
  (:f offs Bytes)
  (:f idCap Int64)
  (:f count Int64))

fn ivNew n: Int64 -> Bytes
  (bytesAlloc (* 8 (max 1 n)))

fn ivGet v: Bytes i: Int64 -> Int64
  (mt (float64ToInt64 (bytesGetFloat64 v i)) ((some x) x) ((none) 0))

fn ivSet! v: Bytes i: Int64 x: Int64 -> Unit
  (bytesSetFloat64 v i (int64ToFloat64 x))

fn ivAdd! v: Bytes i: Int64 d: Int64 -> Unit
  (ivSet! v i (+ (ivGet v i) d))

fn pow2AtLeast n: Int64 p: Int64 -> Int64
  (if (>= p n) p (pow2AtLeast n (* p 2)))

fn strtabNew n: Int64 -> Strtab
  (let [(cap (pow2AtLeast (* 2 (max 8 n)) 16)) (ids (max 8 n))]
    (Strtab :slots (ivNew cap) :cap cap :keys (bytesAlloc (* 16 ids)) :keyCap (* 16 ids) :used 0
            :offs (ivNew (* 2 ids)) :idCap ids :count 0))

fn strtabCount tab: Strtab -> Int64
  tab.count

fn hashRange b: Bytes s: Int64 e: Int64 h: Int64 -> Int64
  (if (>= s e) h (hashRange b (+ s 1) e (mod (+ (* h 31) (bytesGet b s)) 2147483647)))

fn keyEq? tab: Strtab id: Int64 b: Bytes s: Int64 e: Int64 -> Bool
  (let [(ks (ivGet tab.offs (* 2 id))) (kl (ivGet tab.offs (+ (* 2 id) 1)))]
    (and (= kl (- e s)) (bytesEqLoop tab.keys ks b s kl)))

fn bytesEqLoop a: Bytes i: Int64 b: Bytes j: Int64 k: Int64 -> Bool
  (cond
    ((<= k 0) true)
    ((!= (bytesGet a i) (bytesGet b j)) false)
    (else (bytesEqLoop a (+ i 1) b (+ j 1) (- k 1))))

fn probe tab: Strtab b: Bytes s: Int64 e: Int64 slot: Int64 -> Int64
  (let [(v (ivGet tab.slots slot))]
    (cond
      ((= v 0) (- -1 slot))
      ((keyEq? tab (- v 1) b s e) (- v 1))
      (else (probe tab b s e (mod (+ slot 1) tab.cap)))))

fn lookup tab: Strtab b: Bytes s: Int64 e: Int64 -> Int64
  (let [(r (probe tab b s e (mod (hashRange b s e 0) tab.cap)))]
    (if (< r 0) -1 r))

fn copyBytes! src: Bytes i: Int64 dst: Bytes j: Int64 k: Int64 -> Unit
  (if (<= k 0) ()
    (do (bytesSet dst j (bytesGet src i)) (copyBytes! src (+ i 1) dst (+ j 1) (- k 1))))

fn placeId! slots: Bytes cap: Int64 keys: Bytes offs: Bytes id: Int64 -> Unit
  (let [(ks (ivGet offs (* 2 id))) (kl (ivGet offs (+ (* 2 id) 1)))]
    (placeAt! slots cap (mod (hashRange keys ks (+ ks kl) 0) cap) id))

fn placeAt! slots: Bytes cap: Int64 s: Int64 id: Int64 -> Unit
  (if (= (ivGet slots s) 0) (ivSet! slots s (+ id 1)) (placeAt! slots cap (mod (+ s 1) cap) id))

fn grow! tab: Strtab -> Strtab
  (let [(cap (* 2 tab.cap)) (slots (ivNew cap))]
    (do
      (map (fn [(id Int64)] -> Unit (placeId! slots cap tab.keys tab.offs id)) (range 0 tab.count))
      (with tab :slots slots :cap cap)))

fn reserve! tab: Strtab k: Int64 -> Strtab
  (let [(needKeys (> (+ tab.used k) tab.keyCap))
        (needIds (>= tab.count tab.idCap))
        (keyCap (if needKeys (max (* 2 tab.keyCap) (+ (+ tab.used k) 16)) tab.keyCap))
        (keys (if needKeys (let [(nk (bytesAlloc keyCap))] (do (copyBytes! tab.keys 0 nk 0 tab.used) nk)) tab.keys))
        (idCap (if needIds (* 2 tab.idCap) tab.idCap))
        (offs (if needIds (let [(no (ivNew (* 2 idCap)))] (do (copyBytes! tab.offs 0 no 0 (* 16 tab.count)) no)) tab.offs))]
    (with tab :keys keys :keyCap keyCap :offs offs :idCap idCap))

fn intern! tab: Strtab b: Bytes s: Int64 e: Int64 -> (Pair Strtab Int64)
  (let [(found (lookup tab b s e))]
    (if (>= found 0) (pair tab found)
      (let [(t1 (if (> (* 2 (+ tab.count 1)) tab.cap) (grow! tab) tab))
            (t2 (reserve! t1 (- e s)))
            (id t2.count)]
        (do
          (copyBytes! b s t2.keys t2.used (- e s))
          (ivSet! t2.offs (* 2 id) t2.used)
          (ivSet! t2.offs (+ (* 2 id) 1) (- e s))
          (placeAt! t2.slots t2.cap (mod (hashRange b s e 0) t2.cap) id)
          (pair (Strtab :slots t2.slots :cap t2.cap :keys t2.keys :keyCap t2.keyCap
                        :used (+ t2.used (- e s)) :offs t2.offs :idCap t2.idCap :count (+ id 1))
                id)))))

fn internStr! tab: Strtab s: String -> (Pair Strtab Int64)
  (let [(b (stringToBytes s))] (intern! tab b 0 (bytesLength b)))

fn lookupStr tab: Strtab s: String -> Int64
  (let [(b (stringToBytes s))] (lookup tab b 0 (bytesLength b)))

fn mergeWith less: (Fn T T Bool) a: (List T) b: (List T) acc: (List T) -> (List T)
  (mt (listHead a)
    ((none) (revOnto acc b))
    ((some x)
      (mt (listHead b)
        ((none) (revOnto acc a))
        ((some y)
          (if (less y x)
            (mergeWith less a (optionOr (listTail b) (list)) (cons y acc))
            (mergeWith less (optionOr (listTail a) (list)) b (cons x acc)))))))

fn revOnto acc: (List T) rest: (List T) -> (List T)
  (mt (listHead acc)
    ((none) rest)
    ((some x) (revOnto (optionOr (listTail acc) (list)) (cons x rest))))

fn mergePass less: (Fn T T Bool) runs: (List (List T)) acc: (List (List T)) -> (List (List T))
  (mt (listHead runs)
    ((none) (listReverse acc))
    ((some a)
      (let [(rest (optionOr (listTail runs) (list)))]
        (mt (listHead rest)
          ((none) (listReverse (cons a acc)))
          ((some b) (mergePass less (optionOr (listTail rest) (list)) (cons (mergeWith less a b (list)) acc)))))))

fn mergeAll less: (Fn T T Bool) runs: (List (List T)) -> (List T)
  (cond
    ((listEmpty? runs) (list))
    ((= (listLength runs) 1) (optionOr (listHead runs) (list)))
    (else (mergeAll less (mergePass less runs (list)))))

fn sortWith less: (Fn T T Bool) xs: (List T) -> (List T)
  (mergeAll less (map (fn [(x T)] -> (List T) (list x)) xs))

fn sortPairsByInt xs: (List (Pair Int64 T)) -> (List (Pair Int64 T))
  (sortWith (fn [(a (Pair Int64 T)) (b (Pair Int64 T))] -> Bool (< (pairFirst a) (pairFirst b))) xs)
