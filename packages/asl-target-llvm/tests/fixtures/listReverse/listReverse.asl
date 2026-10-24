(module listReverse
  :x [main]
  :i [])

fn build i: Int64 n: Int64 acc: (List Int64) -> (List Int64)
  (if (= i n) acc (build (+ i 1) n (cons i acc)))

fn digits xs: (List Int64) -> String
  (stringJoin (map (fn [(x Int64)] -> String (stringFromInt64 x)) xs) ",")

fn weigh xs: (List Int64) -> Int64
  (pairSecond (fold (fn [(a (Pair Int64 Int64)) (v Int64)] -> (Pair Int64 Int64) (pair (+ (pairFirst a) 1) (+ (pairSecond a) (* (pairFirst a) v)))) (pair 0 0) xs))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(big (listReverse (build 0 100000 (list))))
        (shared (list 1 2 3))
        (partial (listReverse (cons 9 (cons 8 shared))))
        (whole (listReverse shared))
        (names (listReverse (list "a" (str "b" (stringFromInt64 (listLength shared))) "c")))
        (twice (listReverse (listReverse (build 0 5 (list)))))
        (empty (listReverse (list)))]
    (do (println (str (weigh big) " " (listLength big)))
        (println (str (digits partial) " " (digits whole) " " (digits shared)))
        (println (str (stringJoin names ",") " " (digits twice) " " (listLength empty)))
        (ok 0)))
