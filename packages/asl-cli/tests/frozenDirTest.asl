(module asl-cli/tests/frozenDirTest :x [runTests] :i [(tools/fleet/run :a run)])

fn ! cli! root: String cache: String argv: (List String) -> run/Done
  (run/runOneLimited
    (run/job (listAppend (list "/usr/bin/nice" "-n" "15" (str root "/bin/asl")) argv) root
             (run/childEnv (list (str "ASL_ROOT=" root)
                                 (str "ASL_CLI_ROOT=" root)
                                 (str "ASL_PRELUDE=" root "/asl/prelude/prelude.asl")
                                 (str "ASL_NATIVE_CLI_CACHE=" cache))))
    (run/limits 180 64))

fn ! host! root: String argv: (List String) -> run/Done
  (run/runOneLimited
    (run/job (listAppend (list "/usr/bin/nice" "-n" "15" (str root "/asl/host/out/asl-host")
                         "run" (str root "/asl/packages/asl-cli/src/command.asl")) argv) root
             (run/childEnv (list (str "ASL_ROOT=" root)
                                 (str "ASL_CLI_ROOT=" root)
                                 (str "ASL_PRELUDE=" root "/asl/prelude/prelude.asl"))))
    (run/limits 180 64))

fn ! checks! mode: String frozenFile: String cli: run/Done explicit: run/Done live: run/Done -> Bool
  (do
    (assert (or (= cli.exit 0) (= cli.exit 1)) (str mode " frozen directory exited normally: " cli.out))
    (assert (stringContains? cli.out "(:test :frozen ") (str mode " prints frozen count"))
    (assert (not (stringContains? cli.out frozenFile)) (str mode " does not run frozen suites from directory: " cli.out))
    (assert (not (stringContains? cli.out "asl/packages/asl-target-sh/tests/astTest.asl:")) (str mode " skips astTest"))
    (assert (not (stringContains? cli.out "asl/packages/asl-target-sh/tests/emitPs1Test.asl:")) (str mode " skips emitPs1Test"))
    (assert (not (stringContains? cli.out "asl/packages/asl-target-sh/tests/lowerTest.asl:")) (str mode " skips lowerTest"))
    (assert (not (stringContains? cli.out "(:test :frozen 0)")) (str mode " reports at least one frozen suite"))
    (assert (= explicit.exit 0) (str mode " explicitly named frozen file still runs: " explicit.out))
    (assert (stringContains? explicit.out "emitShTest.asl:") (str mode " runs explicitly named frozen suite"))
    (assert (= live.exit 0) (str mode " live directory exits successfully: " live.out))
    (assert (stringContains? live.out "(:test :frozen 0)") (str mode " reports zero frozen suites for live directory"))
    true)

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (configuredCache (optionOr (envGet "ASL_NATIVE_CLI_CACHE") ""))
        (ownsCache (stringEmpty? configuredCache))
        (cache (if ownsCache (str "/tmp/aslFrozenDirTest." (stringFromInt64 (procSelf))) configuredCache))
        (frozenDir "asl/packages/asl-target-sh/tests")
        (frozenFile "asl/packages/asl-target-sh/tests/emitShTest.asl")
        (liveDir "asl/packages/asl-cli/tests/fixtures/testChanged")
        (nativeDir (cli! root cache (list "test" frozenDir)))
        (nativeFile (cli! root cache (list "test" frozenFile)))
        (nativeLive (cli! root cache (list "test" liveDir)))
        (hostDir (host! root (list "test" frozenDir)))
        (hostFile (host! root (list "test" frozenFile)))
        (hostLive (host! root (list "test" liveDir)))
        (nativeChecks (checks! "bin/asl native path" frozenFile nativeDir nativeFile nativeLive))
        (hostChecks (checks! "asl-host command path" frozenFile hostDir hostFile hostLive))
        (removed (if ownsCache (pathRemove cache) (ok ()) ))]
    (and nativeChecks (and hostChecks (ok? removed))))
