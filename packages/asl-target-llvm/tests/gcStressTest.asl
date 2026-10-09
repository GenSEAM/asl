(module asl-target-llvm/tests/gcStressTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn host -> String
  "asl/host/out/asl-host"

fn abiTest -> String
  "asl/packages/asl-target-llvm/tests/abiPrograms.asl"

fn clangLink -> String
  "/usr/bin/clang -Wno-override-module -x ir "

fn lib -> String
  " -x none asl/host/out/libaslrt.a -lm -o "

fn programs -> (List (Pair String Int64))
  (list (pair "allocSmall" 0) (pair "switchPick" 3) (pair "fusedVariantInt" 0) (pair "fusedVariantFloat" 0)
        (pair "fusedVariantBool" 0) (pair "fusedRecordInt" 0) (pair "joined" 42) (pair "deepTail" 42) (pair "nestedTail" 42))

fn heapSource -> String
  (stringJoin (list
    "(module stressMod"
    "  :x [main]"
    "  :i [])"
    ""
    "(schema Item (:f name String) (:f n Int64))"
    ""
    "(enum Shape (:c circle [(r Int64)] \"Round\") (:c rect [(w Int64) (h Int64)] \"Rectangle\"))"
    ""
    "fn area s: Shape -> Int64"
    "  (mt s ((circle r) (* r r)) ((rect w h) (* w h)))"
    ""
    "fn wide a: String b: String c: String d: String it: Item -> String"
    "  (str a b c d it.name (stringFromInt64 it.n))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(items (map (fn [(i Int64)] -> Item (Item :name (str \"i\" (stringFromInt64 i)) :n i)) (range 0 300)))"
    "        (k \"k\")"
    "        (names (fold (fn [(acc String) (it Item)] -> String (if (= it.n 299) (str acc it.name k) acc)) \"\" items))"
    "        (shapes (map (fn [(i Int64)] -> Shape (if (= (mod i 2) 0) (circle i) (rect i 2))) (range 0 200)))"
    "        (total (fold (fn [(acc Int64) (s Shape)] -> Int64 (+ acc (area s))) 0 shapes))"
    "        (w (wide \"a\" \"b\" \"c\" \"d\" (Item :name \"x\" :n 7)))"
    "        (sum (fold (fn [(acc Int64) (i Int64)] -> Int64 (+ acc ((fn [(x Int64)] -> Int64 (+ x i)) 1))) 0 (range 0 300)))]"
    "    (do (println names)"
    "        (println (stringFromInt64 total))"
    "        (println w)"
    "        (println (stringFromInt64 sum))"
    "        (ok 0)))")
    "\n")

fn listStressSource -> String
  (stringJoin (list
    "(module listStressMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn add3 a: Int64 b: Int64 c: Int64 -> Int64"
    "  (+ a (+ b c))"
    ""
    "fn build n: Int64 acc: (List (List Int64)) -> (List (List Int64))"
    "  (if (= n 0) acc (build (- n 1) (cons (list n (+ n 1) (+ n 2) (+ n 3)) acc)))"
    ""
    "fn sumAll xs: (List (List Int64)) acc: Int64 -> Int64"
    "  (mt (listHead xs) ((some l) (sumAll (optionOr (listTail xs) (list)) (+ acc (+ (optionOr (listGet l 0) 0) (optionOr (listGet l 3) 0))))) ((none) acc))"
    ""
    "fn slices s: String n: Int64 acc: String -> String"
    "  (if (= n 0) acc (slices s (- n 1) (str (optionOr (stringSlice s (mod n 5) (+ (mod n 5) 3)) \"\") (optionOr (stringSlice acc 0 (if (> (stringLength acc) 40) 40 (stringLength acc))) \"\"))))"
    ""
    "fn bytesRound n: Int64 total: Int64 -> Int64"
    "  (if (= n 0) total"
    "    (let [(b (bytesAlloc 24))]"
    "      (do (bytesSet b 0 (mod n 256)) (bytesSetFloat64 b 1 2.5)"
    "          (bytesRound (- n 1) (+ total (+ (bytesGet b 0) (+ (bytesLength b) (float64ToInt64Or (bytesGetFloat64 b 1)))))))))"
    ""
    "fn float64ToInt64Or x: Float64 -> Int64"
    "  (if (> x 2.0) 1 0)"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(lists (build 400 (list)))"
    "        (ps (map (fn [(i Int64)] -> Int64 ((partial add3 i 1) 2)) (range 0 300)))]"
    "    (do (println (stringFromInt64 (sumAll lists 0)))"
    "        (println (stringFromInt64 (fold (fn [(a Int64) (b Int64)] -> Int64 (+ a b)) 0 ps)))"
    "        (println (slices \"abcdefgh\" 300 \"\"))"
    "        (println (stringFromInt64 (bytesRound 300 0)))"
    "        (ok 0)))")
    "\n")

fn objectStressSource -> String
  (stringJoin (list
    "(module objStressMod"
    "  :x [main]"
    "  :i [])"
    ""
    "(schema Wide (:f f0 Int64) (:f f1 Int64) (:f f2 Int64) (:f f3 Int64) (:f f4 Int64) (:f f5 Int64) (:f f6 Int64) (:f f7 Int64) (:f f8 Int64) (:f f9 Int64))"
    ""
    "(enum Many (:c a0 [] \"No fields\") (:c a3 [(x Int64) (y Int64) (z Int64)] \"Three fields\") (:c a8 [(b0 Int64) (b1 Int64) (b2 Int64) (b3 Int64) (b4 Int64) (b5 Int64) (b6 Int64) (b7 Int64)] \"Eight fields\"))"
    ""
    "fn idOf x: T -> T"
    "  x"
    ""
    "fn makeAdder k: Int64 s: String -> T"
    "  (let [(a (idOf k)) (b (idOf (+ k 1))) (t (idOf s))]"
    "    (idOf (fn [(x Int64)] -> Int64 (+ x (+ a (+ b (stringLength t)))))))"
    ""
    "fn shape i: Int64 -> Many"
    "  (if (= (mod i 3) 0) a0 (if (= (mod i 3) 1) (a3 i 1 2) (a8 i 1 2 3 4 5 6 7)))"
    ""
    "fn weight m: Many -> Int64"
    "  (mt m ((a0) 1) ((a3 x y z) (+ x (+ y z))) ((a8 b0 b1 b2 b3 b4 b5 b6 b7) (+ b0 b7)))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(recs (map (fn [(i Int64)] -> Wide (Wide :f0 i :f1 1 :f2 2 :f3 3 :f4 4 :f5 5 :f6 6 :f7 7 :f8 8 :f9 9)) (range 0 300)))"
    "        (total (fold (fn [(acc Int64) (w Wide)] -> Int64 (+ acc (+ (idOf w).f0 (idOf w).f9))) 0 recs))"
    "        (adders (map (fn [(i Int64)] -> T (makeAdder i (str \"s\" i))) (range 0 300)))"
    "        (applied (fold (fn [(acc Int64) (f T)] -> Int64 (+ acc (f 1))) 0 adders))"
    "        (shapes (fold (fn [(acc Int64) (i Int64)] -> Int64 (+ acc (weight (idOf (shape i))))) 0 (range 0 300)))"
    "        (kws (filter (fn [(k T)] -> Bool (= k :alpha)) (map (fn [(i Int64)] -> T (if (= (mod i 2) 0) :alpha :beta)) (range 0 300))))"
    "        (texts (fold (fn [(acc String) (i Int64)] -> String (if (> (stringLength acc) 40) \"const\" (str acc \"const\"))) \"\" (range 0 300)))]"
    "    (do (println (str total \" \" applied \" \" shapes \" \" (listLength kws) \" \" texts))"
    "        (println (str (idOf (listHead recs))))"
    "        (ok 0)))")
    "\n")

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compiledText path: String -> (Result String String)
  (mt (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn asanLink -> String
  "/usr/bin/clang -Wno-override-module -fsanitize=address,undefined -x ir "

fn asanLib -> String
  " -x none asl/host/out/libaslrt-asan.a -lm -o "

fn asanStress -> String
  "ASAN_OPTIONS=detect_stack_use_after_return=1 ASL_GC_STRESS=1 "

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! sameUnderAsanStress label: String ll: String bin: String args: String want: Int64 plainOut: String -> Bool
  (let [(linked (sh (str (asanLink) ll (asanLib) bin)))
        (run (sh (str (asanStress) bin args)))]
    (do (assert (= linked.exitCode 0) (str label ": links against the ASan library; " linked.stderr))
        (assert (= run.exitCode want) (str label ": exit under ASan fake stacks and ASL_GC_STRESS=1 " run.exitCode ", want " want "; stderr " run.stderr))
        (assert (= run.stdout plainOut) (str label ": same output under ASan fake stacks and stress; got " run.stdout))
        true))

fn ! sameUnderStress label: String bin: String want: Int64 -> Bool
  (let [(plain (sh bin))
        (stressed (sh (str "ASL_GC_STRESS=1 " bin)))]
    (do (assert (= plain.exitCode want) (str label ": exit " plain.exitCode ", want " want "; stderr " plain.stderr))
        (assert (= stressed.exitCode want) (str label ": exit under ASL_GC_STRESS=1 " stressed.exitCode ", want " want "; stderr " stressed.stderr))
        (assert (= stressed.stdout plain.stdout) (str label ": same output under stress; plain " plain.stdout " stressed " stressed.stdout))
        true))

fn ! testPrograms work: String -> Bool
  (do
    (map (fn [(p (Pair String Int64))] -> Bool
           (let [(name (pairFirst p))
                 (ll (str work "/" name ".ll"))
                 (emitted (sh (str (host) " run " (abiTest) " " name " > " ll)))
                 (linked (sh (str (clangLink) ll (lib) work "/" name)))]
             (do (assert (= emitted.exitCode 0) (str name ": emits .ll; " emitted.stderr))
                 (assert (= linked.exitCode 0) (str name ": links; " linked.stderr))
                 (sameUnderStress name (str work "/" name (if (= name "joined") " ab cde" "")) (pairSecond p))
                 (sameUnderAsanStress name ll (str work "/" name ".asan") (if (= name "joined") " ab cde" "") (pairSecond p)
                   (sh (str work "/" name (if (= name "joined") " ab cde" ""))).stdout))))
         (programs))
    true)

fn ! testSource work: String -> Bool
  (let [(src (str work "/stressMod.asl"))
        (ll (str work "/stressMod.ll"))]
    (do (assert (ok? (fileWrite src (heapSource))) "stressMod: source written")
        (let [(built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll)))
              (linked (sh (str (clangLink) ll (lib) work "/stressMod")))
              (interp (sh (str (host) " run " src)))]
          (do (assert (= built.exitCode 0) (str "stressMod: asl1 builds it; " built.stderr))
              (assert (= linked.exitCode 0) (str "stressMod: links; " linked.stderr))
              (assert (= interp.stdout "i299k\n1333400\nabcdx7\n45150\n") (str "stressMod: host output; got " interp.stdout))
              (sameUnderStress "stressMod" (str work "/stressMod") 0)
              (sameUnderAsanStress "stressMod" ll (str work "/stressMod.asan") "" 0 interp.stdout)
              (assert (= (sh (str "ASL_GC_STRESS=1 " work "/stressMod")).stdout interp.stdout) "stressMod: stressed native output equals host output")))
        true))

fn ! testListStress work: String -> Bool
  (let [(src (str work "/listStressMod.asl"))
        (ll (str work "/listStressMod.ll"))]
    (do (assert (ok? (fileWrite src (listStressSource))) "listStressMod: source written")
        (mt (compiledText src)
          ((err e) (assert false (str "listStressMod: links and emits; " e)))
          ((ok code)
            (let [(written (fileWrite ll code))
                  (linked (sh (str (clangLink) ll (lib) work "/listStressMod")))
                  (interp (sh (str (host) " run " src)))]
              (do (assert (ok? written) "listStressMod: .ll written")
                  (assert (= linked.exitCode 0) (str "listStressMod: links; " linked.stderr))
                  (assert (= interp.exitCode 0) (str "listStressMod: asl-host run exit 0; " interp.stderr))
                  (sameUnderStress "listStressMod" (str work "/listStressMod") 0)
                  (sameUnderAsanStress "listStressMod" ll (str work "/listStressMod.asan") "" 0 interp.stdout)
                  (assert (= (sh (str work "/listStressMod")).stdout interp.stdout) "listStressMod: native output equals asl-host run output")
                  (assert (= (sh (str "ASL_GC_STRESS=1 " work "/listStressMod")).stdout interp.stdout) "listStressMod: stressed native output equals asl-host run output")))))
        true))

fn ! testObjectStress work: String -> Bool
  (let [(src (str work "/objStressMod.asl"))
        (ll (str work "/objStressMod.ll"))]
    (do (assert (ok? (fileWrite src (objectStressSource))) "objStressMod: source written")
        (mt (compiledText src)
          ((err e) (assert false (str "objStressMod: links and emits; " e)))
          ((ok code)
            (let [(written (fileWrite ll code))
                  (linked (sh (str (clangLink) ll (lib) work "/objStressMod")))
                  (interp (sh (str (host) " run " src)))]
              (do (assert (ok? written) "objStressMod: .ll written")
                  (assert (= linked.exitCode 0) (str "objStressMod: links; " linked.stderr))
                  (assert (= interp.stdout "47550 91390 31100 150 constconstconst\n(some {:f0 0 :f1 1 :f2 2 :f3 3 :f4 4 :f5 5 :f6 6 :f7 7 :f8 8 :f9 9})\n") (str "objStressMod: host output; got " interp.stdout interp.stderr))
                  (sameUnderStress "objStressMod" (str work "/objStressMod") 0)
                  (sameUnderAsanStress "objStressMod" ll (str work "/objStressMod.asan") "" 0 interp.stdout)
                  (assert (= (sh (str "ASL_GC_STRESS=1 " work "/objStressMod")).stdout interp.stdout) "objStressMod: stressed native output equals asl-host run output")))))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (= (sh "sh asl/host/build.sh --sanitize").exitCode 0) "ASan host library builds")
        (testPrograms work)
        (testSource work)
        (testListStress work)
        (testObjectStress work)
        (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
        true))
