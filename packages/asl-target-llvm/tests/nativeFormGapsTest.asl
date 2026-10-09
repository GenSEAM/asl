(module asl-target-llvm/tests/nativeFormGapsTest
  :x [runTests]
  :i [(asl-ir/lower :a low)
      (asl-ir/types :a irTy)
      (asl-target-llvm :a llvm)])

fn source -> String
  (stringJoin (list
    "(module formGap :x [main])"
    "(schema GapSession (:f id String) (:f deadlocked Bool))"
    "(schema GapWire (:f valid? Bool) (:f errorKind String) (:f message String))"
    "(enum GapChoice (:c chosen [(text String)]))"
    "fn pick choice: GapChoice -> String"
    "  (mt choice ((chosen text) text))"
    "fn ! main -> Int64"
    "  (let [(session (GapSession :id \"s\")) (wire (GapWire :valid? true :errorKind \"\" :message \"ok\"))]"
    "    (do (println (.-id session)) (println (if (== (.-valid? wire) true) \"true\" \"false\")) (println (pick (chosen \"variant\"))) 0))") "\n")

fn omittedBoolSource -> String
  (stringJoin (list
    "(module omittedBool :x [main])"
    "(schema GapSession (:f id String) (:f deadlocked Bool))"
    "fn ! main -> Int64"
    "  (let [(session (GapSession :id \"s\"))]"
    "    (do (println (.-id session)) (if (.-deadlocked session) 1 0)))") "\n")

fn diagText diags: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code ": " d.message)) diags) "; ")

fn ! testQuestionKeyedRecord -> Bool
  (let [(completeSource (stringReplace (source) "(GapSession :id \"s\")" "(GapSession :id \"s\" :deadlocked false)"))
        (src (stringReplace completeSource "(GapWire :valid? true" "(GapWire (mt :valid) true"))
        (made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))
        (srcPath (str dir "/questionKeyed.asl"))
        (interpreterPath (str dir "/interpreterEquivalent.asl"))
        (llPath (str dir "/questionKeyed.ll"))
        (exePath (str dir "/questionKeyed"))]
    (do
      (assert (= made.exitCode 0) "question-keyed temporary fixture directory created")
      (assert (stringContains? src "(mt :valid)") "question-keyed fixture uses the mt field marker")
      (assert (ok? (fileWrite srcPath src)) "question-keyed fixture source written")
      (assert (ok? (fileWrite interpreterPath (source))) "interpreter-equivalent keyword record fixture written")
      (mt (low/lowerSource src)
        ((err diags) (do (assert (listEmpty? diags) (str "question-keyed fixture lowers: " (diagText diags))) false))
        ((ok m)
         (mt (llvm/emitLlvmProgramNative! m "main")
           ((err diags) (do (assert (listEmpty? diags) (str "question-keyed fixture emits: " (diagText diags))) false))
           ((ok code)
            (do
              (assert (ok? (fileWrite llPath code)) "question-keyed LLVM fixture written")
              (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " llPath " -x none asl/host/out/libaslrt.a -lm -o " exePath)))]
                (assert (= linked.exitCode 0) (str "question-keyed fixture linked: " linked.stderr)))
              (let [(native (processRun exePath))
                    (interp (processRun (str "asl/host/out/asl-host run " interpreterPath)))]
                (do
                  (assert (= native.exitCode 0) (str "question-keyed native fixture exits 0: " native.stderr))
                  (assert (= interp.exitCode 0) (str "interpreter-equivalent fixture exits 0: " interp.stderr))
                  (assert (= native.exitCode interp.exitCode) "question-keyed native and equivalent interpreter exit statuses agree")
                  (assert (= native.stdout interp.stdout) (str "question-keyed native output " native.stdout " matches equivalent interpreter " interp.stdout))
                  (assert (= native.stdout "s\ntrue\nvariant\n") (str "question-keyed field value survives native execution: " native.stdout))
                  true)))))))
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "question-keyed temporary fixture directory removed")
      true))

fn ! testNativeParity -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))
        (src (str dir "/formGap.asl"))
        (ll (str dir "/formGap.ll"))
        (exe (str dir "/formGap"))]
    (do
      (assert (= made.exitCode 0) "temporary fixture directory created")
      (assert (ok? (fileWrite src (source))) "native fixture source written")
      (mt (low/lowerSource (source))
        ((err diags) (do (assert (listEmpty? diags) (str "fixture lowers: " (diagText diags))) false))
        ((ok m)
         (mt (llvm/emitLlvmProgramNative! m "main")
           ((err diags) (do (assert (listEmpty? diags) (str "fixture emits: " (diagText diags))) false))
           ((ok code)
            (do
              (assert (ok? (fileWrite ll code)) "LLVM fixture written")
              (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe)))]
                (assert (= linked.exitCode 0) (str "native fixture linked: " linked.stderr)))
              (let [(native (processRun exe))
                    (interp (processRun (str "asl/host/out/asl-host run " src)))]
                (do
                  (assert (= native.exitCode 0) (str "native fixture exits 0: " native.stderr))
                  (assert (= interp.exitCode 0) (str "interpreter fixture exits 0: " interp.stderr))
                  (assert (= native.exitCode interp.exitCode) "native and interpreter exit statuses agree")
                  (assert (= native.stdout interp.stdout) (str "native output " native.stdout " matches interpreter " interp.stdout " (exit " (stringFromInt64 interp.exitCode) ", stderr " interp.stderr ")"))
                  (assert (= native.stdout "s\ntrue\nvariant\n") (str "omitted fields, == and positional variant values survive native execution: " native.stdout))
                  true)))))))
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "temporary fixture directory removed")
      true))

fn ! testOmittedBool dir: String -> Bool
  (let [(src (str dir "/omittedBool.asl"))
        (ll (str dir "/omittedBool.ll"))
        (exe (str dir "/omittedBool"))]
    (do
      (assert (ok? (fileWrite src (omittedBoolSource))) "omitted-Bool fixture source written")
      (mt (low/lowerSource (omittedBoolSource))
        ((err diags) (do (assert (listEmpty? diags) (str "omitted-Bool fixture lowers: " (diagText diags))) false))
        ((ok m)
         (mt (llvm/emitLlvmProgramNative! m "main")
           ((err diags) (do (assert (listEmpty? diags) (str "omitted-Bool fixture emits: " (diagText diags))) false))
           ((ok code)
            (do
              (assert (ok? (fileWrite ll code)) "omitted-Bool LLVM fixture written")
              (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe)))]
                (assert (= linked.exitCode 0) (str "omitted-Bool fixture linked: " linked.stderr)))
              (let [(native (processRun exe))
                    (interp (processRun (str "asl/host/out/asl-host run " src)))]
                (do
                  (assert (= native.exitCode 1) (str "native access to omitted Bool fails: " native.stderr))
                  (assert (= interp.exitCode 1) (str "interpreter access to omitted Bool fails: " interp.stderr))
                  (assert (= native.exitCode interp.exitCode) "omitted-Bool native and interpreter exit statuses agree")
                  (assert (= native.stdout interp.stdout) (str "omitted-Bool native output matches interpreter: " native.stdout " / " interp.stdout))
                  (assert (= native.stdout "s\n") (str "omitted Bool is not read as a value: " native.stdout))
                  (assert (stringContains? native.stderr "ERR_FIELD") (str "native omitted-Bool access reports the interpreter's missing-field error: " native.stderr))
                  (assert (stringContains? interp.stderr "ERR_FIELD") (str "interpreter omitted-Bool access reports a missing-field error: " interp.stderr))
                  true)))))))))

fn ! runTests -> Bool
  (let [(question (testQuestionKeyedRecord))
        (parity (testNativeParity))
        (made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))]
    (do
      (assert question "question-keyed native record matches the equivalent interpreter record")
      (assert parity "native equality, keyed records, and positional variants match interpreter")
      (assert (= made.exitCode 0) "omitted-Bool temporary directory created")
      (testOmittedBool dir)
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "omitted-Bool temporary directory removed")
      true))
