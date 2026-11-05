(module asl-cli/tests/vcsCmdTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref VCS-CLI-ENTRY :do "asl vcs through the real bin/asl over temp repos: an unbalanced staged file exits 1 with a refused receipt and HEAD unchanged, a good file exits 0 with a sha and exactly the named path, no paths or no message or an unknown op exit 2, status and head exit 0")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsCmdTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 240 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> fr/Done
  (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args))

fn goodAsl -> String
  "(module fx/good\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"

fn goodMsg -> String
  "(:c :a fixture :do \"a clean change\" :g \"gate\" :ev (VCS-CLI-ENTRY))"

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

fn ! vcs root: String args: (List String) -> fr/Done
  (sh root (cons (str root "/bin/asl") (cons "vcs" args)))

fn ! vcsIn dir: String root: String args: (List String) -> fr/Done
  (sh dir (cons (str root "/bin/asl") (cons "vcs" args)))

fn ! scenarios root: String base: String -> Bool
  (let [(r1 (repoAt base "bad"))
        (_a (put (str r1 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (h1 (head r1))
        (o1 (vcs root (list "commit" "--repo" r1 "--asl-root" root "--msg" (goodMsg) "--" "bad.asl")))
        (r2 (repoAt base "good"))
        (_b (put (str r2 "/good.asl") (goodAsl)))
        (_c (put (str r2 "/stray.txt") "stray\n"))
        (h2 (head r2))
        (o2 (vcs root (list "commit" "--repo" r2 "--asl-root" root "--msg" (goodMsg) "--" "good.asl")))
        (o3 (vcs root (list "commit" "--repo" r2 "--asl-root" root "--msg" (goodMsg))))
        (o4 (vcs root (list "commit" "--repo" r2 "--asl-root" root "--" "good.asl")))
        (o5 (vcs root (list "frobnicate")))
        (o6 (vcs root (list "status" "--repo" r2)))
        (o7 (vcs root (list "head" "--repo" r2)))
        (d1 (vcsIn r2 root (list "diff" "HEAD~1" "HEAD")))
        (d2 (vcs root (list "diff" "--repo" r2 "HEAD~1" "HEAD")))
        (d3 (vcs root (list "diff" "HEAD~1" "HEAD" "--repo" r2)))
        (l1 (vcsIn r2 root (list "log" "HEAD~1..HEAD")))
        (l2 (vcs root (list "log" "--repo" r2 "HEAD~1..HEAD")))
        (r4 (repoAt base "warned"))
        (_w (put (str r4 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (w1 (vcs root (list "commit" "--repo" r4 "--asl-root" root "--warn" "--msg" (goodMsg) "--" "bad.asl")))
        (wlog (resultOr (fileReadString (str r4 "/.asl/log/commitGuard.asn")) ""))
        (r3 (repoAt base "noRoot"))
        (_d (put (str r3 "/g.asl") (goodAsl)))
        (o8 (vcs root (list "commit" "--repo" r3 "--msg" (goodMsg) "--" "g.asl")))]
    (do
      (assert (= o1.exit 1) (str "an unbalanced staged file exits 1: " o1.exit " " o1.out))
      (assert (stringContains? o1.out ":status :refused") (str "the receipt says refused: " o1.out))
      (assert (= (head r1) h1) "HEAD unchanged after the refusal")
      (assert (= o2.exit 0) (str "a good file exits 0: " o2.exit " " o2.out))
      (assert (stringContains? o2.out ":sha ") "the receipt carries a sha")
      (assert (!= (head r2) h2) "HEAD moved")
      (assert (= (committed r2) "good.asl") "exactly the named path is committed")
      (assert (= o3.exit 2) (str "no paths exits 2: " o3.out))
      (assert (= o4.exit 2) "no message exits 2")
      (assert (= o5.exit 2) "an unknown op exits 2")
      (assert (= o6.exit 0) (str "status exits 0: " o6.out))
      (assert (stringContains? o6.out "?? stray.txt") "status lists the stray file")
      (assert (and (= o7.exit 0) (stringContains? o7.out (head r2))) "head prints the sha")
      (assert (and (= d1.exit 0) (stringContains? d1.out "good.asl")) (str "diff HEAD~1 HEAD with the injected root: " d1.exit " " d1.out))
      (assert (and (= d2.exit 0) (stringContains? d2.out "good.asl")) (str "diff with --repo before the refs: " d2.out))
      (assert (and (= d3.exit 0) (stringContains? d3.out "good.asl")) (str "diff with --repo after the refs: " d3.out))
      (assert (and (= l1.exit 0) (stringContains? l1.out "fixture")) (str "log HEAD~1..HEAD: " l1.exit " " l1.out))
      (assert (and (= l2.exit 0) (stringContains? l2.out "fixture")) (str "log with --repo before the range: " l2.out))
      (assert (and (= w1.exit 0) (stringContains? w1.out ":status :warned")) (str "--warn commits and says warned: " w1.out))
      (assert (stringContains? wlog ":rule :balance") (str "--warn records the blocking rows: " wlog))
      (assert (= o8.exit 0) (str "without --asl-root the CLI passes its own root, no env needed: " o8.out))
      true))

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (scenarios root base) "scenarios")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))
