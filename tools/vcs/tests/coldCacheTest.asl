(module asl/tools/vcs/tests/coldCacheTest
  :x [runTests]
  :i [(asl-tools/vcs/vcs :a v) (asl-tools/fleet/run :a fr)])

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

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (stubCase! base) "stub cold toolchain")
        (assert (deadCase! base) "a toolchain with no verdict")
        (assert (realCase! root base) "fresh worktree with the warm tree's binary")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))
