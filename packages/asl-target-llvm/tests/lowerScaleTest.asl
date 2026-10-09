(module asl-target-llvm/tests/lowerScaleTest
  :x [runTests]
  :i [(asl-ir/types :a ir)
      (asl-ir/lower :a low)
      (asl-parser/ast :a ast)
      (asl-ir/verify :a vfy)
      (asl-target-llvm :a llvm)])

(schema PhaseTimes
  (:f lowerCpuUs Int64)
  (:f verifyCpuUs Int64))

(schema FixtureRun
  (:f failure String)
  (:f exitCode Int64)
  (:f stdout String)
  (:f removed Bool))

fn listSource n: Int64 -> String
  (let [(items (stringJoin (map (fn [(i Int64)] -> String "1") (range 0 n)) " "))]
    (str "(module scale :x [main])\n(fn main [] -> Int64 (do (list " items ") 0))"))

fn straightSource n: Int64 -> String
  (let [(items (stringJoin (map (fn [(i Int64)] -> String "1") (range 0 n)) " "))]
    (str "(module straight :x [main])\n(fn main [] -> Int64 (do " items "))"))

fn sumRunSource n: Int64 -> String
  (let [(items (stringJoin (map (fn [(i Int64)] -> String "1") (range 0 n)) " "))]
    (str "(module lowerScaleRun :x [main])\n"
         "(fn main [] -> Int64\n"
         "  (let [(total (fold (fn [(acc Int64) (item Int64)] -> Int64 (+ acc item)) 0 (list " items ")))]\n"
         "    (do (println (stringFromInt64 total)) total)))"))

fn brokenRunSource -> String
  "(module lowerScaleBroken :x [main])\n(fn main [] -> Int64 (lowerScaleUnboundSymbol 1))"

fn ! fixtureDirectory -> String
  (str "/tmp/lowerScale_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs)))

fn fixtureFailure failure: String -> FixtureRun
  (FixtureRun :failure failure :exitCode -1 :stdout "" :removed false)

fn ! buildAndRun source: String prelude: String directory: String -> FixtureRun
  (mt (llvm/emitLlvmSourceWith source prelude "main")
    ((err diagnostics) (fixtureFailure (str "cannot compile runtime fixture: " diagnostics)))
    ((ok llvmText)
      (mt (fileWrite (str directory "/sum.ll") llvmText)
        ((err e) (fixtureFailure (str "cannot write generated LLVM: " e)))
        ((ok written)
          (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " directory "/sum.ll -x none asl/host/out/libaslrt.a -lm -o " directory "/sum")))]
            (if (!= linked.exitCode 0)
              (fixtureFailure (str "clang failed: " linked.stderr))
              (let [(ran (processRun (str directory "/sum")))]
                (FixtureRun :failure "" :exitCode ran.exitCode :stdout ran.stdout :removed false))))))))

fn ! runFixture source: String directory: String -> FixtureRun
  (mt (fileReadString "asl/prelude/prelude.asl")
    ((err e) (fixtureFailure (str "cannot read prelude: " e)))
    ((ok prelude)
      (mt (dirCreate directory)
        ((err e) (fixtureFailure (str "cannot create runtime fixture: " e)))
        ((ok created)
          (let [(outcome (buildAndRun source prelude directory))
                (removed (pathRemove directory))]
            (FixtureRun :failure outcome.failure :exitCode outcome.exitCode :stdout outcome.stdout :removed (ok? removed)))))))

fn ! cpuMicros -> Int64
  (let [(usageResult (procRusage))]
    (mt usageResult
      ((err e) (do (assert (ok? usageResult) (str "procRusage failed: " e)) 0))
      ((ok usage) (+ usage.selfUserUs usage.selfSysUs))))

fn ! measure source: String -> PhaseTimes
  (mt (ast/parse source)
    ((err parseError) (PhaseTimes :lowerCpuUs -1 :verifyCpuUs -1))
    ((ok forms)
      (let [(positions (low/declPositions source))
            (startLower (cpuMicros))
            (lowered (low/lowerModule forms positions))
            (endLower (cpuMicros))]
        (mt lowered
          ((err ds) (do (println "lowerScale lower diagnostic:" ds) (PhaseTimes :lowerCpuUs (- endLower startLower) :verifyCpuUs -1)))
          ((ok m) (let [(startVerify (cpuMicros))
                        (verified (vfy/verifySsa m))
                        (endVerify (cpuMicros))]
                    (do
                      (assert (ok? verified) (str "SSA verification failed during scale measurement: " verified))
                      (PhaseTimes :lowerCpuUs (- endLower startLower) :verifyCpuUs (- endVerify startVerify)))))))))

fn measured source: String -> Bool
  (mt (low/lowerSource source)
    ((err ds) false)
    ((ok m) (mt (llvm/emitLlvmProgram m "main")
             ((err ds) false)
             ((ok text) true))))

fn ! testLiteralScales -> Bool
  (let [(warm (measure (listSource 1000)))
        (medium (measure (listSource 2000)))
        (a (measure (listSource 4000)))
        (b (measure (listSource 8000)))
        (straightA (measure (straightSource 4000)))
        (straight (measure (straightSource 8000)))
        (lowRatio (/ (* 1000 b.lowerCpuUs) (max 1 a.lowerCpuUs)))
        (verifyRatio (/ (* 1000 b.verifyCpuUs) (max 1 a.verifyCpuUs)))]
    (do
      (println "lowerScale literal phases CPU us, 1000/2000/4000/8000 lower/verify:" warm.lowerCpuUs warm.verifyCpuUs medium.lowerCpuUs medium.verifyCpuUs a.lowerCpuUs a.verifyCpuUs b.lowerCpuUs b.verifyCpuUs "straight 4000/8000 lower/verify:" straightA.lowerCpuUs straightA.verifyCpuUs straight.lowerCpuUs straight.verifyCpuUs)
      (assert (measured (straightSource 8000)) "8000-expression straight-line source lowers and emits")
      (assert (and (> a.lowerCpuUs 0) (> b.lowerCpuUs 0)) "literal lowering measurements succeeded")
      (assert (and (> a.verifyCpuUs 0) (> b.verifyCpuUs 0)) "literal SSA verification measurements succeeded")
      (assert (<= lowRatio 2600) "lowering 4000->8000 list literal is at most 2.6x")
      (assert (<= verifyRatio 2600) "SSA verification 4000->8000 list literal is at most 2.6x")
      (assert (and (> straightA.lowerCpuUs 0) (> straight.lowerCpuUs 0)) "straight-line lowering measurements succeeded")
      (assert (<= (/ (* 1000 straight.lowerCpuUs) (max 1 straightA.lowerCpuUs)) 2600) "lowering 4000->8000 straight-line body is at most 2.6x")
      true))

fn ! testSumRuns -> Bool
  (let [(directory (fixtureDirectory))
        (outcome (runFixture (sumRunSource 6000) directory))]
    (do
      (assert (= outcome.failure "") (str "6000-element runtime fixture failed: " outcome.failure))
      (assert (= outcome.exitCode (mod 6000 256)) (str "runtime exit was " outcome.exitCode))
      (assert (= outcome.stdout "6000\n") (str "runtime sum output was " outcome.stdout))
      (assert outcome.removed "runtime fixture directory removal succeeded")
      (assert (not (fileExists? directory)) (str "runtime fixture directory remains: " directory))
      true))

fn ! testFailedFixtureRemoved -> Bool
  (let [(directory (fixtureDirectory))
        (outcome (runFixture (brokenRunSource) directory))]
    (do
      (assert (!= outcome.failure "") "an unbound symbol fails the runtime fixture compile")
      (assert (= outcome.exitCode -1) "a fixture that failed to compile does not run")
      (assert outcome.removed "failed runtime fixture directory removal succeeded")
      (assert (not (fileExists? directory)) (str "failed runtime fixture directory remains: " directory))
      true))

fn ! runTests -> Bool
  (do
    (assert (testFailedFixtureRemoved) "runtime fixture is removed after a failed compile")
    (assert (testLiteralScales) "list literal and straight-line lowering/verification scaling")
    (assert (testSumRuns) "6000-element all-ones list compiles, runs, and prints its sum")
    true)
