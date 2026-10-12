(module asl-target-llvm/tests/exitCodeTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)
      (tools/nativeTest :a nt)])

fn asl1Path -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! asl1Bin! -> String
  (let [(built (nt/prepareRun (asl1Path) (nt/fingerprint)))]
    (mt built.binary
      ((some bin) bin)
      ((none) (do (assert false (str "asl1.asl builds natively: " built.reason)) ""))))

fn ok0Source -> String
  (stringJoin
    (list
      "(module progOk0 :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (ok 0)")
    "\n")

fn ok42Source -> String
  (stringJoin
    (list
      "(module progOk42 :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (ok 42)")
    "\n")

fn okStrSource -> String
  (stringJoin
    (list
      "(module progOkStr :x [main] :i [])"
      ""
      "fn ! main -> (Result String String)"
      "  (ok \"hello\")")
    "\n")

fn errSource -> String
  (stringJoin
    (list
      "(module progErr :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (err \"boom\")")
    "\n")

fn ! runProgram work: String name: String src: String wantExit: Int64 wantStdout: String -> Bool
  (let [(srcFile (str work "/" name ".asl"))
        (llFile (str work "/" name ".ll"))
        (binFile (str work "/" name ".bin"))]
    (do
      (assert (ok? (fileWrite srcFile src)) (str "write " srcFile))
      (let [(buildRes (sh (str (asl1Bin!) " build " srcFile " -o " llFile)))
            (linkRes (sh (str (clang) " -x ir " llFile " -x none " (lib) " -lm -o " binFile)))
            (nativeOut (sh binFile))]
        (do
          (assert (= buildRes.exitCode 0) (str "asl1 build " name ": " buildRes.stderr))
          (assert (= linkRes.exitCode 0) (str "clang link " name ": " linkRes.stderr))
          (assert (= nativeOut.exitCode wantExit)
                  (str name ": exit code; native=" nativeOut.exitCode " want=" wantExit "; stderr: " nativeOut.stderr))
          (assert (= nativeOut.stdout wantStdout)
                  (str name ": stdout; native=" nativeOut.stdout " want=" wantStdout))
          true))))

fn ! testMainEntry work: String -> Bool
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
      (let [(emitRes (llvm/emitLlvmSource src "main"))]
        (do
          (assert (ok? emitRes)
                  (str "emitLlvmSource with entry main: "
                       (mt emitRes
                         ((err ds) (str (optionOr (listHead ds) (ty/makeIrDiag "" "" "")).code " "
                                        (optionOr (listHead ds) (ty/makeIrDiag "" "" "")).message))
                         ((ok _) ""))))
          (mt emitRes
            ((err _) false)
            ((ok code)
              (do
                (assert (ok? (fileWrite llFile code)) "write testMain.ll")
                (let [(linkRes (sh (str (clang) " -x ir " llFile " -x none " (lib) " -lm -o " binFile)))
                      (nativeOut (sh binFile))]
                  (do
                    (assert (= linkRes.exitCode 0) (str "clang link testMain: " linkRes.stderr))
                    (assert (= nativeOut.exitCode 42)
                            (str "testMain: exit code; native=" nativeOut.exitCode " want=42"))
                    (assert (= nativeOut.stdout "")
                            (str "testMain: stdout; native=" nativeOut.stdout " want=empty"))
                    true)))))))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (assert (runProgram work "progOk0" (ok0Source) 0 "") "progOk0")
      (assert (runProgram work "progOk42" (ok42Source) 42 "") "progOk42")
      (assert (runProgram work "progOkStr" (okStrSource) 0 "") "progOkStr")
      (assert (runProgram work "progErr" (errSource) 1 "") "progErr")
      (assert (testMainEntry work) "testMainEntry")
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
      true))
