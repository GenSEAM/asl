(module prelude/tests/hashMapTest :x [runTests] :i [])

; (:m :ref INTHASHMAP :do "semantics of the prelude HashMap on whatever backend runs the test: persistence under aliasing, colliding keys, growth, backward-shift removal, String and Int64 keys, fold and pairs against an association-list model")
fn fillInts i: Int64 n: Int64 m: (HashMap Int64 Int64) -> (HashMap Int64 Int64)
  (if (= i n) m (fillInts (+ i 1) n (hashMapSet m (mod (* i 48271) 2147483647) i)))

fn hitsInts i: Int64 n: Int64 m: (HashMap Int64 Int64) acc: Int64 -> Int64
  (if (= i n) acc
    (hitsInts (+ i 1) n m (+ acc (if (= (hashMapGet m (mod (* i 48271) 2147483647)) (some i)) 1 0))))

fn lcg s: Int64 -> Int64
  (mod (+ (* s 1103515245) 12345) 2147483648)

fn modelSet model: (List (Pair K Int64)) k: K v: Int64 -> (List (Pair K Int64))
  (cons (pair k v) (filter (fn [p] (!= (pairFirst p) k)) model))

fn modelRemove model: (List (Pair K Int64)) k: K -> (List (Pair K Int64))
  (filter (fn [p] (!= (pairFirst p) k)) model)

fn modelGet model: (List (Pair K Int64)) k: K -> (Option Int64)
  (match (listFind (fn [p] (= (pairFirst p) k)) model)
    ((some p) (some (pairSecond p)))
    ((none) none))

fn replay keyOf: (fn [Int64] -> K) steps: Int64 seed: Int64 m: (HashMap K Int64) model: (List (Pair K Int64)) -> (Pair (HashMap K Int64) (List (Pair K Int64)))
  (if (= steps 0) (pair m model)
    (let [(s (lcg seed))
          (k (keyOf (mod (/ s 7) 61)))]
      (if (= (mod s 3) 0)
        (replay keyOf (- steps 1) s (hashMapRemove m k) (modelRemove model k))
        (replay keyOf (- steps 1) s (hashMapSet m k steps) (modelSet model k steps)))))

fn sortedPairs ps: (List (Pair K Int64)) -> (List (Pair K Int64))
  (listSortBy (fn [p] (pairFirst p)) ps)

fn agrees? keyOf: (fn [Int64] -> K) seed: Int64 -> Bool
  (let [(r (replay keyOf 600 seed (hashMapEmpty) (list)))
        (m (pairFirst r))
        (model (pairSecond r))]
    (and (= (sortedPairs (hashMapPairs m)) (sortedPairs model))
      (and (= (hashMapLength m) (listLength model))
        (listAll? (fn [i] (= (hashMapGet m (keyOf i)) (modelGet model (keyOf i)))) (range 0 61)))))

fn runTests -> Bool
  (let [(a (hashMapSet (hashMapSet (hashMapEmpty) "x" 1) "y" 2))
        (b (hashMapSet a "x" 10))
        (c (hashMapRemove a "y"))
        (d (hashMapSet a "z" 3))
        (colliding (fold (fn [m i] (hashMapSet m (* i 1024) i)) (hashMapEmpty) (range 0 300)))
        (cut (fold (fn [m i] (hashMapRemove m (* i 1024))) colliding (filter (fn [i] (= (mod i 3) 0)) (range 0 300))))
        (big (fillInts 0 20000 (hashMapEmpty)))
        (bigAlias big)
        (bigPlus (hashMapSet big -5 -5))
        (strs (fold (fn [m i] (hashMapSet m (str "k" i) i)) (hashMapEmpty) (range 0 5000)))
        (kws (list :alpha :beta :gamma :delta :epsilon :zeta :eta :theta :iota :kappa :lambda :mu))
        (kmap (fold (fn [m i] (hashMapSet m (optionOr (listGet kws i) :alpha) i)) (hashMapEmpty) (range 0 12)))
        (kcut (hashMapRemove kmap :beta))
        (sized (fold (fn [m i] (hashMapSet m i (* i 2))) (hashMapWithCapacity 1000) (range 0 1000)))
        (istr (fold (fn [m i] (hashMapSet m i (str "v" i))) (hashMapEmpty) (range 0 2000)))
        (iodd (fold (fn [m i] (hashMapRemove m (* i 2))) istr (range 0 1000)))]
    (do
      (assert (= (hashMapGet a "x") (some 1)) "a set on an alias leaves the original value")
      (assert (= (hashMapGet b "x") (some 10)) "the new map carries the new value")
      (assert (= (hashMapLength b) 2) "overwrite keeps the length")
      (assert (= (hashMapGet a "y") (some 2)) "a remove on an alias leaves the original key")
      (assert (= (hashMapGet c "y") none) "the removed key is gone from the new map")
      (assert (= (hashMapLength c) 1) "remove lowers the length")
      (assert (= (hashMapGet a "z") none) "an insert on an alias does not show in the original")
      (assert (= (hashMapLength a) 2) "the original keeps its length after three derived maps")
      (assert (= (hashMapGet d "z") (some 3)) "the derived map has the inserted key")
      (assert (= (hashMapGet (hashMapEmpty) 1) none) "the empty map has no keys")
      (assert (= (hashMapLength (hashMapEmpty)) 0) "the empty map has length 0")
      (assert (= (hashMapRemove (hashMapEmpty) 1) (hashMapEmpty)) "removing from the empty map gives the empty map")
      (assert (= (hashMapLength colliding) 300) "300 keys sharing their low bits are all kept")
      (assert (listAll? (fn [i] (= (hashMapGet colliding (* i 1024)) (some i))) (range 0 300)) "every colliding key is found with its value")
      (assert (= (hashMapLength cut) 200) "removing every third colliding key leaves 200")
      (assert (listAll? (fn [i] (= (hashMapGet cut (* i 1024)) (if (= (mod i 3) 0) none (some i)))) (range 0 300)) "after removals inside probe runs every remaining key is still found and removed ones are not")
      (assert (= (hashMapLength big) 20000) "growth from 8 slots keeps 20000 distinct keys")
      (assert (= (hitsInts 0 20000 big 0) 20000) "every one of 20000 keys is found after growth")
      (assert (= (hashMapGet bigAlias -5) none) "a set on a grown map does not reach its alias")
      (assert (= (hashMapLength bigPlus) 20001) "the derived grown map has one more key")
      (assert (= (hashMapGetOr strs "k4999" -1) 4999) "String keys are found")
      (assert (= (hashMapGetOr strs "k5000" -1) -1) "a missing String key gives the default")
      (assert (hashMapHas? strs "k0") "hashMapHas? is true for a present key")
      (refute (hashMapHas? strs "k") "hashMapHas? is false for a missing key")
      (assert (= (hashMapFold strs 0 (fn [acc k v] (+ acc v))) 12497500) "fold visits every value once")
      (assert (= (listLength (hashMapPairs strs)) 5000) "pairs lists every entry")
      (assert (= (hashMapGet (hashMapFromPairs (list (pair 2 "b") (pair 1 "a") (pair 2 "c"))) 2) (some "c")) "fromPairs keeps the last value of a repeated key")
      (assert (listAll? (fn [seed] (agrees? (fn [i] (str "s" (* i 7919))) seed)) (list 1 2 3)) "random String-key set and remove sequences agree with the model")
      (assert (listAll? (fn [seed] (agrees? (fn [i] (- (* i 104729) 3000000)) seed)) (list 4 5 6)) "random Int64-key sequences, negatives included, agree with the model")
      (assert (listAll? (fn [i] (= (hashMapGet kmap (optionOr (listGet kws i) :alpha)) (some i))) (range 0 12)) "every Keyword key is found with its value")
      (assert (and (= (hashMapGet kcut :beta) none) (= (hashMapGet kmap :beta) (some 1)) (= (hashMapLength kcut) 11)) "a Keyword key removed from a copy stays in the original")
      (assert (and (= (hashMapLength sized) 1000) (listAll? (fn [i] (= (hashMapGetOr sized i -1) (* i 2))) (range 0 1000))) "a pre-sized map holds what it was sized for")
      (assert (= (hashMapGetOr sized 5000 -1) -1) "getOr answers the default for a missing key")
      (assert (and (= (hashMapLength iodd) 1000) (= (hashMapLength istr) 2000) (listAll? (fn [i] (= (hashMapGet iodd i) (if (= (mod i 2) 0) none (some (str "v" i))))) (range 0 2000)) (listAll? (fn [i] (= (hashMapGetOr istr i "") (str "v" i))) (range 0 2000))) "Int64 keys with String values: removal of every even key leaves the odd ones and the original whole")
      true))
