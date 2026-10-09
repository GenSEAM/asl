(module asl-target-llvm/tests/arrayNativeTest
  :x [runTests]
  :i [])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn arraySource -> String
  (stringJoin (list
    "(module arrayNativeMod"
    "  :x [main]"
    "  :i [])"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(f (f64ArrayGenerate 5 (fn [(i Int64)] -> Float64 (* 1.5 (int64ToFloat64 i)))))"
    "        (fc (f64ArrayConcat (list f (f64ArraySlice f 1 3))))"
    "        (fs (f64ArrayScan (fn [(a Float64) (x Float64)] -> Float64 (+ a x)) 0.5 f))"
    "        (n (i64ArrayGenerate 6 (fn [(i Int64)] -> Int64 (- (* i i) 4))))"
    "        (nc (i64ArrayConcat (list (i64ArraySlice n 2 5) n)))"
    "        (ns (i64ArrayScan (fn [(a Int64) (x Int64)] -> Int64 (+ (* a 2) x)) 1 n))"
    "        (b (i8ArrayGenerate 7 (fn [(i Int64)] -> Int64 (- 90 (* i 30)))))"
    "        (bc (i8ArrayConcat (list b (i8ArraySlice b 0 2))))"
    "        (bs (i8ArrayScan (fn [(a Int64) (x Int64)] -> Int64 (- x a)) 3 b))]"
    "    (do (println (str (f64ArrayLen fc) \" \" (stringFromFloat64 (f64ArrayGet fc 6)) \" \" (stringFromFloat64 (f64ArraySum fc)) \" \""
    "                      (f64ArrayCountEq fc 3.0) \" \" (stringFromFloat64 (f64ArrayFold (fn [(a Float64) (x Float64)] -> Float64 (- (* a 2.0) x)) 1.0 f)) \" \""
    "                      (f64ArrayFold (fn [(a Int64) (x Float64)] -> Int64 (if (> x 2.0) (+ a 1) a)) 0 fc) \" \""
    "                      (f64ArrayLen fs) \" \" (stringFromFloat64 (f64ArrayGet fs 4))))"
    "        (println (str (i64ArrayLen nc) \" \" (i64ArrayGet nc 0) \" \" (i64ArraySum nc) \" \" (i64ArrayCountEq nc 5) \" \""
    "                      (i64ArrayFold (fn [(a Int64) (x Int64)] -> Int64 (- x a)) 7 n) \" \" (i64ArrayLen ns) \" \" (i64ArrayGet ns 5)))"
    "        (println (str (i8ArrayLen bc) \" \" (i8ArrayGet bc 6) \" \" (i8ArraySum bc) \" \" (i8ArrayCountEq bc 90) \" \""
    "                      (i8ArrayFold (fn [(a Int64) (x Int64)] -> Int64 (+ a (* x x))) 0 b) \" \" (i8ArrayLen bs) \" \" (i8ArrayGet bs 6)))"
    "        (ok 0)))")
    "\n")

fn arrayExpected -> String
  "7 3.0 19.5 2 -7.0 4 5 15.5\n9 0 48 2 22 6 -47\n9 -90 150 2 25200 7 -3\n"

fn arrayNames -> (List String)
  (fold (fn [(acc (List String)) (p String)] -> (List String)
          (listAppend acc (map (fn [(op String)] -> String (str p "Array" op)) (list "Len" "Get" "Slice" "Concat" "Generate" "Sum" "CountEq" "Fold" "Scan"))))
        (list) (list "f64" "i64" "i8"))

fn ! testArrayNative work: String -> Bool
  (let [(src (str work "/arrayNativeMod.asl"))
        (ll (str work "/arrayNativeMod.ll"))
        (bin (str work "/arrayNativeMod"))]
    (do
      (assert (ok? (fileWrite src (arraySource))) "arrayNativeMod: source written")
      (map (fn [(name String)] -> Bool (do (assert (stringContains? (arraySource) (str "(" name " ")) (str "arrayNativeMod calls " name)) true)) (arrayNames))
      (let [(built (sh (str (host) " run asl/packages/asl-compiler/src/asl1.asl build " src " -o " ll)))]
        (assert (= built.exitCode 0) (str "arrayNativeMod: asl1 builds it; exit " built.exitCode "; stdout " built.stdout "; stderr " built.stderr)))
      (let [(llText (mt (fileReadString ll) ((ok t) t) ((err e) (str "unreadable " ll ": " e))))]
        (do
          (refute (stringContains? llText "@asl_rt_builtin_array") "arrayNativeMod: .ll neither calls nor declares asl_rt_builtin_array")
          (assert (stringContains? llText "@asl$2Dtarget$2Dllvm$2Farrays$2Ef64ArrayFold(") "arrayNativeMod: .ll calls the routed f64ArrayFold")
          (refute (stringContains? llText "ERR_LOWER_UNSUPPORTED") "arrayNativeMod: .ll has no unsupported-lowering trap")))
      (let [(linked (sh (str (clang) " -x ir " ll " -x none " (lib) " -lm -o " bin)))]
        (assert (= linked.exitCode 0) (str "arrayNativeMod: links against libaslrt.a; stderr " linked.stderr)))
      (let [(symbols (sh (str "nm -P " bin)))]
        (do
          (assert (= symbols.exitCode 0) (str "arrayNativeMod: nm -P inspects linked program; stderr " symbols.stderr))
          (refute (stringContains? symbols.stdout "asl_rt_builtin_kernel") "arrayNativeMod: native binary has no asl_rt_builtin_kernel")
          (refute (stringContains? symbols.stdout "asl_rt_builtin_array") "arrayNativeMod: native binary has no C array builtin entry")))
      (let [(native (sh bin))
            (interp (sh (str (host) " run " src)))]
        (do
          (assert (= native.exitCode 0) (str "arrayNativeMod: native exit " native.exitCode "; stderr " native.stderr))
          (assert (= interp.exitCode 0) (str "arrayNativeMod: host run exit " interp.exitCode "; stderr " interp.stderr))
          (assert (= native.stdout (arrayExpected)) (str "arrayNativeMod: native output is the worked values; got " native.stdout))
          (assert (= native.stdout interp.stdout) (str "arrayNativeMod: native stdout equals host stdout " interp.stdout))))
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testArrayNative work)
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
      true))
