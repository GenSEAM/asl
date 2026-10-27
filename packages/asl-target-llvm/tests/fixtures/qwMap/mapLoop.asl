(module mapLoop
  :x [main churn tally probe]
  :i [])

fn churn i: Int64 n: Int64 m: (Map Int64 Int64) -> (Map Int64 Int64)
  (if (= i n) m
    (let [(k (mod (* i 7) 16))
          (old (optionOr (mapGet m k) 0))]
      (churn (+ i 1) n (mapSet m k (mod (+ old i) 1000003)))))

fn tally i: Int64 n: Int64 m: (Map String Int64) -> (Map String Int64)
  (if (= i n) m
    (let [(k (str "k" (stringFromInt64 (mod i 5))))
          (old (optionOr (mapGet m k) 100))]
      (tally (+ i 1) n (mapSet m k (+ old i)))))

fn probe m: (Map Int64 Int64) k: Int64 -> Int64
  (match (mapGet m k)
    ((some v) v)
    ((none) -1))

fn ! main args: (List String) -> (Result Unit String)
  (let [(n (optionOr (stringToInt64 (optionOr (listHead args) "1000")) 1000))
        (m (churn 0 n (mapEmpty)))
        (t (tally 0 n (mapEmpty)))]
    (do (println (str (mapSize m) " " (fold (fn [(a Int64) (v Int64)] -> Int64 (+ a v)) 0 (mapValues m))))
        (println (str (mapSize t) " " (fold (fn [(a Int64) (v Int64)] -> Int64 (+ a v)) 0 (mapValues t))
                      " " (optionOr (mapGet t "k0") -1) " " (optionOr (mapGet t "none") -1)
                      " " (stringFromInt64 (probe m 3)) " " (stringFromInt64 (probe m 99))))
        (ok ())))
