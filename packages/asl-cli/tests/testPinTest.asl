(module asl-cli/tests/testPinTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-cli/src/nativeRefresh :a nr) (asl/packages/asl-cli/src/cliClosure :a cc) (asl-tools/fleet/run :a fr)])

; (:m :ref PERF-CLI-REBUILD :do "part one: argv shapes testArgv? accepts; part two: a scratch root with a fake CLI dir (deps, a cached testClosure, a head file as the stamp) shows testPinned? and aslNativeBuild refresh keeping the CLI for asl test when only a dep outside the reached files moved, and refusing to keep it when a reached file, a toolchain root or a non-.asl dep moved, a dep is gone, a reached file is not a dep, the verb is not test, or :testPin false is set; part three: the reachability walk on a fixture (a gate's cut call is not followed, a cut called from a non-gate is an error) and on the real native.asl (the test path reaches the suite runner, not the gateway or the forms delegate); no assert reads a duration")
fn ! shapes -> Bool
  (do (assert (nc/testArgv? (list "test" "a/bTest.asl")) "one suite path")
      (assert (nc/testArgv? (list "test" "a/bTest.asl" "c/dir")) "several paths")
      (assert (nc/testArgv? (list "test" "--jobserverDir" "/tmp/js" "a/bTest.asl")) "the jobserver dir pair a re-exec adds")
      (assert (not (nc/testArgv? (list "test"))) "no path")
      (assert (not (nc/testArgv? (list "test" "--jobserverDir" "/tmp/js"))) "only the jobserver pair")
      (assert (not (nc/testArgv? (list "test" "--all"))) "a sweep")
      (assert (not (nc/testArgv? (list "test" "--changed"))) "a changed run")
      (assert (not (nc/testArgv? (list "test" "--trace" "a/bTest.asl"))) "a traced run takes the hosted path")
      (assert (not (nc/testArgv? (list "test" "--native" "a/bTest.asl"))) "the native flag")
      (assert (not (nc/testArgv? (list "test" "(:read)"))) "a form")
      (assert (not (nc/testArgv? (list "check" "a/bTest.asl"))) "check is another verb")
      (assert (not (nc/testArgv? (list "run" "tools/x.asl"))) "run is another verb")
      (assert (nc/testPinOn? "") "on when the config says nothing")
      (assert (not (nc/testPinOn? ":nativeCli (:testPin false)")) "false turns it off")
      true)

fn ! mkdirs! path: String -> Bool
  (fold (fn [(acc Bool) (p String)] -> Bool (do (dirCreate p) acc)) true
        (fold (fn [(acc (List String)) (part String)] -> (List String) (if (stringEmpty? part) acc (listAppend acc (list (str (optionOr (listLast acc) "") "/" part))))) (list) (stringSplit path "/")))

fn ! touch! path: String -> Bool
  (do (sleepMs 30)
      (ok? (fileAppend path "; moved\n")))

fn ! write! path: String text: String -> Bool
  (ok? (fileWrite path text))

; (:m :ref PERF-CLI-REBUILD :do "a fresh scratch: every source and its DIR/src copy written with the same bytes and the head file last, so nothing has moved until a case appends to a source")
fn ! scratch! base: String n: Int64 -> String
  (let [(root (str base "/testPin-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 n)))
        (dir (str root "-cli"))
        (_ (mkdirs! (str root "/asl/packages/asl-compiler/src")))
        (_ (mkdirs! dir))
        (_ (write! (str root "/inside.asl") "(module inside)\n"))
        (_ (write! (str root "/outside.asl") "(module outside)\n"))
        (_ (write! (str root "/seed.asn") "(:seed)\n"))
        (_ (write! (str root "/asl/packages/asl-compiler/src/emit.asl") "(module emit)\n"))
        (_ (mkdirs! (str dir "/src/asl/packages/asl-compiler/src")))
        (_ (write! (str dir "/src/inside.asl") "(module inside)\n"))
        (_ (write! (str dir "/src/outside.asl") "(module outside)\n"))
        (_ (write! (str dir "/src/seed.asn") "(:seed)\n"))
        (_ (write! (str dir "/src/asl/packages/asl-compiler/src/emit.asl") "(module emit)\n"))
        (_ (write! (str dir "/deps") "inside.asl\noutside.asl\nseed.asn\nasl/packages/asl-compiler/src/emit.asl\n"))
        (_ (write! (str dir "/testClosure") "inside.asl\n"))
        (_ (sleepMs 30))
        (_ (write! (str root "-head") (str dir "\n")))]
    root)

fn ! pinnedAfter base: String n: Int64 moved: String cmd: (List String) -> Bool
  (let [(root (scratch! base n))
        (_ (if (stringEmpty? moved) true (touch! (str root "/" moved))))]
    (nc/kept? root (str root "-cli") (str root "-head") cmd))

fn ! decisions base: String -> Bool
  (let [(t (list "test" "x/yTest.asl"))]
    (do (assert (not (pinnedAfter base 1 "" (list "check" "x/yTest.asl"))) "check is never test-pinned")
        (assert (pinnedAfter base 2 "outside.asl" t) "a moved dep outside the reached files keeps the CLI for test")
        (assert (not (pinnedAfter base 3 "outside.asl" (list "check" "x/yTest.asl"))) "the same move does not keep it for check")
        (assert (not (pinnedAfter base 4 "inside.asl" t)) "a moved reached file rebuilds")
        (assert (not (pinnedAfter base 5 "asl/packages/asl-compiler/src/emit.asl" t)) "a moved toolchain root rebuilds")
        (assert (not (pinnedAfter base 6 "seed.asn" t)) "a moved non-.asl dep rebuilds")
        (let [(root (scratch! base 7)) (_ (pathRemove (str root "/outside.asl")))]
          (assert (not (nc/testPinned? root (str root "-cli") (str root "-head") t)) "a missing dep rebuilds"))
        (let [(root (scratch! base 8)) (_ (write! (str root "-cli/testClosure") "inside.asl\nnotADep.asl\n")) (_ (touch! (str root "/outside.asl")))]
          (assert (not (nc/testPinned? root (str root "-cli") (str root "-head") t)) "a reached file that is not a dep rebuilds"))
        (let [(root (scratch! base 11)) (_ (write! (str root "-cli/src/inside.asl") "(module insideBefore)\n"))]
          (assert (not (nc/kept? root (str root "-cli") (str root "-head") t)) "a reached file whose bytes differ from the built copy rebuilds even with an old mtime"))
        (assert (pinnedAfter base 12 "" t) "nothing moved keeps it")
        (let [(root (scratch! base 9)) (_ (write! (str root "/.asl.config.asn") "(:workspace :nativeCli (:testPin false))\n")) (_ (touch! (str root "/outside.asl")))]
          (assert (not (nc/testPinned? root (str root "-cli") (str root "-head") t)) ":testPin false rebuilds"))
        true))

; (:m :ref PERF-CLI-REBUILD :do "the builder's refresh is what bin/asl runs for a suspect head: kept for test it answers 0 without calling build; for a reached file it never answers 0 (refused or a failed build)")
fn ! refreshes base: String -> Bool
  (let [(root (scratch! base 10))
        (cache (str root "-cache"))
        (_ (mkdirs! cache))
        (_ (write! (nc/headPath cache root) (str root "-cli\n")))
        (_ (sleepMs 30))
        (marker (str root "-built"))
        (build (fn [(r String) (c String)] -> Int64 (do (fileWrite marker r) 1)))
        (_ (touch! (str root "/outside.asl")))
        (kept (nr/refresh! root cache (list "test" "x/yTest.asl") build))
        (builtKept (fileExists? marker))
        (_ (touch! (str root "/inside.asl")))
        (stale (nr/refresh! root cache (list "test" "x/yTest.asl") build))]
    (do (assert (and (= kept 0) (not builtKept)) (str "refresh keeps the CLI for test without building when only an outside dep moved: rc " (stringFromInt64 kept)))
        (assert (!= stale 0) (str "refresh does not keep it once a reached file moved: rc " (stringFromInt64 stale)))
        true))

fn ! walks -> Bool
  (let [(fx "asl/packages/asl-cli/tests/fixtures/testPin")
        (entry (str fx "/entry.asl"))
        (cuts (list "run!"))
        (gates (list "main" "dispatch!"))
        (got (cc/closureOf! entry (list "main") cuts gates))
        (files (resultOr got (list)))
        (has (fn [(name String)] -> Bool (listAny? (fn [(f String)] -> Bool (stringEndsWith? f (str fx "/" name))) files)))
        (leak (cc/closureOf! entry (list "main" "leak!") cuts gates))
        (uncut (cc/closureOf! entry (list "main") (list) gates))
        (real (cc/closureOf! (cc/testEntry) (list "main") (cc/testCuts) (cc/testGates)))
        (realFiles (resultOr real (list)))
        (realHas (fn [(suffix String)] -> Bool (listAny? (fn [(f String)] -> Bool (stringEndsWith? f suffix)) realFiles)))]
    (do (assert (ok? got) (str "the fixture walk succeeds: " (match got ((err e) e) ((ok _) ""))))
        (assert (and (has "entry.asl") (has "used.asl")) "the gate test! reaches used.asl")
        (assert (has "shape.asl") "a schema named in a reached signature is reached")
        (assert (not (has "cutOnly.asl")) "a module only a cut handler calls is not reached")
        (assert (and (has "table.asl") (has "valueOnly.asl")) "a function stored as a value in a string-keyed map is reached")
        (assert (has "deep.asl") "the walk goes on through a function reached only as a value")
        (assert (has "lambdaOnly.asl") "a call inside a lambda kept in a list is reached")
        (assert (stringContains? (match leak ((err e) e) ((ok _) "")) "leak! -> run!") "a cut called from a reached non-gate is an error")
        (assert (listAny? (fn [(f String)] -> Bool (stringEndsWith? f "cutOnly.asl")) (resultOr uncut (list))) "without the cut the handler's module is reached")
        (assert (ok? real) (str "the native.asl test walk succeeds: " (match real ((err e) e) ((ok _) ""))))
        (assert (and (realHas "asl-cli/src/native.asl") (realHas "asl-gates/src/suiteRunner.asl")) "the test path reaches native.asl and the suite runner")
        (assert (realHas "asl/tools/nativeTest.asl") "the test path reaches nativeTest")
        (assert (not (realHas "asl-gateway/src/config.asl")) "the test path does not reach the gateway config")
        (assert (not (realHas "asl-forms/src/delegate.asl")) "the test path does not reach the forms delegate")
        true))

fn ! runTests -> Bool
  (let [(base0 (optionOr (listHead (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (list (optionOr (envGet "ASL_RUN_TMP") "") (optionOr (envGet "TMPDIR") "")))) "/tmp"))
        (base (str base0 "/testPinTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (mkdirs! base))
        (ok1 (shapes))
        (ok2 (decisions base))
        (ok3 (refreshes base))
        (ok4 (walks))
        (_ (fr/runOneLimited (fr/job (list "/bin/rm" "-rf" "--" base) "." (list)) (fr/limits 60 50)))]
    (do (assert (not (fileExists? base)) "the scratch is removed")
        (and ok1 (and ok2 (and ok3 ok4)))))
