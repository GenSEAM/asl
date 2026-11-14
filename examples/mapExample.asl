(module aslExamples/mapExample
  :x [counts getOr bump sortedKeys])

fn counts ws: (List String) -> (Map String Int64)
  (fold (fn [m w] (mapSet m w (+ 1 (optionOr (mapGet m w) 0)))) (mapEmpty) ws)

fn getOr m: (Map String Int64) k: String d: Int64 -> Int64
  (optionOr (mapGet m k) d)

fn bump m: (Map String Int64) k: String -> (Map String Int64)
  (mapSet m k (+ 1 (getOr m k 0)))

fn sortedKeys m: (Map String Int64) -> (List String)
  (listSort (mapKeys m))
