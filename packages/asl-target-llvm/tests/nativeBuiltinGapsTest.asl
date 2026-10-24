(module asl-target-llvm/tests/nativeBuiltinGapsTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-proc/coreProcess :a proc) (asl-target-llvm :a llvm)])

; (:m :ref HL-E-LLVM :do "HL-E-LLVM (asl-host deleted): fixtureSource is fixed and deterministic (self-checks its own SHA/NaN/infinity values before printing), so recordedInterp below is a one-time capture of asl-host's own output for this exact fixture, taken before HL-DELETE removed the binary (asl-host run <fixtureSource>: exit 0, stdout is the two SHA hex digests then true/true/true, stderr empty)")

fn recordedInterp -> proc/ProcessOutput
  (proc/ProcessOutput :exitCode 0
    :stdout "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\ntrue\ntrue\ntrue\n"
    :stderr "" :durationMs 0)

fn fixtureSource -> String
  (str "(module nativeBuiltinGapFixture :x [main] :i [])\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(emptyHash (bytesSha256 (stringToBytes \"\")))\n"
       "        (abcHash (bytesSha256 (stringToBytes \"abc\")))\n"
       "        (nan (floatNan)) (posInf (floatInf)) (negInf (floatNegInf))]\n"
       "    (if (and (= emptyHash \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\")\n"
       "             (and (= abcHash \"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\")\n"
       "                  (and (not (= nan nan))\n"
       "                       (and (= posInf (floatInf)) (= negInf (floatNegInf))))))\n"
       "      (do (println emptyHash) (println abcHash) (println (isNan? nan))\n"
       "           (println (= posInf (floatInf))) (println (= negInf (floatNegInf))) (ok 0))\n"
       "      (err \"native builtin values mismatch\")))\n")

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String
                       (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn directFloatModule -> irTy/SsaModule
  (irTy/ssaModule "nativeBuiltinGapFixture" (list) (list) (list) (list) (list)
    (list
      (irTy/ssaFunction "nativeBuiltinGapFixture.main" (list) (list) (irTy/tyI1)
        (list
          (irTy/ssaBlock "entry" (list)
            (list
              (irTy/ssaInstr "%nan" (irTy/tyVal) (irTy/opBuiltin "floatNan" (list)))
              (irTy/ssaInstr "%nanRaw" (irTy/tyF64) (irTy/opUnbox "%nan"))
              (irTy/ssaInstr "%nanIsNan" (irTy/tyI1) (irTy/opPrim "neFloat" (list "%nanRaw" "%nanRaw")))
              (irTy/ssaInstr "%pos" (irTy/tyVal) (irTy/opBuiltin "floatInf" (list)))
              (irTy/ssaInstr "%posRaw" (irTy/tyF64) (irTy/opUnbox "%pos"))
              (irTy/ssaInstr "%posIsFiniteEq" (irTy/tyI1) (irTy/opPrim "eqFloat" (list "%posRaw" "%posRaw")))
              (irTy/ssaInstr "%neg" (irTy/tyVal) (irTy/opBuiltin "floatNegInf" (list)))
              (irTy/ssaInstr "%negRaw" (irTy/tyF64) (irTy/opUnbox "%neg"))
              (irTy/ssaInstr "%negIsFiniteEq" (irTy/tyI1) (irTy/opPrim "eqFloat" (list "%negRaw" "%negRaw")))
              (irTy/ssaInstr "%infinities" (irTy/tyI1) (irTy/opPrim "andBool" (list "%posIsFiniteEq" "%negIsFiniteEq")))
              (irTy/ssaInstr "%valid" (irTy/tyI1) (irTy/opPrim "andBool" (list "%nanIsNan" "%infinities"))))
            (irTy/termReturn "%valid"))))))

fn ! compileNative path: String llPath: String exePath: String -> proc/ProcessOutput
  (match (lk/linkEntry! path)
    ((err ds) (proc/ProcessOutput :exitCode 1 :stdout "" :stderr (str "link failed: " (formatDiags ds)) :durationMs 0))
    ((ok m)
      (match (llvm/emitLlvmProgramNative! m "nativeBuiltinGapFixture.main")
        ((err ds) (proc/ProcessOutput :exitCode 1 :stdout "" :stderr (str "LLVM emission failed: " (formatDiags ds)) :durationMs 0))
        ((ok code)
          (do
            (fileWrite llPath code)
            (processRun (str "/usr/bin/clang -Wno-override-module -x ir " llPath
                            " -x none asl/host/out/libaslrt.a -lm -o " exePath)))))))

fn ! testNativeParity -> Bool
  (let [(dir (str "/tmp/asl-native-builtin-gaps-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))
        (path (str dir "/nativeBuiltinGapFixture.asl"))
        (llPath (str dir "/nativeBuiltinGapFixture.ll"))
        (exePath (str dir "/nativeBuiltinGapFixture"))
        (written (fileWrite path (fixtureSource)))
        (native (if (and (ok? made) (ok? written)) (compileNative path llPath exePath)
                    (proc/ProcessOutput :exitCode 1 :stdout "" :stderr "fixture setup failed" :durationMs 0)))
        (interp (recordedInterp))
        (ran (if (= native.exitCode 0) (processRun exePath)
                 (proc/ProcessOutput :exitCode 1 :stdout "" :stderr native.stderr :durationMs 0)))
        (removedExe (if (fileExists? exePath) (pathRemove exePath) (ok ())))
        (removedLl (if (fileExists? llPath) (pathRemove llPath) (ok ())))
        (removedSrc (if (fileExists? path) (pathRemove path) (ok ())))
        (removedDir (if (fileExists? dir) (pathRemove dir) (ok ())))]
    (do
      (assert (ok? made) "temporary fixture directory is created")
      (assert (ok? written) "fixture source is written")
      (assert (= native.exitCode 0) (str "LLVM fixture links with libaslrt.a: " native.stderr))
      (assert (= interp.exitCode 0) "recorded asl-host output exits 0")
      (assert (= ran.exitCode interp.exitCode) "native exit matches the recorded asl-host output")
      (assert (= ran.stdout interp.stdout) "native stdout matches the recorded asl-host output for SHA vectors, NaN, and infinities")
      (assert (= ran.exitCode 0) (str "native fixture passes vector and float checks: " ran.stderr))
      (assert (ok? removedExe) "native executable is removed")
      (assert (ok? removedLl) "LLVM file is removed")
      (assert (ok? removedSrc) "fixture source is removed")
      (assert (ok? removedDir) "temporary directory is removed")
      true))

fn ! testDirectFloatBuiltin -> Bool
  (let [(dir (str "/tmp/asl-native-float-builtins-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))
        (llPath (str dir "/floatBuiltin.ll"))
        (exePath (str dir "/floatBuiltin"))
        (emitted (llvm/emitLlvmProgramNative! (directFloatModule) "nativeBuiltinGapFixture.main"))
        (code (match emitted ((ok s) s) ((err _) "")))
        (written (if (and (ok? made) (ok? emitted)) (fileWrite llPath code) (err "emission failed")))
        (linked (if (ok? written)
                    (processRun (str "/usr/bin/clang -Wno-override-module -x ir " llPath
                                    " -x none asl/host/out/libaslrt.a -lm -o " exePath))
                    (proc/ProcessOutput :exitCode 1 :stdout "" :stderr "LLVM write failed" :durationMs 0)))
        (ran (if (= linked.exitCode 0) (processRun exePath)
                 (proc/ProcessOutput :exitCode 1 :stdout "" :stderr linked.stderr :durationMs 0)))
        (removedExe (if (fileExists? exePath) (pathRemove exePath) (ok ())))
        (removedLl (if (fileExists? llPath) (pathRemove llPath) (ok ())))
        (removedDir (if (fileExists? dir) (pathRemove dir) (ok ())))]
    (do
      (assert (ok? made) "direct-float temporary directory is created")
      (assert (ok? emitted) (str "floatNan/floatInf/floatNegInf emit directly: " (match emitted ((ok _) "ok") ((err ds) (formatDiags ds)))))
      (assert (ok? written) "direct-float LLVM module is written")
      (assert (= linked.exitCode 0) (str "direct-float LLVM links: " linked.stderr))
      (assert (= ran.exitCode 1) (str "native direct float builtins make NaN unequal to itself and infinities equal to themselves: " ran.stderr))
      (assert (ok? removedExe) "direct-float executable is removed")
      (assert (ok? removedLl) "direct-float LLVM file is removed")
      (assert (ok? removedDir) "direct-float temporary directory is removed")
      true))

; (:m :ref PERF-VERIFY-ONCE :do "the native entry skips the route input verify (its input is a linked module); an unlinked invalid module, here one returning an undefined value after a routed sys builtin, is still rejected by the emit verify in every RC mode")
fn invalidModule -> irTy/SsaModule
  (irTy/ssaModule "nativeBuiltinGapFixture" (list) (list) (list) (list) (list)
    (list
      (irTy/ssaFunction "nativeBuiltinGapFixture.main" (list) (list) (irTy/tyVal)
        (list
          (irTy/ssaBlock "entry" (list)
            (list (irTy/ssaInstr "%now" (irTy/tyVal) (irTy/opBuiltin "monotonicNs" (list))))
            (irTy/termReturn "%missing"))))))

fn diagCodes r: (Result String (List irTy/IrDiag)) -> (List String)
  (match r ((ok _) (list)) ((err ds) (map (fn [(d irTy/IrDiag)] -> String d.code) ds)))

fn ! rejectedIn mode: String -> Bool
  (let [(r (llvm/emitLlvmProgramNativeWith! (invalidModule) "nativeBuiltinGapFixture.main" mode))]
    (do (assert (err? r) (str "mode " mode ": a module returning an undefined value is rejected"))
        (assert (listAny? (fn [(c String)] -> Bool (stringStartsWith? c "ERR_IR")) (diagCodes r)) (str "mode " mode ": by an SSA verify diagnostic: " (stringJoin (diagCodes r) " ")))
        true))

fn ! testInvalidModuleRejected -> Bool
  (and (rejectedIn "0") (and (rejectedIn "1") (rejectedIn "notrace")))

fn ! runTests -> Bool
  (do
    (assert (testNativeParity) "native builtin fixture matches the interpreter")
    (assert (testDirectFloatBuiltin) "direct native float constants execute")
    (assert (testInvalidModuleRejected) "an invalid module is rejected on the native entry")
    true)
