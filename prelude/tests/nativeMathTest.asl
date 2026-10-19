(module prelude/tests/nativeMathTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-target-llvm :a llvm)])

fn host -> String
  "bin/asl"

fn mathNames -> (List String)
  (list "int64ToFloat64" "float64ToInt64" "floor" "ceil" "round" "clamp" "pow" "exp" "log" "log2" "log10" "sqrt"
        "sin" "cos" "tan" "atan2" "abs" "min" "max" "nowNs" "monotonicNs" "sleepMs")

fn deletedEntries -> (List String)
  (list "abs" "min" "max" "int64ToFloat64" "float64ToInt64" "nowNs" "monotonicNs")

fn fixtureSrc -> String
  (stringJoin
    (list
      "(module mathFixture :x [main] :i [])"
      ""
      "fn values -> String"
      "  (let [(clock nowNs) (mono monotonicNs) (bound clamp)]"
      "    (str (map floor (list -0.5 2.5)) (map ceil (list -0.5)) (map round (list -0.5 2.5)) (map exp (list 0.0)) (map log (list 1.0))"
      "         (map log2 (list 8.0)) (map log10 (list 100.0)) (map sqrt (list 4.0)) (map sin (list 0.0)) (map cos (list 0.0)) (map tan (list 0.0))"
      "         (map abs (list -3 4)) (map abs (list -2.5)) (map int64ToFloat64 (list 9007199254740993)) (map float64ToInt64 (list 2.5 9.3e18))"
      "         (fold min 5 (list 3 7)) (fold max 5 (list 3 7)) (fold pow 2.0 (list 3.0)) (fold atan2 1.0 (list -1.0))"
      "         (map sleepMs (list 0 1)) (bound 0.0 1.0 2.0) (> (clock) 0) (> (mono) 0)))"
      ""
      "fn absCases -> String"
      "  (str (abs -3) \" \" (abs 0) \" \" (abs 9223372036854775807) \" \" (abs -2.5) \" \" (abs -0.0) \" \" (abs (floatNan)) \" \" (abs (floatNegInf)))"
      ""
      "fn minMaxCases -> String"
      "  (str (min 1 2) \" \" (max 1 2) \" \" (min 2 2) \" \" (min 1.5 -0.5) \" \" (max 1.5 -0.5) \" \""
      "       (min (floatNan) 1.0) \" \" (min 1.0 (floatNan)) \" \" (max (floatNan) 1.0) \" \" (max 1.0 (floatNan)) \" \""
      "       (min -0.0 0.0) \" \" (min 0.0 -0.0) \" \" (max -0.0 0.0) \" \" (max 0.0 -0.0))"
      ""
      "fn clampCases -> String"
      "  (str (clamp 0.0 1.0 0.5) \" \" (clamp 0.0 1.0 -1.0) \" \" (clamp 0.0 1.0 2.0) \" \" (clamp 0.0 1.0 (floatNan)) \" \""
      "       (clamp -1.0 -1.0 3.0) \" \" (clamp (floatNegInf) (floatInf) 7.5) \" \" (clamp 0.0 1.0 -0.0))"
      ""
      "fn convertCases -> String"
      "  (str (float64ToInt64 9.3e18) \" \" (float64ToInt64 -9.3e18) \" \" (float64ToInt64 (floatNan)) \" \" (float64ToInt64 (floatInf)) \" \""
      "       (float64ToInt64 (floatNegInf)) \" \" (float64ToInt64 2.5) \" \" (float64ToInt64 -2.5) \" \" (float64ToInt64 -9223372036854775808.0) \" \""
      "       (float64ToInt64 9223372036854775807.0) \" \" (int64ToFloat64 9007199254740993) \" \" (int64ToFloat64 -9007199254740993) \" \""
      "       (int64ToFloat64 9223372036854775807))"
      ""
      "fn libmCases -> String"
      "  (str (log 0.0) \" \" (log -1.0) \" \" (sqrt -0.0) \" \" (pow 0.0 0.0) \" \" (atan2 0.0 -1.0) \" \" (atan2 -0.0 -1.0) \" \" (atan2 -0.0 1.0) \" \""
      "       (atan2 0.0 0.0) \" \" (atan2 -1.0 0.0) \" \" (log2 0.0) \" \" (log10 -1.0) \" \" (exp 1000.0) \" \" (exp -1000.0) \" \" (floor -0.5) \" \""
      "       (ceil -0.5) \" \" (round -0.5) \" \" (round 0.5) \" \" (round 2.5) \" \" (sin -0.0) \" \" (cos (floatInf)) \" \" (tan 1.0) \" \""
      "       (pow -8.0 (/ 1.0 3.0)) \" \" (sqrt (floatInf)))"
      ""
      "fn ! sleepCase -> String"
      "  (let [(t0 (monotonicNs))"
      "        (a (sleepMs 0))"
      "        (b (sleepMs 5))"
      "        (t1 (monotonicNs))]"
      "    (str a \" \" b \" \" (>= (- t1 t0) 5000000)))"
      ""
      "fn ! failing op: String -> String"
      "  (cond ((= op \"absMin\") (str (abs (- -9223372036854775807 1))))"
      "        ((= op \"clampHi\") (str (clamp 2.0 1.0 0.5)))"
      "        ((= op \"clampNan\") (str (clamp (floatNan) 1.0 0.5)))"
      "        ((= op \"sleepNeg\") (str (sleepMs -1)))"
      "        (else \"no such case\"))"
      ""
      "fn ! main args: (List String) -> (Result Int64 String)"
      "  (let [(op (optionOr (listHead args) \"\"))]"
      "    (do (println (cond ((= op \"values\") (values))"
      "                       ((= op \"abs\") (absCases))"
      "                       ((= op \"minMax\") (minMaxCases))"
      "                       ((= op \"clamp\") (clampCases))"
      "                       ((= op \"convert\") (convertCases))"
      "                       ((= op \"libm\") (libmCases))"
      "                       ((= op \"sleep\") (sleepCase))"
      "                       ((= op \"now\") (stringFromInt64 (nowNs)))"
      "                       (else (failing op))))"
      "        (ok 0)))")
    "\n")

fn valueCases -> (List String)
  (list "values" "abs" "minMax" "clamp" "convert" "libm" "sleep")

fn failingCases -> (List String)
  (list "absMin" "clampHi" "clampNan" "sleepNeg")

; (:m :ref CLUSTER-U4GATE-RESTRUCTURE :do "absStr/minMixed/maxStr/clampType/sleepType/toIntType/toFloatType are statically ill-typed (confirmed via asl check on each in isolation), unlike absMin/clampHi/clampNan/sleepNeg which are well-typed and only trap at runtime (ERR_INT_OVERFLOW/ERR_RANGE); U4-MARKER-PARITY's whole-file gate correctly rejects the 7 static ones, but bundling them into one failing cond blocked the WHOLE fixture (every good case too) under asl run. Each gets its own single-purpose probe module (the nativeRun/nativeEval pattern) asserting rejection, not a runtime comparison")
fn typeProbeCases -> (List String)
  (list "absStr" "minMixed" "maxStr" "clampType" "sleepType" "toIntType" "toFloatType")

fn typeProbeExpr name: String -> String
  (cond ((= name "absStr") "(abs \"x\")")
        ((= name "minMixed") "(min 1 2.0)")
        ((= name "maxStr") "(max \"a\" \"b\")")
        ((= name "clampType") "(clamp 1 2.0 0.5)")
        ((= name "sleepType") "(sleepMs \"x\")")
        ((= name "toIntType") "(float64ToInt64 1)")
        ((= name "toFloatType") "(int64ToFloat64 1.5)")
        (else ""))

fn typeProbeWant name: String -> String
  (cond ((= name "absStr") "ERR_TYPE_MISMATCH argument to abs: expected a number, found String")
        ((= name "minMixed") "ERR_TYPE_MISMATCH argument to min: expected an integer, found Float64")
        ((= name "maxStr") "ERR_TYPE_MISMATCH argument to max: expected a number, found String")
        ((= name "clampType") "ERR_TYPE_MISMATCH argument to clamp: expected Float64, found an integer")
        ((= name "sleepType") "ERR_TYPE_MISMATCH argument to sleepMs: expected Int64, found String")
        ((= name "toIntType") "ERR_TYPE_MISMATCH argument to float64ToInt64: expected Float64, found an integer")
        ((= name "toFloatType") "ERR_TYPE_MISMATCH argument to int64ToFloat64: expected Int64, found Float64")
        (else ""))

fn ! testTypeRejected dir: String name: String -> Bool
  (let [(path (str dir "/" name ".asl"))
        (src (str "(module mathTypeProbe/" name " :x [main] :i [])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (do (println (str " (typeProbeExpr name) "))\n      (ok 0))\n"))
        (_ (fileWrite path src))
        (r (processRun (str (host) " check " path)))
        (want (typeProbeWant name))]
    (do
      (assert (!= r.exitCode 0) (str name ": asl check must reject " path ", got exit " r.exitCode))
      (assert (stringContains? r.stderr "4:3: ") (str name ": error locus must be at the println line (4:3), got " r.stderr))
      (assert (stringContains? r.stderr want) (str name ": expected '" want "' in check output, got " r.stderr))
      true))

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn ! compiled path: String -> (Result String String)
  (mt (lk/linkEntry! path)
    ((err ds) (err (formatDiags ds)))
    ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
              ((err ds) (err (formatDiags ds)))
              ((ok code) (ok code)))))

fn ! optBin -> (Option String)
  (let [(known (filter (fn [(c String)] -> Bool (= (processRun (str "test -x " c)).exitCode 0))
                        (list "/opt/homebrew/opt/llvm/bin/opt" "/usr/local/opt/llvm/bin/opt")))]
    (mt (listHead known)
      ((some o) (some o))
      ((none) (if (= (processRun "command -v opt >/dev/null 2>&1").exitCode 0) (some "opt") (none)))))

fn ! testRuntimeDecls -> Bool
  (do
    (map (fn [(n String)] -> Bool
           (do (refute (listAny? (fn [(d String)] -> Bool (stringContains? d (str "@asl_rt_b_" n "("))) (llvm/runtimeDecls))
                       (str "runtimeDecls declares no asl_rt_b_" n))
               true))
         (deletedEntries))
    true)

fn ! testIr dir: String code: String -> Bool
  (let [(ll (str dir "/mathFixture.ll"))]
    (do
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? code (str "@asl_rt_b_" n "(")) (str "the IR neither declares nor calls asl_rt_b_" n))
                 true))
           (deletedEntries))
      (map (fn [(n String)] -> Bool
             (do (refute (stringContains? code (str "@name." n " ")) (str "no @name." n " constant: no asl_rt_builtin call names " n))
                 true))
           (mathNames))
      (refute (stringContains? code "@asl_rt_builtin(ptr @name.") "no core asl_rt_builtin call at all in the fixture")
      (map (fn [(n String)] -> Bool
             (do (assert (stringContains? code (str "call %Val @mathrt." n "(")) (str n " calls its @mathrt helper"))
                 true))
           (list "abs" "min" "max" "clamp" "int64ToFloat64" "float64ToInt64"))
      (map (fn [(n String)] -> Bool
             (do (assert (stringContains? code (str "@asl$2Dtarget$2Dllvm$2FsysRoute$2E" n "(")) (str n " calls the sysRoute clock wrapper"))
                 true))
           (list "nowNs" "monotonicNs" "sleepMs"))
      (assert (ok? (fileWrite ll code)) (str "fileWrite " ll))
      (mt (optBin)
        ((none) (do (println "opt not found on this host, skipping -passes=verify") true))
        ((some o) (let [(v (processRun (str o " -passes=verify -disable-output " ll)))]
                    (do (assert (= v.exitCode 0) (str "opt -passes=verify accepts the emitted IR: " v.stderr)) true))))
      true))

fn ! nativeExe dir: String -> String
  (let [(exe (str dir "/mathFixture"))
        (linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " dir "/mathFixture.ll -x none asl/host/out/libaslrt.a -lm -o " exe)))]
    (do (assert (= linked.exitCode 0) (str "mathFixture links against libaslrt.a: " linked.stderr))
        exe))

fn ! testValueParity exe: String src: String op: String -> Bool
  (let [(native (processRun (str exe " " op)))
        (interp (processRun (str (host) " run " src " " op)))]
    (do
      (assert (= interp.exitCode 0) (str op ": ./bin/asl run exit " interp.exitCode "; stderr " interp.stderr))
      (assert (= native.exitCode 0) (str op ": native exit " native.exitCode "; stderr " native.stderr))
      (assert (= native.stdout interp.stdout) (str op ": native prints " native.stdout " and ./bin/asl run " interp.stdout))
      (assert (= native.stderr "") (str op ": native stderr empty, got " native.stderr))
      true))

fn ! testFailingParity exe: String src: String op: String -> Bool
  (let [(native (processRun (str exe " " op)))
        (interp (processRun (str (host) " run " src " " op)))
        (line (stringReplace native.stderr "\n" ""))]
    (do
      (assert (= native.exitCode 1) (str op ": native exit " native.exitCode ", want 1; stderr " native.stderr))
      (assert (= native.exitCode interp.exitCode) (str op ": native exit equals ./bin/asl run exit " interp.exitCode))
      (assert (stringStartsWith? line "ERR_") (str op ": native stderr is one error line: " native.stderr))
      (assert (= native.stderr (str line "\n")) (str op ": native stderr is a single line: " native.stderr))
      (assert (stringContains? interp.stderr line) (str op ": ./bin/asl run reports " line "; it reported " interp.stderr))
      (assert (= native.stdout interp.stdout) (str op ": native stdout equals ./bin/asl run stdout"))
      true))

fn ! testNow exe: String -> Bool
  (let [(native (processRun (str exe " now")))
        (date (processRun "date +%s"))
        (ns (optionOr (stringToInt64 (stringTrim native.stdout)) -1))
        (secs (optionOr (stringToInt64 (stringTrim date.stdout)) -1))
        (gap (- (/ ns 1000000000) secs))]
    (do
      (assert (= native.exitCode 0) (str "now: native exit " native.exitCode "; stderr " native.stderr))
      (assert (> secs 0) (str "date +%s prints the epoch seconds: " date.stdout))
      (assert (and (>= gap -5) (<= gap 5)) (str "native nowNs " ns " is within 5 s of date +%s " secs))
      true))

fn ! runTests -> Bool
  (let [(dir (str "scratch/nativeMathTest." (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))
        (src (str dir "/mathFixture.asl"))]
    (do
      (assert (ok? made) "dirCreate makes a work directory inside the workspace root")
      (testRuntimeDecls)
      (assert (ok? (fileWrite src (fixtureSrc))) (str "fileWrite " src))
      (mt (compiled src)
        ((err e) (do (assert false (str "mathFixture links and emits: " e)) true))
        ((ok code)
          (do
            (testIr dir code)
            (let [(exe (nativeExe dir))]
              (do
                (map (fn [(op String)] -> Bool (testValueParity exe src op)) (valueCases))
                (map (fn [(op String)] -> Bool (testFailingParity exe src op)) (failingCases))
                (map (fn [(n String)] -> Bool (testTypeRejected dir n)) (typeProbeCases))
                (testNow exe))))))
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "work directory removed")
      true))
