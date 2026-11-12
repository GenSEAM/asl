(module asl/tools/vcs/tests/vcsSwitchTest
  :x [runTests]
  :i [(asl-tools/vcs/git :a gb) (asl-tools/fleet/run :a fr)])

; (:m :ref VCS-DIRECT :do "gb/switch! over a temp repo with two commits: creates a branch at a base that is not HEAD, resets an existing branch to another base, re-checks out a branch where it is, refuses an empty or option-like name and an unknown base without moving anything")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsSwitchTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! git dir: String args: (List String) -> String
  (stringTrim (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).out)

fn ! repoAt dir: String -> Bool
  (let [(_ (sh "." (list "rm" "-rf" dir)))
        (mk (sh "." (list "mkdir" "-p" dir)))
        (_ (git dir (list "init" "-q" "-b" "main")))
        (a (fileWrite (str dir "/a.txt") "0\n"))
        (_ (git dir (list "add" "-A")))
        (_ (git dir (list "commit" "-q" "-m" "c0")))
        (b (fileWrite (str dir "/a.txt") "1\n"))
        (_ (git dir (list "commit" "-q" "-a" "-m" "c1")))]
    (and (= mk.exit 0) (and (ok? a) (ok? b))))

fn ! runTests -> Bool
  (let [(dir (scratch))
        (made (repoAt dir))
        (c0 (git dir (list "rev-parse" "main~1")))
        (c1 (git dir (list "rev-parse" "main")))
        (s1 (gb/switch! dir "feat" "main~1"))
        (cur1 (git dir (list "branch" "--show-current")))
        (feat1 (git dir (list "rev-parse" "feat")))
        (file1 (resultOr (fileReadString (str dir "/a.txt")) ""))
        (s2 (gb/switch! dir "feat" "main"))
        (feat2 (git dir (list "rev-parse" "feat")))
        (s3 (gb/switch! dir "main" "main"))
        (cur3 (git dir (list "branch" "--show-current")))
        (main3 (git dir (list "rev-parse" "main")))
        (e1 (gb/switch! dir "" "main"))
        (e2 (gb/switch! dir "-x" "main"))
        (e3 (gb/switch! dir "other" "noSuchRef"))
        (curE (git dir (list "branch" "--show-current")))
        (other (git dir (list "branch" "--list" "other")))
        (_ (sh "." (list "rm" "-rf" dir)))]
    (do (assert (and made (and (not (stringEmpty? c0)) (!= c0 c1))) "fixture: a repo with two commits on main")
        (assert (and (= s1.exit 0) (and (= cur1 "feat") (and (= feat1 c0) (= file1 "0\n")))) (str "switch! creates feat at main~1 and checks it out: " s1.out " " cur1 " " feat1))
        (assert (and (= s2.exit 0) (= feat2 c1)) (str "switch! resets an existing branch to a new base: " s2.out " " feat2))
        (assert (and (= s3.exit 0) (and (= cur3 "main") (= main3 c1))) (str "switch! with base = name checks the branch out where it is: " s3.out " " cur3))
        (assert (and (= e1.exit 1) (stringContains? e1.out "not accepted")) (str "an empty branch name is refused: " e1.out))
        (assert (and (= e2.exit 1) (stringContains? e2.out "not accepted")) (str "an option-like branch name is refused: " e2.out))
        (assert (and (= e3.exit 1) (and (stringContains? e3.out "unknown base noSuchRef") (and (= curE "main") (stringEmpty? other)))) (str "an unknown base is an error and creates nothing: " e3.out " " other))
        true))
