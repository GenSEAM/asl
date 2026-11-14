(module aslExamples/optionExample
  :x [firstOrZero lookupOr describe])

fn firstOrZero xs: (List Int64) -> Int64
  (match (listHead xs)
    ((none) 0)
    ((some h) h))

fn lookupOr m: (Map String Int64) k: String d: Int64 -> Int64
  (optionOr (mapGet m k) d)

fn describe xs: (List Int64) -> String
  (match (listHead xs)
    ((none) "empty")
    ((some h) (str "head " (stringFromInt64 h))))
