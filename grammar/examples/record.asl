(module asl/grammar/examples/record
  :x [Point origin moveBy describePoint]
  :i [])

; (:m :ref AGSURF :do "canonical example, principal 2026-10-15: schema and with, the current record spelling, kept beside greeting.asl so a surface can point here instead of re-typing a drifting copy")

(schema Point (:f x Int64) (:f y Int64))

fn origin -> Point
  (Point :x 0 :y 0)

fn moveBy p: Point dx: Int64 dy: Int64 -> Point
  (with p :x (+ p.x dx) :y (+ p.y dy))

fn describePoint p: Point -> String
  (str "(" (stringFromInt64 p.x) "," (stringFromInt64 p.y) ")")
