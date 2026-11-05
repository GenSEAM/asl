(module asl/tools/vcs/tests/vcsTest
  :x [runTests]
  :i [(asl-tools/vcs/vcs :a v) (asl-tools/fleet/run :a fr)])

; (:m :ref VCS-LAYER-CORE :do "the vcs layer over temp repos: a commit with an unbalanced file, a partial check (slow stub as asl binary), an empty or widening path list refuse and leave HEAD; a good file commits exactly the named path even with another file staged; a repo-level core.hooksPath hook that writes a marker does not run; stage never touches unnamed paths")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> fr/Done
  (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args))

fn goodAsl -> String
  "(module fx/good\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"

fn goodMsg -> String
  "(:c :a fixture :do \"a clean change\" :g \"gate\" :ev (VCS-LAYER-CORE))\n"

fn ! repoAt base: String name: String -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/scripts/audit"))).exit 0) (str name ": dir"))
        (assert (= (git dir (list "init" "-q" "-b" "main")).exit 0) (str name ": init"))
        (assert (put (str dir "/scripts/audit/foreignBaseline.asn") "(:foreignBaseline :v 1\n)\n") (str name ": baseline"))
        (assert (= (git dir (list "add" "-A")).exit 0) (str name ": add"))
        (assert (= (git dir (list "commit" "-q" "-m" "base")).exit 0) (str name ": base commit"))
        dir))

fn ! head dir: String -> String
  (stringTrim (git dir (list "rev-parse" "HEAD")).out)

fn ! committed dir: String -> String
  (stringTrim (git dir (list "show" "--name-only" "--format=" "HEAD")).out)

fn ! stubRoot! base: String name: String body: String -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/bin"))).exit 0) (str name ": stub dir"))
        (assert (put (str dir "/bin/asl") body) (str name ": stub body"))
        (assert (= (sh "." (list "chmod" "+x" (str dir "/bin/asl"))).exit 0) (str name ": stub exec"))
        (assert (put (str dir "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 1\n)\n") (str name ": stub config"))
        dir))

fn ! scenarios root: String base: String -> Bool
  (let [(slow (stubRoot! base "slowRoot" "#!/bin/sh\nsleep 20\n"))
        (r1 (repoAt base "bad"))
        (_a (put (str r1 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (h1 (head r1))
        (o1 (v/commit! r1 root (list "bad.asl") (goodMsg) "commit"))
        (r2 (repoAt base "slow"))
        (_b (put (str r2 "/good.asl") (goodAsl)))
        (h2 (head r2))
        (o2 (v/commit! r2 slow (list "good.asl") (goodMsg) "commit"))
        (r3 (repoAt base "empty"))
        (h3 (head r3))
        (o3 (v/commit! r3 root (list) (goodMsg) "commit"))
        (o3b (v/commit! r3 root (list ".") (goodMsg) "commit"))
        (o3c (v/stage! r3 (list)))
        (r4 (repoAt base "good"))
        (_c (put (str r4 "/good.asl") (goodAsl)))
        (_d (put (str r4 "/other.asl") "(module fx/other\n"))
        (_e (git r4 (list "add" "other.asl")))
        (_f0 (sh "." (list "mkdir" "-p" (str r4 "/hooks"))))
        (_f (put (str r4 "/hooks/pre-commit") "#!/bin/sh\ntouch hookRan\n"))
        (_g (sh r4 (list "chmod" "+x" "hooks/pre-commit")))
        (_h (git r4 (list "config" "core.hooksPath" (str r4 "/hooks"))))
        (_n (put (str r4 "/stray.txt") "stray\n"))
        (h4 (head r4))
        (o4 (v/commit! r4 root (list "good.asl") (goodMsg) "commit"))
        (st4 (v/status! r4 (list)))
        (r5 (repoAt base "ctl"))
        (_i (sh "." (list "mkdir" "-p" (str r5 "/hooks"))))
        (_j (put (str r5 "/hooks/pre-commit") "#!/bin/sh\ntouch hookRan\n"))
        (_k (sh r5 (list "chmod" "+x" "hooks/pre-commit")))
        (_l (put (str r5 "/x.txt") "x\n"))
        (_m (git r5 (list "add" "x.txt")))
        (ctl (git r5 (list "-c" (str "core.hooksPath=" r5 "/hooks") "commit" "-q" "-m" "x")))]
    (do
      (assert (= o1.code 1) (str "an unbalanced file refuses: " o1.text))
      (assert (stringContains? o1.text ":status :refused") "refused status")
      (assert (stringContains? o1.text ":rule :balance") "the guard row names balance")
      (assert (= (head r1) h1) "HEAD unchanged after the balance refusal")
      (assert (= o2.code 1) (str "a partial check refuses: " o2.text))
      (assert (stringContains? o2.text ":unchecked (\"good.asl\")") "the unchecked file is named")
      (assert (= (head r2) h2) "HEAD unchanged after the partial refusal")
      (assert (= o3.code 1) "an empty path list refuses")
      (assert (stringContains? o3.text "no paths named") "and says why")
      (assert (= o3b.code 1) "the whole-tree path . refuses")
      (assert (= o3c.code 1) "stage with no paths refuses")
      (assert (= (head r3) h3) "HEAD unchanged after empty and widening refusals")
      (assert (= o4.code 0) (str "a good named file commits: " o4.text))
      (assert (stringContains? o4.text ":status :done :sha ") "done with a sha")
      (assert (!= (head r4) h4) "HEAD moved")
      (assert (= (committed r4) "good.asl") (str "exactly the named path is committed: " (committed r4)))
      (assert (and (= ctl.exit 0) (fileExists? (str r5 "/hookRan"))) "control: the same hook does run under a plain git commit")
      (assert (fileExists? (str r4 "/hooks/pre-commit")) "the hook file exists in the guarded repo")
      (assert (not (fileExists? (str r4 "/hookRan"))) "the repo-level hooksPath hook did not run")
      (assert (stringContains? st4.text "other.asl") "the unnamed staged file stays out of the commit")
      (assert (stringContains? st4.text "?? stray.txt") (str "an unnamed untracked file is never staged: " st4.text))
      true))

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (scenarios root base) "scenarios")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))
