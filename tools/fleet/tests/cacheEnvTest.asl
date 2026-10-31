(module asl-tools/fleet/tests/cacheEnvTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref CACHE-HOME-LEAK :do "bin/asl run tools/remote/vps.asl (no verb, no network) is warmed with this HOME, then run twice, each time with a new empty HOME and only PATH plus fr/cacheEnv!: the second run answers in under 10 s and neither fresh HOME gets a check cache, so every HOME-keyed cache came from the rows; the temp homes are removed")
fn ! runFresh! home: String -> fr/Done
  (fr/runOneLimited (fr/job (list "./bin/asl" "run" "tools/remote/vps.asl") (resultOr (realPath ".") ".")
                            (listAppend (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" home)) (fr/cacheEnv!)))
                    (fr/limits 900 200))

fn ! freshHome! tag: String -> String
  (let [(dir (str (resultOr (realPath (optionOr (envGet "TMPDIR") "/tmp")) "/tmp") "/cacheEnvTest-" tag "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate dir))]
    dir)

fn ! names rows: (List String) -> (List String)
  (map (fn [(r String)] -> String (optionOr (listHead (stringSplit r "=")) r)) rows)

fn ! runTests -> Bool
  (let [(rows (fr/cacheEnv!))
        (warm (fr/runOneLimited (fr/job (list "./bin/asl" "run" "tools/remote/vps.asl") (resultOr (realPath ".") ".") (fr/childEnv (list))) (fr/limits 1800 400)))
        (h1 (freshHome! "a"))
        (one (runFresh! h1))
        (h2 (freshHome! "b"))
        (t0 (monotonicNs))
        (two (runFresh! h2))
        (ms (/ (- (monotonicNs) t0) 1000000))
        (leaked (or (fileExists? (str h1 "/.asl/cache/check")) (fileExists? (str h2 "/.asl/cache/check"))))
        (removed (= (fr/runShell! (str "rm -rf \"" h1 "\" \"" h2 "\"") "." (fr/childEnv (list)) (fr/limits 60 4)).exit 0))]
    (do (assert (listAll? (fn [(n String)] -> Bool (listContains? (names rows) n)) (list "ASL_NATIVE_CLI_CACHE" "ASL_HOST_CACHE_DIR" "ASL_NATIVE_ASL1_CACHE" "ASL_CHECK_CACHE" "ASL_CORPUS_CACHE"))
                (str "cacheEnv! names every HOME-keyed cache: " (stringJoin rows " ")))
        (assert (listAll? (fn [(r String)] -> Bool (stringStartsWith? (optionOr (listGet (stringSplit r "=") 1) "") "/")) rows) "every row is an absolute dir")
        (assert (stringContains? warm.out "(:err :code ") (str "the warm run answers: " (optionOr (stringSlice warm.out 0 300) "")))
        (assert (and (stringContains? one.out "(:err :code ") (stringContains? two.out "(:err :code ")) (str "both fresh-HOME runs answer: " (optionOr (stringSlice two.out 0 300) "")))
        (assert (< ms 10000) (str "a fresh HOME with the cache rows reuses the shared caches: " (stringFromInt64 ms) " ms"))
        (assert (not leaked) "no check cache was made under a fresh HOME")
        (assert removed "the temp homes are removed")
        true))
