(module rcReuse
  :x [main]
  :i [])

enum Shape (circle r: Int64) (rect w: Int64 h: Int64)

enum Tag (one a: String) (two a: String b: String)

fn make i: Int64 -> Shape
  (if (= (mod i 3) 0) (circle i) (rect i (+ i 1)))

fn widen i: Int64 -> Shape
  (mt (make i)
    ((circle r) (circle (+ r 1)))
    ((rect w h) (rect h w)))

fn area s: Shape -> Int64
  (mt s ((circle r) r) ((rect w h) (* w h)))

fn parse i: Int64 -> (Result Int64 String)
  (if (= (mod i 7) 0) (err (str "bad " i)) (ok i))

fn bump i: Int64 -> (Result Int64 String)
  (mt (parse i) ((ok v) (ok (+ v 1))) ((err e) (err e)))

fn mk i: Int64 -> Tag
  (if (= (mod i 2) 0) (one (str "a" i)) (two (str "b" i) (str "c" i)))

fn size t: Tag -> Int64
  (mt t ((one a) (stringLength a)) ((two a b) (+ (stringLength a) (* 2 (stringLength b)))))

fn flip i: Int64 -> Tag
  (mt (mk i)
    ((one a) (one (stringConcat a "!")))
    ((two a b) (two b a)))

fn shared i: Int64 -> Int64
  (let [(t (mk i))
        (keep (pair t i))
        (u (mt t ((one a) (one a)) ((two a b) (two b a))))]
    (+ (size u) (size (pairFirst keep))))

fn loop i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc
    (loop (+ i 1) n (+ acc (+ (+ (area (widen i)) (mt (bump i) ((ok v) v) ((err e) (stringLength e)))) (+ (size (flip i)) (shared i))))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (loop 0 3000 0)))
      (ok 0))
