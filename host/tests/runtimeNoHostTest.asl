(module asl/host/tests/runtimeNoHostTest :x [runTests] :i [(tools/fleet/run :a run)])

fn members -> (List String)
  (list "gcAsl.o" "rtAbi.o" "rtFloor.o")

fn sampler -> String
  (str "\"$0\" \"$@\" & b=$!; "
       "while kill -0 $b 2>/dev/null; do "
       "ps -axo pid=,ppid=,args= | awk -v r=$b '{p[$1]=$2; a[$1]=$0} END {for (k in p) {x=k; n=0; while (x>1 && n<64) {if (x==r) {print a[k]; break}; x=p[x]; n++}}}' >> \"$SNAP\"; "
       "sleep 0.2; done; wait $b")

fn argv0 line: String -> String
  (optionOr (listGet (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim line) " ")) 2) "")

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 60 8))

fn ! sameMember? a: String b: String name: String -> Bool
  (mt (fileReadBytes (str a "/" name))
    ((err _) false)
    ((ok x) (mt (fileReadBytes (str b "/" name)) ((err _) false) ((ok y) (= (bytesSha256 x) (bytesSha256 y))))))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/runtimeNoHost/" (stringFromInt64 (procSelf))))
        (fresh (sh! root (list "/bin/rm" "-rf" work)))
        (made (dirCreate work))
        (snap (str work "/snap"))
        (env (listAppend (list (str "ASL_HOST_OUT=" work "/out") (str "ASL_HOST_CACHE_DIR=" work "/hosts") (str "ASL_NATIVE_RT=" root "/asl/host/out/libaslrt.a") (str "SNAP=" snap))
               (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST_") (or (stringStartsWith? row "ASL_NATIVE_") (stringStartsWith? row "SNAP="))))) (run/childEnv (list)))))
        (built (run/runOneLimited (run/job (list "/bin/sh" "-c" (sampler) "/bin/sh" (str root "/asl/host/build.sh")) root env) (run/limits 1200 64)))
        (seen (map argv0 (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines (resultOr (fileRead snap) "")))))
        (split (sh! root (list "/bin/sh" "-c" "mkdir -p \"$1/native\" \"$1/host\" && cd \"$1/native\" && ar x \"$1/out/libaslrt.a\" && cd \"$1/host\" && ar x \"$2\"" "split" work (str root "/asl/host/out/libaslrt.a"))))
        (equal (map (fn [(m String)] -> Bool (sameMember? (str work "/native") (str work "/host") m)) (members)))
        (cleaned (sh! root (list "/bin/rm" "-rf" work)))]
    (do (assert (ok? made) "the work dir was created")
        (assert (= built.exit 0) (str "build.sh finished: " built.out))
        (refute (stringContains? built.out "run on asl-host to bootstrap") "build.sh took the native emitter path")
        (refute (listAny? (fn [(c String)] -> Bool (or (stringEndsWith? c "/asl-host") (= c "asl-host"))) seen) "no asl-host ran in the build's tree")
        (assert (listAny? (fn [(c String)] -> Bool (stringEndsWith? c "/asl1")) seen) "the sampler saw the seed asl1 in the build's tree")
        (assert (= split.exit 0) (str "both archives split into members: " split.out))
        (assert (listAll? (fn [(b Bool)] -> Bool b) equal) "gcAsl.o, rtAbi.o and rtFloor.o equal the host-emitted members byte for byte")
        (assert (= cleaned.exit 0) "the work dir was removed")
        true))
