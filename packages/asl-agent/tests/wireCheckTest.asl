(module aslAgent/tests/wireCheckTest
  :x [runTests]
  :i [(aslAgent/gateIntegrity :a gi)])

fn runTests -> Bool
  (let [headA (list (pair "src/a.asl" "fn main -> Int64\n  0"))
        calledNow (list (pair "src/a.asl" "fn helper x: Int64 -> Int64\n  (+ x 1)\n\nfn main -> Int64\n  (helper 1)"))
        uncalledNow (list (pair "src/a.asl" "fn helper x: Int64 -> Int64\n  (+ x 1)\n\nfn main -> Int64\n  0"))
        oldNow (list (pair "src/a.asl" "fn old x: Int64 -> Int64\n  (+ x 1)"))
        oldHead (list (pair "src/a.asl" "fn old x: Int64 -> Int64\n  x"))
        crossNow (list (pair "src/a.asl" "fn helper x: Int64 -> Int64\n  (+ x 1)") (pair "src/b.asl" "fn main -> Int64\n  (helper 1)"))
        crossHead (list (pair "src/a.asl" "") (pair "src/b.asl" "fn main -> Int64\n  0"))
        exportedUncalledNow (list (pair "src/a.asl" "(module a\n  :x [helper]\n  :i [])\n\nfn helper x: Int64 -> Int64\n  (+ x 1)\n\nfn main -> Int64\n  0"))
        exportedCalledNow (list (pair "src/a.asl" "(module a\n  :x [helper]\n  :i [])\n\nfn helper x: Int64 -> Int64\n  (+ x 1)\n\nfn main -> Int64\n  (helper 1)"))]
    (do
      (assert (listEmpty? (gi/unwiredFns calledNow headA)) "a new helper called by another fn in the same file is wired")
      (assert (= (gi/unwiredFns uncalledNow headA) (list "helper")) "a new helper called nowhere is listed")
      (assert (listEmpty? (gi/unwiredFns oldNow oldHead)) "a fn that existed at head is never listed")
      (assert (listEmpty? (gi/unwiredFns crossNow crossHead)) "a new fn called only from a second impl file is wired")
      (assert (= (gi/unwiredFns exportedUncalledNow headA) (list "helper")) "an exported new fn called nowhere is listed")
      (assert (listEmpty? (gi/unwiredFns exportedCalledNow headA)) "an exported new fn called by another fn is wired")
      true))
