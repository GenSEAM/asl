"Reshaping a list, with the composed return shapes the former differential harness"

"had to encode: `(Option (List T))` and `(List (Pair A B))`. The slice cases sit on"

"both ends of the half-open interval, and `listGet` reads index 1 — neither the"

"head nor the last element, so an off-by-one is visible."

(module list/reshape :x [reshape window pairs])

fn showList xs: (List Int64) -> String
  (str "[" (stringJoin (map (fn [v] (stringFromInt64 v)) xs) ",") "]")

fn showOpt o: (Option Int64) -> String
  (match o ((some n) (str "some " (stringFromInt64 n))) ((none) "none"))

fn showOptList o: (Option (List Int64)) -> String
  (match o ((some xs) (str "some " (showList xs))) ((none) "none"))

fn reshape n: Int64 -> String
  (let [(xs (range 0 n)) (ys (list 100 200 300))] (stringJoin (list (showList (cons 9 xs)) (showList (listAppend xs ys)) (showList (listReverse xs)) (showOptList (listTail xs)) (showOpt (listHead xs)) (showOpt (listGet xs 1))) "|"))

fn window n: Int64 a: Int64 b: Int64 -> (Option (List Int64))
  (listSlice (range 0 n) a b)

fn pairs n: Int64 -> (List (Pair Int64 String))
  (zip (range 0 n) (list "a" "b" "c"))
