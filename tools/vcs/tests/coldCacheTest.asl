(module asl/tools/vcs/tests/coldCacheTest
  :x [runTests]
  :i [(asl-tools/vcs/vcs :a v) (asl-tools/fleet/run :a fr) (asl-tools/coord/commitGuard :a cg)])

; (:m :ref WORKTREE-COLD-CACHE :do "a cold native cache must not refuse a good commit: a stub asl binary that needs 4 s on its first call (a build) and is fast afterwards, with a 2 s per-file deadline, lands only through the warm-up check; the given tool tree's binary runs with the commit worktree as cwd, so a fresh worktree of this repo with no host build commits a new module and its importer")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/coldCacheTest-" (stringFromInt64 (procSelf)))

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
        (r (v/commitWith! wt wt root (list "asl/tools/zzCold/zzLib.asl" "asl/tools/zzCold/zzUse.asl") (goodMsg) "commit"))]
    (do (assert (= mk.exit 0) (str "fresh worktree of this repo: " mk.out))
        (assert (= r.code 0) (str "a new module and its importer land in a fresh worktree with no host build: " r.text))
        (assert (!= (head wt) h0) "the worktree HEAD moved")
        (assert (= (stringTrim (git wt (list "show" "--name-only" "--format=" "HEAD")).out) "asl/tools/zzCold/zzLib.asl\nasl/tools/zzCold/zzUse.asl") "exactly the two modules are committed")
        (assert (= (sh root (list "git" "worktree" "remove" "--force" wt)).exit 0) "fresh worktree removed")
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
  (filter (fn [(l String)] -> Bool (not (stringEmpty? l)))
          (stringLines (sh "." (list "find" (exportBase base) "-maxdepth" "1" "-name" (str "commitGuard-" (stringFromInt64 (procSelf)) "-*"))).out))

fn ! inPlaceCases! base: String -> Bool
  (let [(foreign (logStub! base "logTool"))
        (repo (repoAt base "inplace"))
        (_s (logStub! base "inplace"))
        (_cfg (put (str repo "/.asl.config.asn") (str "(:aslConfig\n  :commitGuardExportDir \"" (exportBase base) "\"\n)\n")))
        (logP (str repo "/bin/calls.log"))
        (_a (put (str repo "/ip.asl") (goodAsl)))
        (_b (put (str repo "/part.asl") (goodAsl)))
        (r1 (v/commit! repo repo (list "ip.asl") (goodMsg) "commit"))
        (log1 (resultOr (fileReadString logP) ""))
        (_g (put (str repo "/fo.asl") (goodAsl)))
        (r2 (v/commitWith! repo repo foreign (list "fo.asl") (goodMsg) "commit"))
        (logF (resultOr (fileReadString (str foreign "/bin/calls.log")) ""))
        (_c (git repo (list "add" "part.asl")))
        (_d (put (str repo "/part.asl") (str (goodAsl) "; edited after staging\n")))
        (old (str (exportBase base) "/commitGuard-stale-old"))
        (fresh (str (exportBase base) "/commitGuard-stale-fresh"))
        (_e (sh "." (list "mkdir" "-p" old fresh)))
        (_f (sh "." (list "touch" "-t" "202001010000" old)))
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
        (assert (listEmpty? (exportDirs! base)) (str "the export dir is gone after the guard: " (stringJoin (exportDirs! base) ",")))
        (assert (not (fileExists? old)) "a stale export dir older than an hour is swept")
        (assert (fileExists? fresh) "a fresh export dir is left alone")
        (assert (= (sh "." (list "rm" "-rf" fresh)).exit 0) "fresh dir removed")
        true))

fn ! realMain! root: String base: String -> Bool
  (let [(wt (str base "/mainWt"))
        (mk (sh root (list "git" "worktree" "add" "-q" "--detach" wt "HEAD")))
        (_cfg (put (str wt "/.asl.config.asn") (stringReplace (resultOr (fileReadString (str wt "/.asl.config.asn")) "") "(:aslConfig" "(:aslConfig\n  :commitGuardPerFileS 900\n  :commitGuardTotalS 1800")))
        (f1 "asl/packages/asl-agent/src/main.asl")
        (f2 "asl/tools/coord/conductor.asl")
        (_a (put (str wt "/" f1) (str (resultOr (fileReadString (str wt "/" f1)) "") "\n")))
        (t1 (/ (monotonicNs) 1000000))
        (r1 (v/commitWith! wt wt root (list f1) (goodMsg) "commit"))
        (m1 (- (/ (monotonicNs) 1000000) t1))
        (_b (put (str wt "/" f2) (str (resultOr (fileReadString (str wt "/" f2)) "") "\n")))
        (t2 (/ (monotonicNs) 1000000))
        (r2 (v/commitWith! wt wt root (list f2) (goodMsg) "commit"))
        (m2 (- (/ (monotonicNs) 1000000) t2))
        (_c (put (str wt "/asl/tools/zzBadImp.asl") "(module asl-tools/zzBadImp\n  :x []\n  :i [(nope/missingModule :a m)])\n"))
        (r3 (v/commitWith! wt wt root (list "asl/tools/zzBadImp.asl") (goodMsg) "commit"))]
    (do (assert (= mk.exit 0) (str "fresh worktree: " mk.out))
        (assert (= r1.code 0) (str "a no-op edit of asl-agent main.asl lands in a fresh worktree (" (stringFromInt64 m1) " ms): " r1.text))
        (assert (= r2.code 0) (str "a no-op edit of conductor.asl lands (" (stringFromInt64 m2) " ms): " r2.text))
        (assert (= r3.code 1) (str "a real unresolved import still blocks: " r3.text))
        (assert (= (sh root (list "git" "worktree" "remove" "--force" wt)).exit 0) "worktree removed")
        true))

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (stubCase! base) "stub cold toolchain")
        (assert (deadCase! base) "a toolchain with no verdict")
        (assert (realCase! root base) "fresh worktree with the warm tree's binary")
        (assert (inPlaceCases! base) "in place and export")
        (assert (realMain! root base) "the audit probe files")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))
