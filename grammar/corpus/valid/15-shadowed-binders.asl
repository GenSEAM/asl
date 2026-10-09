"A binder inside an imported module must win over a top-level name it collides"

"with. The higher-order case is the sharp one: passing the shadowed name to"

"`map` compiled, type-checked and ran on both former targets while calling the wrong"

"function, so only a written-down expected output catches it."

(module shadowDemo :x [main stringFromShadow] :i [(core/shadow :a sh)])

fn stringFromShadow -> String
  (stringJoin (list (stringFromInt64 (sh/g 7)) (stringFromInt64 (sh/tripled 2)) (stringJoin (map (fn [(n Int64)] -> String (stringFromInt64 n)) (sh/scaled (list 1 2))) " ")) " ")

fn ! main args: (List String) -> (Result Unit IoError)
  (println (stringFromShadow))
