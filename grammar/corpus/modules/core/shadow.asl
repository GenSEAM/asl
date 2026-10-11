(module core/shadow :x [x g triple tripled scaled])

fn x -> Int64
  1

fn g x: Int64 -> Int64
  x

fn triple y: Int64 -> Int64
  (* y 3)

fn tripled n: Int64 -> Int64
  (triple n)

fn scaled xs: (List Int64) -> (List Int64)
  (let [(triple (fn [(y Int64)] -> Int64 (+ y 100)))] (map triple xs))
