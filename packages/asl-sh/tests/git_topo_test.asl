(module asl-sh/git-topo-test
  :d "Falsifiable test suite for pure ASL Git topology orientation, worktree parser, and linearized history codec."
  :x [run-tests]
  :i [(git_topo :a topo)])

(df test-git-topo-porcelain-v2 [] -> Bool
  :d "Verifies parsing and formatting of git status porcelain v2 with branch tracking and changes."
  (let [(status-text (str "# worktree /Users/purplelephant/projects/asex\n"
                          "# branch.oid 1234567890abcdef1234567890abcdef12345678\n"
                          "# branch.head main\n"
                          "# branch.upstream origin/main\n"
                          "# branch.ab +2 -1\n"
                          "1 M. N... 100644 100644 100644 1234 5678 staged_file.txt\n"
                          "1 .M N... 100644 100644 100644 1234 5678 unstaged_file.txt\n"
                          "? untracked_file.txt\n"
                          "u conflict_file.txt\n"))
        (t (topo/git-topo-parse status-text))
        (fmt (topo/git-topo-format t))]
    (assert (= (.-branch t) "main") "Branch name must be parsed as main")
    (assert (= (.-commit t) "1234567890abcdef1234567890abcdef12345678") "Commit OID must match fixture")
    (assert (= (.-oid t) "1234567890abcdef1234567890abcdef12345678") "OID alias must match commit")
    (assert (= (.-upstream t) "origin/main") "Upstream tracking reference must be parsed as origin/main")
    (assert (not (.-detached t)) "Detached status must be false for branch main")
    (assert (= (.-root t) "/Users/purplelephant/projects/asex") "Root path must match fixture worktree")
    (assert (= (.-worktree-root t) "/Users/purplelephant/projects/asex") "Worktree root alias must match root")
    (assert (= (.-staged t) 1) "Staged changes count must be exactly 1")
    (assert (= (.-unstaged t) 1) "Unstaged changes count must be exactly 1")
    (assert (= (.-untracked t) 1) "Untracked files count must be exactly 1")
    (assert (= (.-conflicts t) 1) "Conflicts count must be exactly 1")
    (assert (= (.-ahead t) 2) "Ahead count must be parsed as 2")
    (assert (= (.-behind t) 1) "Behind count must be parsed as 1")
    (assert (= fmt "(:where-am-i :branch \"main\" :commit \"1234567890abcdef1234567890abcdef12345678\" :upstream \"origin/main\" :root \"/Users/purplelephant/projects/asex\" :clean false :staged 1 :unstaged 1 :untracked 1 :conflicts 1 :ahead 2 :behind 1)") "Formatted ASN where-am-i string must match expected structure")
    true))

(df test-git-topo-detached-head [] -> Bool
  :d "Verifies parsing of detached HEAD state with zero changes and clean format."
  (let [(status-text (str "# worktree /tmp/detached-repo\n"
                          "# branch.oid deadbeefcafe1234567890abcdef1234567890ab\n"
                          "# branch.head (detached)\n"))
        (t (topo/git-topo-parse status-text))
        (fmt (topo/git-topo-format t))]
    (assert (= (.-branch t) "(detached)") "Branch name must be (detached)")
    (assert (.-detached t) "Detached status must be true for (detached) head")
    (assert (= (.-commit t) "deadbeefcafe1234567890abcdef1234567890ab") "Commit OID must match detached commit")
    (assert (= (.-upstream t) "") "Upstream must be empty when no tracking branch is configured")
    (assert (= (.-root t) "/tmp/detached-repo") "Root must match worktree header")
    (assert (= (.-staged t) 0) "Clean repo must have 0 staged changes")
    (assert (= (.-unstaged t) 0) "Clean repo must have 0 unstaged changes")
    (assert (= (.-untracked t) 0) "Clean repo must have 0 untracked files")
    (assert (= (.-conflicts t) 0) "Clean repo must have 0 conflicts")
    (assert (= (.-ahead t) 0) "Clean repo must have 0 ahead")
    (assert (= (.-behind t) 0) "Clean repo must have 0 behind")
    (assert (= fmt "(:where-am-i :branch \"(detached)\" :commit \"deadbeefcafe1234567890abcdef1234567890ab\" :detached true :root \"/tmp/detached-repo\" :clean true :staged 0 :unstaged 0 :untracked 0 :conflicts 0 :ahead 0 :behind 0)") "Clean detached repo must format with :detached true and :clean true")
    true))

(df test-git-worktree-parse [] -> Bool
  :d "Verifies porcelain worktree list parsing including locked and prunable entries."
  (let [(wt-text (str "worktree /Users/purplelephant/projects/asex\n"
                      "HEAD aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
                      "branch refs/heads/main\n"
                      "\n"
                      "worktree /Users/purplelephant/projects/asex-wt1\n"
                      "HEAD bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"
                      "branch refs/heads/feature-1\n"
                      "locked work in progress\n"
                      "\n"
                      "worktree /Users/purplelephant/projects/asex-wt2\n"
                      "HEAD cccccccccccccccccccccccccccccccccccccccc\n"
                      "detached\n"
                      "prunable gitdir file points to non-existent location\n"))
        (wts (topo/git-worktree-parse wt-text))]
    (assert (= (list-length wts) 3) "Must parse exactly 3 worktrees")
    (let [(w0 (option-or (list-get wts 0) (topo/GitWorktreeEntry :path "" :commit "" :head "" :branch "" :locked false :lock-reason "" :prunable false)))
          (w1 (option-or (list-get wts 1) (topo/GitWorktreeEntry :path "" :commit "" :head "" :branch "" :locked false :lock-reason "" :prunable false)))
          (w2 (option-or (list-get wts 2) (topo/GitWorktreeEntry :path "" :commit "" :head "" :branch "" :locked false :lock-reason "" :prunable false)))]
      (assert (= (.-path w0) "/Users/purplelephant/projects/asex") "Worktree 0 path must be root path")
      (assert (= (.-commit w0) "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") "Worktree 0 commit must match HEAD")
      (assert (= (.-head w0) "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") "Worktree 0 head alias must match commit")
      (assert (= (.-branch w0) "main") "Worktree 0 branch ref must strip refs/heads/ prefix")
      (assert (not (.-locked w0)) "Worktree 0 must not be locked")
      (assert (not (.-prunable w0)) "Worktree 0 must not be prunable")

      (assert (= (.-path w1) "/Users/purplelephant/projects/asex-wt1") "Worktree 1 path must match")
      (assert (= (.-commit w1) "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb") "Worktree 1 commit must match")
      (assert (= (.-branch w1) "feature-1") "Worktree 1 branch must be feature-1")
      (assert (.-locked w1) "Worktree 1 must be marked locked")
      (assert (= (.-lock-reason w1) "work in progress") "Worktree 1 lock reason must be extracted")
      (assert (not (.-prunable w1)) "Worktree 1 must not be prunable")

      (assert (= (.-path w2) "/Users/purplelephant/projects/asex-wt2") "Worktree 2 path must match")
      (assert (= (.-commit w2) "cccccccccccccccccccccccccccccccccccccccc") "Worktree 2 commit must match")
      (assert (= (.-branch w2) "(detached)") "Worktree 2 with detached keyword must report branch as (detached)")
      (assert (not (.-locked w2)) "Worktree 2 must not be locked")
      (assert (.-prunable w2) "Worktree 2 must be marked prunable")

      (let [(fmt (topo/git-worktrees-format wts))]
        (assert (= fmt "(:git-worktrees :count 3 :entries ((:git-worktree :path \"/Users/purplelephant/projects/asex\" :commit \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\" :branch \"main\") (:git-worktree :path \"/Users/purplelephant/projects/asex-wt1\" :commit \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\" :branch \"feature-1\" :locked true :lock-reason \"work in progress\") (:git-worktree :path \"/Users/purplelephant/projects/asex-wt2\" :commit \"cccccccccccccccccccccccccccccccccccccccc\" :branch \"(detached)\" :prunable true)))") "Worktree roster format must match expected ASN")
        true))))

(df test-git-log-parse [] -> Bool
  :d "Verifies custom git log format parsing and ASN envelope formatting."
  (let [(log-text (str "1111111111111111111111111111111111111111|Alice|2026-09-08|feat: initial commit\n"
                       "2222222222222222222222222222222222222222|Bob|2026-09-08|fix: resolve issue with \"quotes\"\n"))
        (commits (topo/git-log-parse log-text))]
    (assert (= (list-length commits) 2) "Must parse exactly 2 commits from log text")
    (let [(c0 (option-or (list-get commits 0) (topo/GitCommitEntry :hash "" :short-hash "" :author "" :date "" :message "" :summary "")))
          (c1 (option-or (list-get commits 1) (topo/GitCommitEntry :hash "" :short-hash "" :author "" :date "" :message "" :summary "")))]
      (assert (= (.-hash c0) "1111111111111111111111111111111111111111") "Commit 0 full hash must match")
      (assert (= (.-short-hash c0) "1111111") "Commit 0 short hash must be 7 chars prefix")
      (assert (= (.-author c0) "Alice") "Commit 0 author must be Alice")
      (assert (= (.-date c0) "2026-09-08") "Commit 0 date must be 2026-09-08")
      (assert (= (.-message c0) "feat: initial commit") "Commit 0 message must match")
      (assert (= (.-summary c0) "feat: initial commit") "Commit 0 summary alias must match message")

      (assert (= (.-hash c1) "2222222222222222222222222222222222222222") "Commit 1 full hash must match")
      (assert (= (.-short-hash c1) "2222222") "Commit 1 short hash must be 7 chars prefix")
      (assert (= (.-author c1) "Bob") "Commit 1 author must be Bob")
      (assert (= (.-date c1) "2026-09-08") "Commit 1 date must be 2026-09-08")
      (assert (= (.-message c1) "fix: resolve issue with \"quotes\"") "Commit 1 message must preserve raw quotes")

      (let [(fmt (topo/git-log-format commits))]
        (assert (= fmt "(:git-log :count 2 :commits ((:git-commit :hash \"1111111111111111111111111111111111111111\" :short \"1111111\" :author \"Alice\" :date \"2026-09-08\" :message \"feat: initial commit\") (:git-commit :hash \"2222222222222222222222222222222222222222\" :short \"2222222\" :author \"Bob\" :date \"2026-09-08\" :message \"fix: resolve issue with \\\"quotes\\\"\")))") "Commit log format must properly escape quotes in JSON format")
        true))))

(df test-git-edge-cases [] -> Bool
  :d "Verifies edge case handling for empty inputs and boundary conditions."
  (let [(empty-topo (topo/git-topo-parse ""))
        (empty-wts (topo/git-worktree-parse ""))
        (empty-commits (topo/git-log-parse ""))]
    (assert (= (.-branch empty-topo) "unknown") "Empty status text must produce unknown branch")
    (assert (= (.-commit empty-topo) "") "Empty status text must produce empty commit")
    (assert (= (list-length empty-wts) 0) "Empty worktree text must produce 0 entries")
    (assert (= (topo/git-worktrees-format empty-wts) "(:git-worktrees :count 0 :entries ())") "Empty worktree list must format with count 0 and empty entries")
    (assert (= (list-length empty-commits) 0) "Empty log text must produce 0 commits")
    (assert (= (topo/git-log-format empty-commits) "(:git-log :count 0 :commits ())") "Empty log list must format with count 0 and empty commits")
    true))

(df run-tests [] -> Bool
  :d "Runs all falsifiable tests for Git topology orientation and worktree management."
  (and (test-git-topo-porcelain-v2)
       (and (test-git-topo-detached-head)
            (and (test-git-worktree-parse)
                 (and (test-git-log-parse)
                      (test-git-edge-cases))))))

(run-tests)
