(module prelude/tests/mapTreeTest :x [runTests] :i [])

fn fill keys: (List K) m: (Map K Int64) -> (Map K Int64)
  (fold (fn [acc k] (mapSet acc k (* 10 (listLength (mapKeys acc))))) m keys)

fn fillValue keys: (List K) m: (Map K Int64) -> (Map K Int64)
  (fold (fn [acc k] (mapSet acc k (stringLength (str k)))) m keys)

fn grow i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (= i n) m (grow (+ i 1) n (mapSet m (mod (* i 7919) 1000003) i)))

fn found i: Int64 n: Int64 m: (Map Int64 Int64) acc: Int64 -> Int64
  (if (= i n) acc
    (found (+ i 1) n m (+ acc (if (= (mapGet m (mod (* i 7919) 1000003)) (some i)) 1 0))))

fn depth t: (PreludeTree K V) -> Int64
  (match t
    ((preludeLeaf) 0)
    ((preludeNode _ _ _ l g) (+ 1 (max (depth l) (depth g)))))

fn family n: Int64 -> (List String)
  (if (= n 0) (list "")
    (let [rest (family (- n 1))]
      (listAppend (map (fn [s] (str "MMMMM" s)) rest) (map (fn [s] (str "LQGQN" s)) rest))))

fn shuffle xs: (List T) seed: Int64 -> (List T)
  (map (fn [p] (pairSecond p))
    (listSortBy (fn [p] (pairFirst p))
      (map (fn [p] (pair (mod (+ (* (pairFirst p) 7919) seed) 104729) (pairSecond p))) (enumerate xs))))

fn churn keys: (List K) drop: (List K) seed: Int64 -> (Map K Int64)
  (let [full (fold (fn [acc k] (mapSet acc k 1)) (mapEmpty) (shuffle keys seed))
        cut (fold (fn [acc k] (mapRemove acc k)) full (shuffle drop (+ seed 31)))]
    (fold (fn [acc k] (mapSet acc k 1)) cut (shuffle drop (+ seed 57))))

; (:m :ref PERF-MAPRANK :do "a reference model for random insert and remove sequences: an association list with the last write of each key, sorted by key at the end")
fn modelSet model: (List (Pair K Int64)) k: K v: Int64 -> (List (Pair K Int64))
  (cons (pair k v) (filter (fn [p] (!= (pairFirst p) k)) model))

fn modelRemove model: (List (Pair K Int64)) k: K -> (List (Pair K Int64))
  (filter (fn [p] (!= (pairFirst p) k)) model)

fn lcg s: Int64 -> Int64
  (mod (+ (* s 1103515245) 12345) 2147483648)

fn replay keyOf: (fn [Int64] -> K) steps: Int64 seed: Int64 m: (Map K Int64) model: (List (Pair K Int64)) -> (Pair (Map K Int64) (List (Pair K Int64)))
  (if (= steps 0) (pair m model)
    (let [s (lcg seed)
          k (keyOf (mod (/ s 7) 97))]
      (if (= (mod s 5) 0)
        (replay keyOf (- steps 1) s (mapRemove m k) (modelRemove model k))
        (replay keyOf (- steps 1) s (mapSet m k steps) (modelSet model k steps)))))

; (:m :ref PERF-MONO-MAPKEY :do "mapGet of every key the replay could touch, present or removed, answers as the model does; mapHas? and mapGetOr too (PERF-FREECHAIN walks them without an Option)")
fn modelGet model: (List (Pair K Int64)) k: K -> (Option Int64)
  (match (listFind (fn [p] (= (pairFirst p) k)) model)
    ((some p) (some (pairSecond p)))
    ((none) none))

fn agrees? keyOf: (fn [Int64] -> K) seed: Int64 -> Bool
  (let [r (replay keyOf 600 seed (mapEmpty) (list))
        m (pairFirst r)
        want (listSortBy (fn [p] (pairFirst p)) (pairSecond r))]
    (and (and (= (mapPairs m) want) (= m (mapFromPairs want)))
         (listAll? (fn [i] (and (= (mapGet m (keyOf i)) (modelGet want (keyOf i)))
                                (and (= (mapHas? m (keyOf i)) (some? (modelGet want (keyOf i))))
                                     (= (mapGetOr m (keyOf i) -1) (optionOr (modelGet want (keyOf i)) -1)))))
                   (range 0 97))))

fn sorted? xs: (List Int64) -> Bool
  (match (listHead xs)
    ((none) true)
    ((some a) (match (listGet xs 1)
                ((none) true)
                ((some b) (and (< a b) (sorted? (listDrop xs 1)))))))

fn ! runTests -> Bool
  (let [(words (list "pear" "apple" "fig" "kiwi" "banana" "cherry" "date" "elder" "grape" "honeydew"))
        (m (fillValue words (mapEmpty)))
        (asc (fillValue (listSort words) (mapEmpty)))
        (desc (fillValue (listReverse (listSort words)) (mapEmpty)))
        (ints (list 50 3 -7 12 99 0 41 -100 8 77 23 64 5 18))
        (im (fold (fn [acc k] (mapSet acc k (* k k))) (mapEmpty) ints))
        (imRev (fold (fn [acc k] (mapSet acc k (* k k))) (mapEmpty) (listReverse ints)))
        (over (mapSet m "fig" 100))
        (gone (mapRemove m "kiwi"))
        (back (mapSet gone "kiwi" 4))
        (t0 (monotonicNs))
        (big (grow 0 100000 (mapEmpty)))
        (hits (found 0 100000 big 0))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (crafted (family 12))
        (attack (fold (fn [acc k] (mapSet acc k 1)) (mapEmpty) crafted))
        (words400 (map (fn [i] (str "w" (mod (* i 7919) 100003))) (range 0 400)))
        (shape0 (churn words400 (listTake words400 150) 0))
        (shapes (map (fn [seed] (churn words400 (listTake words400 150) seed)) (list 1 2 3 4 5)))]
    (do
      (assert (= (mapKeys m) (listSort words)) "mapKeys is sorted by < whatever the insertion order")
      (assert (= (mapValues m) (map (fn [w] (stringLength w)) (listSort words))) "mapValues follows key order")
      (assert (= (mapPairs m) (map (fn [w] (pair w (stringLength w))) (listSort words))) "mapPairs is key-sorted pairs")
      (assert (= (mapKeys im) (listSort ints)) "Int keys sort numerically, negatives first")
      (assert (= (mapSize m) 10) "mapSize counts distinct keys")
      (assert (= (mapGet over "fig") (some 100)) "mapSet on a present key overwrites its value")
      (assert (= (mapSize over) 10) "overwrite keeps the size")
      (assert (= (mapGet m "fig") (some 3)) "the original map is unchanged by a later set")
      (assert (= (mapGet gone "kiwi") none) "mapRemove drops the key")
      (assert (= (mapSize gone) 9) "mapRemove lowers the size")
      (assert (= (mapKeys gone) (filter (fn [w] (!= w "kiwi")) (listSort words))) "mapRemove keeps the other keys sorted")
      (assert (= (mapRemove m "zucchini") m) "removing a missing key leaves the map equal")
      (assert (= (mapGet m "zucchini") none) "a missing key gets none")
      (refute (mapHas? m "zucchini") "mapHas? is false for a missing key")
      (assert (mapHas? m "pear") "mapHas? is true for a present key")
      (assert (= (mapSize (mapEmpty)) 0) "the empty map has size 0")
      (assert (= (mapKeys (mapEmpty)) (list)) "the empty map has no keys")
      (assert (= (mapRemove (mapEmpty) 1) (mapEmpty)) "removing from the empty map gives the empty map")
      (assert (= m asc) "maps built in different orders are equal")
      (assert (= m desc) "maps built in ascending and descending order are equal")
      (assert (= im imRev) "Int-keyed maps built in reverse order are equal")
      (assert (= back m) "remove then re-insert gives a map equal to the original")
      (assert (= (fold (fn [acc w] (mapRemove acc w)) m words) (mapEmpty)) "removing every key gives the empty map")
      (refute (= over m) "maps differing in one value are not equal")
      (refute (= gone m) "maps differing in one key are not equal")
      (assert (= (mapFromPairs (list (pair 2 "b") (pair 1 "a") (pair 2 "c"))) (mapSet (mapSet (mapEmpty) 1 "a") 2 "c")) "mapFromPairs keeps the last value of a repeated key")
      (assert (= (mapFromPairs (mapPairs im)) im) "mapFromPairs of mapPairs round-trips")
      (assert (= (mapSize big) 100000) "100000 distinct keys are all kept")
      (assert (= hits 100000) "every one of 100000 keys is found with its value")
      (assert (sorted? (listTake (mapKeys big) 1000)) "the keys of the large map come out sorted")
      (assert (< ms 20000) (str "100000 inserts and lookups take under 20s, took " ms "ms"))
      (assert (= (mapSize attack) 4096) "the crafted MMMMM/LQGQN family has 4096 distinct keys")
      (assert (< (depth (preludeTree attack)) 64) (str "the crafted equal-rank family stays shallow, depth " (depth (preludeTree attack))))
      (assert (= (listLength (filter (fn [m] (= m shape0)) shapes)) 5) "equal key sets under shuffled inserts and removes give identical trees")
      (assert (< (depth (preludeTree shape0)) 40) "400 keys give a tree of depth under 40")
      (assert (listAll? (fn [seed] (agrees? (fn [i] (str "k" (* i 7919))) seed)) (list 1 2 3 4)) "random String-key insert and remove sequences give the model's key-sorted pairs and a map equal to one built from them")
      (assert (listAll? (fn [seed] (agrees? (fn [i] (- (* i 104729) 5000000)) seed)) (list 5 6 7 8)) "random Int64-key sequences, negatives included, agree with the model")
      (assert (listAll? (fn [seed] (agrees? (fn [i] (str "q\"-0.0" (mod i 9) "\\" (mod i 11))) seed)) (list 9 10 11 12)) "random keys holding quotes, backslashes and -0.0 text agree with the model")
      (assert (= (mapKeys (mapFromPairs (list (pair "ab" 1) (pair "" 2) (pair "abc" 3) (pair "b" 4) (pair "a" 5) (pair "aa" 6)))) (list "" "a" "aa" "ab" "abc" "b")) "String keys order bytewise with a prefix before its extensions")
      (assert (= (mapGet (mapFromPairs (list (pair "ab" 1) (pair "abc" 3) (pair "a" 5))) "abd") none) "a String key absent but sharing a prefix is not found")
      true))
