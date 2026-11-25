(module asl-text/wildcard :x [globMatch pathMatch] :i [])

fn ch s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn classClose p: String from: Int64 -> Int64
  (if (>= from (stringLength p))
    -1
    (if (= (ch p from) "]")
      from
      (classClose p (+ from 1))))

fn classScan cls: String c: String i: Int64 -> Bool
  (cond
    ((>= i (stringLength cls)) false)
    ((and (< (+ i 2) (stringLength cls)) (= (ch cls (+ i 1)) "-"))
      (if (and (>= (charCode c) (charCode (ch cls i))) (<= (charCode c) (charCode (ch cls (+ i 2)))))
        true
        (classScan cls c (+ i 3))))
    ((= c (ch cls i)) true)
    (else (classScan cls c (+ i 1))))

fn classHit cls: String c: String -> Bool
  (if (stringStartsWith? cls "!")
    (not (classScan (optionOr (stringSlice cls 1 (stringLength cls)) "") c 0))
    (classScan cls c 0))

fn starTry p: String s: String pi: Int64 k: Int64 path: Bool cross: Bool -> Bool
  (if (matchFrom p s pi k path)
    true
    (if (>= k (stringLength s))
      false
      (if (and path (not cross) (= (ch s k) "/"))
        false
        (starTry p s pi (+ k 1) path cross))))

fn starCase p: String s: String pi: Int64 si: Int64 path: Bool -> Bool
  (if (and path (= (ch p (+ pi 1)) "*"))
    (if (= (ch p (+ pi 2)) "/")
      (or (matchFrom p s (+ pi 3) si path) (starTry p s (+ pi 2) si path true))
      (starTry p s (+ pi 2) si path true))
    (starTry p s (+ pi 1) si path false))

fn qCase p: String s: String pi: Int64 si: Int64 path: Bool -> Bool
  (if (>= si (stringLength s))
    false
    (if (and path (= (ch s si) "/"))
      false
      (matchFrom p s (+ pi 1) (+ si 1) path)))

fn litCase p: String s: String pi: Int64 si: Int64 path: Bool -> Bool
  (if (and (< si (stringLength s)) (= (ch s si) (ch p pi)))
    (matchFrom p s (+ pi 1) (+ si 1) path)
    false)

fn bracketCase p: String s: String pi: Int64 si: Int64 path: Bool -> Bool
  (let [(close (classClose p (+ pi 1)))]
    (if (< close 0)
      (litCase p s pi si path)
      (if (>= si (stringLength s))
        false
        (if (and path (= (ch s si) "/"))
          false
          (if (classHit (optionOr (stringSlice p (+ pi 1) close) "") (ch s si))
            (matchFrom p s (+ close 1) (+ si 1) path)
            false)))))

fn matchFrom p: String s: String pi: Int64 si: Int64 path: Bool -> Bool
  (if (>= pi (stringLength p))
    (= si (stringLength s))
    (let [(c (ch p pi))]
      (cond
        ((= c "*") (starCase p s pi si path))
        ((= c "?") (qCase p s pi si path))
        ((= c "[") (bracketCase p s pi si path))
        (else (litCase p s pi si path)))))

fn globMatch pattern: String s: String -> Bool
  (matchFrom pattern s 0 0 false)

fn pathMatch pattern: String s: String -> Bool
  (matchFrom pattern s 0 0 true)
