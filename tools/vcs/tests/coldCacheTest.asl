(module asl/tools/vcs/tests/coldCacheTest
  :x [runTests]
  :i [(asl-tools/vcs/vcs :a v) (asl-tools/fleet/run :a fr) (asl-tools/coord/commitGuard :a cg)])

; (:m :ref WORKTREE-COLD-CACHE :do "a cold native cache must not refuse a good commit: a stub asl binary that needs 4 s on its first call (a build) and is fast afterwards, with a 2 s per-file deadline, lands only through the warm-up check; the given tool tree's binary runs with the commit worktree as cwd, so a fresh worktree of this repo with no host build commits a new module and its importer")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/coldCacheTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 120 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> fr/Done
  (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args))

fn goodMsg -> String
  "(:c :a fixture :do \"a clean change\" :g \"gate\" :ev (WORKTREE-COLD-CACHE))\n"

fn ! repoAt base: String name: String -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/scripts/audit"))).exit 0) (str name ": dir"))
        (assert (= (git dir (list "init" "-q" "-b" "main")).exit 0) (str name ": init"))
        (assert (put (str dir "/scripts/audit/foreignBaseline.asn") "(:foreignBaseline :v 1\n)\n") (str name ": baseline"))
        (assert (put (str dir "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 2\n  :commitGuardWarmS 30\n)\n") (str name ": config"))
        (assert (= (git dir (list "add" "-A")).exit 0) (str name ": add"))
        (assert (= (git dir (list "commit" "-q" "-m" "base")).exit 0) (str name ": base commit"))
        dir))

fn ! stubTool! base: String name: String -> String
  (let [(dir (str base "/" name))
        (body "#!/bin/sh\nD=\"$(dirname \"$0\")\"\nif [ ! -e \"$D/warm\" ]; then sleep 4; : > \"$D/warm\"; fi\nshift\nfor a in \"$@\"; do echo \"ok $a:\"; done\n")]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/bin"))).exit 0) (str name ": dir"))
        (assert (put (str dir "/bin/asl") body) (str name ": body"))
        (assert (= (sh "." (list "chmod" "+x" (str dir "/bin/asl"))).exit 0) (str name ": exec"))
        dir))

fn ! head dir: String -> String
  (stringTrim (git dir (list "rev-parse" "HEAD")).out)

fn goodAsl -> String
  "(module fx/good\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"

fn ! stubCase! base: String -> Bool
  (let [(tool (stubTool! base "tool"))
        (repo (repoAt base "stub"))
        (_a (put (str repo "/good.asl") (goodAsl)))
        (h0 (head repo))
        (r (v/commitWith! repo repo tool (list "good.asl") (goodMsg) "commit"))]
    (do (assert (= r.code 0) (str "a cold stub toolchain lands the commit through the warm-up check: " r.text))
        (assert (!= (head repo) h0) "HEAD moved")
        (assert (stringContains? r.text ":status :done") (str "the commit is :done: " r.text))
        (assert (stringContains? r.text ":unchecked ()") (str "no file was left unchecked: " r.text))
        true))

fn ! deadCase! base: String -> Bool
  (let [(tool (str base "/deadTool"))
        (mk (sh "." (list "mkdir" "-p" (str tool "/bin"))))
        (_a (put (str tool "/bin/asl") "#!/bin/sh\nexit 0\n"))
        (_b (sh "." (list "chmod" "+x" (str tool "/bin/asl"))))
        (repo (repoAt base "dead"))
        (_c (put (str repo "/good.asl") (goodAsl)))
        (h0 (head repo))
        (r (v/commitWith! repo repo tool (list "good.asl") (goodMsg) "commit"))]
    (do (assert (= r.code 1) (str "a toolchain that gives no verdict refuses, never passes silently: " r.text))
        (assert (stringContains? r.text "toolchain warm-up failed") (str "the refusal names the warm-up cause: " r.text))
        (assert (= (head repo) h0) "HEAD unchanged")
        true))

fn ! realCase! root: String base: String -> Bool
  (let [(wt (str base "/freshWt"))
        (mk (sh root (list "git" "worktree" "add" "-q" "--detach" wt "HEAD")))
        (_cfg (put (str wt "/.asl.config.asn") (stringReplace (resultOr (fileReadString (str wt "/.asl.config.asn")) "") "(:aslConfig" "(:aslConfig\n  :commitGuardPerFileS 900\n  :commitGuardTotalS 1800")))
        (_d (sh "." (list "mkdir" "-p" (str wt "/asl/tools/zzCold"))))
        (_a (put (str wt "/asl/tools/zzCold/zzLib.asl") "(module asl-tools/zzCold/zzLib\n  :x [one]\n  :i [])\n\nfn one -> Int64\n  1\n"))
        (_b (put (str wt "/asl/tools/zzCold/zzUse.asl") "(module asl-tools/zzCold/zzUse\n  :x [two]\n  :i [(asl-tools/zzCold/zzLib :a z)])\n\nfn two -> Int64\n  (+ (z/one) 1)\n"))
        (h0 (head wt))
        (r (v/commitWith! wt wt root (list "asl/tools/zzCold/zzLib.asl" "asl/tools/zzCold/zzUse.asl") (goodMsg) "commit"))
        (moved (!= (head wt) h0))
        (shown (stringTrim (git wt (list "show" "--name-only" "--format=" "HEAD")).out))
        (rm (sh root (list "git" "worktree" "remove" "--force" wt)))]
    (do (assert (= rm.exit 0) "fresh worktree removed")
        (assert (= mk.exit 0) (str "fresh worktree of this repo: " mk.out))
        (assert (= r.code 0) (str "a new module and its importer land in a fresh worktree with no host build: " r.text))
        (assert moved "the worktree HEAD moved")
        (assert (= shown "asl/tools/zzCold/zzLib.asl\nasl/tools/zzCold/zzUse.asl") "exactly the two modules are committed")
        true))

; (:m :ref COMMIT-GUARD-IN-PLACE :do "a staged file equal to its working-tree file is checked in the repo (cwd and ASL_ROOT = the repo, the file path under the repo, no workspace export); a partly staged file is checked from the export of its staged blob; the export dir is gone after the guard; a stale export dir older than an hour is swept and a fresh one is left")
fn logStub! base: String name: String -> String
  (let [(dir (str base "/" name))
        (body "#!/bin/sh\nD=\"$(dirname \"$0\")\"\necho \"cwd=$PWD root=$ASL_ROOT args=$*\" >> \"$D/calls.log\"\nshift\nfor a in \"$@\"; do echo \"ok $a:\"; done\n")]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/bin"))).exit 0) (str name ": dir"))
        (assert (put (str dir "/bin/asl") body) (str name ": body"))
        (assert (= (sh "." (list "chmod" "+x" (str dir "/bin/asl"))).exit 0) (str name ": exec"))
        dir))

fn exportBase base: String -> String
  (str base "/exports")

fn ! exportDirs! base: String -> (List String)
  (filter (fn [(l String)] -> Bool (and (not (stringEmpty? l)) (not (stringContains? l "keepme"))))
          (stringLines (sh "." (list "find" (exportBase base) "-maxdepth" "1" "(" "-name" (str "commitGuard-" (stringFromInt64 (procSelf)) "-*") "-o" "-name" "*.lock" ")")).out))

fn ! inPlaceCases! base: String -> Bool
  (let [(foreign (logStub! base "logTool"))
        (repo (repoAt base "inplace"))
        (_s (logStub! base "inplace"))
        (_cfg (put (str repo "/.asl.config.asn") (str "(:aslConfig\n  :commitGuardExportDir \"" (exportBase base) "\"\n)\n")))
        (logP (str repo "/bin/calls.log"))
        (_cc (git repo (list "add" ".asl.config.asn")))
        (_cd (git repo (list "commit" "-q" "-m" "cfg")))
        (_a (put (str repo "/ip.asl") (goodAsl)))
        (r1 (v/commit! repo repo (list "ip.asl") (goodMsg) "commit"))
        (log1 (resultOr (fileReadString logP) ""))
        (_g (put (str repo "/fo.asl") (goodAsl)))
        (_b (put (str repo "/part.asl") (goodAsl)))
        (r2 (v/commitWith! repo repo foreign (list "fo.asl") (goodMsg) "commit"))
        (logF (resultOr (fileReadString (str foreign "/bin/calls.log")) ""))
        (_c (git repo (list "add" "part.asl")))
        (_d (put (str repo "/part.asl") (str (goodAsl) "; edited after staging\n")))
        (old (str (exportBase base) "/commitGuard-999999-1"))
        (live (str (exportBase base) "/commitGuard-" (stringFromInt64 (procSelf)) "-keepme"))
        (fresh (str (exportBase base) "/commitGuard-stale-fresh"))
        (_e (sh "." (list "mkdir" "-p" old fresh live)))
        (_f (sh "." (list "touch" "-t" "202001010000" old live)))
        (j3 (cg/guardIndex! repo repo (list "part.asl") (goodMsg) true ""))
        (log3 (resultOr (fileReadString logP) ""))]
    (do (assert (= r1.code 0) (str "an in-place commit lands: " r1.text))
        (assert (stringContains? log1 (str "cwd=" repo)) (str "the check ran with the repo as cwd: " log1))
        (assert (stringContains? log1 (str "root=" repo)) "and the repo as ASL_ROOT")
        (assert (stringContains? log1 (str "args=check " repo "/ip.asl")) (str "on the file where it lies: " log1))
        (assert (= r2.code 0) (str "a commit checked by another tree's binary lands: " r2.text))
        (assert (stringContains? logF "/commitGuard-") (str "another tree's binary checks the export, never the file in place: " logF))
        (assert (stringContains? logF (str "cwd=" repo)) "with the repo as workspace")
        (assert (not (stringContains? log3 (str "args=check " repo "/part.asl"))) (str "a partly staged file is not checked in place: " log3))
        (assert (stringContains? log3 "part.asl") "but it is checked, from the export of the staged blob")
        (assert (listEmpty? (exportDirs! base)) (str "no unique export dir and no lock is left after the guard: " (stringJoin (exportDirs! base) ",")))
        (assert (not (fileExists? old)) "a dead-pid export dir older than an hour is swept")
        (assert (fileExists? live) "a live owner's old export dir is not swept")
        (assert (= (sh "." (list "rm" "-rf" live)).exit 0) "live dir removed")
        (assert (fileExists? fresh) "a fresh export dir is left alone")
        (assert (= (sh "." (list "rm" "-rf" fresh)).exit 0) "fresh dir removed")
        true))

; (:m :ref COMMIT-GUARD-STABLE-EXPORT :do "the export is reused: slot 0 is the export dir of a run, a dead owner's lock is taken over, four held locks fall back to a unique dir, a stale file the index no longer has is pruned; an untracked module in the working tree sends an otherwise in-place path to the export; without :commitGuardExportDir a stale dead-pid dir in the shared temp dir is never swept")
fn ! stableCases! base: String -> Bool
  (let [(eb (exportBase base))
        (repo (repoAt base "stable"))
        (_s (logStub! base "stable"))
        (logP (str repo "/bin/calls.log"))
        (_cfg (put (str repo "/.asl.config.asn") (str "(:aslConfig\n  :commitGuardExportDir \"" eb "\"\n)\n")))
        (_a (put (str repo "/base1.asl") (goodAsl)))
        (_b (git repo (list "add" "base1.asl" ".asl.config.asn")))
        (_c (git repo (list "commit" "-q" "-m" "b1")))
        (_d (sh "." (list "mkdir" "-p" (str eb "/commitGuard-ws-0") (str eb "/commitGuard-ws-0.lock"))))
        (_e (put (str eb "/commitGuard-ws-0.lock/pid") "999999"))
        (_f (put (str eb "/commitGuard-ws-0/gone.asl") (goodAsl)))
        (_g (put (str repo "/x1.asl") (goodAsl)))
        (_h (put (str repo "/zzUntracked.asl") (goodAsl)))
        (_h2 (git repo (list "add" "x1.asl")))
        (j1 (cg/guardIndex! repo repo (list "x1.asl") (goodMsg) true ""))
        (log1 (resultOr (fileReadString logP) ""))
        (pruned (not (fileExists? (str eb "/commitGuard-ws-0/gone.asl"))))
        (_j (fileWrite logP ""))
        (_l (put (str repo "/x2.asl") (str (goodAsl) ";2\n")))
        (_m (git repo (list "add" "x2.asl")))
        (_n (sh "." (list "rm" "-f" (str repo "/zzUntracked.asl"))))
        (j2 (cg/guardIndex! repo repo (list "x2.asl") (goodMsg) true ""))
        (log2 (resultOr (fileReadString logP) ""))
        (_o (fileWrite logP ""))
        (_p (sh "." (list "mkdir" "-p" (str eb "/commitGuard-ws-0.lock") (str eb "/commitGuard-ws-1.lock") (str eb "/commitGuard-ws-2.lock") (str eb "/commitGuard-ws-3.lock"))))
        (_q (put (str eb "/commitGuard-ws-0.lock/pid") (stringFromInt64 (procSelf))))
        (_r (put (str eb "/commitGuard-ws-1.lock/pid") (stringFromInt64 (procSelf))))
        (_t (put (str eb "/commitGuard-ws-2.lock/pid") (stringFromInt64 (procSelf))))
        (_u (put (str eb "/commitGuard-ws-3.lock/pid") (stringFromInt64 (procSelf))))
        (_v (put (str repo "/x3.asl") (str (goodAsl) ";3\n")))
        (_w (git repo (list "add" "x3.asl")))
        (j3 (cg/guardIndex! repo repo (list "x3.asl") (goodMsg) true ""))
        (log3 (resultOr (fileReadString logP) ""))
        (_x (sh "." (list "rm" "-rf" (str eb "/commitGuard-ws-0.lock") (str eb "/commitGuard-ws-1.lock") (str eb "/commitGuard-ws-2.lock") (str eb "/commitGuard-ws-3.lock"))))
        (shared (str (optionOr (envGet "TMPDIR") "/tmp") "/commitGuard-999998-1"))
        (_y (sh "." (list "mkdir" "-p" shared)))
        (_z (sh "." (list "touch" "-t" "202001010000" shared)))
        (foreign (logStub! base "noCfgTool"))
        (_aa (put (str repo "/x4.asl") (str (goodAsl) ";4\n")))
        (_ab (git repo (list "add" "x4.asl")))
        (j4 (cg/guardIndex! repo foreign (list "x4.asl") (goodMsg) true ""))
        (survives (fileExists? shared))
        (_ac (sh "." (list "rm" "-rf" shared)))]
    (do (assert (stringContains? log1 (str eb "/commitGuard-ws-0/")) (str "a dead owner's lock is taken over and slot 0 is the export: " log1))
        (assert (not (stringContains? log1 (str "args=check " repo "/x1.asl"))) "an untracked module in the working tree sends the path to the export, never in place")
        (assert (stringContains? log2 (str "args=check " repo "/x2.asl")) (str "with the working tree clean the path is checked in place: " log2))
        (assert pruned "a file the index no longer has is pruned from the reused export")
        (assert (not (stringContains? log3 "/commitGuard-ws-")) (str "four held locks fall back to a unique dir: " log3))
        (assert (stringContains? log3 "/commitGuard-") "and the check still ran from an export")
        (assert survives "without :commitGuardExportDir a stale dir in the shared temp dir is never swept")
        true))

; (:m :ref COMMIT-GUARD-STABLE-EXPORT :do "the production deadlines hold: a first fresh worktree warms the shared export slot under large deadlines (a cold checker cache costs minutes once), then a second fresh worktree at another path lands the same no-op edits of asl-agent main.asl and conductor.asl under the default deadlines because the export slot is reused and its checks hit the cache")
fn ! realMain! root: String base: String -> Bool
  (let [(wa (str base "/mainWtA"))
        (mkA (sh root (list "git" "worktree" "add" "-q" "--detach" wa "HEAD")))
        (_cfgA (put (str wa "/.asl.config.asn") (stringReplace (resultOr (fileReadString (str wa "/.asl.config.asn")) "") "(:aslConfig" (str "(:aslConfig\n  :commitGuardExportDir \"" base "/realExports\"\n  :commitGuardPerFileS 900\n  :commitGuardTotalS 1800"))))
        (f1 "asl/packages/asl-agent/src/main.asl")
        (f2 "asl/tools/coord/conductor.asl")
        (_a1 (put (str wa "/" f1) (str (resultOr (fileReadString (str wa "/" f1)) "") "\n")))
        (_a2 (put (str wa "/" f2) (str (resultOr (fileReadString (str wa "/" f2)) "") "\n")))
        (rA (v/commitWith! wa wa root (list f1 f2) (goodMsg) "commit"))
        (wb (str base "/mainWtB"))
        (mkB (sh root (list "git" "worktree" "add" "-q" "--detach" wb "HEAD")))
        (_cfgB (put (str wb "/.asl.config.asn") (stringReplace (resultOr (fileReadString (str wb "/.asl.config.asn")) "") "(:aslConfig" (str "(:aslConfig\n  :commitGuardExportDir \"" base "/realExports\""))))
        (_b1 (put (str wb "/" f1) (str (resultOr (fileReadString (str wb "/" f1)) "") "\n")))
        (t1 (/ (monotonicNs) 1000000))
        (r1 (v/commitWith! wb wb root (list f1) (goodMsg) "commit"))
        (m1 (- (/ (monotonicNs) 1000000) t1))
        (_b2 (put (str wb "/" f2) (str (resultOr (fileReadString (str wb "/" f2)) "") "\n")))
        (t2 (/ (monotonicNs) 1000000))
        (r2 (v/commitWith! wb wb root (list f2) (goodMsg) "commit"))
        (m2 (- (/ (monotonicNs) 1000000) t2))
        (_c (put (str wb "/asl/tools/zzBadImp.asl") "(module asl-tools/zzBadImp\n  :x []\n  :i [(nope/missingModule :a m)])\n"))
        (r3 (v/commitWith! wb wb root (list "asl/tools/zzBadImp.asl") (goodMsg) "commit"))
        (rmA (sh root (list "git" "worktree" "remove" "--force" wa)))
        (rmB (sh root (list "git" "worktree" "remove" "--force" wb)))]
    (do (assert (and (= rmA.exit 0) (= rmB.exit 0)) "worktrees removed")
        (assert (and (= mkA.exit 0) (= mkB.exit 0)) (str "fresh worktrees: " mkA.out mkB.out))
        (assert (= rA.code 0) (str "the warming commit lands under large deadlines: " rA.text))
        (assert (= r1.code 0) (str "a no-op edit of asl-agent main.asl lands in a second fresh worktree at the default deadlines (" (stringFromInt64 m1) " ms): " r1.text))
        (assert (= r2.code 0) (str "a no-op edit of conductor.asl lands at the default deadlines (" (stringFromInt64 m2) " ms): " r2.text))
        (assert (= r3.code 1) (str "a real unresolved import still blocks: " r3.text))
        true))

; (:m :ref COMMIT-GUARD-STABLE-EXPORT :do "slot lock rules: a lock of a live owner is held; a dead owner's is taken over; a lock with no owner is held while younger than a minute and taken over after; a live takeover mutex blocks a takeover, a stale one does not")
fn ! lockCases! base: String -> Bool
  (let [(d (str base "/locks"))
        (_a (sh "." (list "mkdir" "-p" d)))
        (live (str d "/live.lock"))
        (_b (sh "." (list "mkdir" "-p" live)))
        (_c (put (str live "/pid") (stringFromInt64 (procSelf))))
        (heldLive (cg/tryLock! live))
        (dead (str d "/dead.lock"))
        (_d (sh "." (list "mkdir" "-p" dead)))
        (_e (put (str dead "/pid") "999999"))
        (takenDead (cg/tryLock! dead))
        (ownerNow (stringTrim (resultOr (fileReadString (str dead "/pid")) "")))
        (noOwner (str d "/noOwner.lock"))
        (_f (sh "." (list "mkdir" "-p" noOwner)))
        (youngNo (cg/tryLock! noOwner))
        (_g (sh "." (list "touch" "-t" "202001010000" noOwner)))
        (oldNo (cg/tryLock! noOwner))
        (blk (str d "/blk.lock"))
        (_h (sh "." (list "mkdir" "-p" blk (str blk ".take"))))
        (_i (put (str blk "/pid") "999999"))
        (mutexHeld (cg/tryLock! blk))
        (_j (sh "." (list "touch" "-t" "202001010000" (str blk ".take"))))
        (mutexStale (cg/tryLock! blk))
        (free (not (fileExists? (str blk ".take"))))]
    (do (assert (not heldLive) "a lock owned by a live pid is held")
        (assert (and takenDead (= ownerNow (stringFromInt64 (procSelf)))) "a dead owner's lock is taken over and now names this process")
        (assert (not youngNo) "a fresh lock without an owner is held")
        (assert oldNo "a lock without an owner older than a minute is taken over")
        (assert (not mutexHeld) "a live takeover mutex blocks a second taker")
        (assert (and mutexStale free) "a stale takeover mutex is cleared and the takeover succeeds, the mutex released after")
        true))

; (:m :ref COMMIT-GUARD-STABLE-EXPORT :do "a test run removes only the private bases of dead runs (coldCacheTest-PID-NS, PID not alive) and the worktrees under them by explicit path; a live run's base is never touched and no global worktree prune runs")
fn ! staleBases! root: String -> Bool
  (let [(tmp (optionOr (envGet "TMPDIR") "/tmp"))
        (found (sh "." (list "find" tmp "-maxdepth" "1" "-name" "coldCacheTest-*")))
        (dirs (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines found.out)))]
    (fold (fn [(acc Bool) (d String)] -> Bool (and acc (staleBase! root d))) true dirs))

fn ! staleBase! root: String dir: String -> Bool
  (let [(name (optionOr (listLast (stringSplit dir "/")) dir))
        (pid (optionOr (listGet (stringSplit name "-") 1) ""))]
    (match (stringToInt64 pid)
      ((none) true)
      ((some n)
        (if (= (sh "." (list "kill" "-0" pid)).exit 0)
          true
          (let [(wts (map (fn [(w String)] -> Bool (or (not (fileExists? (str dir "/" w))) (= (sh root (list "git" "worktree" "remove" "--force" (str dir "/" w))).exit 0))) (list "freshWt" "mainWtA" "mainWtB")))]
            (= (sh "." (list "rm" "-rf" dir)).exit 0))))))

fn ! staleCases! root: String -> Bool
  (let [(tmp (optionOr (envGet "TMPDIR") "/tmp"))
        (dead (str tmp "/coldCacheTest-999999-1"))
        (live (str tmp "/coldCacheTest-" (stringFromInt64 (procSelf)) "-1"))
        (_a (sh "." (list "mkdir" "-p" dead live)))
        (r (staleBases! root))
        (deadGone (not (fileExists? dead)))
        (liveKept (fileExists? live))
        (_b (sh "." (list "rm" "-rf" live)))]
    (do (assert r "the sweep of dead runs succeeds")
        (assert deadGone "a dead run's base is removed")
        (assert liveKept "a live run's base is never touched")
        true))

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (staleBases! root) "bases of dead runs removed with their worktrees")
        (assert (staleCases! root) "stale sweep only touches dead runs")
        (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (stubCase! base) "stub cold toolchain")
        (assert (deadCase! base) "a toolchain with no verdict")
        (assert (realCase! root base) "fresh worktree with the warm tree's binary")
        (assert (inPlaceCases! base) "in place and export")
        (assert (stableCases! base) "stable export")
        (assert (lockCases! base) "slot lock rules")
        (assert (realMain! root base) "the audit probe files")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))
