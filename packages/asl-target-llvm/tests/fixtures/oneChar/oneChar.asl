(module oneChar
  :x [main]
  :i [])

fn pick s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "?")

fn bare s: String i: Int64 -> String
  (match (stringSlice s i (+ i 1)) ((some x) x) ((none) "?"))

fn literal -> String
  "define internal ptr @strrt.single(ptr %src) {"

fn pieces s: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (= i n) acc (pieces s (+ i 1) n (cons (pick s (mod i (stringLength s))) acc)))

fn weigh xs: (List String) -> Int64
  (fold (fn [(a Int64) (x String)] -> Int64 (mod (+ (* a 31) (+ (stringLength x) (stringLength (str x x)))) 1000003)) 0 xs)

fn rounds r: Int64 s: String acc: Int64 -> Int64
  (if (= r 0) acc (rounds (- r 1) s (+ acc (weigh (pieces s 0 50000 (list))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(s (str "ab" (stringFromInt64 (listLength args)) "cdefghijklmnopqrstuvwxyz"))
        (xs (pieces s 0 100000 (list)))
        (joined (stringJoin (listReverse xs) ""))
        (twice (stringJoin (map (fn [(x String)] -> String (str x "")) xs) ""))]
    (do (println (str (stringLength joined) " " (stringLength twice) " " (optionOr (stringSlice joined 0 8) "")))
        (println (str (rounds 8 s 0) " " (= (pick s 3) (pick s 3)) " " (pick s 2)))
        (println (str (stringLength (stringJoin xs "")) " " (listLength xs)))
        (println (str (listLength (list (pick s 1) (pick s 4) joined))))
        (println (str (bare s 5) (bare s 6) (bare s 99) " " (stringLength (literal)) " " (stringSlice (literal) 0 6)))
        (ok 0)))
