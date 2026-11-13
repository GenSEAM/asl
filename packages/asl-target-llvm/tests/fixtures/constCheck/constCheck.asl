(module constCheck
  :x [main]
  :i [])

fn upLoop i: Int64 n: Int64 -> Int64
  (if (= i n) i (upLoop (+ i 1) n))

fn leftLoop i: Int64 n: Int64 -> Int64
  (if (= i n) i (leftLoop (+ 5 i) n))

fn downLoop i: Int64 n: Int64 -> Int64
  (if (= i n) i (downLoop (- i 3) n))

fn addNegLoop i: Int64 n: Int64 -> Int64
  (if (= i n) i (addNegLoop (+ i -4) n))

fn subNegLoop i: Int64 n: Int64 -> Int64
  (if (= i n) i (subNegLoop (- i -2) n))

fn zeroLoop i: Int64 k: Int64 -> Int64
  (if (= k 0) i (zeroLoop (+ i 0) (- k 1)))

fn varLoop i: Int64 n: Int64 d: Int64 -> Int64
  (if (= i n) i (varLoop (+ i d) n d))

fn nonStep x: Int64 -> Int64
  (+ x 1)

fn subVar x: Int64 y: Int64 -> Int64
  (- x y)

fn shiftConst x: Int64 -> Int64
  (<< x 13)

fn shiftVar x: Int64 k: Int64 -> Int64
  (<< x k)

fn line label: String v: Int64 -> Unit
  (println (str label " " (stringFromInt64 v)))

fn maxInt -> Int64 9223372036854775807
fn minInt -> Int64 (- (- 0 9223372036854775807) 1)

fn ! run which: String n: Int64 -> Unit
  (cond
    ((= which "ok") (do (line "upLoop" (upLoop (- (maxInt) (+ n 3)) (maxInt)))
                        (line "leftLoop" (leftLoop (- (maxInt) (+ n 10)) (maxInt)))
                        (line "downLoop" (downLoop (+ (minInt) (+ n 6)) (minInt)))
                        (line "addNegLoop" (addNegLoop (+ (minInt) (+ n 8)) (minInt)))
                        (line "subNegLoop" (subNegLoop (- (maxInt) (+ n 4)) (maxInt)))
                        (line "zeroLoop" (zeroLoop (+ n 7) 3))
                        (line "varLoop" (varLoop (- (maxInt) (+ n 20)) (maxInt) 10))
                        (line "nonStep" (nonStep (- (maxInt) (+ n 1))))
                        (line "subVar" (subVar (+ (minInt) 10) (+ n 10)))
                        (line "shiftConst" (shiftConst (+ n 3)))
                        (line "shiftVar" (shiftVar (+ n 3) (+ n 64)))))
    ((= which "upOver") (line "upOver" (upLoop (- (maxInt) (+ n 1)) (- (maxInt) 3))))
    ((= which "leftOver") (line "leftOver" (leftLoop (- (maxInt) (+ n 9)) (maxInt))))
    ((= which "downOver") (line "downOver" (downLoop (+ (minInt) (+ n 5)) (minInt))))
    ((= which "addNegOver") (line "addNegOver" (addNegLoop (+ (minInt) (+ n 7)) (minInt))))
    ((= which "subNegOver") (line "subNegOver" (subNegLoop (- (maxInt) (+ n 3)) (maxInt))))
    ((= which "varOver") (line "varOver" (varLoop (- (maxInt) (+ n 19)) (maxInt) 10)))
    ((= which "nonStepOver") (line "nonStepOver" (nonStep (- (maxInt) n))))
    ((= which "subVarOver") (line "subVarOver" (subVar (+ (minInt) 10) (+ n 11))))
    (else (line "unknown" 0)))

fn ! main args: (List String) -> (Result Unit String)
  (do (run (optionOr (listHead args) "ok") (optionOr (stringToInt64 (optionOr (listGet args 1) "0")) 0))
      (ok ()))
