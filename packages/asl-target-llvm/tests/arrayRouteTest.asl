(module asl-target-llvm/tests/arrayRouteTest
  :x [runTests]
  :i [(asl-ir/lower :a low)
      (asl-ir/types :a irTy)
      (asl-target-llvm :a llvm)])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module -O2"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn arrayNames -> (List String)
  (listAppend (fold (fn [(acc (List String)) (p String)] -> (List String)
                      (listAppend acc (map (fn [(op String)] -> String (str p "Array" op)) (list "Len" "Get" "Slice" "Concat" "Generate" "Sum" "CountEq" "Fold" "Scan"))))
                    (list) (list "f64" "i64" "i8"))
              (list "dot" "axpy" "gemm"))

fn forbiddenSymbols -> (List String)
  (list "arrayBuiltins" "mkArray" "kernelBuiltins" "bDot" "bGemm")

fn arraySource -> String
  (stringJoin (list
      "(module arrMod"
      "  :x [main]"
      "  :i [])"
      ""
      "fn scaleDown a: Float64 e: Int64 -> (Pair Float64 Int64)"
      "  (if (>= a 9007199254740992.0) (scaleDown (/ a 2.0) (+ e 1)) (pair a e))"
      ""
      "fn scaleUp a: Float64 e: Int64 -> (Pair Float64 Int64)"
      "  (if (and (< a 4503599627370496.0) (> e -1074)) (scaleUp (* a 2.0) (- e 1)) (pair a e))"
      ""
      "fn bits x: Float64 -> String"
      "  (cond"
      "    ((!= x x) \"nan\")"
      "    ((= x 0.0) (stringFromFloat64 x))"
      "    ((> (abs x) 1.7976931348623157e+308) (stringFromFloat64 x))"
      "    (else"
      "      (let [(a (if (< x 0.0) (- 0.0 x) x))"
      "            (down (scaleDown a 0))"
      "            (up (scaleUp (pairFirst down) (pairSecond down)))]"
      "        (str (stringFromFloat64 x) \"=\" (if (< x 0.0) \"-\" \"+\") (pairSecond up) \":\" (optionOr (float64ToInt64 (pairFirst up)) -1)))))"
      ""
      "fn tri i: Int64 -> Float64"
      "  (cond ((= i 0) 1e+16) ((= i 1) 1.0) (else -1e+16))"
      ""
      "fn wave i: Int64 -> Float64"
      "  (cond ((= (mod i 4) 0) 1e+16) ((= (mod i 4) 2) -1e+16) (else (* 0.1 (int64ToFloat64 i))))"
      ""
      "fn ! main args: (List String) -> (Result Int64 String)"
      "  (let [(showF (fn [xs] (stringJoin (map (fn [i] (bits (f64ArrayGet xs i))) (range 0 (f64ArrayLen xs))) \" \")))"
      "        (showI (fn [xs] (stringJoin (map (fn [i] (stringFromInt64 (i64ArrayGet xs i))) (range 0 (i64ArrayLen xs))) \" \")))"
      "        (showB (fn [xs] (stringJoin (map (fn [i] (stringFromInt64 (i8ArrayGet xs i))) (range 0 (i8ArrayLen xs))) \" \")))"
      "        (f (f64ArrayGenerate 7 (fn [i] (- (* 0.1 (int64ToFloat64 i)) 0.3))))"
      "        (n (i64ArrayGenerate 6 (fn [i] (- (* (* i i) 1000000007) 4))))"
      "        (b (i8ArrayGenerate 9 (fn [i] (- (* i 31) 128))))"
      "        (k 3)"
      "        (kf 1.5)"
      "        (t (f64ArrayGenerate 3 tri))"
      "        (w (f64ArrayGenerate 41 wave))"
      "        (fe (f64ArraySlice f 0 0))"
      "        (ne (i64ArraySlice n 6 6))"
      "        (be (i8ArraySlice b 9 9))]"
      "    (do"
      "      (println (str \"len \" (f64ArrayLen f) \" \" (i64ArrayLen n) \" \" (i8ArrayLen b) \" \" (f64ArrayLen fe) \" \" (i64ArrayLen ne) \" \" (i8ArrayLen be)))"
      "      (println (str \"elems \" (showF f) \" | \" (showI n) \" | \" (showB b)))"
      "      (println (str \"get \" (bits (f64ArrayGet f 6)) \" \" (i64ArrayGet n 5) \" \" (i8ArrayGet b 0) \" \" (i8ArrayGet b 8)))"
      "      (println (str \"slice \" (showF (f64ArraySlice f 2 5)) \" | \" (showI (i64ArraySlice n 0 6)) \" | \" (showB (i8ArraySlice b 1 3))))"
      "      (println (str \"concat0 \" (f64ArrayLen (f64ArrayConcat (list))) \" \" (i64ArrayLen (i64ArrayConcat (list))) \" \" (i8ArrayLen (i8ArrayConcat (list)))))"
      "      (println (str \"concat1 \" (showF (f64ArrayConcat (list f))) \" | \" (showI (i64ArrayConcat (list n))) \" | \" (showB (i8ArrayConcat (list b)))))"
      "      (println (str \"concat3 \" (showF (f64ArrayConcat (list f fe (f64ArraySlice f 1 3)))) \" | \" (showI (i64ArrayConcat (list ne n n))) \" | \" (showB (i8ArrayConcat (list b b be)))))"
      "      (println (str \"sum \" (bits (f64ArraySum t)) \" \" (bits (f64ArraySum w)) \" \" (bits (f64ArraySum f)) \" \" (bits (f64ArraySum fe)) \" \" (i64ArraySum n) \" \" (i8ArraySum b) \" \" (i8ArraySum be)))"
      "      (println (str \"fold \" (bits (f64ArrayFold (fn [a x] (+ a x)) 0.0 t)) \" \" (bits (f64ArrayFold (fn [a x] (- (* a kf) x)) 0.25 f))"
      "                    \" \" (f64ArrayFold (fn [a x] (if (> x 0.0) (+ a k) a)) 0 f)"
      "                    \" \" (i64ArrayFold (fn [a x] (- x (* a k))) 7 n) \" \" (i8ArrayFold (fn [a x] (+ (* a k) x)) 1 b)))"
      "      (println (str \"scan \" (showF (f64ArrayScan (fn [a x] (+ (* a kf) x)) 0.5 f)) \" | \" (showI (i64ArrayScan (fn [a x] (- (* a 2) x)) k n))"
      "                    \" | \" (showB (i8ArrayScan (fn [a x] (/ (+ a x) 2)) 3 b)) \" | \" (f64ArrayLen (f64ArrayScan (fn [a x] (+ a x)) 0.0 fe))))"
      "      (println (str \"count \" (f64ArrayCountEq f 0.3) \" \" (f64ArrayCountEq (f64ArrayConcat (list f f)) -0.3) \" \" (i64ArrayCountEq n -4) \" \" (i8ArrayCountEq b -66) \" \" (i8ArrayCountEq b 5)))"
      "      (println (str \"dot \" (bits (dot f f)) \" \" (bits (dot (f64ArrayGenerate 2 (fn [i] (if (= i 0) -1.0 1.0000000009313226))) (f64ArrayGenerate 2 (fn [i] (if (= i 0) 1.0 1.0000000009313226))))) \" \" (bits (dot fe fe))))"
      "      (println (str \"axpy \" (showF (axpy 2.5 f (f64ArraySlice w 0 7))) \" \" (f64ArrayLen (axpy 1.0 fe fe))))"
      "      (println (str \"gemm \" (showF (gemm 2 2 3 (f64ArraySlice f 0 6) (f64ArraySlice w 3 9))) \" \" (f64ArrayLen (gemm 0 3 2 fe (f64ArraySlice f 0 6))) \" \" (showF (gemm 2 2 0 fe fe))))"
      "      (println (str \"values \" (stringJoin (map (fn [g] (stringFromInt64 (g f))) (list (fn [a] (f64ArrayLen a)) (fn [a] (f64ArrayCountEq a 0.3)))) \",\")"
      "                    \" \" (stringJoin (map (fn [g] (bits (g f))) (list (fn [a] (f64ArrayGet a 1)) (fn [a] (f64ArraySum a)) (fn [a] (dot a a)) (fn [a] (f64ArrayFold (fn [x y] (+ x y)) 0.0 a)))) \",\")"
      "                    \" \" (stringJoin (map (fn [g] (showF (g f))) (list (fn [a] (f64ArraySlice a 1 2)) (fn [a] (f64ArrayConcat (list a a))) (fn [a] (f64ArrayGenerate 2 (fn [i] (f64ArrayGet a i))))"
      "                                                                (fn [a] (f64ArrayScan (fn [x y] (+ x y)) 0.0 a)) (fn [a] (axpy 1.0 a a)) (fn [a] (gemm 1 1 1 (f64ArraySlice a 0 1) (f64ArraySlice a 1 2))))) \",\")"
      "                    \" \" (stringJoin (map (fn [g] (stringFromInt64 (g n))) (list (fn [a] (i64ArrayLen a)) (fn [a] (i64ArrayGet a 2)) (fn [a] (i64ArraySum a)) (fn [a] (i64ArrayCountEq a -4))"
      "                                                                            (fn [a] (i64ArrayFold (fn [x y] (+ x y)) 0 a)) (fn [a] (i64ArrayLen (i64ArraySlice a 1 3))) (fn [a] (i64ArrayLen (i64ArrayConcat (list a a))))"
      "                                                                            (fn [a] (i64ArrayLen (i64ArrayGenerate 4 (fn [i] i)))) (fn [a] (i64ArrayLen (i64ArrayScan (fn [x y] (+ x y)) 0 a))))) \",\")"
      "                    \" \" (stringJoin (map (fn [g] (stringFromInt64 (g b))) (list (fn [a] (i8ArrayLen a)) (fn [a] (i8ArrayGet a 2)) (fn [a] (i8ArraySum a)) (fn [a] (i8ArrayCountEq a -66))"
      "                                                                            (fn [a] (i8ArrayFold (fn [x y] (+ x y)) 0 a)) (fn [a] (i8ArrayLen (i8ArraySlice a 1 3))) (fn [a] (i8ArrayLen (i8ArrayConcat (list a a))))"
      "                                                                            (fn [a] (i8ArrayLen (i8ArrayGenerate 4 (fn [i] i)))) (fn [a] (i8ArrayLen (i8ArrayScan (fn [x y] y) 0 a))))) \",\")))"
      "      (ok 0)))")
      "\n")

fn errorSource -> String
  (stringJoin (list
      "(module errMod"
      "  :x [main]"
      "  :i [])"
      ""
      "fn ! main args: (List String) -> (Result Int64 String)"
      "  (let [(f (f64ArrayGenerate 4 (fn [i] (* 0.5 (int64ToFloat64 i)))))"
      "        (n (i64ArrayGenerate 4 (fn [i] (* i 3))))"
      "        (b (i8ArrayGenerate 4 (fn [i] (- i 2))))"
      "        (which (optionOr (listHead args) \"\"))]"
      "    (do (println (cond"
      "        ((= which \"getPast\") (str (f64ArrayGet f 4)))"
      "        ((= which \"getNegative\") (str (i64ArrayGet n -1)))"
      "        ((= which \"getI8\") (str (i8ArrayGet b 9)))"
      "        ((= which \"slicePast\") (str (f64ArrayLen (f64ArraySlice f 2 8))))"
      "        ((= which \"sliceBackward\") (str (i8ArrayLen (i8ArraySlice b 3 2))))"
      "        ((= which \"sliceNegative\") (str (i64ArrayLen (i64ArraySlice n -1 2))))"
      "        ((= which \"generateNegative\") (str (f64ArrayLen (f64ArrayGenerate -1 (fn [i] 1.0)))))"
      "        ((= which \"limitF64\") (str (f64ArrayLen (f64ArrayGenerate 16777217 (fn [i] 1.0)))))"
      "        ((= which \"limitI64\") (str (i64ArrayLen (i64ArrayGenerate 16777217 (fn [i] i)))))"
      "        ((= which \"limitI8\") (str (i8ArrayLen (i8ArrayGenerate 16777217 (fn [i] 1)))))"
      "        ((= which \"limitConcat\") (str (f64ArrayLen (f64ArrayConcat (list (f64ArrayGenerate 8388609 (fn [i] 0.0)) (f64ArrayGenerate 8388608 (fn [i] 0.0)))))))"
      "        ((= which \"i8High\") (str (i8ArrayLen (i8ArrayGenerate 3 (fn [i] (* i 200))))))"
      "        ((= which \"i8Low\") (str (i8ArrayLen (i8ArrayGenerate 3 (fn [i] (* i -100))))))"
      "        ((= which \"i8Scan\") (str (i8ArrayLen (i8ArrayScan (fn [a x] (* a 100)) 2 b))))"
      "        ((= which \"sumOverflow\") (str (i64ArraySum (i64ArrayGenerate 3 (fn [i] 4611686018427387904)))))"
      "        ((= which \"dotShape\") (str (dot f (f64ArraySlice f 0 3))))"
      "        ((= which \"axpyShape\") (str (f64ArrayLen (axpy 1.0 f (f64ArraySlice f 0 3)))))"
      "        ((= which \"gemmShapeA\") (str (f64ArrayLen (gemm 1 2 2 f f))))"
      "        ((= which \"gemmShapeB\") (str (f64ArrayLen (gemm 2 2 2 f (f64ArraySlice f 0 3)))))"
      "        ((= which \"gemmNegative\") (str (f64ArrayLen (gemm 2 -1 2 f f))))"
      "        ((= which \"gemmMk\") (str (f64ArrayLen (gemm 4611686018427387904 1 1 f f))))"
      "        ((= which \"gemmKn\") (str (f64ArrayLen (gemm 1 4611686018427387904 1 f f))))"
      "        ((= which \"gemmMn\") (str (f64ArrayLen (gemm 2147483648 2147483648 0 (f64ArraySlice f 0 0) (f64ArraySlice f 0 0)))))"
      "        (else \"no case\")))"
      "        (ok 0)))")
      "\n")

fn errorCases -> (List String)
  (list "getPast" "getNegative" "getI8" "slicePast" "sliceBackward" "sliceNegative" "generateNegative" "limitF64" "limitI64" "limitI8" "limitConcat" "i8High" "i8Low" "i8Scan" "sumOverflow" "dotShape" "axpyShape" "gemmShapeA" "gemmShapeB" "gemmNegative" "gemmMk" "gemmKn" "gemmMn")

fn gcSource -> String
  (stringJoin (list
      "(module gcMod"
      "  :x [main]"
      "  :i [])"
      ""
      "fn ! main args: (List String) -> (Result Int64 String)"
      "  (let [(total (fold (fn [acc i]"
      "                       (let [(a (f64ArrayGenerate 400 (fn [j] (int64ToFloat64 (+ (listLength (range 0 (mod j 5))) (* i j))))))"
      "                             (s (f64ArrayScan (fn [x y] (+ x (f64ArraySum (f64ArrayGenerate 2 (fn [q] y))))) 0.0 a))"
      "                             (c (f64ArrayConcat (list a (f64ArraySlice s 10 20) (axpy 2.0 (f64ArraySlice a 0 5) (f64ArraySlice s 0 5)))))"
      "                             (folded (f64ArrayFold (fn [x y] (+ x (f64ArrayGet (f64ArrayGenerate 1 (fn [q] y)) 0))) 0.0 (f64ArrayGenerate 50 (fn [j] (int64ToFloat64 j)))))"
      "                             (bb (i8ArrayGenerate 300 (fn [j] (- (mod (+ i j) 256) 128))))"
      "                             (nn (i64ArrayScan (fn [x y] (+ x (i64ArrayLen (i64ArrayGenerate 1 (fn [q] y))))) 0 (i64ArrayGenerate 100 (fn [j] (* i j)))))]"
      "                         (+ acc (+ (f64ArraySum c) (+ folded (int64ToFloat64 (+ (i8ArraySum bb) (i64ArraySum nn))))))))"
      "                     0.0 (range 0 120)))]"
      "    (do (println (stringFromFloat64 total))"
      "        (ok 0)))")
      "\n")

fn occurrences text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn routedSymbol name: String -> String
  (str "@asl$2Dtarget$2Dllvm$2Farrays$2E" name)

fn symbolNames text: String -> (List String)
  (map (fn [(line String)] -> String
         (let [(word (optionOr (listHead (stringSplit line " ")) ""))]
           (if (stringStartsWith? word "_") (optionOr (stringSlice word 1 (stringLength word)) word) word)))
       (filter (fn [(line String)] -> Bool (not (stringEmpty? line))) (stringSplit text "\n")))

fn ! build work: String name: String src: String -> String
  (let [(file (str work "/" name ".asl"))
        (ll (str work "/" name ".ll"))
        (bin (str work "/" name))]
    (do
      (assert (ok? (fileWrite file src)) (str name ": source written"))
      (let [(built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " file " -o " ll)))]
        (assert (= built.exitCode 0) (str name ": asl1 builds it; exit " built.exitCode "; " built.stdout built.stderr)))
      (let [(text (mt (fileReadString ll) ((ok t) t) ((err e) (str "unreadable " ll ": " e))))
            (called (filter (fn [(n String)] -> Bool (stringContains? src (str "(" n " "))) (arrayNames)))]
        (do
          (refute (stringContains? text "asl_rt_builtin_array") (str name ": IR neither calls nor declares asl_rt_builtin_array"))
          (refute (stringContains? text "asl_rt_builtin_kernel") (str name ": IR neither calls nor declares asl_rt_builtin_kernel"))
          (map (fn [(n String)] -> Bool
                 (do (assert (stringContains? text (str "define internal tailcc %Val " (routedSymbol n) "(")) (str name ": IR defines the routed " n " internal"))
                     (refute (stringContains? text (str "@name." n ", i64")) (str name ": IR calls no builtin " n " by name"))
                     true))
               called)
          (let [(linked (sh (str (clang) " -x ir " ll " -x none " (lib) " -lm -o " bin)))
                (nm (sh (str "nm -P " bin)))
                (syms (symbolNames nm.stdout))]
            (do
              (assert (= linked.exitCode 0) (str name ": links against libaslrt.a; " linked.stderr))
              (assert (= nm.exitCode 0) (str name ": nm -P lists the binary; " nm.stderr))
              (assert (> (listLength syms) 0) (str name ": nm -P prints symbols"))
              (map (fn [(s String)] -> Bool (do (refute (listContains? syms s) (str name ": binary has no " s " symbol")) true)) (forbiddenSymbols))
              text))))))

fn ! testProgram work: String -> Bool
  (let [(src (arraySource))
        (values (optionOr (stringSlice src (optionOr (stringIndexOf src "(map (fn [g]") (stringLength src)) (stringLength src)) ""))]
    (do
      (assert (not (stringEmpty? values)) "arrMod has a values line mapping closures")
      (map (fn [(n String)] -> Bool
             (do (assert (> (occurrences src (str "(" n " ")) (occurrences values (str "(" n " "))) (str "arrMod calls " n " directly"))
                 (assert (stringContains? values (str "(" n " ")) (str "arrMod calls " n " inside a closure passed as a value"))
                 true))
           (arrayNames))
      (build work "arrMod" src)
      (let [(native (sh (str work "/arrMod")))
            (interp (sh (str (host) " run " work "/arrMod.asl")))]
        (do
          (assert (= interp.exitCode 0) (str "arrMod: asl-host run exits 0; " interp.stderr))
          (assert (= native.exitCode 0) (str "arrMod: native exits 0; " native.stderr))
          (assert (= (occurrences interp.stdout "\n") 15) (str "arrMod: asl-host prints 15 lines; got " interp.stdout))
          (assert (= native.stdout interp.stdout) (str "arrMod: native stdout equals asl-host's; native " native.stdout "; host " interp.stdout))
          (assert (= native.stderr "") (str "arrMod: native stderr is empty; " native.stderr))
          true))))

fn ! testErrors work: String -> Bool
  (do
    (build work "errMod" (errorSource))
    (map (fn [(c String)] -> Bool
           (let [(native (sh (str work "/errMod " c)))
                 (interp (sh (str (host) " run " work "/errMod.asl " c)))
                 (line (stringReplace native.stderr "\n" ""))]
             (do
               (assert (= interp.exitCode 1) (str c ": asl-host exits 1; " interp.exitCode " " interp.stderr))
               (assert (= native.exitCode 1) (str c ": native exits 1; " native.exitCode " " native.stderr))
               (assert (stringStartsWith? line "ERR_") (str c ": native stderr is an error line; " native.stderr))
               (assert (= (occurrences native.stderr "\n") 1) (str c ": native stderr is one line; " native.stderr))
               (assert (stringContains? interp.stderr (str ": " line " (after")) (str c ": asl-host reports the same error; native " line "; host " interp.stderr))
               (assert (= native.stdout interp.stdout) (str c ": same stdout; " native.stdout))
               true)))
         (errorCases))
    true)

fn statOf stats: String key: String -> Int64
  (mt (listGet (stringSplit stats (str ":" key " ")) 1)
    ((none) -1)
    ((some rest) (optionOr (stringToInt64 (optionOr (listHead (stringSplit rest " ")) "")) -1)))

fn ! testGc work: String -> Bool
  (do
    (build work "gcMod" (gcSource))
    (let [(interp (sh (str (host) " run " work "/gcMod.asl")))
          (plain (sh (str work "/gcMod")))
          (stressed (sh (str "ASL_GC_STRESS=1 ASL_GC_STATS=1 " work "/gcMod")))
          (stats stressed.stderr)
          (allocated (statOf stats "objectsAllocated"))
          (freed (statOf stats "objectsFreed"))]
      (do
        (assert (= interp.exitCode 0) (str "gcMod: asl-host exits 0; " interp.stderr))
        (assert (not (stringEmpty? interp.stdout)) "gcMod: asl-host prints the total")
        (assert (= plain.exitCode 0) (str "gcMod: native exits 0; " plain.stderr))
        (assert (= plain.stdout interp.stdout) (str "gcMod: native stdout equals asl-host's; " plain.stdout " vs " interp.stdout))
        (assert (= stressed.exitCode 0) (str "gcMod: exits 0 under ASL_GC_STRESS=1; " stats))
        (assert (= stressed.stdout interp.stdout) (str "gcMod: stressed stdout equals asl-host's; " stressed.stdout))
        (assert (> (statOf stats "collections") 1000) (str "gcMod: the stressed run collects; " stats))
        (assert (> allocated 10000) (str "gcMod: the stressed run allocates; " stats))
        (assert (>= (+ freed 16) allocated) (str "gcMod: the stressed run frees all but a few objects; " stats))
        true)))

fn accountSource -> String
  (stringJoin (list
      "(module accountMod"
      "  :x [main]"
      "  :i [])"
      ""
      "fn ! main args: (List String) -> (Result Int64 String)"
      "  (let [(kind (optionOr (listHead args) \"\"))"
      "        (n (optionOr (stringToInt64 (optionOr (listGet args 1) \"\")) 0))]"
      "    (do (println (str (cond ((= kind \"f64\") (f64ArrayLen (f64ArrayGenerate n (fn [j] 0.0))))"
      "                            ((= kind \"i64\") (i64ArrayLen (i64ArrayGenerate n (fn [j] 0))))"
      "                            (else (i8ArrayLen (i8ArrayGenerate n (fn [j] 0)))))))"
      "        (ok 0)))")
      "\n")

fn ! testAccount work: String -> Bool
  (do
    (build work "accountMod" (accountSource))
    (map (fn [(kind String)] -> Bool
           (let [(bytes (fn [(cmd String) (n Int64)] -> Int64
                          (let [(out (sh (str "ASL_GC_STATS=1 " cmd " " kind " " n)))]
                            (do (assert (= out.exitCode 0) (str "accountMod " kind " " n ": exits 0; " out.stderr))
                                (assert (= out.stdout (str n "\n")) (str "accountMod " kind " " n ": prints the length; " out.stdout))
                                (statOf out.stderr "bytesAllocated")))))
                 (native (str work "/accountMod"))
                 (interp (str (host) " run " work "/accountMod.asl"))
                 (nativeDelta (- (bytes native 200000) (bytes native 100000)))
                 (hostDelta (- (bytes interp 200000) (bytes interp 100000)))]
             (do
               (assert (> hostDelta 0) (str kind ": asl-host's bytesAllocated grows with the array; delta " hostDelta))
               (assert (= nativeDelta hostDelta) (str kind ": native bytesAllocated grows by asl-host's " hostDelta " for 100000 more elements; got " nativeDelta))
               true)))
         (list "f64" "i64" "i8"))
    true)

fn twoMainSource -> String
  (stringJoin (list
    "(module twoA"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (str (f64ArraySum (f64ArrayGenerate 4 (fn [i] (int64ToFloat64 i))))))"
    "      (ok 0))")
    "\n")

fn twoLibSource -> String
  (stringJoin (list
    "(module twoB"
    "  :x [total]"
    "  :i [])"
    ""
    "fn total n: Int64 -> Float64"
    "  (f64ArraySum (f64ArrayGenerate n (fn [i] (int64ToFloat64 i))))")
    "\n")

fn diagsText ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn ! testTwoModules work: String -> Bool
  (let [(a (llvm/emitLlvmSource (twoMainSource) "main"))
        (b (mt (low/lowerSource (twoLibSource)) ((err ds) (err ds)) ((ok m) (llvm/emitLlvmModule m))))]
    (mt a
      ((err ds) (do (assert false (str "twoA emits: " (diagsText ds))) false))
      ((ok aText)
        (mt b
          ((err ds) (do (assert false (str "twoB emits: " (diagsText ds))) false))
          ((ok bText)
            (do
              (assert (stringContains? aText (str "define internal tailcc %Val " (routedSymbol "f64ArraySum") "(")) "twoA defines the routed f64ArraySum internal")
              (assert (stringContains? bText (str "define internal tailcc %Val " (routedSymbol "f64ArraySum") "(")) "twoB defines the routed f64ArraySum internal")
              (assert (ok? (fileWrite (str work "/twoA.ll") aText)) "twoA.ll written")
              (assert (ok? (fileWrite (str work "/twoB.ll") bText)) "twoB.ll written")
              (assert (ok? (fileWrite (str work "/twoA.asl") (twoMainSource))) "twoA.asl written")
              (let [(linked (sh (str (clang) " -x ir " work "/twoA.ll " work "/twoB.ll -x none " (lib) " -lm -o " work "/two")))
                    (native (sh (str work "/two")))
                    (interp (sh (str (host) " run " work "/twoA.asl")))]
                (do
                  (assert (= linked.exitCode 0) (str "twoA and twoB link into one binary; " linked.stderr))
                  (assert (= native.exitCode 0) (str "the two-module binary exits 0; " native.stderr))
                  (assert (= interp.exitCode 0) (str "asl-host runs twoA; " interp.stderr))
                  (assert (= native.stdout interp.stdout) (str "the two-module binary prints asl-host's " interp.stdout "; got " native.stdout))
                  true))))))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testProgram work)
      (testErrors work)
      (testGc work)
      (testAccount work)
      (testTwoModules work)
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
      true))
