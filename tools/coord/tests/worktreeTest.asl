(module asl/tools/coord/tests/worktreeTest
  :x [runTests]
  :i [(asl-tools/coord/worktree :a w) (asl-tools/fleet/run :a fr)])

fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/worktreeTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 120 16))

fn ! git dir: String args: (List String) -> Bool
  (= (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).exit 0)

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! gitOut dir: String args: (List String) -> String
  (stringTrim (sh dir (cons "git" args)).out)

fn ! cfgOf root: String -> w/Cfg
  (w/Cfg :repo (str root "/repo") :base (str root "/wts") :prefix "asex-" :archive (str root "/archive") :mainRef "main")

fn ! fixture root: String -> Bool
  (let [(repo (str root "/repo"))]
    (and (= (sh "." (list "mkdir" "-p" repo)).exit 0)
      (and (git repo (list "init" "-q" "-b" "main"))
        (and (put (str repo "/data.txt") "1\n")
          (and (put (str repo "/.gitignore") "out/\n")
            (and (git repo (list "add" "-A"))
              (git repo (list "commit" "-q" "-m" "base"))))))))

fn ! resText r: (Result String String) -> String
  (match r ((ok s) s) ((err e) (str "ERR " e)))

fn ! unitsOf cfg: w/Cfg -> (List String)
  (match (w/listWt! cfg) ((ok ws) (map (fn [(x w/Wt)] -> String x.unit) ws)) ((err e) (list (str "ERR " e))))

fn ! wtOf cfg: w/Cfg unit: String -> (Option w/Wt)
  (match (w/listWt! cfg) ((ok ws) (listHead (filter (fn [(x w/Wt)] -> Bool (= x.unit unit)) ws))) ((err _) (none)))

fn ! testPure -> Bool
  (do (assert (w/safeUnit? "FKWT-1.a") "plain unit names are safe")
      (assert (not (w/safeUnit? "../x")) "dot segments are unsafe")
      (assert (not (w/safeUnit? "a b")) "spaces are unsafe")
      (assert (not (w/safeUnit? "-rf")) "a leading dash is unsafe")
      (assert (not (w/safeUnit? "")) "empty is unsafe")
      (let [(es (w/parseWorktrees "worktree /a\nHEAD abc\nbranch refs/heads/main\n\nworktree /b\nHEAD def\ndetached\n"))]
        (do (assert (= (listLength es) 2) "two porcelain blocks parsed")
            (assert (= (map (fn [(e w/Entry)] -> String e.branch) es) (list "main" "")) "branch parsed without refs/heads")
            (assert (= (map (fn [(e w/Entry)] -> Bool e.detached) es) (list false true)) "detached parsed")
            true)))

fn ! testLifecycle root: String -> Bool
  (let [(cfg (cfgOf root))
        (repo (str root "/repo"))]
    (do
      (assert (match (w/addWt! cfg "u1" "") ((ok _) true) ((err e) false)) "add u1")
      (assert (= (gitOut repo (list "rev-parse" "--abbrev-ref" "sh/u1")) "sh/u1") "add makes branch sh/UNIT")
      (assert (match (w/addWt! cfg "u1" "") ((ok _) false) ((err _) true)) "adding an existing unit is refused")
      (assert (match (w/addWt! cfg "../evil" "") ((ok _) false) ((err _) true)) "an unsafe unit is refused")
      (assert (put (str root "/wts/asex-u1/out.txt") "x") "scratch file")
      (assert (= (sh "." (list "mkdir" "-p" (str root "/wts/asex-u1/out"))).exit 0) "ignored dir")
      (assert (put (str root "/wts/asex-u1/out/b.o") "obj") "ignored file")
      (assert (match (wtOf cfg "u1") ((some x) (and (= x.dirty 1) (and (= x.ignored 1) x.merged))) ((none) false)) "u1 lists dirty 1 (out.txt), ignored 1, merged")
      (assert (= (sh "." (list "rm" (str root "/wts/asex-u1/out.txt"))).exit 0) "u1 made clean")
      (assert (stringContains? (resText (w/removeWt! cfg "u1" false)) "wtRemoved") "merged clean worktree is removed, ignored output does not block")
      (assert (not (fileExists? (str root "/wts/asex-u1"))) "u1 path gone")
      (assert (match (w/addWt! cfg "u2" "") ((ok _) true) ((err _) false)) "add u2")
      (assert (put (str root "/wts/asex-u2/new.txt") "n") "u2 file")
      (assert (git (str root "/wts/asex-u2") (list "add" "-A")) "u2 add")
      (assert (git (str root "/wts/asex-u2") (list "commit" "-q" "-m" "u2 work")) "u2 commit")
      (assert (stringContains? (resText (w/removeWt! cfg "u2" false)) "unmerged") "unmerged clean worktree is kept")
      (assert (fileExists? (str root "/wts/asex-u2")) "u2 still there")
      (assert (match (w/addWt! cfg "u3" "") ((ok _) true) ((err _) false)) "add u3")
      (assert (put (str root "/wts/asex-u3/data.txt") "changed\n") "u3 tracked change")
      (assert (put (str root "/wts/asex-u3/loose.txt") "loose\n") "u3 untracked")
      (assert (put (str root "/wts/asex-u3/odd\nname.txt") "odd\n") "u3 untracked name with a newline")
      (assert (stringContains? (resText (w/removeWt! cfg "u3" false)) "dirty") "dirty worktree is kept without force")
      (assert (fileExists? (str root "/wts/asex-u3/loose.txt")) "u3 untouched")
      (let [(r (resText (w/removeWt! cfg "u3" true)))]
        (do (assert (stringContains? r "wtRemoved") (str "forced removal: " r))
            (assert (not (fileExists? (str root "/wts/asex-u3"))) "u3 path gone after force")
            (let [(files (resultOr (dirList (str root "/archive")) (list)))
                  (diffName (optionOr (listHead (filter (fn [(n String)] -> Bool (stringEndsWith? n ".diff")) files)) ""))
                  (tarName (optionOr (listHead (filter (fn [(n String)] -> Bool (stringEndsWith? n ".tar")) files)) ""))
                  (tarList (sh "." (list "tar" "-tf" (str root "/archive/" tarName))))
                  (diffText (resultOr (fileReadString (str root "/archive/" diffName)) ""))
                  (arch (str diffText tarList.out))]
              (do (assert (stringContains? arch "+changed") "archive holds the tracked diff")
                  (assert (stringContains? arch "loose.txt") "archive holds the untracked file")
                  (assert (stringContains? arch "odd\\nname.txt") "archive holds an untracked name with a newline")
                  true))))
      (assert (match (w/addWt! cfg "u4" "") ((ok _) true) ((err _) false)) "add u4")
      (assert (git (str root "/wts/asex-u4") (list "checkout" "-q" "--detach")) "u4 detached")
      (assert (put (str root "/wts/asex-u4/d.txt") "d") "u4 file")
      (assert (git (str root "/wts/asex-u4") (list "add" "-A")) "u4 add")
      (assert (git (str root "/wts/asex-u4") (list "commit" "-q" "-m" "detached work")) "u4 commit")
      (let [(head (gitOut (str root "/wts/asex-u4") (list "rev-parse" "HEAD")))
            (r (resText (w/removeWt! cfg "u4" false)))
            (rescued (gitOut repo (list "branch" "--list" "rescue/u4-*" "--format=%(objectname)")))]
        (do (assert (stringContains? r "unmerged") (str "detached unmerged head is kept: " r))
            (assert (= rescued head) "a rescue branch points at the detached head")
            (assert (stringContains? (resText (w/removeWt! cfg "u4" true)) "rescue") "forced removal reports the rescue branch")
            (assert (not (fileExists? (str root "/wts/asex-u4"))) "u4 path gone")
            (assert (= (gitOut repo (list "branch" "--list" "rescue/u4-*" "--format=%(objectname)")) head) "the rescue branch survives removal")
            true))
      (assert (git repo (list "worktree" "add" "-q" "--detach" (str root "/wts/vtbotfeature") "main")) "foreign worktree")
      (assert (= (unitsOf cfg) (list "u2")) (str "list shows only prefixed units: " (stringJoin (unitsOf cfg) ",")))
      (assert (match (w/removeWt! cfg "vtbotfeature" true) ((ok _) false) ((err _) true)) "a foreign worktree cannot be removed")
      (assert (fileExists? (str root "/wts/vtbotfeature")) "foreign worktree intact")
      true))

fn ! runTests -> Bool
  (let [(root (scratch))]
    (do (assert (fixture root) "fixture repository built")
        (assert (testPure) "pure helpers")
        (assert (testLifecycle root) "lifecycle")
        (assert (= (sh "." (list "rm" "-rf" root)).exit 0) "fixture removed")
        true))
