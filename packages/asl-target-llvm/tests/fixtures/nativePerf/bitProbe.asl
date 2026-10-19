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

; (:m :ref CLUSTER-U4GATE-RESTRUCTURE :do "andText/notText moved out to bitAndTextProbe.asl/bitNotTextProbe.asl: each applied &/~ to a String Val, a genuine static type error (confirmed via asl check in isolation), not a runtime trap like the rest of main's boxed cond; U4-MARKER-PARITY's whole-file gate on nativeTest run rejected the whole bitProbe.asl file over them, blocking every well-typed bitCases case in the same file")
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
                 (else 0)))]
    (do (println (str (rawOp which a b) " " boxed))
        (ok ())))
