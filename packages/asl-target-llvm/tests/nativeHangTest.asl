(module asl-target-llvm/tests/nativeHangTest
  :x [runTests]
  :i [(asl-ir/types :a ir)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-parser/ast :a ast)
      (asl-target-llvm :a llvm)])

(schema FlatCost
  (:f lowerUs Int64)
  (:f emitUs Int64)
  (:f functions Int64)
  (:f widest Int64))

(schema NativeRun
  (:f failure String)
  (:f exitCode Int64)
  (:f stdout String)
  (:f stderr String))

fn ! cpuMicros -> Int64
  (let [(usage (procRusage))]
    (mt usage
      ((err e) (do (assert (ok? usage) (str "procRusage failed: " e)) 0))
      ((ok u) (+ u.selfUserUs u.selfSysUs))))

fn floatOf i: Int64 -> Float
  (+ (* (int64ToFloat64 i) 1.25) 0.5)

fn assertLine i: Int64 bad: Int64 -> String
  (let [(x (floatOf i))
        (text (stringFromFloat64 x))]
    (str "(assert (chk " text " \"" (if (= i bad) "x" "") text "\") \"v" (stringFromInt64 i) "\")"))

fn flatSource n: Int64 bad: Int64 -> String
  (str "(module flatHang :x [main])\n"
       "(fn chk [(x Float) (s String)] -> Bool (and (= (stringFromFloat64 x) s) (= (stringToFloat64 s) (some x))))\n"
       "(fn main [] -> Int64 (do\n"
       (stringJoin (map (fn [(i Int64)] -> String (assertLine i bad)) (range 0 n)) "\n")
       "\n(println \"flat ok\") 0))\n")

fn instrCount f: ir/SsaFunction -> Int64
  (fold (fn [(acc Int64) (b ir/SsaBlock)] -> Int64 (+ acc (listLength b.instrs))) 0 f.blocks)

fn ! flatCost n: Int64 -> FlatCost
  (let [(source (flatSource n -1))
        (c0 (cpuMicros))
        (lowered (low/lowerSource source))
        (c1 (cpuMicros))]
    (mt lowered
      ((err ds) (do (assert false (str "flat body of " n " asserts lowers: " (stringJoin (map (fn [(d ir/IrDiag)] -> String (str d.code " " d.message)) ds) "; "))) (FlatCost :lowerUs 0 :emitUs 0 :functions 0 :widest 0)))
      ((ok m)
        (let [(c2 (cpuMicros))
              (emitted (llvm/emitLlvmModule m))
              (c3 (cpuMicros))]
          (do (assert (ok? emitted) (str "flat body of " n " asserts emits LLVM IR"))
              (FlatCost :lowerUs (- c1 c0) :emitUs (- c3 c2)
                        :functions (listLength m.functions)
                        :widest (fold (fn [(acc Int64) (f ir/SsaFunction)] -> Int64 (max acc (instrCount f))) 0 m.functions)))))))

fn ! testFlatScaling -> Bool
  (let [(warm (flatCost 200))
        (small (flatCost 500))
        (large (flatCost 2000))
        (lowerRatio (/ (* 1000 large.lowerUs) (max 1 small.lowerUs)))
        (emitRatio (/ (* 1000 large.emitUs) (max 1 small.emitUs)))]
    (do
      (println "nativeHang flat CPU us 200/500/2000 lower/emit:" warm.lowerUs warm.emitUs small.lowerUs small.emitUs large.lowerUs large.emitUs "ratios per mille:" lowerRatio emitRatio "functions:" large.functions "widest:" large.widest)
      (assert (<= lowerRatio 6000) "lowering a flat body 4x as long costs at most 6x the CPU time")
      (assert (<= emitRatio 6000) "emitting a flat body 4x as long costs at most 6x the CPU time")
      (assert (> large.functions small.functions) "the longer flat body lowers to more continuation functions")
      (assert (<= large.widest 2048) "no lowered function of the 2000-assert body exceeds 2048 instructions")
      true))

fn ! fixtureDirectory -> String
  (str "/tmp/nativeHang_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs)))

fn runFailure failure: String -> NativeRun
  (NativeRun :failure failure :exitCode -1 :stdout "" :stderr "")

fn ! buildAndRun source: String prelude: String directory: String -> NativeRun
  (mt (llvm/emitLlvmSourceWith source prelude "main")
    ((err ds) (runFailure (str "cannot compile: " ds)))
    ((ok text)
      (mt (fileWrite (str directory "/flat.ll") text)
        ((err e) (runFailure (str "cannot write LLVM IR: " e)))
        ((ok _)
          (let [(linked (processRun (str "/usr/bin/clang -O2 -Wno-override-module -x ir " directory "/flat.ll -x none asl/host/out/libaslrt.a -lm -o " directory "/flat")))]
            (if (!= linked.exitCode 0)
              (runFailure (str "clang failed: " linked.stderr))
              (let [(ran (processRun (str directory "/flat")))]
                (NativeRun :failure "" :exitCode ran.exitCode :stdout ran.stdout :stderr ran.stderr))))))))

fn ! runFlat n: Int64 bad: Int64 -> NativeRun
  (mt (fileReadString "asl/prelude/prelude.asl")
    ((err e) (runFailure (str "cannot read prelude: " e)))
    ((ok prelude)
      (let [(directory (fixtureDirectory))]
        (mt (dirCreate directory)
          ((err e) (runFailure (str "cannot create " directory ": " e)))
          ((ok _)
            (let [(outcome (buildAndRun (flatSource n bad) prelude directory))
                  (removed (pathRemove directory))]
              (do (assert (ok? removed) (str "fixture directory " directory " is removed"))
                  outcome)))))))

fn ! testFlatRuns -> Bool
  (let [(passing (runFlat 1200 -1))
        (failing (runFlat 1200 1100))]
    (do
      (assert (= passing.failure "") (str "1200-assert flat body builds natively: " passing.failure))
      (assert (= passing.exitCode 0) (str "1200-assert flat body exits 0 natively, got " passing.exitCode ": " passing.stderr))
      (assert (= (stringTrim passing.stdout) "flat ok") (str "1200-assert flat body prints flat ok, got " passing.stdout))
      (assert (= failing.failure "") (str "flat body with a failing assert builds natively: " failing.failure))
      (assert (!= failing.exitCode 0) "the failing assert in the last continuation exits nonzero")
      (assert (stringContains? failing.stderr "assertion failed: v1100") (str "the native failure names assertion v1100: " failing.stderr))
      (assert (= failing.stdout "") "nothing after the failing assert runs")
      true))

fn deepSource k: Int64 -> String
  (str "(module deepHang\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  (do\n    (assert (= "
       (stringJoin (map (fn [(i Int64)] -> String "(do ") (range 0 k)) "")
       "1"
       (stringJoin (map (fn [(i Int64)] -> String ")") (range 0 k)) "")
       " 1) \"deep\")\n    true)\n")

fn parseVerdict r: (Result (List ast/TopForm) ast/ParseError) -> String
  (mt r
    ((ok forms) "ok")
    ((err e) (str e.msg " at " e.line ":" e.col)))

fn ! testDepthGuard -> Bool
  (let [(c0 (cpuMicros))
        (deep (parseVerdict (ast/parse (deepSource 2000))))
        (c1 (cpuMicros))
        (lowered (low/lowerSource (deepSource 2000)))
        (c2 (cpuMicros))
        (limit (parseVerdict (ast/parse (deepSource 996))))
        (over (parseVerdict (ast/parse (deepSource 997))))]
    (do
      (println "nativeHang depth CPU us parse/lower 2000-deep:" (- c1 c0) (- c2 c1))
      (assert (= deep "ERR_DEPTH expression nested deeper than 1000 at 7:4004") (str "a 2000-deep nest fails to parse with ERR_DEPTH where asl-host reports it, got " deep))
      (assert (< (- c1 c0) 3000000) "the 2000-deep nest is rejected within 3 s of CPU time")
      (assert (mt lowered ((err ds) (= (optionOr (listHead (map (fn [(d ir/IrDiag)] -> String d.code) ds)) "") "ERR_DEPTH")) ((ok _) false)) "lowerSource reports the 2000-deep nest as ERR_DEPTH")
      (assert (= limit "ok") (str "an expression at depth 1000 parses, as asl-host accepts it, got " limit))
      (assert (= over "ERR_DEPTH expression nested deeper than 1000 at 7:4004") (str "one level deeper fails as asl-host does, got " over))
      true))

fn ! loadVerdict path: String -> String
  (mt (lk/loadClosure! path)
    ((ok units) "ok")
    ((err ds) (stringJoin (map (fn [(d ir/IrDiag)] -> String (str d.code " " d.message " " d.locus)) ds) "; ")))

fn ! testDeepFiles -> Bool
  (let [(c0 (cpuMicros))
        (deepDo (loadVerdict "tests/acceptance/r1Host/generated/invalid/depth/deepDoTest.asl"))
        (deepNot (loadVerdict "tests/acceptance/r1Host/generated/invalid/depth/deepNotTest.asl"))
        (c1 (cpuMicros))]
    (do
      (println "nativeHang depth CPU us load deepDo+deepNot:" (- c1 c0))
      (assert (= deepDo "ERR_DEPTH expression nested deeper than 1000 tests/acceptance/r1Host/generated/invalid/depth/deepDoTest.asl:7:4004") (str "deepDoTest loads as ERR_DEPTH at asl-host's position, got " deepDo))
      (assert (= deepNot "ERR_DEPTH expression nested deeper than 1000 tests/acceptance/r1Host/generated/invalid/depth/deepNotTest.asl:7:5001") (str "deepNotTest loads as ERR_DEPTH at asl-host's position, got " deepNot))
      (assert (< (- c1 c0) 3000000) "both 1e5-deep files are rejected within 3 s of CPU time")
      true))

fn ! runTests -> Bool
  (and (testDepthGuard) (testDeepFiles) (testFlatScaling) (testFlatRuns))
