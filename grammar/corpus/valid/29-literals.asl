"A sign belongs to the digits it precedes. `-1` used to be read as the"

"subtraction operator applied to `1` — a legal parse of the same characters,"

"and the one the Earley resolver chose — so `(+ x -1)` lowered to"

"`_agentscript.add(x, _)` and `rt::add(x.clone(), _.clone())`: the wildcard token,"

"leaking out of pattern position, on both backends at once. No fixture had ever"

"written a negative number, so every gate was green over it."

"Every literal form that can carry a sign is here, because a sign is not the"

"only thing a literal can get wrong: both integer widths at both boundaries"

"(Int64::MIN has no positive counterpart, so it exists only as a signed"

"literal), a negative float, negative zero, a negative literal as a match"

"pattern, as a field default, and inside an elided lambda."

(module math/literals :x [signs floats near step])

(schema Cursor (:f at Int64 "Position, before anything has moved it." :default -1))

fn signs x: Int64 -> String
  (stringJoin (list (stringFromInt64 (+ x -1)) (stringFromInt64 (- x -1)) (stringFromInt64 (* x -2)) (stringFromInt64 (- -5)) (stringFromInt64 (min x -9223372036854775808)) (stringFromInt64 (max x -9223372036854775808)) (stringFromInt64 9223372036854775807) (stringFromInt64 -9223372036854775808) (stringFromInt64 (int32ToInt64 2147483647)) (stringFromInt64 (int32ToInt64 -2147483648))) "|")

fn floats x: Float64 -> String
  (stringJoin (list (stringFromFloat64 (+ x -1.5)) (stringFromFloat64 -0.0) (stringFromFloat64 (* x -1.0)) (stringFromFloat64 (/ -3.0 2.0))) "|")

fn near x: Int64 -> String
  (stringJoin (list (match x (-1 "minus-one") (_ "other")) (stringFromInt64 (Cursor :at -1).at) (stringJoin (map (fn [n] (stringFromInt64 (* n -1))) (list 1 2)) ",")) "|")

fn step n: Int32 -> Int32
  (+ n -1)
