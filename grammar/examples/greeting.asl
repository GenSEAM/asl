(module asl/grammar/examples/greeting
  :x [Shape describeShape mkCircle mkSquare greet makeGreeting!]
  :i [])

; (:m :ref AGSURF :do "canonical example, principal 2026-10-15: the current syntax only, so agent-facing surfaces have one real source to quote instead of hand-written duplicates that drift to the old spelling; match instead of mt, fn name! instead of fn ! name")

(enum Shape (:c circle [(r Int64)] "A circle of radius r") (:c square [(side Int64)] "A square of side length side"))

fn describeShape s: Shape -> String
  (match s
    ((circle r) (str "circle r=" (stringFromInt64 r)))
    ((square side) (str "square side=" (stringFromInt64 side))))

fn mkCircle r: Int64 -> Shape
  (circle r)

fn mkSquare side: Int64 -> Shape
  (square side)

fn greet name: String -> String
  (str "Hello, " name "!")

fn makeGreeting! name: String -> String
  (greet name)
