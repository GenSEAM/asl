(module asl-target-llvm/tests/nativeGapsTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn fixtureSource -> String
  (str "(module nativeGapRecord :x [main] :i [])\n"
       "(schema NativeGapPair (:f left Int64) (:f right Int64))\n"
       "fn ! main -> (Result Int64 String)\n"
       "  (let [(pair (NativeGapPair left 7 right 11))]\n"
       "    (do (println (+ pair.left pair.right)) (ok 0)))\n")

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String
                       (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compileFixture dir: String -> (Result String String)
  (let [(path (str dir "/nativeGapRecord.asl"))]
    (do
      (assert (ok? (fileWrite path (fixtureSource))) "fixture source written")
      (mt (lk/linkEntry! path)
        ((err ds) (err (formatDiags ds)))
        ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
                  ((err ds) (err (formatDiags ds)))
                  ((ok code) (ok code)))))))

fn ! testRecordNative dir: String -> Bool
  (let [(ll (str dir "/nativeGapRecord.ll"))
        (exe (str dir "/nativeGapRecord"))
        (built (compileFixture dir))]
    (do
      (assert (ok? built) (str "named record constructor lowers: " (mt built ((ok _) "ok") ((err e) e))))
      (let [(code (mt built ((ok s) s) ((err _) "")))]
        (do
          (assert (ok? (fileWrite ll code)) "LLVM fixture written")
          (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe)))]
            (assert (= linked.exitCode 0) (str "record fixture linked: " linked.stderr)))
          (let [(native (processRun exe))]
            (do
              (assert (= native.exitCode 0) (str "record fixture native exit: " native.stderr))
              (assert (= native.stdout "18\n") (str "record constructor native output: " native.stdout))))))
      true))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "temporary directory created")
      (testRecordNative dir)
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "temporary directory removed")
      true))
