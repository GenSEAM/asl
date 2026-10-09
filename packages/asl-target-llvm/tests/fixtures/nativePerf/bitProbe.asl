(module asl-target-llvm/tests/fixtures/nativePerf/bitProbe
  :x [main rawOp]
  :i [])

fn arg args: (List String) i: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (listGet args i) "0")) 0)

fn rawOp which: String a: Int64 b: Int64 -> Int64
  (cond
    ((= which "and") (& a b))
    ((= which "or") (| a b))
    ((= which "xor") (^ a b))
    ((= which "not") (~ a))
    ((= which "shl") (<< a b))
    ((= which "shr") (>> a b))
    (else 0))

fn ! main args: (List String) -> (Result Unit String)
  (let [(which (optionOr (listHead args) ""))
        (a (arg args 1))
        (b (arg args 2))
        (boxed (cond
                 ((= which "and") ((fn [x y] (& x y)) a b))
                 ((= which "or") ((fn [x y] (| x y)) a b))
                 ((= which "xor") ((fn [x y] (^ x y)) a b))
                 ((= which "not") ((fn [x] (~ x)) a))
                 ((= which "shl") ((fn [x y] (<< x y)) a b))
                 ((= which "shr") ((fn [x y] (>> x y)) a b))
                 ((= which "andText") ((fn [x y] (& x y)) a which))
                 ((= which "notText") ((fn [x] (~ x)) which))
                 (else 0)))]
    (do (println (str (rawOp which a b) " " boxed))
        (ok ())))
