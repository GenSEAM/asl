(module asl-target-llvm/tests/entryResultTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/emit :a em)])

fn host -> String
  "asl/host/out/asl-host"

fn asl1Path -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn clangCmd -> String
  "clang -Wno-override-module"

fn libPath -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ok0Source -> String
  (stringJoin
    (list
      "(module progOk0 :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (ok 0)")
    "\n")

fn ok1Source -> String
  (stringJoin
    (list
      "(module progOk1 :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (ok 1)")
    "\n")

fn ok42Source -> String
  (stringJoin
    (list
      "(module progOk42 :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (ok 42)")
    "\n")

fn ok255Source -> String
  (stringJoin
    (list
      "(module progOk255 :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (ok 255)")
    "\n")

fn okStrSource -> String
  (stringJoin
    (list
      "(module progOkStr :x [main] :i [])"
      ""
      "fn ! main -> (Result String String)"
      "  (ok \"hello\")")
    "\n")

fn okUnitSource -> String
  (stringJoin
    (list
      "(module progOkUnit :x [main] :i [])"
      ""
      "fn ! main -> (Result Unit String)"
      "  (ok ())")
    "\n")

fn errStrSource -> String
  (stringJoin
    (list
      "(module progErrStr :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (err \"failure\")")
    "\n")

fn errIntSource -> String
  (stringJoin
    (list
      "(module progErrInt :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 Int64)"
      "  (err 7)")
    "\n")

fn mainArgsSource -> String
  (stringJoin
    (list
      "(module progMainArgs :x [main] :i [])"
      ""
      "fn ! main args: (List String) -> (Result Int64 String)"
      "  (if (listEmpty? args) (ok 0) (ok 1))")
    "\n")

fn ! runProgram work: String name: String src: String expectedExit: Int64 -> Bool
  (let [(srcFile (str work "/" name ".asl"))
        (llFile (str work "/" name ".ll"))
        (binFile (str work "/" name ".bin"))]
    (do
      (assert (ok? (fileWrite srcFile src)) (str "write " srcFile))
      (let [(hostOut (sh (str (host) " run " srcFile)))
            (buildRes (sh (str (host) " run " (asl1Path) " build " srcFile " -o " llFile)))
            (linkRes (sh (str (clangCmd) " -x ir " llFile " -x none " (libPath) " -lm -o " binFile)))
            (nativeOut (sh binFile))]
        (do
          (assert (= buildRes.exitCode 0) (str "asl1 build " name ": " buildRes.stderr))
          (assert (= linkRes.exitCode 0) (str "clang link " name ": " linkRes.stderr))
          (assert (= nativeOut.exitCode expectedExit)
                  (str name ": expected exit " (stringFromInt64 expectedExit) ", got " (stringFromInt64 nativeOut.exitCode)))
          (assert (= nativeOut.exitCode hostOut.exitCode)
                  (str name ": exit code parity; native=" (stringFromInt64 nativeOut.exitCode) " host=" (stringFromInt64 hostOut.exitCode)))
          (assert (= nativeOut.stdout hostOut.stdout)
                  (str name ": stdout parity; native=" nativeOut.stdout " host=" hostOut.stdout))
          true))))

fn ! testMainEntrySource work: String -> Bool
  (let [(src (stringJoin
               (list
                 "(module testMain :x [main] :i [])"
                 ""
                 "fn ! main -> (Result Int64 String)"
                 "  (ok 42)")
               "\n"))
        (srcFile (str work "/testMain.asl"))
        (llFile (str work "/testMain.ll"))
        (binFile (str work "/testMain.bin"))]
    (do
      (assert (ok? (fileWrite srcFile src)) "write testMain.asl")
      (let [(emitRes (llvm/emitLlvmSource src "main"))
            (emitDefault (llvm/emitLlvmSource src ""))]
        (do
          (assert (ok? emitRes) "emitLlvmSource with explicit entry main succeeds")
          (assert (ok? emitDefault) "emitLlvmSource with empty string defaults to main and succeeds")
          (mt emitRes
            ((err _) false)
            ((ok code)
              (do
                (assert (stringContains? code "define tailcc %Val @asl_main()") "emitted IR mangles ASL main to @asl_main, a tailcc module function")
                (assert (stringContains? code "define i32 @main(") "emitted IR includes @main wrapper")
                (assert (stringContains? code "call i32 @rterr.exit(%Val %result)") "emitted IR routes exit code through the native rterr.exit (ABIVAL-2)")
                (refute (stringContains? code "@asl_rt_exit_code") "emitted IR names no abi.c asl_rt_exit_code")
                (assert (ok? (fileWrite llFile code)) "write testMain.ll")
                (let [(linkRes (sh (str (clangCmd) " -x ir " llFile " -x none " (libPath) " -lm -o " binFile)))
                      (hostOut (sh (str (host) " run " srcFile)))
                      (nativeOut (sh binFile))]
                  (do
                    (assert (= linkRes.exitCode 0) (str "clang link testMain: " linkRes.stderr))
                    (assert (= nativeOut.exitCode 42) "testMain: exit code 42")
                    (assert (= nativeOut.exitCode hostOut.exitCode) "testMain: exit code parity with host")
                    (assert (= nativeOut.stdout hostOut.stdout) "testMain: stdout parity with host")
                    true)))))))))

fn testEmitFunctionMain -> Bool
  (let [(i64Ty (ty/makeIrType "i64" "default" false))
        (f (ty/IrFunction :name "main" :params (list) :retType i64Ty :body (list)))
        (fnText (em/emitLlvmFunction f))]
    (do
      (assert (stringContains? fnText "define i64 @asl_main()") "em/emitLlvmFunction mangles main to @asl_main")
      (assert (not (stringContains? fnText "define i64 @main()")) "em/emitLlvmFunction does not emit bare @main")
      true))

fn testEmitModuleMain -> Bool
  (let [(i64Ty (ty/makeIrType "i64" "default" false))
        (retStmt (ty/IrStmt :kind "return" :target "" :field "" :value "42" :ty i64Ty
                            :expr (ty/IrExpr :kind "atom" :op "" :left "42" :right "" :args (list)
                                             :ty i64Ty :wrap "" :shiftMask false :divModFloor false :codeLabel "")
                            :label "" :args (list) :scrutinee "" :cases (list) :defaultBody (list) :loopBody (list)))
        (f (ty/IrFunction :name "main" :params (list) :retType i64Ty :body (list retStmt)))
        (m (ty/IrModule :name "testMod" :profile "c11" :funcs (list f)))
        (res (em/emitLlvmModule m))]
    (do
      (assert (ok? res) "em/emitLlvmModule succeeds for module with main")
      (mt res
        ((err _) false)
        ((ok code)
          (do
            (assert (stringContains? code "define i64 @asl_main()") "em/emitLlvmModule defines @asl_main")
            (assert (stringContains? code "define i32 @main(i32 %argc, ptr %argv)") "em/emitLlvmModule defines @main wrapper")
            (assert (stringContains? code "call i64 @asl_main()") "em/emitLlvmModule wrapper calls @asl_main")
            (assert (stringContains? code "%code = trunc i64 %res to i32") "em/emitLlvmModule wrapper truncates res to i32")
            (assert (stringContains? code "ret i32 %code") "em/emitLlvmModule wrapper returns code")
            true)))))

fn ! testRunParityLlvm -> Bool
  (let [(res (sh (str (host) " run tests/acceptance/targetParity/runParity.asl llvm")))]
    (do
      (assert (= res.exitCode 0) (str "runParity llvm passes exit 0: " res.stderr))
      (assert (stringContains? res.stdout "6/6 passed, 0 failed, 0 skipped") "runParity llvm reports 6/6 passed on whole corpus")
      true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (assert (runProgram work "progOk0" (ok0Source) 0) "progOk0")
      (assert (runProgram work "progOk1" (ok1Source) 1) "progOk1")
      (assert (runProgram work "progOk42" (ok42Source) 42) "progOk42")
      (assert (runProgram work "progOk255" (ok255Source) 255) "progOk255")
      (assert (runProgram work "progOkStr" (okStrSource) 0) "progOkStr")
      (assert (runProgram work "progOkUnit" (okUnitSource) 0) "progOkUnit")
      (assert (runProgram work "progErrStr" (errStrSource) 1) "progErrStr")
      (assert (runProgram work "progErrInt" (errIntSource) 1) "progErrInt")
      (assert (runProgram work "progMainArgs" (mainArgsSource) 0) "progMainArgs")
      (assert (testMainEntrySource work) "testMainEntrySource")
      (assert (testEmitFunctionMain) "testEmitFunctionMain")
      (assert (testEmitModuleMain) "testEmitModuleMain")
      (assert (testRunParityLlvm) "testRunParityLlvm")
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
      true))
