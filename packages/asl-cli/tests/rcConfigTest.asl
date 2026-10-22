(module asl-cli/tests/rcConfigTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys)
      (asl/packages/asl-cli/src/rcConfig :a rcc)
      (asl-tools/fleet/run :a run)])

fn fixtureSource -> String
  (stringJoin (list
    "(module rcConfigFixture :x [main] :i [])"
    ""
    "(schema Point (:f x Int64) (:f y Int64))"
    ""
    "fn step p: Point i: Int64 -> Point"
    "  (Point :x (+ p.x i) :y (- p.y i))"
    ""
    "fn loop p: Point i: Int64 n: Int64 -> Point"
    "  (if (>= i n) p (loop (step p i) (+ i 1) n))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(p (loop (Point :x 0 :y 0) 0 1000))]"
    "    (do (println (str p.x \" \" p.y))"
    "        (ok 0)))"
    "") "\n")

(schema Ran (:f build run/Done) (:f run run/Done) (:f err String))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! runIn argv: (List String) cwd: String env: (List String) secs: Int64 -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv env)) (run/limits secs 24))

; (:m :ref RC-CONFIG :do "one fixture dir per mode, its .asl.config.asn the only input that differs; ASL_RC_STATS=1 is the runtime's stats switch, set for every run so only the build decides whether the RC runtime is present")
fn ! buildMode! root: String work: String name: String config: String -> Ran
  (let [(dir (str work "/" name))
        (_ (dirCreate dir))
        (_ (if (stringEmpty? config) (ok ()) (fileWrite (str dir "/.asl.config.asn") config)))
        (src (str dir "/rcConfigFixture.asl"))
        (_ (fileWrite src (fixtureSource)))
        (exe (str dir "/fixture"))
        (built (runIn (list (str root "/bin/asl") "build" src "-o" exe) root (list) 600))
        (errFile (str dir "/stderr"))
        (ran (if (= built.exit 0) (runIn (list "/bin/sh" "-c" (str (shellQuote exe) " 2> " (shellQuote errFile))) dir (list "ASL_RC_STATS=1") 60) built))]
    (Ran :build built :run ran :err (resultOr (fileReadString errFile) "")))

fn ! nmOf path: String -> String
  (if (sys/isFile? path) (runIn (list "/usr/bin/nm" path) (sys/parentOf path) (list) 60).out "")

fn ! testModeOf -> Bool
  (do (assert (= (rcc/rcModeOf "(:aslConfig :workspace \"w\")" "notrace") (ok "notrace")) "a config without :native selects the caller's fallback")
      (assert (= (rcc/rcModeOf "(:aslConfig :workspace \"w\")" "0") (ok "0")) "the fallback is the caller's, not fixed")
      (assert (= (rcc/rcModeOf "(:aslConfig :native (:opt 2))" "notrace") (ok "notrace")) "a :native block without :rc selects the fallback")
      (assert (= (rcc/rcModeOf "(:aslConfig :native (:rc :counted))" "notrace") (ok "1")) ":rc :counted selects mode 1")
      (assert (= (rcc/rcModeOf "(:aslConfig :native (:rc :notrace))" "notrace") (ok "notrace")) ":rc :notrace selects the untraced mode")
      (assert (= (rcc/rcModeOf "(:aslConfig :native (:rc :asan))" "notrace") (ok "asan")) ":rc :asan selects the sanitized mode")
      (assert (= (rcc/rcModeOf "(:aslConfig :native (:rc :tracing))" "notrace") (ok "0")) ":rc :tracing selects mode 0")
      (match (rcc/rcModeOf "(:aslConfig :native (:rc :fast))" "notrace")
        ((ok m) (do (assert false (str "an unknown :rc value is rejected, got " m)) false))
        ((err e) (do (assert (stringStartsWith? e "ERR_CONFIG: ") (str "an unknown :rc value is an ERR_CONFIG: " e))
                     (assert (stringContains? e ":fast") (str "the rejection names the value: " e))
                     true))))

fn ! testBuild root: String work: String -> Bool
  (let [(plain (buildMode! root work "plain" ""))
        (tracing (buildMode! root work "tracing" "(:aslConfig :native (:rc :tracing))"))
        (counted (buildMode! root work "counted" "(:aslConfig :native (:rc :counted))"))
        (notrace (buildMode! root work "notrace" "(:aslConfig :native (:rc :notrace))"))
        (bad (buildMode! root work "bad" "(:aslConfig :native (:rc :fast))"))
        (want "499500 -499500\n")
        (plainNm (nmOf (str work "/plain/fixture")))
        (tracingNm (nmOf (str work "/tracing/fixture")))
        (countedNm (nmOf (str work "/counted/fixture")))
        (notraceNm (nmOf (str work "/notrace/fixture")))]
    (do (assert (= plain.build.exit 0) (str "the build without :native :rc succeeds: " plain.build.out))
        (assert (= tracing.build.exit 0) (str "the build under :rc :tracing succeeds: " tracing.build.out))
        (assert (= counted.build.exit 0) (str "the build under :rc :counted succeeds: " counted.build.out))
        (assert (= notrace.build.exit 0) (str "the build under :rc :notrace succeeds: " notrace.build.out))
        (assert (= tracing.run.out want) (str "the tracing build prints " want ", got " tracing.run.out))
        (assert (= plain.run.out want) (str "the default build prints the same output: " plain.run.out))
        (assert (= counted.run.out (str want)) (str "the counted build prints the same output: " counted.run.out))
        (assert (= notrace.run.out (str want)) (str "the untraced build prints the same output: " notrace.run.out))
        (refute (stringContains? tracing.err ":rcStats") (str ":rc :tracing builds carry no RC runtime: " tracing.err))
        (assert (stringContains? plain.err ":rcStats") (str "without :native :rc, asl build emits RC code by default: " plain.err))
        (assert (stringContains? counted.err ":rcStats") (str ":rc :counted in .asl.config.asn makes asl build emit RC code: " counted.err))
        (assert (stringContains? notrace.err ":rcStats") (str ":rc :notrace in .asl.config.asn makes asl build emit RC code: " notrace.err))
        (assert (stringContains? tracingNm "markPhase") "the :rc :tracing build links the tracing collector")
        (refute (stringContains? plainNm "markPhase") "the default build links the untraced runtime (RC-DEFAULT notrace)")
        (assert (stringContains? countedNm "markPhase") "the counted build links the tracing collector")
        (refute (stringContains? notraceNm "markPhase") "the :rc :notrace build links the untraced runtime")
        (assert (!= bad.build.exit 0) "an unknown :rc value fails the build")
        (assert (stringContains? bad.build.out "ERR_CONFIG") (str "the failed build reports ERR_CONFIG: " bad.build.out))
        true))

fn ! removeAll! path: String -> (Result Unit String)
  (if (sys/isFile? path) (pathRemove path)
    (do (map (fn [(n String)] -> (Result Unit String) (removeAll! (str path "/" n))) (resultOr (dirList path) (list)))
        (pathRemove path)))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/rcConfigTest." (stringFromInt64 (procSelf))))
        (made (dirCreate work))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (testModeOf)
        (testBuild root work)
        (assert (ok? (removeAll! work)) (str "the work directory " work " is removed"))
        true))
