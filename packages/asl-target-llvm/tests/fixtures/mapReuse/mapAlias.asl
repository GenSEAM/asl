(module mapAlias
  :x [main]
  :i [])

schema Box
  m: (Map Int64 Int64)
  tag: Int64

fn keyAt i: Int64 -> Int64
  (mod (* i 7919) 1009)

fn fill i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (fill (+ i 1) n (mapSet m (keyAt i) i)))

fn bump i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (bump (+ i 1) n (mapSet m (keyAt i) (+ (mapGetOr m (keyAt i) 0) 1000))))

fn drop i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (drop (+ i 1) n (mapRemove m (keyAt i))))

fn view m: (Map Int64 Int64) -> String
  (str (mapSize m) ":" (fold (fn [(a Int64) (p (Pair Int64 Int64))] -> Int64 (mod (+ (* a 31) (+ (* 7 (pairFirst p)) (pairSecond p))) 1000000007)) 0 (mapPairs m)))

fn keepAndSet m: (Map Int64 Int64) -> (Pair (Map Int64 Int64) (Map Int64 Int64))
  (pair m (bump 0 50 (drop 50 80 m)))

fn versions i: Int64 n: Int64 m: (Map Int64 Int64) acc: (List (Map Int64 Int64)) -> (List (Map Int64 Int64))
  (if (>= i n) (cons m acc)
    (versions (+ i 1) n (if (= (mod i 3) 0) (mapRemove m (keyAt (- i 1))) (mapSet m (keyAt i) (* i 3))) (cons m acc)))

fn nestedFill i: Int64 n: Int64 o: (Map String (Map Int64 Int64)) -> (Map String (Map Int64 Int64))
  (if (>= i n) o
    (let [(name (str "k" (mod i 5)))
          (inner (mapGetOr o name (mapEmpty)))]
      (nestedFill (+ i 1) n (mapSet o name (mapSet inner (keyAt i) i)))))

fn nview o: (Map String (Map Int64 Int64)) -> String
  (stringJoin (map (fn [(p (Pair String (Map Int64 Int64)))] -> String (str (pairFirst p) "=" (view (pairSecond p)))) (mapPairs o)) ",")

fn strFill i: Int64 n: Int64 m: (Map String String) -> (Map String String)
  (if (>= i n) m (strFill (+ i 1) n (mapSet m (str "s" (mod (* i 13) 97)) (str (mapGetOr m (str "s" (mod (* i 13) 97)) "") "x" i))))

fn strDrop i: Int64 n: Int64 m: (Map String String) -> (Map String String)
  (if (>= i n) m (strDrop (+ i 1) n (mapRemove m (str "s" (mod (* i 13) 97)))))

fn sview m: (Map String String) -> String
  (str (mapSize m) ":" (fold (fn [(a Int64) (p (Pair String String))] -> Int64 (mod (+ (* a 31) (+ (stringLength (pairFirst p)) (* 3 (stringLength (pairSecond p))))) 1000000007)) 0 (mapPairs m)) ":" (mapGetOr m "s5" "-"))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(m0 (fill 0 600 (mapEmpty)))
        (held (list m0))
        (box (Box :m m0 :tag 1))
        (cl (fn [] -> String (view m0)))
        (hm (hashMapSet (hashMapEmpty) "a" m0))
        (m1 (bump 0 600 m0))
        (m1b (drop 0 300 m1))
        (kp (keepAndSet m1b))
        (same1 (str (view (mapSet m1b 3 77)) "|" (view m1b)))
        (same2 (= m1b (mapSet m1b (keyAt 400) 5)))
        (vs (versions 1 200 (fill 0 100 (mapEmpty)) (list)))
        (o (nestedFill 0 400 (mapEmpty)))
        (oInner (mapGetOr o "k1" (mapEmpty)))
        (o2 (nestedFill 400 800 o))
        (o3 (mapSet o2 "k2" (mapEmpty)))
        (s0 (strFill 0 500 (mapEmpty)))
        (s1 (strDrop 0 40 (strFill 500 900 s0)))
        (s2 (strFill 0 300 s1))
        (fromHm (hashMapGetOr hm "a" (mapEmpty)))
        (hm2 (hashMapSet hm "b" (bump 0 100 fromHm)))
        (r1 (mapRemove (drop 0 200 m0) (keyAt 300)))
        (r2 (drop 300 600 r1))]
    (do (println (str "m0 " (view m0)))
        (println (str "held " (view (optionOr (listHead held) (mapEmpty)))))
        (println (str "box " (view box.m)))
        (println (str "cl " (cl)))
        (println (str "hm a " (view (hashMapGetOr hm "a" (mapEmpty)))))
        (println (str "hm2 a " (view (hashMapGetOr hm2 "a" (mapEmpty))) " b " (view (hashMapGetOr hm2 "b" (mapEmpty)))))
        (println (str "m1 " (view m1) " m1b " (view m1b)))
        (println (str "kp " (view (pairFirst kp)) " " (view (pairSecond kp))))
        (println (str "same1 " same1 " same2 " same2))
        (println (str "vs " (listLength vs) " " (fold (fn [(a Int64) (m (Map Int64 Int64))] -> Int64 (mod (+ (* a 17) (+ (mapSize m) (fold (fn [(b Int64) (v Int64)] -> Int64 (+ b v)) 0 (mapValues m)))) 1000000007)) 0 vs)))
        (println (str "o " (nview o)))
        (println (str "oInner " (view oInner)))
        (println (str "o2 " (nview o2)))
        (println (str "o3 " (nview o3)))
        (println (str "s0 " (sview s0) " s1 " (sview s1) " s2 " (sview s2)))
        (println (str "r1 " (view r1) " r2 " (view r2)))
        (println (str "m0again " (view m0) " " (cl)))
        (ok 0)))
