(module mapReuse
  :x [main]
  :i [])

fn keyAt i: Int64 -> Int64
  (mod (* i 7919) 100003)

fn fill i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (fill (+ i 1) n (mapSet m (keyAt i) i)))

fn bump i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (bump (+ i 1) n (mapSet m (keyAt i) (+ (mapGetOr m (keyAt i) 0) 1000000))))

fn drop i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (>= i n) m (drop (+ i 1) n (mapRemove m (keyAt i))))

fn total i: Int64 n: Int64 m: (Map Int64 Int64) acc: Int64 -> Int64
  (if (>= i n) acc (total (+ i 1) n m (+ acc (mapGetOr m (keyAt i) 0))))

fn present i: Int64 n: Int64 m: (Map Int64 Int64) acc: Int64 -> Int64
  (if (>= i n) acc (present (+ i 1) n m (if (mapHas? m (keyAt i)) (+ acc 1) acc)))

fn view m: (Map Int64 Int64) -> String
  (str (mapSize m) ":" (present 0 4000 m 0) ":" (total 0 4000 m 0) ":" (fold (fn [(a Int64) (k Int64)] -> Int64 (mod (+ (* a 31) k) 1000000007)) 0 (mapKeys m)))

fn words i: Int64 n: Int64 m: (Map String Int64) -> (Map String Int64)
  (if (>= i n) m (words (+ i 1) n (mapSet m (str "w" (mod (* i 37) 211)) (+ (mapGetOr m (str "w" (mod (* i 37) 211)) 0) i))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(m1 (fill 0 3000 (mapEmpty)))
        (snap m1)
        (m2 (bump 0 1500 (fill 3000 4000 m1)))
        (holder (list m2 (mapEmpty)))
        (m3 (drop 0 700 (bump 1000 2000 m2)))
        (seen (fn [] -> String (view m3)))
        (m4 (fill 0 4000 (drop 2000 3500 m3)))
        (m5 (mapFromPairs (mapPairs m4)))
        (s1 (words 0 3000 (mapEmpty)))
        (s2 (mapRemove (mapSet s1 "w5" -1) "w7"))
        (u (drop 0 4000 (bump 0 4000 (fill 0 4000 (mapEmpty)))))]
    (do (println (str "snap " (view snap)))
        (println (str "m2 " (view m2)))
        (println (str "held " (view (optionOr (listHead holder) (mapEmpty)))))
        (println (str "m3 " (view m3)))
        (println (str "seen " (seen)))
        (println (str "m4 " (view m4) " " (= m4 m5)))
        (println (str "s1 " (mapSize s1) " " (mapGetOr s1 "w5" 0) " " (mapGetOr s1 "w7" 0) " " (mapHas? s1 "w7")))
        (println (str "s2 " (mapSize s2) " " (mapGetOr s2 "w5" 0) " " (mapGetOr s2 "w7" 0) " " (mapHas? s2 "w7")))
        (println (str "u " (view u)))
        (ok 0)))
