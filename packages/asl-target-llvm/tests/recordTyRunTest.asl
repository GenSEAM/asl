(module asl-target-llvm/tests/recordTyRunTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-target-llvm :a llvm)])

fn clangCmd -> String
  "clang -Wno-override-module"

fn libPath -> String
  "asl/host/out/libaslrt.a"

fn source -> String
  (stringJoin (list
    "(module recordRun :x [main start])"
    "(schema Point (:f x Int64) (:f y Int64))"
    "(fn mk [(a Int64)] -> Point (Point :x a :y 2))"
    "(fn getY [(p Point)] -> Int64 p.y)"
    "(fn relay [(n Int64)] -> Any (mk n))"
    "(fn pick [(flag Bool) (p Point)] -> Point (if flag p (mk 9)))"
    "(fn sumPt [(p Point)] -> Int64 (let [(q Point (pick false p))] (+ q.x (getY p))))"
    "(fn g [(n Int64)] -> Any n)"
    "(fn start [] -> Point (mk 5))"
    "(fn main [] -> Int64 (let [(base Int64 (g 2)) (p Point (relay 40))] (+ base (sumPt p))))") "\n")

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) ds) "; ")

fn emitted m: ty/SsaModule entry: String -> String
  (mt (llvm/emitLlvmProgram m entry) ((ok text) text) ((err ds) (str "emit failed: " (diagText ds))))

fn fnBody text: String header: String -> String
  (mt (stringIndexOf text header)
    ((none) "")
    ((some i) (let [(rest (optionOr (stringSlice text i (stringLength text)) ""))]
                (mt (stringIndexOf rest "\n}\n") ((none) rest) ((some j) (optionOr (stringSlice rest 0 j) ""))))))

fn ! runNative work: String text: String -> Int64
  (let [(llFile (str work "/recordRun.ll"))
        (binFile (str work "/recordRun.bin"))]
    (do
      (assert (ok? (fileWrite llFile text)) (str "write " llFile))
      (let [(linkRes (processRun (str (clangCmd) " -x ir " llFile " -x none " (libPath) " -lm -o " binFile)))]
        (do
          (assert (= linkRes.exitCode 0) (str "clang links the record program: " linkRes.stderr))
          (processRun binFile).exitCode))))

fn ! runTests -> Bool
  (mt (low/lowerSource (source))
    ((err ds) (assert false (str "record program lowers: " (diagText ds))))
    ((ok m)
      (let [(program (emitted m "main"))
            (startProgram (emitted m "start"))
            (made (processRun "mktemp -d"))
            (work (stringReplace made.stdout "\n" ""))]
        (do
          (refute (stringStartsWith? program "emit failed") program)
          (refute (stringContains? program "rec:Point") "no record type name leaks into LLVM IR")
          (assert (stringContains? program "define tailcc i64 @getY(%Val %p)") (str "a record parameter is a %Val:\n" program))
          (assert (stringContains? (fnBody program "define tailcc %Val @relay(") "musttail call tailcc %Val @mk(") (str "a Val function returning a record call stays a musttail call:\n" (fnBody program "define tailcc %Val @relay(")))
          (assert (stringContains? startProgram "call i32 @rterr.exit(%Val %result)") (str "an entry returning a record gets the Val main wrapper:\n" startProgram))
          (refute (stringContains? startProgram "@asl_rt_exit_code") "the deleted abi.c asl_rt_exit_code is neither declared nor called")
          (assert (= made.exitCode 0) "mktemp -d makes a work directory")
          (assert (= (runNative work program) 13) "the record program exits with 2 + 9 + 2")
          (assert (= (processRun (str "rm -rf " work)).exitCode 0) "work directory removed")
          true))))
