(module asl-target-llvm/tests/lowerScaleTest
  :x [runTests]
  :i [(asl-ir/lower :a low)
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
  (match (llvm/emitLlvmSourceWith source prelude "main")
    ((err diagnostics) (fixtureFailure (str "cannot compile runtime fixture: " diagnostics)))
    ((ok llvmText)
      (match (fileWrite (str directory "/sum.ll") llvmText)
        ((err e) (fixtureFailure (str "cannot write generated LLVM: " e)))
        ((ok written)
          (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " directory "/sum.ll -x none asl/host/out/libaslrt.a -lm -o " directory "/sum")))]
            (if (!= linked.exitCode 0)
              (fixtureFailure (str "clang failed: " linked.stderr))
              (let [(ran (processRun (str directory "/sum")))]
                (FixtureRun :failure "" :exitCode ran.exitCode :stdout ran.stdout :removed false))))))))

fn ! runFixture source: String directory: String -> FixtureRun
  (match (fileReadString "asl/prelude/prelude.asl")
    ((err e) (fixtureFailure (str "cannot read prelude: " e)))
    ((ok prelude)
      (match (dirCreate directory)
        ((err e) (fixtureFailure (str "cannot create runtime fixture: " e)))
        ((ok created)
          (let [(outcome (buildAndRun source prelude directory))
                (removed (pathRemove directory))]
            (FixtureRun :failure outcome.failure :exitCode outcome.exitCode :stdout outcome.stdout :removed (ok? removed)))))))

fn ! cpuMicros -> Int64
  (let [(usageResult (procRusage))]
    (match usageResult
      ((err e) (do (assert (ok? usageResult) (str "procRusage failed: " e)) 0))
      ((ok usage) (+ usage.selfUserUs usage.selfSysUs))))

fn ! measure source: String -> PhaseTimes
  (measureBurn source 0)

; (:m :ref TRAIN-RED-SUITES :do "CPU work of burnUs microseconds inside a timed window: the stand-in for a load burst that inflates one sample (cache contention and throttling on node2 under a train), done in chunks so the loop depth stays small")
fn ! burn! untilUs: Int64 acc: Int64 -> Int64
  (if (>= (cpuMicros) untilUs) acc
    (burn! untilUs (+ acc (fold (fn [(s Int64) (i Int64)] -> Int64 (+ s (mod (* i 7) 13))) 0 (range 0 20000)))))

fn ! measureBurn source: String burnUs: Int64 -> PhaseTimes
  (match (ast/parse source)
    ((err parseError) (PhaseTimes :lowerCpuUs -1 :verifyCpuUs -1))
    ((ok forms)
      (let [(positions (low/declPositions source))
            (startLower (cpuMicros))
            (_burnt (if (> burnUs 0) (burn! (+ startLower burnUs) 0) 0))
            (lowered (low/lowerModule forms positions))
            (endLower (cpuMicros))]
        (match lowered
          ((err ds) (do (println "lowerScale lower diagnostic:" ds) (PhaseTimes :lowerCpuUs (- endLower startLower) :verifyCpuUs -1)))
          ((ok m) (let [(startVerify (cpuMicros))
                        (verified (vfy/verifySsa m))
                        (endVerify (cpuMicros))]
                    (do
                      (assert (ok? verified) (str "SSA verification failed during scale measurement: " verified))
                      (PhaseTimes :lowerCpuUs (- endLower startLower) :verifyCpuUs (- endVerify startVerify)))))))))

fn minTimes x: PhaseTimes y: PhaseTimes -> PhaseTimes
  (PhaseTimes :lowerCpuUs (min x.lowerCpuUs y.lowerCpuUs) :verifyCpuUs (min x.verifyCpuUs y.verifyCpuUs))

; (:m :ref TRAIN-RED-SUITES :do "the two sizes of a ratio are sampled k times in turn (small, large, small, large ...) and each phase keeps its least CPU time: one sample inflated by load no longer decides the ratio, and both sizes see the same machine state; the first large sample carries burnUs of extra work in its lowering window when a test injects one. lowerScaleTest red 6 times in node2 trains 2026-11-17..20 on 4000->8000 at most 2.6x, for units that do not touch lowering (STD-INI) and green on their retries")
fn ! pairMin srcA: String srcB: String k: Int64 burnUs: Int64 -> (Pair PhaseTimes PhaseTimes)
  (let [(a (measure srcA))
        (b (measureBurn srcB burnUs))]
    (if (<= k 1) (pair a b)
      (let [(rest (pairMin srcA srcB (- k 1) 0))]
        (pair (minTimes a (pairFirst rest)) (minTimes b (pairSecond rest))))))

fn samples -> Int64
  3

fn ratio b: Int64 a: Int64 -> Int64
  (/ (* 1000 b) (max 1 a))

fn measured source: String -> Bool
  (match (low/lowerSource source)
    ((err ds) false)
    ((ok m) (match (llvm/emitLlvmProgram m "main")
             ((err ds) false)
             ((ok text) true))))

fn ! testLiteralScales -> Bool
  (let [(warm (measure (listSource 1000)))
        (medium (measure (listSource 2000)))
        (lit (pairMin (listSource 4000) (listSource 8000) (samples) 0))
        (a (pairFirst lit))
        (b (pairSecond lit))
        (line (pairMin (straightSource 4000) (straightSource 8000) (samples) 0))
        (straightA (pairFirst line))
        (straight (pairSecond line))
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

; (:m :ref TRAIN-RED-SUITES :do "the reproduction of the node2 red: the first large sample carries a burst of six times the small size's lowering CPU; that one sample alone puts the ratio past 2.6x, which is what one sample per size did under load, and the least of the samples keeps it under")
fn ! testOneNoisySample -> Bool
  (let [(clean (measure (listSource 4000)))
        (burnUs (* 6 (max 1000 clean.lowerCpuUs)))
        (single (pairMin (listSource 4000) (listSource 8000) 1 burnUs))
        (singleA (pairFirst single))
        (singleB (pairSecond single))
        (robust (pairMin (listSource 4000) (listSource 8000) (samples) burnUs))
        (robustA (pairFirst robust))
        (robustB (pairSecond robust))
        (singleRatio (ratio singleB.lowerCpuUs singleA.lowerCpuUs))
        (robustRatio (ratio robustB.lowerCpuUs robustA.lowerCpuUs))]
    (do
      (println "lowerScale noisy sample: burn us" burnUs "single ratio" singleRatio "robust ratio" robustRatio)
      (assert (> singleRatio 2600) (str "one burst-inflated large sample alone is past 2.6x, the single-sample red: " (stringFromInt64 singleRatio)))
      (assert (<= robustRatio 2600) (str "the least of the samples keeps the 4000->8000 lowering ratio at most 2.6x: " (stringFromInt64 robustRatio)))
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
    (assert (testOneNoisySample) "one load-inflated sample does not decide the scaling ratio")
    (assert (testSumRuns) "6000-element all-ones list compiles, runs, and prints its sum")
    true)
