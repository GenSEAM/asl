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
