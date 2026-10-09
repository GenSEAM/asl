(module asl-ir/tests/lowerClosureTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)
      (asl-ir/link :a lk)])

fn joinLines xs: (List String) -> String
  (stringJoin xs "\n")

fn printed res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (mt res ((ok m) (prn/printSsa m)) ((err ds) (str "lowering failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message " " d.locus)) ds) "; "))))

fn verified? res: (Result ty/SsaModule (List ty/IrDiag)) -> Bool
  (mt res ((ok m) (ok? (vfy/verifySsa m))) ((err _) false))

fn diagsOf res: (Result ty/SsaModule (List ty/IrDiag)) -> (List ty/IrDiag)
  (mt res ((ok _) (list)) ((err ds) ds))

fn codes diags: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.code) diags)

fn loci diags: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.locus) diags)

fn messageAt diags: (List ty/IrDiag) i: Int64 -> String
  (optionOr (listGet diags i) (ty/makeIrDiag "" "" "")).message

fn captureSource -> String
  (joinLines (list
    "(module demo/capture :x [shift])"
    ""
    "(fn shift [(n Int64) (xs (List Int64))] -> (List Int64)"
    "  (let [(k (+ n 1))"
    "        (bump (fn [(x Int64)] -> Int64 (let [(n 2)] (+ x (* k n)))))]"
    "    (do (bump 0) (map bump xs))))"))

fn captureGolden -> String
  (joinLines (list
    "(ssa-module \"demo/capture\""
    "  (strings)"
    "  (fn shift (captures) (params (n i64) (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (prim addIntHost n %0))"
    "      (let %2 val (box %1))"
    "      (let %3 val (make-closure shift@lambda0 %2))"
    "      (let %4 i64 (const int 0))"
    "      (let %5 val (box %4))"
    "      (let %6 val (call-closure %3 %5))"
    "      (let %7 val (call prelude.map %3 xs))"
    "      (return %7)))"
    "  (fn shift@lambda0 (captures (k val)) (params (x val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox k))"
    "      (let %1 i64 (unbox x))"
    "      (let %2 i64 (const int 2))"
    "      (let %3 i64 (prim mulIntHost %0 %2))"
    "      (let %4 i64 (prim addIntHost %1 %3))"
    "      (let %5 val (box %4))"
    "      (return %5)))"
    "  (fn prelude.map (captures) (params (f val) (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeMapOnto f xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeMapOnto (captures) (params (f val) (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (call-closure f %1))"
    "      (let %5 val (entry \"cons\" %4 acc))"
    "      (let %6 val (call prelude.preludeMapOnto f %3 %5))"
    "      (jump (join1 %6)))"
    "    (block join1 ((%7 val))"
    "      (jump (join0 %7)))"
    "    (block arm0.1 ()"
    "      (let %8 val (call prelude.listReverse acc))"
    "      (jump (join0 %8)))"
    "    (block join0 ((%9 val))"
    "      (return %9)))"
    "  (fn prelude.listReverse (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeReverseOnto xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeReverseOnto (captures) (params (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (entry \"cons\" %1 acc))"
    "      (let %5 val (call prelude.preludeReverseOnto %3 %4))"
    "      (jump (join1 %5)))"
    "    (block join1 ((%6 val))"
    "      (jump (join0 %6)))"
    "    (block arm0.1 ()"
    "      (jump (join0 acc)))"
    "    (block join0 ((%7 val))"
    "      (return %7))))"))

fn foldSource -> String
  (joinLines (list
    "(module demo/folds :x [weighted evens])"
    ""
    "(fn weighted [(xs (List Int64)) (w Int64)] -> Int64"
    "  (fold (fn [(acc Int64) (x Int64)] -> Int64 (+ acc (* x w))) 0 xs))"
    ""
    "(fn evens [(xs (List Int64))] -> (List Int64)"
    "  (filter (fn [x] (= (mod x 2) 0)) xs))"))

fn foldGolden -> String
  (joinLines (list
    "(ssa-module \"demo/folds\""
    "  (strings)"
    "  (fn weighted (captures) (params (xs val) (w i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 val (box w))"
    "      (let %1 val (make-closure weighted@lambda0 %0))"
    "      (let %2 i64 (const int 0))"
    "      (let %3 val (box %2))"
    "      (let %4 val (call prelude.fold %1 %3 xs))"
    "      (let %5 i64 (unbox %4))"
    "      (return %5)))"
    "  (fn weighted@lambda0 (captures (w val)) (params (acc val) (x val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox w))"
    "      (let %1 i64 (unbox acc))"
    "      (let %2 i64 (unbox x))"
    "      (let %3 i64 (prim mulIntHost %2 %0))"
    "      (let %4 i64 (prim addIntHost %1 %3))"
    "      (let %5 val (box %4))"
    "      (return %5)))"
    "  (fn evens (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (make-closure evens@lambda0))"
    "      (let %1 val (call prelude.filter %0 xs))"
    "      (return %1)))"
    "  (fn evens@lambda0 (captures) (params (x val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 2))"
    "      (let %1 i64 (unbox x))"
    "      (let %2 i64 (prim modIntHost %1 %0))"
    "      (let %3 i64 (const int 0))"
    "      (let %4 i1 (prim eqInt %2 %3))"
    "      (let %5 val (box %4))"
    "      (return %5)))"
    "  (fn prelude.filter (captures) (params (f val) (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeFilterOnto f xs %0))"
    "      (return %1)))"
    "  (fn prelude.fold (captures) (params (f val) (init val) (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (call-closure f init %1))"
    "      (let %5 val (call prelude.fold f %4 %3))"
    "      (jump (join1 %5)))"
    "    (block join1 ((%6 val))"
    "      (jump (join0 %6)))"
    "    (block arm0.1 ()"
    "      (jump (join0 init)))"
    "    (block join0 ((%7 val))"
    "      (return %7)))"
    "  (fn prelude.preludeFilterOnto (captures) (params (f val) (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (call-closure f %1))"
    "      (branch %4 (then2) (else2)))"
    "    (block then2 ()"
    "      (let %5 val (entry \"cons\" %1 acc))"
    "      (jump (join2 %5)))"
    "    (block else2 ()"
    "      (jump (join2 acc)))"
    "    (block join2 ((%6 val))"
    "      (let %7 val (call prelude.preludeFilterOnto f %3 %6))"
    "      (jump (join1 %7)))"
    "    (block join1 ((%8 val))"
    "      (jump (join0 %8)))"
    "    (block arm0.1 ()"
    "      (let %9 val (call prelude.listReverse acc))"
    "      (jump (join0 %9)))"
    "    (block join0 ((%10 val))"
    "      (return %10)))"
    "  (fn prelude.listReverse (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeReverseOnto xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeReverseOnto (captures) (params (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (entry \"cons\" %1 acc))"
    "      (let %5 val (call prelude.preludeReverseOnto %3 %4))"
    "      (jump (join1 %5)))"
    "    (block join1 ((%6 val))"
    "      (jump (join0 %6)))"
    "    (block arm0.1 ()"
    "      (jump (join0 acc)))"
    "    (block join0 ((%7 val))"
    "      (return %7))))"))

fn valueSource -> String
  (joinLines (list
    "(module demo/values :x [pick apply bumpAll])"
    ""
    "(fn inc [(x Int64)] -> Int64 (+ x 1))"
    ""
    "(fn pick [(b Bool)] -> (fn [Int64] -> Int64)"
    "  (if b inc (fn [(x Int64)] -> Int64 x)))"
    ""
    "(fn apply [(b Bool) (v Int64)] -> Int64"
    "  (let [(f (pick b))] (f v)))"
    ""
    "(fn bumpAll [(xs (List Int64))] -> (List Int64)"
    "  (map inc xs))"))

fn valueGolden -> String
  (joinLines (list
    "(ssa-module \"demo/values\""
    "  (strings)"
    "  (fn inc (captures) (params (x i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (prim addIntHost x %0))"
    "      (return %1)))"
    "  (fn pick (captures) (params (b i1)) (returns val)"
    "    (block entry ()"
    "      (branch b (then0) (else0)))"
    "    (block then0 ()"
    "      (let %0 val (make-closure pick@lambda0))"
    "      (jump (join0 %0)))"
    "    (block else0 ()"
    "      (let %1 val (make-closure pick@lambda1))"
    "      (jump (join0 %1)))"
    "    (block join0 ((%2 val))"
    "      (return %2)))"
    "  (fn pick@lambda0 (captures) (params (@0 val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox @0))"
    "      (let %1 i64 (call inc %0))"
    "      (let %2 val (box %1))"
    "      (return %2)))"
    "  (fn pick@lambda1 (captures) (params (x val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox x))"
    "      (return x)))"
    "  (fn apply (captures) (params (b i1) (v i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 val (call pick b))"
    "      (let %1 val (box v))"
    "      (let %2 val (call-closure %0 %1))"
    "      (let %3 i64 (unbox %2))"
    "      (return %3)))"
    "  (fn bumpAll (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (make-closure bumpAll@lambda0))"
    "      (let %1 val (call prelude.map %0 xs))"
    "      (return %1)))"
    "  (fn bumpAll@lambda0 (captures) (params (@0 val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox @0))"
    "      (let %1 i64 (call inc %0))"
    "      (let %2 val (box %1))"
    "      (return %2)))"
    "  (fn prelude.map (captures) (params (f val) (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeMapOnto f xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeMapOnto (captures) (params (f val) (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (call-closure f %1))"
    "      (let %5 val (entry \"cons\" %4 acc))"
    "      (let %6 val (call prelude.preludeMapOnto f %3 %5))"
    "      (jump (join1 %6)))"
    "    (block join1 ((%7 val))"
    "      (jump (join0 %7)))"
    "    (block arm0.1 ()"
    "      (let %8 val (call prelude.listReverse acc))"
    "      (jump (join0 %8)))"
    "    (block join0 ((%9 val))"
    "      (return %9)))"
    "  (fn prelude.listReverse (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeReverseOnto xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeReverseOnto (captures) (params (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (entry \"cons\" %1 acc))"
    "      (let %5 val (call prelude.preludeReverseOnto %3 %4))"
    "      (jump (join1 %5)))"
    "    (block join1 ((%6 val))"
    "      (jump (join0 %6)))"
    "    (block arm0.1 ()"
    "      (jump (join0 acc)))"
    "    (block join0 ((%7 val))"
    "      (return %7))))"))

fn nestedSource -> String
  (joinLines (list
    "(module demo/nested :x [adder])"
    ""
    "(fn adder [(a Int64) (unused Int64)] -> (fn [Int64] -> (fn [Int64] -> Int64))"
    "  (fn [(b Int64)] (fn [(c Int64)] (+ a (+ b c)))))"))

fn nestedGolden -> String
  (joinLines (list
    "(ssa-module \"demo/nested\""
    "  (strings)"
    "  (fn adder (captures) (params (a i64) (unused i64)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (box a))"
    "      (let %1 val (make-closure adder@lambda0 %0))"
    "      (return %1)))"
    "  (fn adder@lambda1 (captures (a val) (b val)) (params (c val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox a))"
    "      (let %1 i64 (unbox b))"
    "      (let %2 i64 (unbox c))"
    "      (let %3 i64 (prim addIntHost %1 %2))"
    "      (let %4 i64 (prim addIntHost %0 %3))"
    "      (let %5 val (box %4))"
    "      (return %5)))"
    "  (fn adder@lambda0 (captures (a val)) (params (b val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox a))"
    "      (let %1 i64 (unbox b))"
    "      (let %2 val (make-closure adder@lambda1 a b))"
    "      (return %2))))"))

fn recursiveSource -> String
  (joinLines (list
    "(module demo/recursive :x [count])"
    ""
    "(fn fine [] -> Int64 1)"
    "(fn count [(n Int64)] -> Int64"
    "  (let [(spin (fn [(i Int64)] -> Int64 (if (= i 0) 0 (spin (- i 1)))))] (spin n)))"))

fn collideSource -> String
  (joinLines (list
    "(module demo/collide :x [f])"
    "(fn f@lambda0 [] -> Int64 1)"))

fn ! testCapture -> Bool
  (let [(res (lk/lowerSourceLinked! (captureSource)))]
    (do (assert (verified? res) "a let-bound capturing lambda lowers and passes verifySsa")
        (assert (= (printed res) (captureGolden)) "the lambda lifts with k captured and the shadowed n not; a call through its name is call-closure; prelude.map takes the closure and is linked with its helpers")
        true))

fn ! testFold -> Bool
  (let [(res (lk/lowerSourceLinked! (foldSource)))]
    (do (assert (verified? res) "lambdas passed to fold and filter lower and pass verifySsa")
        (assert (= (printed res) (foldGolden)) "prelude.fold and prelude.filter take the closure Val as a call argument and are linked with their helpers; a lambda with no free variables has no captures")
        true))

fn ! testValues -> Bool
  (let [(res (lk/lowerSourceLinked! (valueSource)))]
    (do (assert (verified? res) "module functions used as values lower and pass verifySsa")
        (assert (= (printed res) (valueGolden)) "a returned or passed module function is a capture-free make-closure; calling the returned value is call-closure")
        true))

fn ! testNested -> Bool
  (let [(res (lk/lowerSourceLinked! (nestedSource)))]
    (do (assert (verified? res) "nested lambdas lower and pass verifySsa")
        (assert (= (printed res) (nestedGolden)) "the outer lambda captures a for the inner one, which captures a and b; the unused parameter is not captured")
        (assert (= (printed (lk/lowerSourceLinked! (nestedSource))) (printed res)) "lowering the same source twice prints the same module")
        true))

fn ! testRecursive -> Bool
  (let [(ds (diagsOf (lk/lowerSourceLinked! (recursiveSource))))
        (clash (diagsOf (lk/lowerSourceLinked! (collideSource))))]
    (do (assert (= (codes ds) (list "ERR_LOWER_UNSUPPORTED")) "a let-bound lambda calling itself is one diagnostic; the plain function adds none")
        (assert (= (loci ds) (list "count@4:1")) "the diagnostic carries its declaration position")
        (assert (stringContains? (messageAt ds 0) "'spin' is a let-bound lambda that calls itself") "the diagnostic names the binding")
        (assert (= (codes clash) (list "ERR_LOWER_PARSE")) "a source name cannot spell a lifted name, so lifted names never collide")
        true))

fn ! runTests -> Bool
  (do (assert (testCapture) "testCapture")
      (assert (testFold) "testFold")
      (assert (testValues) "testValues")
      (assert (testNested) "testNested")
      (assert (testRecursive) "testRecursive")
      true)
