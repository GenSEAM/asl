(module aslExamples/enumExample
  :x [Shape area describe])

enum Shape (circle r: Int64) (square side: Int64) (dot)

fn area s: Shape -> Int64
  (match s
    ((circle r) (* r r))
    ((square side) (* side side))
    ((dot) 0))

fn describe s: Shape -> String
  (match s
    ((circle r) (str "circle " (stringFromInt64 r)))
    ((square side) (str "square " (stringFromInt64 side)))
    ((dot) "dot"))
