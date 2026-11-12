(module aslAgent/tests/gateDigestReuseTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/tests/gitInitKit :a gk)])

fn ! runTests -> Bool
  (let [_ (assert (m/reuseGateDigest? (some "abc") "abc") "equal digests reuse the verdict")
        _ (assert (not (m/reuseGateDigest? (some "abc") "def")) "different digests run gates")
        _ (assert (not (m/reuseGateDigest? none "abc")) "no previous digest runs gates")
        root (str "/tmp/asl-gate-digest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)))
        _ (assert (ok? (dirCreate root)) "create temp repo")
        _ (assert (ok? (fileWrite (str root "/a.txt") "one\n")) "write tracked file")
        _ (assert (gk/initGitRepoWith! root "Gate Digest" "gate@example.invalid" (list "a.txt")) "temp repo committed with a.txt")
        first (m/worktreeDigest! (list ".") root)
        second (m/worktreeDigest! (list ".") root)
        _ (assert (not (stringEmpty? first)) "digest is not empty")
        _ (assert (= first second) "same tree has the same digest")
        _ (assert (ok? (fileWrite (str root "/a.txt") "two\n")) "edit tracked file")
        third (m/worktreeDigest! (list ".") root)
        _ (assert (!= first third) "editing a file changes the digest")]
    true)
