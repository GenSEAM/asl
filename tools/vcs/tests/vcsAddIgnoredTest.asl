(module asl/tools/vcs/tests/vcsAddIgnoredTest
  :x [runTests]
  :i [(asl-tools/vcs/git :a gb) (asl-tools/fleet/run :a fr)])

; (:m :ref VCS-ADD-TRACKED-IGNORED :do "prepare! over a temp repo whose .gitignore covers cache/: a file already in HEAD under cache/ lands in the private index and the commit carries its new content, a file under cache/ that HEAD does not hold is still refused as ignored, and a normal file is unaffected")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsAddIgnoredTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! git dir: String args: (List String) -> String
  (stringTrim (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).out)

fn ! repoAt dir: String -> Bool
  (let [(_ (sh "." (list "rm" "-rf" dir)))
        (mk (sh "." (list "mkdir" "-p" (str dir "/cache"))))
        (_ (git dir (list "init" "-q" "-b" "main")))
        (a (fileWrite (str dir "/.gitignore") "cache/\n"))
        (b (fileWrite (str dir "/cache/t.txt") "0\n"))
        (c (fileWrite (str dir "/n.txt") "0\n"))
        (_ (git dir (list "add" "-A")))
        (_ (git dir (list "add" "-f" "cache/t.txt")))
        (_ (git dir (list "commit" "-q" "-m" "c0")))]
    (and (= mk.exit 0) (and (ok? a) (and (ok? b) (ok? c)))))

fn ! testAdd -> Bool
  (let [(dir (scratch))
        (made (repoAt dir))
        (held (git dir (list "ls-tree" "-r" "--name-only" "HEAD")))
        (_ (fileWrite (str dir "/cache/t.txt") "1\n"))
        (_ (fileWrite (str dir "/cache/u.txt") "new\n"))
        (_ (fileWrite (str dir "/n.txt") "1\n"))
        (tx1 (gb/prepare! dir (list "cache/t.txt")))
        (fin (if tx1.ok (gb/finish! dir tx1 "tracked ignored" (list "cache/t.txt")) (gb/Out :exit 1 :out tx1.why)))
        (shown (git dir (list "show" "HEAD:cache/t.txt")))
        (tx2 (gb/prepare! dir (list "cache/u.txt")))
        (tx3 (gb/prepare! dir (list "n.txt" "cache/t.txt")))
        (_ (if tx1.ok (gb/discard! tx1) false))
        (_ (if tx2.ok (gb/discard! tx2) (gb/discard! tx2)))
        (_ (if tx3.ok (gb/discard! tx3) false))
        (_ (sh "." (list "rm" "-rf" dir)))]
    (do (assert (and made (stringContains? held "cache/t.txt")) (str "fixture: cache/t.txt is tracked while cache/ is ignored: " held))
        (assert tx1.ok (str "a tracked file under an ignored dir lands in the private index: " tx1.why))
        (assert (and (= fin.exit 0) (= shown "1")) (str "and the commit carries its new content: " fin.out " " shown))
        (assert (and (not tx2.ok) (stringContains? tx2.why "ignored")) (str "an untracked ignored path is still refused: " tx2.ok " " tx2.why))
        (assert tx3.ok (str "a normal file beside a tracked ignored one lands: " tx3.why))
        true))

; (:m :ref VCS-COMMIT-IGNORED-DELETE :do "a path of HEAD that the shared index no longer holds (git rm --cached, the file stays on disk and is ignored) is committed as a deletion; an untracked ignored path beside it is still refused")
fn ! testStagedDelete -> Bool
  (let [(dir (str (scratch) "-del"))
        (made (repoAt dir))
        (_ (git dir (list "rm" "-q" "--cached" "cache/t.txt")))
        (_ (fileWrite (str dir "/cache/u.txt") "new\n"))
        (tx (gb/prepare! dir (list "cache/t.txt")))
        (fin (if tx.ok (gb/finish! dir tx "untrack" (list "cache/t.txt")) (gb/Out :exit 1 :out tx.why)))
        (held (git dir (list "ls-tree" "-r" "--name-only" "HEAD")))
        (onDisk (fileExists? (str dir "/cache/t.txt")))
        (bad (gb/prepare! dir (list "cache/u.txt")))
        (_ (if tx.ok (gb/discard! tx) false))
        (_ (gb/discard! bad))
        (_ (sh "." (list "rm" "-rf" dir)))]
    (do (assert made "fixture built")
        (assert tx.ok (str "a staged deletion of an ignored path is accepted: " tx.why))
        (assert (and (= fin.exit 0) (not (stringContains? held "cache/t.txt")) onDisk) (str "the commit deletes it from HEAD and the file stays on disk: " fin.out " " held))
        (assert (and (not bad.ok) (stringContains? bad.why "ignored")) (str "an untracked ignored path is still refused: " bad.why))
        true))

; (:m :ref VCS-COMMIT-IGNORED-DELETE :do "a missing worktree index must not turn a modified tracked file into a deletion: with the index file removed, committing a modified non-ignored file and a modified tracked ignored file keeps both in HEAD with the new content")
fn ! testNoIndex -> Bool
  (let [(dir (str (scratch) "-noidx"))
        (made (repoAt dir))
        (_ (sh "." (list "rm" "-f" (str dir "/.git/index"))))
        (_ (fileWrite (str dir "/n.txt") "2\n"))
        (_ (fileWrite (str dir "/cache/t.txt") "2\n"))
        (tx (gb/prepare! dir (list "n.txt" "cache/t.txt")))
        (fin (if tx.ok (gb/finish! dir tx "noidx" (list "n.txt" "cache/t.txt")) (gb/Out :exit 1 :out tx.why)))
        (held (git dir (list "ls-tree" "-r" "--name-only" "HEAD")))
        (n (git dir (list "show" "HEAD:n.txt")))
        (t (git dir (list "show" "HEAD:cache/t.txt")))
        (_ (if tx.ok (gb/discard! tx) false))
        (_ (sh "." (list "rm" "-rf" dir)))]
    (do (assert (and made tx.ok (= fin.exit 0)) (str "the commit lands with no index file: " tx.why " " fin.out))
        (assert (and (stringContains? held "n.txt") (stringContains? held "cache/t.txt")) (str "neither file is dropped from HEAD: " held))
        (assert (and (= n "2") (= t "2")) (str "both carry the new content: " n " " t))
        true))

fn ! runTests -> Bool
  (do (testAdd) (testStagedDelete) (testNoIndex) true)
