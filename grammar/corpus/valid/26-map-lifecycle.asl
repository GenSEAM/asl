"A map built, queried and shrunk, with its size printed before and after the"

"removal: a mapRemove that does nothing is indistinguishable from a correct one"

"unless both sizes are shown, and one case removes a key that is absent. The key"

"order is the specification's, not the insertion order, and the two former"

"backends reached it by different routes — sorted() on one, BTreeMap on the other."

(module map/lifecycle :x [lifecycle counts])

fn tally m: (Map String Int64) w: String -> (Map String Int64)
  (match (mapGet m w) ((some n) (mapSet m w (+ n 1))) ((none) (mapSet m w 1)))

fn counts words: String -> (Map String Int64)
  (fold tally (mapEmpty) (filter (fn [w] (not (stringEmpty? w))) (stringSplit words " ")))

fn lifecycle words: String drop: String -> String
  (let [(m (counts words)) (m2 (mapRemove m drop))] (stringJoin (list (stringFromInt64 (mapSize m)) (if (mapHas? m drop) "T" "F") (stringFromInt64 (mapSize m2)) (stringJoin (mapKeys m2) ",")) "|"))
