(module asl/tools/tests/nativeWorkersDefaultTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt)
      (asl/packages/asl-cli/src/nativeBuild :a nb)])

; (:m :ref NATIVE-WORKERS-DEFAULT :do "compile workers for one suite built alone come from the :native :suiteWorkers row, capped at (cpus-2)/2; a sweep (prepareAllIn) builds with none; objects are byte-identical either way")

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! rowFor! dir: String row: String -> Int64
  (do (fileWrite (str dir "/.asl.config.asn") (str "(:config :native (" row "))\n"))
      (nb/suiteWorkersFor! dir))

fn driverSource -> String
  (str "(module nwdDriver\n  :x [main]\n  :i [(asl-tools/nativeTest :a nt)])\n\n"
       "fn ! main args: (List String) -> (Result Int64 String)\n"
       "  (let [(how (optionOr (listGet args 0) \"\"))\n"
       "        (cDir (optionOr (listGet args 1) \"\"))\n"
       "        (suite (optionOr (listGet args 2) \"\"))\n"
       "        (fp (nt/fingerprint))\n"
       "        (bs (if (= how \"all\") (nt/prepareAllIn cDir (list suite) fp 1) (list (nt/prepareIn cDir suite fp \"test\"))))]\n"
       "    (ok (if (listAll? (fn [(b nt/Built)] -> Bool (some? b.binary)) bs) 0 1)))\n")

fn chainStep idx: Int64 -> String
  (str "(v" (stringFromInt64 idx) " (mod (+ (* v" (stringFromInt64 (- idx 1)) " 7) " (stringFromInt64 idx) ") 1000003))")

fn chainFn name: String salt: Int64 steps: Int64 -> String
  (str "fn " name " x: Int64 -> Int64\n  (let [(v0 (+ x " (stringFromInt64 salt) "))\n        "
       (stringJoin (map chainStep (range 1 (+ steps 1))) "\n        ") "]\n    v" (stringFromInt64 steps) ")\n")

; (:m :ref NATIVE-WORKERS-DEFAULT :do "steps 0 gives a one-line module; steps 100 gives about 27 KB, so six of them pass the per-worker minimum twice")
fn depSource importPath: String i: Int64 steps: Int64 -> String
  (str "(module " importPath "\n  :x [f" (stringFromInt64 i) "]\n  :i [])\n\n"
       (if (> steps 0) (stringJoin (map (fn [(j Int64)] -> String (chainFn (str "part" (stringFromInt64 j)) (+ (* i 10) j) steps)) (range 0 6)) "\n") "")
       "\nfn f" (stringFromInt64 i) " x: Int64 -> Int64\n  (+ (* x " (stringFromInt64 (+ i 3)) ") "
       (if (> steps 0) (stringJoin (map (fn [(j Int64)] -> String (str "(part" (stringFromInt64 j) " x)")) (range 0 6)) " ") (stringFromInt64 i)) ")\n")

fn ! writeFixture! dir: String n: Int64 steps: Int64 -> String
  (let [(deps (map (fn [(i Int64)] -> String
                     (let [(rel (str dir "/dep" (stringFromInt64 i) ".asl"))
                           (_ (fileWrite rel (depSource (nt/importPathOf rel) i steps)))]
                       (nt/importPathOf rel)))
                   (range 0 n)))
        (suite (str dir "/fixtureSuite.asl"))
        (imports (stringJoin (map (fn [(i Int64)] -> String (str "(" (optionOr (listGet deps i) "") " :a d" (stringFromInt64 i) ")")) (range 0 n)) " "))
        (calls (stringJoin (map (fn [(i Int64)] -> String (str "(d" (stringFromInt64 i) "/f" (stringFromInt64 i) " 1)")) (range 0 n)) " "))
        (_ (fileWrite suite (str "(module " (nt/importPathOf suite) "\n  :x [runTests]\n  :i [" imports "])\n\nfn ! runTests -> Bool\n  (do (assert (> (+ " calls ") 0) \"sum\") true)\n")))]
    suite)

fn ! drive env: String driver: String how: String cache: String suite: String -> ProcessOutput
  (sh (str "env -u ASL_NATIVE_WORKERS " env " ASL_NATIVE_TRACE=1 ASL_NATIVE_JOBS=4 nice -n 10 bin/asl run " driver " " how " '" cache "' " suite " </dev/null"))

fn ! seedPrelude! from: String to: String -> Bool
  (= (sh (str "mkdir -p '" to "/modules' && cp -p '" from "'/modules/prelude-* '" to "/modules/'")).exitCode 0)

fn ! bytesOf! dir: String -> Int64
  (fold (fn [(a Int64) (n String)] -> Int64 (+ a (match (fileStat (str dir "/" n)) ((ok st) st.size) ((err _) 0)))) 0
        (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) (resultOr (dirList dir) (list))))

fn ! moduleObjects cache: String -> (List String)
  (listSort (filter (fn [(n String)] -> Bool (and (stringEndsWith? n ".o") (not (stringStartsWith? n "prelude-")))) (resultOr (dirList (str cache "/modules")) (list))))

fn ! sameBytes? a: String b: String names: (List String) -> Bool
  (listAll? (fn [(n String)] -> Bool (= (nt/fileDigest (str a "/modules/" n)) (nt/fileDigest (str b "/modules/" n)))) names)

fn ! testResolution dir: String -> Bool
  (let [(cfg (str dir "/cfg"))
        (_ (dirCreate cfg))
        (three (rowFor! cfg ":suiteWorkers 3"))
        (zero (rowFor! cfg ":suiteWorkers 0"))
        (junk (rowFor! cfg ":suiteWorkers \"many\""))]
    (do (assert (= three 3) (str "the :suiteWorkers row is the configured count: " three))
        (assert (= zero (nb/defaultSuiteWorkers)) "a row below 1 falls back to the default")
        (assert (= junk (nb/defaultSuiteWorkers)) "a row that is not a number falls back to the default")
        (assert (= (nt/soloWorkersOf (none) 3 10) 3) "10 cpus allow (10-2)/2 = 4, so 3 configured stays 3")
        (assert (= (nt/soloWorkersOf (none) 8 10) 4) "8 configured on 10 cpus is capped at (10-2)/2 = 4")
        (assert (= (nt/soloWorkersOf (none) 4 3) 1) "a 3-cpu machine gets one process, no workers")
        (assert (= (nt/soloWorkersOf (some 6) 2 4) 4) "an explicit ASL_NATIVE_WORKERS names the count, capped at the cpus")
        (assert (= (nt/workerCount! 1 4) 1) "a sweep's cap of 1 gives one process whatever the config says")
        (assert (= (nt/workerCount! 3 2) 2) "the count never exceeds the clang job slots")
        (assert (= (nt/soloSpread 4 (* 3 (nt/minWorkerBytes))) 3) "three workers' worth of uncached source gets three processes")
        (assert (= (nt/soloSpread 4 30000) 1) "a few KB of uncached source is built in one process: a worker would cost more than it saves")
        (assert (= (nt/soloSpread 2 (* 9 (nt/minWorkerBytes))) 2) "plenty of source never lifts the count above the cap")
        true))

fn ! testSweepAndSolo dir: String -> Bool
  (let [(pkg (str dir "/pkg"))
        (_ (dirCreate pkg))
        (suite (writeFixture! pkg 6 100))
        (small (str dir "/small"))
        (_ (dirCreate small))
        (smallSuite (writeFixture! small 3 0))
        (driver (str dir "/nwdDriver.asl"))
        (_ (fileWrite driver (driverSource)))
        (warm (str dir "/warm"))
        (solo (str dir "/solo"))
        (sweep (str dir "/sweep"))
        (warmOut (drive "ASL_NATIVE_WORKERS=4" driver "one" warm suite))
        (seeded (and (seedPrelude! warm solo) (seedPrelude! warm sweep)))
        (soloOut (drive "" driver "one" solo suite))
        (sweepOut (drive "" driver "all" sweep suite))
        (tinyCache (str dir "/tiny"))
        (seededTiny (seedPrelude! warm tinyCache))
        (tinyOut (drive "" driver "one" tinyCache smallSuite))
        (cpus (resultOr (cpuCount) 1))
        (jobs (min 4 cpus))
        (expected (min (nt/soloSpread (min (nt/soloWorkersOf (none) (nb/suiteWorkersFor! ".") cpus) jobs) (bytesOf! pkg)) 7))
        (objsSolo (moduleObjects solo))
        (objsSweep (moduleObjects sweep))]
    (do (assert (= warmOut.exitCode 0) (str "an explicit 4-worker build compiles the fixture and leaves the self binary built: " warmOut.stderr))
        (assert seeded "the solo and sweep caches start from the warm prelude objects")
        (assert (= soloOut.exitCode 0) (str "the suite built alone passes: " soloOut.stderr))
        (assert (= sweepOut.exitCode 0) (str "the suite built through prepareAllIn passes: " sweepOut.stderr))
        (if (>= expected 2)
          (assert (stringContains? soloOut.stderr (str "NATIVE-WORKERS :k " expected " :units 7")) (str "a suite built alone, with no env, spreads its 7 uncached modules (" (bytesOf! pkg) " bytes) over " expected " processes from the config default: " soloOut.stderr))
          (refute (stringContains? soloOut.stderr "NATIVE-WORKERS :k") "a machine whose cap is 1 builds alone without workers"))
        (assert (and seededTiny (= tinyOut.exitCode 0)) (str "the 3-module tiny suite builds alone: " tinyOut.stderr))
        (refute (stringContains? tinyOut.stderr "NATIVE-WORKERS :k") (str "a tiny suite built alone spawns no workers, so it is not slower than before: " tinyOut.stderr))
        (refute (stringContains? sweepOut.stderr "NATIVE-WORKERS :k") (str "prepareAllIn, the sweep's builder, spawns no compile workers: " sweepOut.stderr))
        (assert (= (listLength objsSolo) 8) (str "the solo cache holds 8 module objects (6 deps, the suite, the entry wrapper): " (listLength objsSolo)))
        (assert (= objsSolo objsSweep) "with and without workers the module objects carry the same keys")
        (assert (sameBytes? solo sweep objsSolo) "every module object built by workers is byte-identical to the one built without")
        true))

fn ! runTests -> Bool
  (let [(dir (str ".asl/cache/nativeWorkersDefaultTest-" (monotonicNs)))
        (made (dirCreate dir))
        (result (and (ok? made) (and (testResolution dir) (testSweepAndSolo dir))))
        (removed (pathRemove dir))]
    (do (assert (ok? made) "the scratch directory is created")
        (assert (ok? removed) "the scratch directory is removed")
        result))
