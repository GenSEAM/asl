(module asl/host/tests/runtimeSeedTest :x [runTests] :i [(tools/fleet/run :a run)])

fn members -> (List String)
  (list "gcAsl.o" "rtAbi.o" "rtFloor.o")

fn freshClone -> String
  (str "export SERVED_STOP_PID=$$; "
       "sh asl/host/build.sh || exit 3; "
       "printf '#!/bin/sh\\necho host-invoked >> \\\"$ASL_HOST_WITNESS\\\"\\nexit 97\\n' > asl/host/out/asl-host; "
       "chmod +x asl/host/out/asl-host; "
       "ASL_NATIVE_CLI_WAIT=1 bin/asl test asl/packages/asl-cli/tests/fixtures/servedBy/failingProbe.asl; code=$?; test $code -eq 1")

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 120 8))

fn ! sameMember? a: String b: String name: String -> Bool
  (mt (fileReadBytes (str a "/" name))
    ((err _) false)
    ((ok x) (mt (fileReadBytes (str b "/" name)) ((err _) false) ((ok y) (= (bytesSha256 x) (bytesSha256 y))))))

fn inherited? row: String -> Bool
  (or (stringStartsWith? row "ASL_HOST_")
      (or (stringStartsWith? row "ASL_NATIVE_")
          (or (stringStartsWith? row "ASL_ROOT=")
              (or (stringStartsWith? row "ASL_PRELUDE=") (or (stringStartsWith? row "SNAP=") (stringStartsWith? row "SERVED_STOP_PID="))))))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/runtimeSeed/" (stringFromInt64 (procSelf))))
        (clone (str work "/root"))
        (fresh (sh! root (list "/bin/rm" "-rf" work)))
        (made (dirCreate work))
        (copied (sh! root (list "/bin/sh" "-c" "mkdir -p \"$1\" && git ls-files -co --exclude-standard -z asl bin tools .asl.config.asn pack.asn | tar --null -T - -cf - | (cd \"$1\" && tar xf -)" "copy" clone)))
        (bare (not (fileExists? (str clone "/asl/host/out/libaslrt.a"))))
        (witness (str work "/host-witness"))
        (env (listAppend (list (str "ASL_HOST_CACHE_DIR=" work "/hosts") (str "ASL_NATIVE_CLI_CACHE=" work "/cli") (str "ASL_HOST_WITNESS=" witness))
               (filter (fn [(row String)] -> Bool (not (inherited? row))) (run/childEnv (list)))))
        (built (run/runOneLimited (run/job (list "/bin/sh" "-c" (freshClone)) clone env) (run/limits 1800 64)))
        (witnessed (fileExists? witness))
        (wrapperReady (stringContains? (resultOr (fileRead (str clone "/asl/host/out/asl-host")) "") "host-invoked"))
        (split (sh! root (list "/bin/sh" "-c" "mkdir -p \"$1/fresh\" \"$1/tree\" && cd \"$1/fresh\" && ar x \"$1/root/asl/host/out/libaslrt.a\" && cd \"$1/tree\" && ar x \"$2\"" "split" work (str root "/asl/host/out/libaslrt.a"))))
        (equal (map (fn [(m String)] -> Bool (sameMember? (str work "/fresh") (str work "/tree") m)) (members)))
        (cleaned (sh! root (list "/bin/rm" "-rf" work)))]
    (do (assert (ok? made) "the work dir was created")
        (assert (= copied.exit 0) (str "the tree was copied: " copied.out))
        (assert bare "the copy starts with no libaslrt.a")
        (assert wrapperReady "the clone's host fallback is replaced by the witness wrapper")
        (refute witnessed (str "no asl-host ran in the fresh clone's native CLI test: " built.out))
        (assert (= built.exit 0) (str "build.sh and the probe finished: " built.out))
        (refute (stringContains? built.out "run on asl-host to bootstrap") "build.sh took the native emitter path")
        (assert (stringContains? built.out "two has two letters") "the probe suite ran, served by a native binary")
        (assert (= split.exit 0) (str "both archives split into members: " split.out))
        (assert (listAll? (fn [(b Bool)] -> Bool b) equal) "gcAsl.o, rtAbi.o and rtFloor.o equal the tree's members byte for byte")
        (assert (= cleaned.exit 0) "the work dir was removed")
        true))
