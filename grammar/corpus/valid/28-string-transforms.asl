(module string/transform :x [transform])

fn showInt o: (Option Int64) -> String
  (match o ((some n) (str "some " (stringFromInt64 n))) ((none) "none"))

fn transform line: String -> String
  (stringJoin (list (stringLower line) (stringUpper line) (stringReverse line) (stringReplace line "X" "-") (stringJoin (stringSplit line " ") "+") (str "n=" (stringFromInt64 (stringLength line))) (showInt (stringToInt64 line)) (stringFromFloat64 (optionOr (stringToFloat64 line) 0.0))) "|")
