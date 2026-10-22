(module asl-cli/nativeBuildStickyFailTest :x [runTests] :i [(asl/packages/asl-cli/src/nativeBuild :a nb) (asl/packages/asl-cli/src/system :a sys) (asl-tools/fleet/run :a run)])

; (:m :ref NATIVECLI-STICKY-FAIL-20261018 :do "an owner-gone/deadline/timeout/runaway/spawnFailed build or link attempt never ran the compiler to completion, so it is never a real diagnostic; compile!'s .failed marker must be written only for a message carrying a d.verdict=exit result (failure()'s 'exited N: ...' shape). transientFailure? is the predicate guarding that write, checked both in isolation and at compile!'s own caching decision site: a real Build whose build step runs to completion (exit 0) but whose link step then observes its owner already dead must leave no .failed marker. the owner's death is caused synchronously by the fake compiler itself (it kills the owner pid and polls kill -0 until that pid is confirmed gone before it exits), not raced against a sleep or a deadline, so the outcome does not depend on host load; only the marker's presence/absence and the error text are asserted, never a duration")

fn ! sh! root: String argv: (List String) -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits 30 8))

; (:m :ref NATIVECLI-STICKY-FAIL-20261018 :do "the owner is a real background process, detached from this job's own stdio so the job runner sees its spawning job finish normally, which also means run.asl's own timeout/descendant tracking never sees the owner (judge! only ever acts on a job still open when it polls, and this spawning job exits on its own well before any poll). bounded to 20s, well past what killOwner! or the fake compiler need, so a leak from an unforeseen early abort is capped rather than open-ended; killOwner! below is called as a plain let-binding, not inside the assert chain, so it runs unconditionally before any assert can abort the function, on top of the fake compiler's own kill on the success path")
fn ! spawnOwner! root: String -> run/Done
  (sh! root (list "/bin/sh" "-c" "sleep 20 </dev/null >/dev/null 2>&1 & echo $!"))

fn ! killOwner! root: String ownerPid: String -> run/Done
  (sh! root (list "/bin/sh" "-c" "kill -9 \"$1\" 2>/dev/null; true" "" ownerPid))

fn ownerKillCompilerScript ownerPid: String -> String
  (stringJoin (list
    "#!/bin/sh"
    "if [ \"$1\" = deps ]; then exit 0; fi"
    (str "kill -9 " ownerPid " 2>/dev/null")
    (str "while kill -0 " ownerPid " 2>/dev/null; do sleep 0.05; done")
    "printf 'ok\\n' > \"$4\""
    "exit 0"
    "") "\n")

fn alwaysFailBuildScript -> String
  (stringJoin (list
    "#!/bin/sh"
    "if [ \"$1\" = deps ]; then exit 0; fi"
    "exit 1"
    "") "\n")

fn markerFile entries: (List String) name: String -> (Option String)
  (listHead (filter (fn [(n String)] -> Bool (and (stringStartsWith? n (str name "-")) (stringEndsWith? n ".failed"))) entries))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/nativeBuildStickyFailTest." (stringFromInt64 (procSelf))))
        (made (dirCreate work))
        (ownerSpawned (spawnOwner! root))
        (ownerPid (stringTrim ownerSpawned.out))
        (compilerPath (str work "/fakeCompiler.sh"))
        (wrote (fileWrite compilerPath (ownerKillCompilerScript ownerPid)))
        (chmodded (sh! root (list "/bin/chmod" "+x" compilerPath)))
        (dir (str work "/stickyFail-dir"))
        (marker (str dir ".failed"))
        (b (nb/Build :root root :cache work :tmp work :lib (str root "/asl/host/out/libaslrt.a") :base "" :clangVersion ""
                     :owner ownerPid :deadlineNs (+ (monotonicNs) 300000000000) :maxDesc 16))
        (result (nb/compile! b "stickyFail" compilerPath "t" "dummyEntry.asl" dir (list) "k1"))
        (markerAfter (sys/isFile? marker))
        (ownerCleanup (killOwner! root ownerPid))
        (cleaned (pathRemove work))
        ; (:m :ref NATIVECLI-STICKY-FAIL-20261018 :do "a second scenario, entirely deterministic (no sleep/deadline), proves stage!'s read side self-heals a .failed marker whose stored text is itself transient-shaped: a real marker is first earned by a compiler that deterministically exits 1, its text is then overwritten with an old, transient-shaped sentinel (simulating a marker written before this fix, or by a stale production run), and a second stage! call must discard that sentinel rather than replay it")
        (work2 (str root "/.asl/cache/nativeBuildStickyFailTest2." (stringFromInt64 (procSelf))))
        (made2 (dirCreate work2))
        (name2 "stageSelfHeal")
        (entry2 "asl/prelude/prelude.asl")
        (compilerPath2 (str work2 "/alwaysFailBuild.sh"))
        (wrote2 (fileWrite compilerPath2 (alwaysFailBuildScript)))
        (chmodded2 (sh! root (list "/bin/chmod" "+x" compilerPath2)))
        (b2 (nb/Build :root root :cache work2 :tmp work2 :lib (str root "/asl/host/out/libaslrt.a") :base "" :clangVersion ""
                      :owner "" :deadlineNs (+ (monotonicNs) 300000000000) :maxDesc 16))
        (firstResult (nb/stage! b2 name2 compilerPath2 "t" entry2 (list)))
        (entries (resultOr (dirList work2) (list)))
        (markerName (markerFile entries name2))
        (markerPath2 (match markerName ((some n) (str work2 "/" n)) ((none) "")))
        (firstMarkerText (if (stringEmpty? markerPath2) "" (stringTrim (resultOr (fileReadString markerPath2) ""))))
        ; (:m :ref NATIVECLI-STICKY-FAIL-20261018 :do "the sentinel is the exact text of the real incident marker this unit was filed for (main's asl1 marker, owner-gone, 2026-10-16), not a synthetic stand-in, so this scenario proves the fix against the actual production shape; the path's leading /<home>/ is built from this run's own HOME rather than the capturing developer's literal username (PUBLIC-BOUNDARY-20261019), the rest of the tail is unchanged")
        (sentinel (str "clang -c of the parts of " (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli/tmp.75849/asl1.ll did not run: owner-gone"))
        (seeded (if (stringEmpty? markerPath2) (err "no marker found after the first deterministic failure") (fileWrite markerPath2 (str sentinel "\n"))))
        (secondResult (nb/stage! b2 name2 compilerPath2 "t" entry2 (list)))
        (secondMarkerText (if (stringEmpty? markerPath2) "" (stringTrim (resultOr (fileReadString markerPath2) ""))))
        (cleaned2 (pathRemove work2))]
    (do
        (assert (nb/transientFailure? "clang -c of the parts of /tmp/x.ll did not run: owner-gone")
                "owner-gone (compileParts!, build step short-circuited) is transient")
        (assert (nb/transientFailure? "clang -c of the parts of /tmp/x.ll did not run: deadline")
                "deadline (compileParts!, build step short-circuited) is transient")
        (assert (nb/transientFailure? "clang link of /tmp/x.ll was killed: timeout")
                "timeout (failure(), a real run/Done verdict) is transient")
        (assert (nb/transientFailure? "clang link of /tmp/x.ll was killed: runaway")
                "runaway (failure(), descendant-count limit) is transient")
        (assert (nb/transientFailure? "clang link of /tmp/x.ll was killed: spawnFailed")
                "spawnFailed (failure(), procSpawnv itself failed) is transient")
        (assert (nb/transientFailure? "clang -c of /tmp/x.ll.part0.ll was killed: owner-gone")
                "owner-gone via failure() on a single compileParts! job is transient")
        (refute (nb/transientFailure? "clang -c of /tmp/x.ll.part0.ll exited 1: undefined symbol _foo")
                "a real clang exit-1 diagnostic is not transient")
        (refute (nb/transientFailure? "clang link of /tmp/x.ll exited 1: duplicate symbol _main")
                "a real link exit-1 diagnostic is not transient")
        (refute (nb/transientFailure? "asl1 build asl/packages/asl-cli/src/native.asl exited 2: ERR_TYPE_MISMATCH operand of + expected Int64, found String")
                "a real asl1 build diagnostic (the build step's own nonzero exit) is not transient")
        (assert (ok? made) (str "the work directory " work " was created"))
        (assert (= ownerSpawned.exit 0) "a real, independently-killable owner process was spawned")
        (assert (> (optionOr (stringToInt64 ownerPid) 0) 1) (str "the owner's pid was captured: " ownerPid))
        (assert (ok? wrote) "the fake compiler script was written")
        (assert (= chmodded.exit 0) "the fake compiler script was made executable")
        (assert (match result ((ok _) false) ((err e) (stringContains? e "was killed: owner-gone")))
                (str "compile! on a build that finishes (exit 0) after itself killing the owner, then links once the owner is confirmed dead, reports the link step killed by owner-gone: " (match result ((ok v) v) ((err e) e))))
        (refute markerAfter
                (str "compile!'s caching decision site (the failed closure guarded by transientFailure?) must not cache an owner-gone-killed link as a .failed marker at " marker))
        (assert (= ownerCleanup.exit 0) "the owner was killed unconditionally as a plain binding, independent of whether the fake compiler's own kill already ran")
        (assert (ok? cleaned) "the work directory was removed")
        (assert (ok? made2) (str "the second work directory " work2 " was created"))
        (assert (ok? wrote2) "the always-fail compiler script was written")
        (assert (= chmodded2.exit 0) "the always-fail compiler script was made executable")
        (assert (match firstResult ((ok _) false) ((err e) (stringContains? e "exited 1")))
                (str "a build step that deterministically exits 1 is cached as a real failure: " (match firstResult ((ok v) v) ((err e) e))))
        (assert (some? markerName) (str "a .failed marker was written next to " work2 " for the deterministic failure"))
        (assert (stringContains? firstMarkerText "exited 1") (str "the marker's own text carries the real exit-1 diagnostic: " firstMarkerText))
        (assert (ok? seeded) "the marker was overwritten with the real incident's transient-shaped sentinel, simulating one written before this fix")
        (assert (match secondResult ((ok _) false) ((err e) (not (stringContains? e "did not run: owner-gone"))))
                (str "stage! must not replay a stale marker whose own stored text is transient-shaped: " (match secondResult ((ok v) v) ((err e) e))))
        (assert (match secondResult ((ok _) false) ((err e) (stringContains? e "exited 1")))
                (str "ignoring the stale sentinel, stage! reran the build and reported its own fresh (deterministic) failure: " (match secondResult ((ok v) v) ((err e) e))))
        (refute (stringContains? secondMarkerText "did not run: owner-gone")
                (str "the on-disk marker itself was cleared of the real incident's sentinel, not just ignored in memory: " secondMarkerText))
        (assert (ok? cleaned2) "the second work directory was removed")
        true))
