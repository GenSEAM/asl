(module asl-target-llvm/tests/exitCodeTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm :a llvm)])

fn host -> String
  "asl/host/out/asl-host"

fn asl1Path -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
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

fn ! runProgram work: String name: String src: String -> Bool
  (let [(srcFile (str work "/" name ".asl"))
        (llFile (str work "/" name ".ll"))
        (binFile (str work "/" name ".bin"))]
    (do
      (assert (ok? (fileWrite srcFile src)) (str "write " srcFile))
      (let [(hostOut (sh (str (host) " run " srcFile)))
            (buildRes (sh (str (host) " run " (asl1Path) " build " srcFile " -o " llFile)))
            (linkRes (sh (str (clang) " -x ir " llFile " -x none " (lib) " -lm -o " binFile)))
            (nativeOut (sh binFile))]
        (do
          (assert (= buildRes.exitCode 0) (str "asl1 build " name ": " buildRes.stderr))
          (assert (= linkRes.exitCode 0) (str "clang link " name ": " linkRes.stderr))
          (assert (= nativeOut.exitCode hostOut.exitCode)
                  (str name ": exit code parity; native=" nativeOut.exitCode " host=" hostOut.exitCode "; stderr: " nativeOut.stderr))
          (assert (= nativeOut.stdout hostOut.stdout)
                  (str name ": stdout parity; native=" nativeOut.stdout " host=" hostOut.stdout))
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
                      (hostOut (sh (str (host) " run " srcFile)))
                      (nativeOut (sh binFile))]
                  (do
                    (assert (= linkRes.exitCode 0) (str "clang link testMain: " linkRes.stderr))
                    (assert (= nativeOut.exitCode hostOut.exitCode)
                            (str "testMain: exit code parity; native=" nativeOut.exitCode " host=" hostOut.exitCode))
                    (assert (= nativeOut.stdout hostOut.stdout)
                            (str "testMain: stdout parity; native=" nativeOut.stdout " host=" hostOut.stdout))
                    true)))))))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (assert (runProgram work "progOk0" (ok0Source)) "progOk0")
      (assert (runProgram work "progOk42" (ok42Source)) "progOk42")
      (assert (runProgram work "progOkStr" (okStrSource)) "progOkStr")
      (assert (runProgram work "progErr" (errSource)) "progErr")
      (assert (testMainEntry work) "testMainEntry")
      (assert (= (sh (str "rm -rf " work)).exitCode 0) "work directory removed")
      true))
