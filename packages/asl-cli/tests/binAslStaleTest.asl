(module asl-cli/binAslStaleTest :x [runTests] :i [(tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeCli :a nc)])

fn probe -> String
  "asl/packages/asl-cli/tests/fixtures/servedBy/servedProbe.asl"

fn passSuite -> String
  "asl/packages/asl-cli/tests/fixtures/sweep/passTest.asl"

fn tampered -> String
  "asl/packages/asl-cli/src/nativeCli.asl"

fn ! envFor cache: (Option String) extra: (List String) -> (List String)
  (listAppend (cons (str "SERVED_STOP_PID=" (stringFromInt64 (procSelf))) (listAppend (match cache ((some c) (list (str "ASL_NATIVE_CLI_CACHE=" c))) ((none) (list))) extra))
    (filter (fn [(row String)] -> Bool (not (or (stringStartsWith? row "ASL_HOST=") (or (stringStartsWith? row "SERVED_STOP_PID=") (or (stringStartsWith? row "ASL_NATIVE_CLI_WAIT=") (and (some? cache) (stringStartsWith? row "ASL_NATIVE_CLI_CACHE="))))))) (run/childEnv (list))))

fn ! binAsl! root: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str root "/bin/asl") args) root env) (run/limits 1500 64))

fn ! binAslAt! path: String root: String args: (List String) env: (List String) -> run/Done
  (run/runOneLimited (run/job (cons (str path "/bin/asl") args) root env) (run/limits 1500 64))

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 120 8))

fn ! nativeBuild! root: String cache: String -> run/Done
  (run/runOneLimited
    (run/job (list (str root "/asl/host/out/aslNativeBuild") root cache "--lock-owner" "99999999") root
      (run/childEnv (list "ASL_NATIVE_CLI_TIMEOUT=2")))
    (run/limits 10000 16))

fn ! headOf cache: String root: String -> String
  (stringTrim (resultOr (fileReadString (nc/headPath cache root)) ""))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (shared (str root "/.asl/cache/binAslStale/shared-" (stringFromInt64 (procSelf))))
        (warm (binAsl! root (list "test" (probe)) (envFor (some shared) (list "ASL_NATIVE_CLI_WAIT=1"))))
        (built (headOf shared root))
        (builtFresh (nc/fresh? root built))
        (clangBefore (resultOr (fileReadString (str built "/clang-version")) ""))
        (builderStamp (str root "/asl/host/out/aslNativeBuild-fresh"))
        (builderVersion (resultOr (fileReadString (str builderStamp "/clang-version")) ""))
        (cache (str root "/.asl/cache/binAslStale/" (stringFromInt64 (procSelf))))
        (copy (str cache "/cli-staleCopy"))
        (badCopy (str cache "/badProbe/cli-broken"))
        (linked (sh! root (list "/bin/sh" "-c" "rm -rf \"$1\" && mkdir -p \"$1\" && cp -R \"$2\" \"$3\" && for d in \"$0\"/seed-* \"$0\"/asl1-* \"$0\"/cli-*; do ln -s \"$d\" \"$1/\"; done" shared cache built copy)))
        (badLinked (sh! root (list "/bin/sh" "-c" "mkdir -p \"$(dirname \"$1\")\" && cp -R \"$2\" \"$1\"" "" badCopy built)))
        (badBin (sh! root (list "/bin/sh" "-c" "printf '#!/bin/sh\\nexit 77\\n' > \"$1\" && chmod +x \"$1\"" "" (str badCopy "/bin"))))
        (badProbed (nc/probe? root badCopy))
        (wrongVersion (fileWrite (str copy "/clang-version") "not the installed clang\n"))
        (versionRejected (not (nc/fresh? root copy)))
        (versionRestored (fileWrite (str copy "/clang-version") clangBefore))
        (builderVersionChanged (fileWrite (str builderStamp "/clang-version") "not the installed clang\n"))
        (builderStale (not (nc/fresh? root builderStamp)))
        (builderVersionRestored (fileWrite (str builderStamp "/clang-version") builderVersion))
        (deadOwnerCache (str cache "/deadOwner"))
        (deadOwnerBuild (nativeBuild! root deadOwnerCache))
        (waitLock (str cache "/waitDeadOwner/lock"))
        (waitLockCreated (dirCreate waitLock))
        (waitPid (fileWrite (str waitLock "/pid") (str (stringFromInt64 (procSelf)) "\n")))
        (waitOwner (fileWrite (str waitLock "/owner") "99999999\n"))
        (deadOwnerWait (binAsl! root (list "test" (passSuite)) (envFor (some (str cache "/waitDeadOwner")) (list "ASL_NATIVE_CLI_WAIT=1"))))
        (edited (match (fileReadString (str copy "/src/" (tampered)))
                  ((err e) (err e))
                  ((ok text) (fileWrite (str copy "/src/" (tampered)) (str text "\n(:m :why \"an edit the cached binary predates\")\n")))))
        (pointed (fileWrite (nc/headPath cache root) (str copy "\n")))
        (staleLock (str cache "/lock"))
        (staleLockCreated (dirCreate staleLock))
        (staleLockPid (fileWrite (str staleLock "/pid") (str (stringFromInt64 (procSelf)) "\n")))
        (staleLockOwner (fileWrite (str staleLock "/owner") (str (stringFromInt64 (procSelf)) "\n")))
        (stale (binAsl! root (list "test" (passSuite)) (envFor (some cache) (list "ASL_NATIVE_BUILD_WAIT=1"))))
        (staleLockCleared (pathRemove staleLock))
        (rebuilt (binAsl! root (list "test" (probe)) (envFor (some cache) (list "ASL_NATIVE_CLI_WAIT=1"))))
        (after (headOf cache root))
        (symlink (str cache "/workspace-link"))
        (linkedRoot (sh! root (list "/bin/ln" "-s" root symlink)))
        (viaLink (binAslAt! symlink root (list "test" (probe)) (envFor (some shared) (list "ASL_NATIVE_CLI_WAIT=1"))))
        (cleaned (sh! root (list "/bin/rm" "-rf" cache shared)))]
    (do (assert (= warm.exit 0) (str "the shared cache serves the probe natively: " warm.out))
        (assert builtFresh (str "the shared head names a binary built from this tree: " built))
        (assert (= linked.exit 0) (str "the stale copy was made: " linked.out))
        (assert (= badLinked.exit 0) "the broken-binary copy was made")
        (assert (= badBin.exit 0) "the broken binary was written in place of the real one")
        (refute badProbed "a binary that doesn't behave like asl-cli fails its external self-probe")
        (assert (ok? wrongVersion) "the cached clang version was changed")
        (assert versionRejected "a toolchain version mismatch makes the native CLI stale")
        (assert (ok? versionRestored) "the cached clang version was restored")
        (assert (nc/fresh? root builderStamp) "the out/aslNativeBuild copy has a current source and clang snapshot")
        (assert (ok? builderVersionChanged) "the build-cache clang version was changed")
        (assert builderStale "out/aslNativeBuild is stale when its clang version changes")
        (assert (ok? builderVersionRestored) "the build-cache clang version was restored")
        (assert (= deadOwnerBuild.exit 1) (str "a detached build exits when its lock owner is gone: " deadOwnerBuild.out))
        (assert (ok? waitLockCreated) "the simulated detached build lock was created")
        (assert (ok? waitPid) "the simulated lock has a live builder pid")
        (assert (ok? waitOwner) "the simulated lock has a dead owner pid")
        (assert (= deadOwnerWait.exit 0) (str "a command behind an orphaned build lock still answers: " deadOwnerWait.out))
        (assert (stringContains? deadOwnerWait.out "passTest.asl: 1 assertion(s) executed, 1 refutation(s) executed (2 passed)") (str "a dead lock owner is cleared and a fresh build served the suite instead of waiting out the deadline: " deadOwnerWait.out))
        (assert (ok? edited) (str "the copy's snapshot of " (tampered) " was edited"))
        (assert (ok? pointed) "the test cache's head names the stale copy")
        (refute (nc/fresh? root copy) "the copy no longer matches the tree")
        (assert (ok? staleLockCreated) "the blocking build lock was created")
        (assert (ok? staleLockPid) "the blocking lock names a live builder pid (this test process)")
        (assert (ok? staleLockOwner) "the blocking lock names a live owner pid (this test process)")
        (assert (= stale.exit 2) (str "a stale native CLI behind a held build lock, with a short ASL_NATIVE_BUILD_WAIT, fails loudly instead of running: " stale.out))
        (assert (stringContains? stale.out "ERR_NATIVE_STALE") (str "the stale-CLI failure is reported as ERR_NATIVE_STALE: " stale.out))
        (refute (stringContains? stale.out "passTest.asl: ") (str "the stale binary never ran the verb's own test logic: " stale.out))
        (assert (ok? staleLockCleared) "the blocking build lock was cleared for the next (real) rebuild")
        (assert (= rebuilt.exit 0) (str "after the rebuild the probe is served natively: " rebuilt.out))
        (assert (stringContains? rebuilt.out "servedProbe.asl: 4 assertion(s) executed, 1 refutation(s) executed") "the rebuilt native binary ran the probe")
        (assert (and (!= after copy) (= (listLast (stringSplit after "/")) (listLast (stringSplit built "/")))) (str "the rebuild pointed the head back at the binary of this tree: " after))
        (assert (= linkedRoot.exit 0) "a logical workspace alias was created")
        (assert (= viaLink.exit 0) (str "the native head is found through a logical workspace path: " viaLink.out))
        (assert (stringContains? viaLink.out "servedProbe.asl: 4 assertion(s) executed") "the canonical head served through the logical path")
        (assert (= cleaned.exit 0) "the test cache was removed")
        true))
