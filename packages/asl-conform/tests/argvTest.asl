(module aslConform/tests/argvTest :x [runTests main] :i [(asl-proc/coreProcess :a proc) (aslConform/runner :a run) (aslConform/mutant :a mut) (aslConform/types :a ty)])

fn checkLine name: Str ok: Bool -> Str
  (str "check " name " " (if ok "1" "0"))

fn childPassed out: Str name: Str -> Bool
  (listContains? (stringLines out) (checkLine name true))

fn ! runChildTest root: Str casePath: Str -> (List Str)
  (let [(result (run/runConformCase! casePath "py" false))
        (record (str root "/python-argv"))
        (mutant (ty/makeMutant "argv probe" "py" "argv probe" "div_mod_neg_neg"))
        (trial (mut/runIsolatedMutantTrial! mutant "tests/conformance/xplat/div_mod_neg_neg"))
        (observed (mt (fileRead record) ((ok value) value) ((err _) "")))
        (cleanup (proc/exec! (proc/cmd "rm" (list "-rf" "tmp/conform/mutants/argv probe"))))]
    (list (checkLine "routePassed" result.passed)
          (checkLine "stubRan" (= result.actualStdout "argv-stub-ran"))
          (checkLine "mutantOneArgv" (stringContains? observed "tmp/conform/mutants/argv probe/run.py"))
          (checkLine "mutantCleanup" (ok? cleanup))))

fn ! main args: (List Str) -> (Result Int64 Str)
  (do
    (println (stringJoin (runChildTest (optionOr (envGet "ASL_CONFORM_ARGV_ROOT") "") (optionOr (envGet "ASL_CONFORM_ARGV_CASE") "")) "\n"))
    (ok 0))

fn ! runTests -> Bool
    (let [(root (str "/tmp/asl-conform-argv-" (stringFromInt64 (monotonicNs))))
            (_ (dirCreate root))
            (stubDir (str root "/bin"))
            (_d (dirCreate stubDir))
            (casePath (str root "/fixture dir"))
            (_c (dirCreate casePath))
            (record (str root "/python-argv"))
            (stub (str stubDir "/python3"))
            (script (str "#!/bin/sh\nif [ \"$#\" -ne 1 ]; then exit 31; fi\nprintf '%s\\n' \"$1\" > \"$ASL_CONFORM_ARGV_RECORD\"\nprintf 'argv-stub-ran\\n'\n"))
            (_w (fileWrite stub script))
            (expected (fileWrite (str casePath "/expect.stdout") "argv-stub-ran\n"))
            (_e (fileWrite (str casePath "/expect.exit") "0\n"))
            (chmod (mt (proc/exec! (proc/cmd "chmod" (list "+x" stub))) ((ok out) out.exitCode) ((err _) 127)))
            (path (str stubDir ":" (optionOr (envGet "PATH") "/usr/bin:/bin")))
            (childCmd (proc/withEnv (proc/withEnv (proc/withEnv (proc/cmd "asl/host/out/asl-host" (list "run" "asl/packages/asl-conform/tests/argvTest.asl")) "PATH" path) "ASL_CONFORM_ARGV_CHILD" "1") "ASL_CONFORM_ARGV_ROOT" root))
            (childCmd (proc/withEnv childCmd "ASL_CONFORM_ARGV_CASE" casePath))
            (childCmd (proc/withEnv childCmd "ASL_CONFORM_ARGV_RECORD" record))
            (child (mt (proc/exec! childCmd) ((ok out) out) ((err _) (proc/ProcessOutput :exitCode 127 :stdout "" :stderr "child test spawn failed" :durationMs 0))) )
            (cleanup (proc/exec! (proc/cmd "rm" (list "-rf" root))))]
        (do
          (assert (= chmod 0) "could not make python3 PATH stub executable")
          (assert (ok? expected) "could not write expected interpreter output")
          (assert (= child.exitCode 0) (str "exported conformance route child failed: " child.stderr))
          (assert (childPassed child.stdout "routePassed") "the exported conformance route must run python3 with its generated script argument")
          (assert (childPassed child.stdout "stubRan") "the PATH-stubbed interpreter must execute through runConformCase!")
          (assert (childPassed child.stdout "mutantOneArgv") "runIsolatedMutantTrial! must pass its generated script as one argv item")
          (assert (childPassed child.stdout "mutantCleanup") "temporary mutant argv fixture removed")
          (assert (ok? cleanup) "temporary conformance argv fixtures removed")
          true))
