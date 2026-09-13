(module asl-compiler/vfs-git-test
  :d "Unit tests for sovereign Git VFS reader in pure ASL."
  :x [testGitReadHead
      testGitCurrentBranch
      testGitHeadCommit
      testGitParsePackedRefs
      testGitParseConfig
      testGitInspectRepoStatus
      runTests]
  :i [(vfs_git :a vfs)])

(df testGitReadHead [] -> Bool
  :d "Verifies reading .git/HEAD on active repository and rejecting invalid roots."
  (let [(headRes (vfs/gitReadHead ""))
        (missingRes (vfs/gitReadHead "/non_existent_directory_99999"))]
    (assert (= (.-_tag headRes) "ok") "gitReadHead on active repo must succeed")
    (refute (!= (.-_tag headRes) "ok") "gitReadHead on active repo must not fail")
    (mt headRes
      ((ok headText)
       (do
         (assert (string-starts-with? headText "ref: refs/heads/") "HEAD must reference a heads branch or commit")
         (refute (string-empty? headText) "HEAD content must not be empty")
         true))
      ((err _) false))
    (assert (= (.-_tag missingRes) "err") "gitReadHead on missing repo must return err")
    (refute (= (.-_tag missingRes) "ok") "gitReadHead on missing repo must not return ok")
    true))

(df testGitCurrentBranch [] -> Bool
  :d "Verifies branch resolution from HEAD without subprocesses."
  (let [(branchRes (vfs/gitCurrentBranch ""))]
    (assert (= (.-_tag branchRes) "ok") "gitCurrentBranch on active repo must succeed")
    (refute (!= (.-_tag branchRes) "ok") "gitCurrentBranch must not fail")
    (mt branchRes
      ((ok branch)
       (do
         (assert (> (string-length branch) 0) "Branch name must not be empty")
         (refute (string-empty? branch) "Branch name must have non-zero length")
         true))
      ((err _) false))))

(df testGitHeadCommit [] -> Bool
  :d "Verifies 40-character commit SHA resolution."
  (let [(commitRes (vfs/gitHeadCommit ""))]
    (assert (= (.-_tag commitRes) "ok") "gitHeadCommit on active repo must succeed")
    (refute (!= (.-_tag commitRes) "ok") "gitHeadCommit must not fail")
    (mt commitRes
      ((ok sha)
       (do
         (assert (= (string-length sha) 40) "HEAD commit SHA must be exactly 40 characters")
         (refute (!= (string-length sha) 40) "Commit SHA must not be truncated or elongated")
         true))
      ((err _) false))))

(df testGitParsePackedRefs [] -> Bool
  :d "Verifies parsing of Git packed-refs format."
  (let [(sample (str "# pack-refs with: peeled fully-peeled sorted\n"
                     "1111111111111111111111111111111111111111 refs/heads/alpha\n"
                     "2222222222222222222222222222222222222222 refs/tags/v1.0.0\n"
                     "^3333333333333333333333333333333333333333\n"))
        (pMap (vfs/gitParsePackedRefs sample))]
    (assert (map-has? pMap "refs/heads/alpha") "packed-refs must contain alpha ref")
    (assert (= (option-or (map-get pMap "refs/heads/alpha") "") "1111111111111111111111111111111111111111") "Alpha SHA must match")
    (assert (map-has? pMap "refs/tags/v1.0.0") "packed-refs must contain tag ref")
    (refute (map-has? pMap "# pack-refs with: peeled") "Header comment must not be stored as ref")
    (refute (map-has? pMap "^3333333333333333333333333333333333333333") "Peeled tag line must not be stored as ref")
    true))

(df testGitParseConfig [] -> Bool
  :d "Verifies parsing of repository configuration."
  (let [(cfg (vfs/gitParseConfig ""))]
    (assert (map-has? cfg "repositoryformatversion") "Config must have repositoryformatversion")
    (assert (= (option-or (map-get cfg "repositoryformatversion") "") "0") "Format version must be 0")
    (refute (map-empty? cfg) "Config map must not be empty")
    true))

(df testGitInspectRepoStatus [] -> Bool
  :d "Verifies high-level status inspection without POSIX git."
  (let [(st (vfs/gitInspectRepoStatus ""))]
    (assert (= (option-or (map-get st "status") "") "clean") "Status must be clean")
    (assert (map-has? st "branch") "Status map must contain branch")
    (assert (map-has? st "commit") "Status map must contain commit")
    (refute (string-empty? (option-or (map-get st "branch") "")) "Branch must not be empty")
    (refute (= (string-length (option-or (map-get st "commit") "")) 0) "Commit SHA must not be empty")
    true))

(df runTests [] -> Bool
  :d "Runs all Git VFS unit tests."
  (do
    (assert (testGitReadHead) "testGitReadHead must pass")
    (assert (testGitCurrentBranch) "testGitCurrentBranch must pass")
    (assert (testGitHeadCommit) "testGitHeadCommit must pass")
    (assert (testGitParsePackedRefs) "testGitParsePackedRefs must pass")
    (assert (testGitParseConfig) "testGitParseConfig must pass")
    (assert (testGitInspectRepoStatus) "testGitInspectRepoStatus must pass")
    true))
