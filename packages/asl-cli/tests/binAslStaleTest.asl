(module asl-cli/binAslStaleTest :x [runTests] :i [(tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeCli :a nc)])

fn probe -> String
  "asl/packages/asl-cli/tests/fixtures/servedBy/servedProbe.asl"

fn passSuite -> String
  "asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl"

fn tampered -> String
  "asl/packages/asl-cli/src/nativeCli.asl"

fn ! envFor cache: (Option String) extra: (List String) -> (List String)
  (listAppend (cons (str "SERVED_STOP_PID=" (stringFromInt64 (procSelf))) (listAppend (mt cache ((some c) (list (str "ASL_NATIVE_CLI_CACHE=" c))) ((none) (list))) extra))
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST=") (or (stringStartsWith? row "SERVED_STOP_PID=") (or (stringStartsWith? row "ASL_NATIVE_CLI_WAIT=") (and (some? cache) (stringStartsWith? row "ASL_NATIVE_CLI_CACHE="))))))) (run/childEnv (list))))

fn ! binAsl! root: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str root "/bin/asl") args) root env) (run/limits 1500 64))

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 120 8))

fn ! headOf cache: String root: String -> String
  (stringTrim (resultOr (fileRead (nc/headPath cache root)) ""))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (shared (nc/cacheDir!))
        (warm (binAsl! root (list "test" (probe)) (envFor (none) (list "ASL_NATIVE_CLI_WAIT=1"))))
        (built (headOf shared root))
        (cache (str root "/.asl/cache/binAslStale/" (stringFromInt64 (procSelf))))
        (copy (str cache "/cli-staleCopy"))
        (linked (sh! root (list "/bin/sh" "-c" "rm -rf \"$1\" && mkdir -p \"$1\" && cp -R \"$2\" \"$3\" && for d in \"$0\"/seed-* \"$0\"/asl1-* \"$0\"/cli-*; do ln -s \"$d\" \"$1/\"; done" shared cache built copy)))
        (edited (mt (fileRead (str copy "/src/" (tampered)))
                  ((err e) (err e))
                  ((ok text) (fileWrite (str copy "/src/" (tampered)) (str text "\n(:m :why \"an edit the cached binary predates\")\n")))))
        (pointed (fileWrite (nc/headPath cache root) (str copy "\n")))
        (stale (binAsl! root (list "test" (passSuite)) (envFor (some cache) (list))))
        (rebuilt (binAsl! root (list "test" (probe)) (envFor (some cache) (list "ASL_NATIVE_CLI_WAIT=1"))))
        (after (headOf cache root))
        (cleaned (sh! root (list "/bin/rm" "-rf" cache)))]
    (do (assert (= warm.exit 0) (str "the shared cache serves the probe natively: " warm.out))
        (assert (nc/fresh? root built) (str "the shared head names a binary built from this tree: " built))
        (assert (= linked.exit 0) (str "the stale copy was made: " linked.out))
        (assert (ok? edited) (str "the copy's snapshot of " (tampered) " was edited"))
        (assert (ok? pointed) "the test cache's head names the stale copy")
        (refute (nc/fresh? root copy) "the copy no longer matches the tree")
        (assert (= stale.exit 0) (str "the stale call still answers: " stale.out))
        (assert (stringContains? stale.out "asl: test runs on asl-host: no native toolchain, the cached binary predates its sources and ") (str "the stale binary handed the verb to asl-host with a note: " stale.out))
        (assert (stringContains? stale.out "passTest.asl: 1 assertion(s) executed, 1 refutation(s) executed (2 passed)") "asl-host carried the verdict")
        (assert (= rebuilt.exit 0) (str "after the rebuild the probe is served natively: " rebuilt.out))
        (assert (stringContains? rebuilt.out "servedProbe.asl: 4 assertion(s) executed, 1 refutation(s) executed") "the rebuilt native binary ran the probe")
        (assert (and (!= after copy) (= (listLast (stringSplit after "/")) (listLast (stringSplit built "/")))) (str "the rebuild pointed the head back at the binary of this tree: " after))
        (assert (= cleaned.exit 0) "the test cache was removed")
        true))
