"Every numeric builtin at Int64 and at Float64, in the same shape, because"

"\"exercised\" has meant \"exercised at one type\": `/` and `mod` were counted as"

"covered while their Rust lowerings took i64 alone. The float leg is the half"

"that did not compile. Truncation toward zero, the zero divisor, the Int32"

"boundary and 2^53+1 each get their own case."

"The Int64 boundary is the second half: the type is fixed, so an operation whose"

"result leaves it traps rather than widening — which one former host did by not"

"having a width at all. A trap is not a value, so the .run expression cannot"

"assert one: each trap* function is expected to trap when called."

(module math/report :x [num fnum narrow minmax edge fromFloat wrapMod trapDiv trapNeg trapAbs trapAdd trapSub trapMul trapSum])

fn oi o: (Option Int64) -> String
  (match o ((some n) (str "some " (stringFromInt64 n))) ((none) "none"))

fn of o: (Option Float64) -> String
  (match o ((some x) (str "some " (stringFromFloat64 x))) ((none) "none"))

fn num a: Int64 b: Int64 -> String
  (if (= b 0) (stringJoin (list (oi (checkedDiv a b)) (oi (checkedMod a b))) "|") (stringJoin (list (stringFromInt64 (+ a b)) (stringFromInt64 (/ a b)) (stringFromInt64 (mod a b)) (stringFromInt64 (* a b)) (stringFromInt64 (- a b)) (stringFromInt64 (abs a)) (stringFromInt64 (- a)) (stringFromInt64 (min a b)) (stringFromInt64 (max a b)) (oi (checkedDiv a b)) (oi (checkedMod a b))) "|"))

fn fnum a: Int64 b: Int64 -> String
  (let [(x (int64ToFloat64 a)) (y (int64ToFloat64 b))] (if (= b 0) (stringJoin (list (of (checkedDiv x y)) (of (checkedMod x y))) "|") (stringJoin (list (stringFromFloat64 (+ x y)) (stringFromFloat64 (/ x y)) (stringFromFloat64 (mod x y)) (stringFromFloat64 (* x y)) (stringFromFloat64 (- x y)) (stringFromFloat64 (abs x)) (stringFromFloat64 (- x)) (stringFromFloat64 (min x y)) (stringFromFloat64 (max x y)) (of (checkedDiv x y)) (of (checkedMod x y))) "|")))

fn narrow a: Int64 -> String
  (let [(wide (optionMap (fn [n] (int32ToInt64 n)) (int64ToInt32 a))) (f (int64ToFloat64 a))] (stringJoin (list (oi wide) (stringFromFloat64 f) (oi (float64ToInt64 f))) "|"))

fn minmax a: String b: String -> String
  (let [(x (optionOr (stringToFloat64 a) 0.0)) (y (optionOr (stringToFloat64 b) 0.0))] (stringJoin (list (stringFromFloat64 (min x y)) (stringFromFloat64 (max x y)) (oi (float64ToInt64 x))) "|"))

fn int64Min -> Int64
  (- (- 9223372036854775807) 1)

fn edge b: Int64 -> String
  (stringJoin (list (oi (checkedDiv (int64Min) b)) (oi (checkedMod (int64Min) b))) "|")

fn fromFloat t: String -> String
  (let [(x (optionOr (stringToFloat64 t) 0.0))] (stringJoin (list (oi (float64ToInt64 x)) (oi (stringToInt64 t))) "|"))

fn wrapMod -> Int64
  (mod (int64Min) (- 1))

fn trapDiv -> Int64
  (/ (int64Min) (- 1))

fn trapNeg -> Int64
  (- (int64Min))

fn trapAbs -> Int64
  (abs (int64Min))

fn trapAdd -> Int64
  (+ 9223372036854775807 1)

fn trapSub -> Int64
  (- (int64Min) 1)

fn trapMul -> Int64
  (* 9223372036854775807 2)

fn trapSum -> Int64
  (listSum (list 9223372036854775807 1))
