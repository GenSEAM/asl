(module asl/host/tests/archiveKeyTest :x [runTests] :i [(tools/fleet/run :a run)])

fn members -> (List String)
  (list "gcAsl.o" "rtAbi.o" "rtFloor.o")

fn rebuildTwice -> String
  (str "ASL_HOST_OUT=\"$1/a\" ASL_HOST_CACHE_DIR=\"$1/ha\" sh asl/host/build.sh && sleep 2 && "
       "ASL_HOST_OUT=\"$1/b\" ASL_HOST_CACHE_DIR=\"$1/hb\" sh asl/host/build.sh")

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 120 8))

fn ! digest path: String -> String
  (mt (fileReadBytes path) ((err _) "") ((ok x) (bytesSha256 x)))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/archiveKey/" (stringFromInt64 (procSelf))))
        (fresh (sh! root (list "/bin/rm" "-rf" work)))
        (made (dirCreate work))
        (env (listAppend (list (str "ASL_NATIVE_RT=" root "/asl/host/out/libaslrt.a"))
               (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST_") (stringStartsWith? row "ASL_NATIVE_")))) (run/childEnv (list)))))
        (built (run/runOneLimited (run/job (list "/bin/sh" "-c" (rebuildTwice) "rebuild" work) root env) (run/limits 1800 64)))
        (split (sh! root (list "/bin/sh" "-c" "mkdir -p \"$1/ma\" \"$1/mb\" && cd \"$1/ma\" && ar x \"$1/a/libaslrt.a\" && cd \"$1/mb\" && ar x \"$1/b/libaslrt.a\"" "split" work)))
        (equal (map (fn [(m String)] -> Bool (let [(x (digest (str work "/ma/" m)))] (and (not (stringEmpty? x)) (= x (digest (str work "/mb/" m)))))) (members)))
        (first (digest (str work "/a/libaslrt.a")))
        (second (digest (str work "/b/libaslrt.a")))
        (cleaned (sh! root (list "/bin/rm" "-rf" work)))]
    (do (assert (ok? made) "the work dir was created")
        (assert (= built.exit 0) (str "both rebuilds finished: " built.out))
        (assert (= split.exit 0) (str "both archives split into members: " split.out))
        (assert (listAll? (fn [(b Bool)] -> Bool b) equal) "the two rebuilds emitted equal gcAsl.o, rtAbi.o and rtFloor.o")
        (refute (stringEmpty? first) "the first archive was read")
        (assert (= first second) "equal members pack a byte-equal libaslrt.a, so every key over it is unchanged")
        (assert (= cleaned.exit 0) "the work dir was removed")
        true))
