(module aslAgent/tests/gitOpsScratchTest
  :x [runTests]
  :i [(aslAgent/gitOps :a go) (asl-tools/fleet/run :a fr)])

; (:m :ref VCSDIRECT-AGENT-MIGRATE :do "scratchTree! over a temp repo with an uncommitted tracked edit and an untracked file: a detached worktree at HEAD carries both and is a recorded worktree of the repo; scratchDrop! removes it even when it holds an untracked file and leaves no worktree record")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/gitOpsScratchTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! gitIn dir: String args: (List String) -> String
  (stringTrim (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).out)

fn ! readAt dir: String name: String -> String
  (resultOr (fileReadString (str dir "/" name)) "<absent>")

fn ! runTests -> Bool
  (let [(fx (scratch))
        (sc (str fx "-scratch"))
        (mk (sh "." (list "mkdir" "-p" fx)))
        (_ (gitIn fx (list "init" "-q" "-b" "main")))
        (w1 (ok? (fileWrite (str fx "/a.txt") "1\n")))
        (_ (gitIn fx (list "add" "-A")))
        (_ (gitIn fx (list "commit" "-q" "-m" "c0")))
        (w2 (and (ok? (fileWrite (str fx "/a.txt") "2\n")) (ok? (fileWrite (str fx "/u.txt") "untracked\n"))))
        (t (go/scratchTree! fx sc))
        (kind (match t ((ok k) k) ((err e) e)))
        (a1 (readAt sc "a.txt"))
        (u1 (readAt sc "u.txt"))
        (listed (gitIn fx (list "worktree" "list" "--porcelain")))
        (d1 (ok? (fileWrite (str sc "/dirty.txt") "d\n")))
        (dropped (go/scratchDrop! fx sc kind))
        (gone (not (fileExists? sc)))
        (listedAfter (gitIn fx (list "worktree" "list" "--porcelain")))
        (_ (pathRemove fx))
        (_ (pathRemove sc))]
    (do (assert (and (= mk.exit 0) w1 w2) "fixture repo with a tracked edit and an untracked file")
        (assert (= kind "worktree") (str "scratchTree! made a worktree, not a copy: " kind))
        (assert (and (= a1 "2\n") (= u1 "untracked\n")) (str "the scratch carries the uncommitted tracked edit and the untracked file: " a1 u1))
        (assert (stringContains? listed "detached") "the scratch is a detached worktree recorded in the repo")
        (assert (and d1 dropped gone) "scratchDrop! removes the scratch even with an untracked file inside")
        (assert (not (stringContains? listedAfter "detached")) (str "and leaves no worktree record: " listedAfter))
        true))
