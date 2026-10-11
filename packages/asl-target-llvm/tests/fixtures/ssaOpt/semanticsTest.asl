(module asl-target-llvm/tests/fixtures/ssaOpt/semanticsTest
  :x [runTests]
  :i [(asl-target-llvm/tests/fixtures/ssaOpt/semantics :a sem)
      (asl-target-llvm/tests/fixtures/ssaOpt/libLeaf :a leaf)])

fn ! runTests -> Bool
  (let [(ls (sem/lines))]
    (do (assert (= (listGet ls 0) (some "init true dark true false 42")) "a module init reads the imported module's singletons")
        (assert (= (listGet ls 1) (some "eq true true true false false false")) "= on nullary constructors")
        (assert (= (listGet ls 2) (some "mt none none some7 light tinted3")) "mt on nullary constructors")
        (assert (= (listGet ls 3) (some "fn 3 4 18 11,12")) "function values passed and called")
        (assert (= (listGet ls 4) (some "par true light 3|true dark 4|true dark 5")) "parMap workers read singletons and call hoisted function values")
        (assert (= (listGet ls 5) (some "parLambda some1,none,none")) "parMap of a hoisted lambda returns singletons across the worker pipe")
        (assert (= (leaf/shadeName (leaf/dark)) "dark") "test wrapper entry reads a singleton")
        true))
