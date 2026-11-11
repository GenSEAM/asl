(module asl/tools/tests/nativeWorkerPhasesQuietTest
  :x [runTests]
  :i [(asl-tools/nativeTest :a nt)
      (asl-tools/fleet/run :a fr)])

; (:m :ref WORKER-PHASES-QUIET :do "a compile worker prints its NATIVE-WORKER-PHASES line only under ASL_NATIVE_TRACE=1: an explicit 4-worker build with no trace and no quiet parent prints none, the same build with the trace prints one per worker; every child starts through fr/runGuarded with a deadline and a descendant limit (spawnSafety)")
fn ! guarded argv: (List String) overrides: (List String) -> fr/ProcOut
  (fr/runGuarded argv "." (fr/childEnv overrides) (fr/limits 900 64))

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

fn ! driveWith! env: (List String) driver: String cache: String suite: String -> fr/ProcOut
  (guarded (list "/usr/bin/nice" "-n" "10" "bin/asl" "run" driver "one" cache suite) (listAppend env (list "ASL_NATIVE_WORKERS=4" "ASL_NATIVE_JOBS=4" "ASL_NATIVE_QUIET_PID=")))

fn ! seedPrelude! from: String to: String -> Bool
  (let [(names (filter (fn [(n String)] -> Bool (stringStartsWith? n "prelude-")) (resultOr (dirList (str from "/modules")) (list))))
        (made (dirCreate (str to "/modules")))]
    (and (ok? made)
         (and (not (listEmpty? names))
              (= (guarded (listAppend (list "/bin/cp" "-p") (listAppend (map (fn [(n String)] -> String (str from "/modules/" n)) names) (list (str to "/modules/")))) (list)).exitCode 0))))

fn ! phaseLines out: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l "NATIVE-WORKER-PHASES")) (stringLines out)))

fn ! runTests -> Bool
  (let [(dir (str ".asl/cache/nativeWorkerPhasesQuietTest-" (monotonicNs)))
        (made (dirCreate dir))
        (pkg (str dir "/pkg"))
        (_ (dirCreate pkg))
        (suite (writeFixture! pkg 6 100))
        (driver (str dir "/nwpDriver.asl"))
        (_ (fileWrite driver (driverSource)))
        (quiet (str dir "/quiet"))
        (traced (str dir "/traced"))
        (quietOut (driveWith! (list) driver quiet suite))
        (seeded (seedPrelude! quiet traced))
        (tracedOut (driveWith! (list "ASL_NATIVE_TRACE=1") driver traced suite))
        (removed (pathRemove dir))]
    (do (assert (nt/workerPhasesWanted? "1") "ASL_NATIVE_TRACE=1 asks for the worker phases line")
        (refute (nt/workerPhasesWanted? "") "no trace, whatever the quiet pid says, does not")
        (refute (nt/workerPhasesWanted? "0") "a trace value other than 1 does not")
        (assert (ok? made) "the scratch directory is created")
        (assert (= quietOut.exitCode 0) (str "the untraced 4-worker build passes: " quietOut.stderr))
        (assert (= (phaseLines quietOut.stderr) 0) (str "without ASL_NATIVE_TRACE no worker prints NATIVE-WORKER-PHASES: " quietOut.stderr))
        (assert seeded "the traced cache starts from the untraced prelude objects")
        (assert (= tracedOut.exitCode 0) (str "the traced 4-worker build passes: " tracedOut.stderr))
        (assert (> (phaseLines tracedOut.stderr) 0) (str "with ASL_NATIVE_TRACE=1 a worker prints NATIVE-WORKER-PHASES: " tracedOut.stderr))
        (assert (ok? removed) "the scratch directory is removed")
        true))
