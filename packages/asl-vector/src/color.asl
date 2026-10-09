(module asl-vector/color :x [rgbToLab labDeltaE quantizeColor formatHexColor parseHexColor])

fn cbrtApprox v: F64 -> F64
  (if (<= v 0.0) 0.0 (let [(x0 (if (> v 1.0) (/ v 2.0) 0.5)) (x1 (/ (+ (* 2.0 x0) (/ v (* x0 x0))) 3.0)) (x2 (/ (+ (* 2.0 x1) (/ v (* x1 x1))) 3.0)) (x3 (/ (+ (* 2.0 x2) (/ v (* x2 x2))) 3.0))] x3))

fn rgbToLab r: Int g: Int b: Int -> (List F64)
  (let [(rf (/ (int64ToFloat64 r) 255.0)) (gf (/ (int64ToFloat64 g) 255.0)) (bf (/ (int64ToFloat64 b) 255.0)) (x (+ (* 0.4124564 rf) (+ (* 0.3575761 gf) (* 0.1804375 bf)))) (y (+ (* 0.2126729 rf) (+ (* 0.7151522 gf) (* 0.0721750 bf)))) (z (+ (* 0.0193339 rf) (+ (* 0.1191920 gf) (* 0.9503041 bf)))) (l (* 116.0 (- (if (> y 0.008856) (cbrtApprox y) (+ (* 7.787 y) 0.137931)) 0.137931))) (a (* 500.0 (- (if (> x 0.008856) (cbrtApprox x) (+ (* 7.787 x) 0.137931)) (if (> y 0.008856) (cbrtApprox y) (+ (* 7.787 y) 0.137931))))) (bVal (* 200.0 (- (if (> y 0.008856) (cbrtApprox y) (+ (* 7.787 y) 0.137931)) (if (> z 0.008856) (cbrtApprox z) (+ (* 7.787 z) 0.137931)))))] (list l a bVal))

fn labDeltaE lab1: (List F64) lab2: (List F64) -> F64
  (let [(l1 (optionOr (listHead lab1) 0.0)) (a1 (optionOr (listHead (optionOr (listTail lab1) (list))) 0.0)) (b1 (optionOr (listHead (optionOr (listTail (optionOr (listTail lab1) (list))) (list))) 0.0)) (l2 (optionOr (listHead lab2) 0.0)) (a2 (optionOr (listHead (optionOr (listTail lab2) (list))) 0.0)) (b2 (optionOr (listHead (optionOr (listTail (optionOr (listTail lab2) (list))) (list))) 0.0)) (dL (- l1 l2)) (da (- a1 a2)) (db (- b1 b2))] (sqrt (+ (* dL dL) (+ (* da da) (* db db)))))

fn quantizeColor colorRgb: (List Int) palette: (List (List Int)) -> (List Int)
  (if (listEmpty? palette) colorRgb (let [(firstPalette (optionOr (listHead palette) colorRgb)) (restPalette (optionOr (listTail palette) (list)))] (quantizeHelper colorRgb restPalette firstPalette (colorDistanceSq colorRgb firstPalette))))

fn quantizeHelper target: (List Int) remaining: (List (List Int)) best: (List Int) bestDist: F64 -> (List Int)
  (if (listEmpty? remaining) best (let [(candidate (optionOr (listHead remaining) best)) (tail (optionOr (listTail remaining) (list))) (dist (colorDistanceSq target candidate))] (if (< dist bestDist) (quantizeHelper target tail candidate dist) (quantizeHelper target tail best bestDist))))

fn colorDistanceSq c1: (List Int) c2: (List Int) -> F64
  (let [(r1 (int64ToFloat64 (optionOr (listHead c1) 0))) (g1 (int64ToFloat64 (optionOr (listHead (optionOr (listTail c1) (list))) 0))) (b1 (int64ToFloat64 (optionOr (listHead (optionOr (listTail (optionOr (listTail c1) (list))) (list))) 0))) (r2 (int64ToFloat64 (optionOr (listHead c2) 0))) (g2 (int64ToFloat64 (optionOr (listHead (optionOr (listTail c2) (list))) 0))) (b2 (int64ToFloat64 (optionOr (listHead (optionOr (listTail (optionOr (listTail c2) (list))) (list))) 0))) (dr (- r1 r2)) (dg (- g1 g2)) (db (- b1 b2))] (+ (* dr dr) (+ (* dg dg) (* db db))))

fn formatHexColor rgb: (List Int) -> String
  (let [(r (optionOr (listHead rgb) 0)) (g (optionOr (listHead (optionOr (listTail rgb) (list))) 0)) (b (optionOr (listHead (optionOr (listTail (optionOr (listTail rgb) (list))) (list))) 0))] (str "#" (hexPad2 r) (hexPad2 g) (hexPad2 b)))

fn hexPad2 val: Int -> String
  (let [(clamped (if (< val 0) 0 (if (> val 255) 255 val))) (hi (/ clamped 16)) (lo (mod clamped 16))] (str (nibbleToChar hi) (nibbleToChar lo)))

fn nibbleToChar n: Int -> String
  (if (< n 10) (str n) (if (== n 10) "a" (if (== n 11) "b" (if (== n 12) "c" (if (== n 13) "d" (if (== n 14) "e" "f"))))))

fn parseHexColor hex: String -> (List Int)
  (let [(clean (if (stringStartsWith? hex "#") (optionOr (stringSlice hex 1 (stringLength hex)) "") hex))] (if (>= (stringLength clean) 6) (list (hexByteAt clean 0) (hexByteAt clean 2) (hexByteAt clean 4)) (list 0 0 0)))

fn hexByteAt s: String idx: Int -> Int
  (let [(h1 (charToNibble (optionOr (stringSlice s idx (+ idx 1)) "0"))) (h2 (charToNibble (optionOr (stringSlice s (+ idx 1) (+ idx 2)) "0")))] (+ (* h1 16) h2))

fn charToNibble c: String -> Int
  (if (== c "0") 0 (if (== c "1") 1 (if (== c "2") 2 (if (== c "3") 3 (if (== c "4") 4 (if (== c "5") 5 (if (== c "6") 6 (if (== c "7") 7 (if (== c "8") 8 (if (== c "9") 9 (if (or (== c "a") (== c "A")) 10 (if (or (== c "b") (== c "B")) 11 (if (or (== c "c") (== c "C")) 12 (if (or (== c "d") (== c "D")) 13 (if (or (== c "e") (== c "E")) 14 (if (or (== c "f") (== c "F")) 15 0))))))))))))))))
