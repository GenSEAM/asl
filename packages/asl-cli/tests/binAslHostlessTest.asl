(module asl-cli/binAslHostlessTest :x [runTests] :i [(asl-tools/fleet/run :a run) (asl/packages/asl-cli/tests/nativeColdFixture :a nf)])

fn probe -> String
  "asl/packages/asl-cli/tests/fixtures/servedBy/servedProbe.asl"

fn ! sh! root: String argv: (List String) timeoutS: Int64 maxDesc: Int64 -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits timeoutS maxDesc))

; (:m :ref CLI-TEST-ADOPT :do "the run's host store (ASL_HOST_CACHE_DIR, else HOME/.asl/run/hosts) is only read: the cold run gets a scratch store whose rt, seed and nativeBuild entries are symlinks to it, so bin/asl copies the builder, runtime and asl1 of the same keys (build.sh stored path) instead of lowering seed and asl1 again, and anything new it wrote would land in the scratch store, never under ~/.asl")
fn ! realHostStore -> String
  (let [(configured (optionOr (envGet "ASL_HOST_CACHE_DIR") ""))]
    (if (stringEmpty? configured) (str (optionOr (envGet "HOME") "") "/.asl/run/hosts") configured))

fn ! dropPrefixes -> (List String)
  (list "ASL_HOST=" "ASL_NATIVE_CLI_" "ASL_HOST_CACHE_DIR=" "ASL_ROOT=" "ASL_PRELUDE=" "PATH=" "HOME=")

fn ! hasAnyPrefix? row: String prefixes: (List String) -> Bool
  (listAny? (fn [(p String)] -> Bool (stringStartsWith? row p)) prefixes)

fn ! bare -> (List String)
  (filter (fn [(row String)] -> Bool (not (hasAnyPrefix? row (dropPrefixes)))) (run/childEnv (list)))

fn ! hostlessEnv home: String cache: String hostCache: String -> (List String)
  (listAppend
    (list "PATH=/usr/bin:/bin" (str "HOME=" home) (str "ASL_NATIVE_CLI_CACHE=" cache) (str "ASL_HOST_CACHE_DIR=" hostCache)
          (str "SERVED_STOP_PID=" (stringFromInt64 (procSelf))))
    (bare))

fn ! binAslHostless! fresh: String args: (List String) home: String cache: String hostCache: String -> run/Done
  (run/runOneLimited (run/job (cons (str fresh "/bin/asl") args) fresh (hostlessEnv home cache hostCache)) (run/limits 1700 128))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (made (sh! root (list "mktemp" "-d") 10 4))
        (tmp (stringTrim made.out))
        (base (str (resultOr (realPath tmp) tmp) "/binAslHostless"))
        (fresh (str base "/wt"))
        (home (str base "/home"))
        (cache (str base "/nativeCli"))
        (hostCache (str base "/hostCache"))
        (precleaned (sh! root (list "/bin/sh" "-c" "git worktree remove --force \"$0\" 2>/dev/null; rm -rf \"$1\"" fresh base) 30 8))
        (added (sh! root (list "git" "worktree" "add" "--detach" fresh "HEAD") 120 16))
        (noOut (not (ok? (dirList (str fresh "/asl/host/out")))))
        (homed (dirCreate home))
        (upstream (nf/adoptFrom! cache (list "seed" "rt" "asl1" "cli")))
        (hostLinked (sh! root (list "/bin/sh" "-c" "mkdir -p \"$1\" && for k in nativeBuild rt seed; do mkdir -p \"$1/$k\" && for e in \"$0\"/$k/*; do [ -e \"$e\" ] && ln -s \"$e\" \"$1/$k/\"; done; done; true" (realHostStore) hostCache) 60 8))
        (noPathHost (sh! fresh (list "/bin/sh" "-c" "command -v asl-host") 10 4))
        (cold (binAslHostless! fresh (list "test" (probe)) home cache hostCache))
        (removed (sh! root (list "git" "worktree" "remove" "--force" fresh) 30 8))
        (cleaned (sh! root (list "/bin/sh" "-c" "rm -rf \"$0\"" tmp) 30 8))]
    (do (assert (and (= made.exit 0) (stringStartsWith? tmp "/")) (str "mktemp -d made a work directory outside the workspace: " made.out))
        (assert (= added.exit 0) (str "a fresh worktree was checked out with no asl/host/out: " added.out added.verdict))
        (assert noOut "the fresh worktree has no asl/host/out/asl-host (a true cold clone)")
        (assert (ok? homed) "a fresh HOME for the cold run was created")
        (assert upstream "the fresh native CLI cache copies seed, runtime, asl1 and the CLI from the run store: the cold run still has no asl/host/out, no asl-host and a fresh HOME, only the lowering work is shared")
        (assert (= hostLinked.exit 0) (str "the scratch host store links the run's rt, seed and nativeBuild entries read-only: " hostLinked.out))
        (assert (!= noPathHost.exit 0) "the cold run's PATH has no asl-host on it either")
        (assert (= cold.verdict "exit") (str "bin/asl test ended on its own, inside the limit: " cold.verdict " " cold.out))
        (assert (= cold.exit 0) (str "a fresh clone with no asl-host and no asl-host on PATH still answers bin/asl test: " cold.out))
        (assert (stringContains? cold.out "servedProbe.asl: 4 assertion(s) executed, 1 refutation(s) executed") "the cold run reports the probe's assertions")
        (refute (stringContains? cold.out "runs on asl-host") "the cold call never fell back to asl-host")
        (assert (= removed.exit 0) (str "the test worktree registration was removed: " removed.out))
        (assert (= cleaned.exit 0) "the test cache dir was removed")
        true))
