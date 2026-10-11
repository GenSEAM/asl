(module text/casing :x [shout area tally Shape] :i [(core/strings :a s)])

(schema Box (:f value T "The wrapped value"))

(enum Shape (:c circle [(radius Float64)] "A circle") (:c rectangle [(width Float64) (height Float64)] "An axis-aligned rectangle") (:c point [] "A degenerate zero-area shape"))

(enum Tree (:c leaf [] "An empty subtree") (:c node [(value T) (left (Tree T)) (right (Tree T))] "An interior node"))

fn swap p: (Pair A B) -> (Pair B A)
  (do "Exchange the two components of a pair." (match p ((pair a b) (pair b a))))

fn area sh: Shape -> Float64
  (match sh ((circle r) (* 3.14159 (* r r))) ((rectangle w h) (* w h)) ((point) 0.0))

fn shout x: String -> String
  (s/concat (s/upper x) "!")

fn tally ws: (List String) -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (w String)] -> (Map String Int64) (match (mapGet m w) ((some n) (mapSet m w (+ n 1))) ((none) (mapSet m w 1)))) (mapEmpty) ws)
