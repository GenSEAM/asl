(module list/aggregate :x [agg aggEmpty lookup rank nanIdentity])

fn showFloats xs: (List Float64) -> String
  (str "[" (stringJoin (map (fn [v] (stringFromFloat64 v)) xs) ",") "]")

fn showInts xs: (List Int64) -> String
  (str "[" (stringJoin (map (fn [v] (stringFromInt64 v)) xs) ",") "]")

fn showFloat o: (Option Float64) -> String
  (match o ((some x) (stringFromFloat64 x)) ((none) "none"))

fn showInt o: (Option Int64) -> String
  (match o ((some n) (str "some " (stringFromInt64 n))) ((none) "none"))

fn report xs: (List Float64) -> String
  (stringJoin (list (if (listEmpty? xs) "T" "F") (stringFromInt64 (listLength xs)) (stringFromFloat64 (listSum xs)) (showFloat (listMin xs)) (showFloat (listMax xs)) (showFloats (listSort xs))) "|")

fn noFloats -> (List Float64)
  (list)

fn agg csv: String -> String
  (report (map (fn [t] (optionOr (stringToFloat64 t) 0.0)) (stringSplit csv ",")))

fn aggEmpty -> String
  (report (noFloats))

fn lookup csv: String needle: Int64 -> String
  (let [(xs (map (fn [t] (optionOr (stringToInt64 t) 0)) (stringSplit csv ",")))] (stringJoin (list (if (listContains? xs needle) "T" "F") (showInt (listIndexOf xs needle)) (stringFromInt64 (listLength xs)) (stringFromInt64 (listSum xs)) (showInts (listSortBy (fn [x] (- x)) xs))) "|"))

fn rank csv: String -> String
  (stringJoin (listSortBy (fn [t] (optionOr (stringToFloat64 t) 0.0)) (stringSplit csv ",")) "|")

fn nanIdentity csv: String -> String
  (let [(xs (map (fn [t] (optionOr (stringToFloat64 t) 0.0)) (stringSplit csv ","))) (h (optionOr (listHead xs) 0.0))] (stringJoin (list (if (listContains? xs h) "T" "F") (showInt (listIndexOf xs h)) (if (= xs xs) "T" "F") (if (= h h) "T" "F")) "|"))
