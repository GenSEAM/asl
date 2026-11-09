(module aslAgent/tests/gateDigestReuseTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/gitOps :a go)])

fn ! runGit! root: String args: (List String) -> Bool
  (match (go/runBounded! (listAppend (list "git") args) (some root) (some 30) none none)
    ((ok b) (= (optionOr b.code 1) 0))
    ((err _) false))

fn ! runTests -> Bool
  (let [_ (assert (m/reuseGateDigest? (some "abc") "abc") "equal digests reuse the verdict")
        _ (assert (not (m/reuseGateDigest? (some "abc") "def")) "different digests run gates")
        _ (assert (not (m/reuseGateDigest? none "abc")) "no previous digest runs gates")
        root (str "/tmp/asl-gate-digest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))
        _ (assert (ok? (dirCreate root)) "create temp repo")
        _ (assert (runGit! root (list "init" "-q")) "git init")
        _ (assert (ok? (fileWrite (str root "/a.txt") "one\n")) "write tracked file")
        _ (assert (runGit! root (list "add" "a.txt")) "git add")
        _ (assert (runGit! root (list "-c" "user.name=Gate Digest" "-c" "user.email=gate@example.invalid" "commit" "-qm" "initial")) "git commit")
        first (m/worktreeDigest! (list ".") root)
        second (m/worktreeDigest! (list ".") root)
        _ (assert (not (stringEmpty? first)) "digest is not empty")
        _ (assert (= first second) "same tree has the same digest")
        _ (assert (ok? (fileWrite (str root "/a.txt") "two\n")) "edit tracked file")
        third (m/worktreeDigest! (list ".") root)
        _ (assert (!= first third) "editing a file changes the digest")]
    true)
