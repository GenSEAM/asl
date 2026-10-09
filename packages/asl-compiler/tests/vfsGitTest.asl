(module asl-compiler/vfsGitTest :x [testGitReadHead! testGitCurrentBranch! testGitHeadCommit! testGitParsePackedRefs testGitParseConfig! testGitInspectRepoStatus! testNormalizePath testGitBoundaryValidation! runTests] :i [(vfsGit :a vfs)])

fn testGitReadHead! -> Bool
  (let [(headRes (vfs/gitReadHead! "")) (missingRes (vfs/gitReadHead! "/non_existent_directory_99999"))] (assert (ok? headRes) "gitReadHead on active repo must succeed") (refute (not (ok? headRes)) "gitReadHead on active repo must not fail") (mt headRes ((ok headText) (do (assert (or (stringStartsWith? headText "ref: refs/heads/") (= (stringLength (stringTrim headText)) 40)) "HEAD must reference a heads branch or commit") (refute (stringEmpty? headText) "HEAD content must not be empty") true)) ((err _) false)) (assert (err? missingRes) "gitReadHead on missing repo must return err") (refute (ok? missingRes) "gitReadHead on missing repo must not return ok") true)

fn testGitCurrentBranch! -> Bool
  (let [(branchRes (vfs/gitCurrentBranch! ""))] (assert (ok? branchRes) "gitCurrentBranch on active repo must succeed") (refute (not (ok? branchRes)) "gitCurrentBranch must not fail") (mt branchRes ((ok branch) (do (assert (> (stringLength branch) 0) "Branch name must not be empty") (refute (stringEmpty? branch) "Branch name must have non-zero length") true)) ((err _) false)))

fn testGitHeadCommit! -> Bool
  (let [(commitRes (vfs/gitHeadCommit! ""))] (assert (ok? commitRes) "gitHeadCommit on active repo must succeed") (refute (not (ok? commitRes)) "gitHeadCommit must not fail") (mt commitRes ((ok sha) (do (assert (= (stringLength sha) 40) "HEAD commit SHA must be exactly 40 characters") (refute (!= (stringLength sha) 40) "Commit SHA must not be truncated or elongated") true)) ((err _) false)))

fn testGitParsePackedRefs -> Bool
  (let [(sample (str "# pack-refs with: peeled fully-peeled sorted\n" "1111111111111111111111111111111111111111 refs/heads/alpha\n" "2222222222222222222222222222222222222222 refs/tags/v1.0.0\n" "^3333333333333333333333333333333333333333\n")) (pMap (vfs/gitParsePackedRefs sample))] (assert (mapHas? pMap "refs/heads/alpha") "packed-refs must contain alpha ref") (assert (= (optionOr (mapGet pMap "refs/heads/alpha") "") "1111111111111111111111111111111111111111") "Alpha SHA must match") (assert (mapHas? pMap "refs/tags/v1.0.0") "packed-refs must contain tag ref") (refute (mapHas? pMap "# pack-refs with: peeled") "Header comment must not be stored as ref") (refute (mapHas? pMap "^3333333333333333333333333333333333333333") "Peeled tag line must not be stored as ref") true)

fn testGitParseConfig! -> Bool
  (let [(cfg (vfs/gitParseConfig! ""))] (assert (mapHas? cfg "repositoryformatversion") "Config must have repositoryformatversion") (assert (= (optionOr (mapGet cfg "repositoryformatversion") "") "0") "Format version must be 0") (refute (= (mapSize cfg) 0) "Config map must not be empty") true)

fn testGitInspectRepoStatus! -> Bool
  (let [(st (vfs/gitInspectRepoStatus! ""))] (assert (= (optionOr (mapGet st "status") "") "clean") "Status must be clean") (assert (mapHas? st "branch") "Status map must contain branch") (assert (mapHas? st "commit") "Status map must contain commit") (refute (stringEmpty? (optionOr (mapGet st "branch") "")) "Branch must not be empty") (refute (= (stringLength (optionOr (mapGet st "commit") "")) 0) "Commit SHA must not be empty") true)

fn testNormalizePath -> Bool
  (do (assert (= (vfs/normalizePath "../../etc/passwd") "../../etc/passwd") "Leading dotdots must be preserved") (assert (= (vfs/normalizePath "/../../etc/passwd") "/etc/passwd") "Absolute leading dotdots stay at root") (assert (= (vfs/normalizePath "a/b/../../etc/passwd") "etc/passwd") "Internal dotdots cancel normal segments") (assert (= (vfs/normalizePath "a/../../etc/passwd") "../etc/passwd") "Out-of-bounds dotdots are preserved") (refute (= (vfs/normalizePath "../../etc/passwd") "etc/passwd") "Consecutive leading dotdots must not be cancelled") true)

fn testGitBoundaryValidation! -> Bool
  (let [(esc1 (vfs/gitResolveRefCommit! ".git" ".git" "../../etc/passwd")) (esc2 (vfs/gitResolveRefCommit! ".git" ".git" "/etc/passwd")) (esc3 (vfs/gitResolveRefCommit! ".git" ".git" "refs/heads/../../etc/passwd")) (esc4 (vfs/gitResolveRefCommit! ".git" ".git" "not-refs/main"))] (assert (err? esc1) "ref with leading dotdots must fail") (assert (err? esc2) "ref with absolute path must fail") (assert (err? esc3) "ref with traversal dotdots must fail") (assert (err? esc4) "ref outside refs/ must fail") (refute (ok? esc1) "ref traversal must not succeed") (refute (ok? esc2) "absolute ref must not succeed") true)

fn ! runTests -> Bool
  (do (assert (testGitReadHead!) "testGitReadHead must pass") (assert (testGitCurrentBranch!) "testGitCurrentBranch must pass") (assert (testGitHeadCommit!) "testGitHeadCommit must pass") (assert (testGitParsePackedRefs) "testGitParsePackedRefs must pass") (assert (testGitParseConfig!) "testGitParseConfig must pass") (assert (testGitInspectRepoStatus!) "testGitInspectRepoStatus must pass") (assert (testNormalizePath) "testNormalizePath must pass") (assert (testGitBoundaryValidation!) "testGitBoundaryValidation must pass") true)
