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
        newModExports (list (pair "src/n.asl" "(module n\n  :x [pubFn other]\n  :i [])\n\nfn pubFn x: Int64 -> Int64\n  (+ x 1)\n\nfn other -> Int64\n  2"))
        newModHead (list (pair "src/n.asl" ""))
        newModMain (list (pair "src/n.asl" "(module n\n  :x [main]\n  :i [])\n\nfn main -> Int64\n  0"))
        newModPrivate (list (pair "src/n.asl" "(module n\n  :x [pubFn]\n  :i [])\n\nfn pubFn x: Int64 -> Int64\n  (+ x 1)\n\nfn hidden x: Int64 -> Int64\n  x"))
        mainExisting (list (pair "src/a.asl" "fn main -> Int64\n  0\n\nfn extra -> Int64\n  1"))
        mainNewNow (list (pair "src/a.asl" "fn main -> Int64\n  0"))
        mainNewHead (list (pair "src/a.asl" "fn other -> Int64\n  1"))
        exportedCalledNow (list (pair "src/a.asl" "(module a\n  :x [helper]\n  :i [])\n\nfn helper x: Int64 -> Int64\n  (+ x 1)\n\nfn main -> Int64\n  (helper 1)"))]
    (do
      (assert (listEmpty? (gi/unwiredFns calledNow headA)) "a new helper called by another fn in the same file is wired")
      (assert (= (gi/unwiredFns uncalledNow headA) (list "helper")) "a new helper called nowhere is listed")
      (assert (listEmpty? (gi/unwiredFns oldNow oldHead)) "a fn that existed at head is never listed")
      (assert (listEmpty? (gi/unwiredFns crossNow crossHead)) "a new fn called only from a second impl file is wired")
      (assert (= (gi/unwiredFns exportedUncalledNow headA) (list "helper")) "an exported new fn called nowhere is listed")
      (assert (listEmpty? (gi/unwiredFns exportedCalledNow headA)) "an exported new fn called by another fn is wired")
      (assert (listEmpty? (gi/unwiredFns newModExports newModHead)) "exports of a new module are not listed")
      (assert (listEmpty? (gi/unwiredFns newModMain newModHead)) "main of a new module is not listed")
      (assert (= (gi/unwiredFns newModPrivate newModHead) (list "hidden")) "a private new fn in a new module is listed")
      (assert (= (gi/unwiredFns mainExisting headA) (list "extra")) "main is never listed, a new fn in an existing module is")
      (assert (listEmpty? (gi/unwiredFns mainNewNow mainNewHead)) "a new main entry point is never listed")
      true))
