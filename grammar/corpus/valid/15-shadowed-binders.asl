(module shadowDemo :x [main stringFromShadow] :i [(core/shadow :a sh)])

fn stringFromShadow -> String
  (stringJoin (list (stringFromInt64 (sh/g 7)) (stringFromInt64 (sh/tripled 2)) (stringJoin (map (fn [(n Int64)] -> String (stringFromInt64 n)) (sh/scaled (list 1 2))) " ")) " ")

fn ! main args: (List String) -> (Result Unit IoError)
  (println (stringFromShadow))
