(module asl-sh/tests/github-test
  :d "Falsifiable test suite for pure ASL GitHub CLI projections, diff compaction, CI rollup, and issue parsing."
  :x [run-tests]
  :i [(github :a gh)])

(df test-pr-listing-and-projections [] -> Bool
  :d "Verifies parsing of GitHub PR list and view payloads into compact summary records."
  (let [(json-fixture (str "[{\"number\": 304, \"title\": \"Pure ASL GitHub projections\", "
                           "\"author\": {\"login\": \"purplelephant\", \"name\": \"Purple Elephant\"}, "
                           "\"headRefName\": \"feat/phase-304\", \"baseRefName\": \"main\", "
                           "\"state\": \"OPEN\", \"labels\": [{\"name\": \"enhancement\"}, {\"name\": \"p2\"}], "
                           "\"additions\": 42, \"deletions\": 5}]"))
        (prs (gh/github-pr-parse json-fixture))]
    (assert (= (list-length prs) 1) "PR list JSON must parse into exactly 1 summary record")
    (let [(pr (option-or (list-get prs 0) (gh/GitHubPrSummary :number 0 :title "" :author "" :head "" :base "" :state "" :labels (list) :additions 0 :deletions 0)))]
      (assert (= (.-number pr) 304) "PR number must match 304")
      (assert (= (.-title pr) "Pure ASL GitHub projections") "PR title must match fixture title")
      (assert (= (.-author pr) "purplelephant") "Author login handle must be extracted from nested author object")
      (assert (and (= (.-head pr) "feat/phase-304") (= (.-base pr) "main")) "Head ref and base ref must match branches")
      (assert (and (= (.-state pr) "OPEN") (and (= (list-length (.-labels pr)) 2) (= (.-additions pr) 42))) "State, labels count, and additions must match")
      true)))

(df test-diff-compaction-and-token-reduction [] -> Bool
  :d "Verifies stripping of commit metadata, hunk range compaction, delta metrics, ordering, and >= 70% token savings."
  (let [(raw-diff (str "commit 9876543210abcdef9876543210abcdef98765432\n"
                       "Author: Developer <dev@example.com>\n"
                       "Date:   Tue Sep 8 11:00:00 2026 +0000\n\n"
                       "    feat: add github adapter and compact projections\n\n"
                       "diff --git a/pkg/a.txt b/pkg/a.txt\n"
                       "index 1234567..89abcdef 100644\n"
                       "--- a/pkg/a.txt\n"
                       "+++ b/pkg/a.txt\n"
                       "@@ -10,12 +10,13 @@\n"
                       " context line 1\n"
                       " context line 2\n"
                       " context line 3\n"
                       " context line 4\n"
                       " context line 5\n"
                       " context line 6\n"
                       "+added line in file a\n"
                       " context line 7\n"
                       " context line 8\n"
                       " context line 9\n"
                       " context line 10\n"
                       " context line 11\n"
                       " context line 12\n"
                       "diff --git a/pkg/b.txt b/pkg/b.txt\n"
                       "index fedcba9..7654321 100644\n"
                       "--- a/pkg/b.txt\n"
                       "+++ b/pkg/b.txt\n"
                       "@@ -20,12 +20,11 @@\n"
                       " context line 13\n"
                       " context line 14\n"
                       " context line 15\n"
                       " context line 16\n"
                       " context line 17\n"
                       " context line 18\n"
                       "-deleted line in file b\n"
                       " context line 19\n"
                       " context line 20\n"
                       " context line 21\n"
                       " context line 22\n"
                       " context line 23\n"
                       " context line 24\n"))
        (compact (gh/github-diff-compact raw-diff))
        (raw-tokens (/ (+ (string-length raw-diff) 3) 4))
        (compact-tokens (/ (+ (string-length compact) 3) 4))
        (tokens-saved (- raw-tokens compact-tokens))
        (pct-saved (/ (* tokens-saved 100) raw-tokens))]
    (assert (not (string-contains? compact "index 1234567..89abcdef")) "Diff compaction must strip index hash headers")
    (assert (and (string-contains? compact "@@ -10,12 +10,13 @@") (string-contains? compact "@@ -20,12 +20,11 @@")) "Hunk ranges must be compacted into canonical @@ notation")
    (assert (string-contains? compact ":+ 1") "Addition count must reflect added lines")
    (assert (string-contains? compact ":- 1") "Deletion count must reflect deleted lines")
    (assert (>= pct-saved 70) "Compacted ASN diff must achieve at least 70% token savings over raw unified diff")
    (let [(idx-a (option-or (string-index-of compact "pkg/a.txt") 0))
          (idx-b (option-or (string-index-of compact "pkg/b.txt") 0))]
      (assert (< idx-a idx-b) "Multi-file diff parsing must preserve file sequence ordering")
      true)))

(df test-ci-status-and-check-summaries [] -> Bool
  :d "Verifies parsing of GitHub Actions check runs, failure detection, target URLs, and rollup verdicts."
  (let [(ci-json (str "[{\"name\": \"build\", \"status\": \"COMPLETED\", \"conclusion\": \"SUCCESS\", \"targetUrl\": \"https://ci.example.com/build/1\"}, "
                      "{\"name\": \"test\", \"status\": \"COMPLETED\", \"conclusion\": \"FAILURE\", \"targetUrl\": \"https://ci.example.com/test/2\"}, "
                      "{\"name\": \"lint\", \"status\": \"IN_PROGRESS\", \"conclusion\": \"\", \"targetUrl\": \"https://ci.example.com/lint/3\"}]"))
        (checks (gh/github-ci-parse ci-json))]
    (assert (= (list-length checks) 3) "Check run JSON must parse into exactly 3 GitHubCiCheck records")
    (let [(c1 (option-or (list-get checks 0) (gh/GitHubCiCheck :name "" :status "" :conclusion "" :target-url "")))
          (c2 (option-or (list-get checks 1) (gh/GitHubCiCheck :name "" :status "" :conclusion "" :target-url "")))]
      (assert (and (= (.-name c1) "build") (and (= (.-status c1) "COMPLETED") (= (.-conclusion c1) "SUCCESS"))) "First check must report completed success")
      (assert (and (= (.-name c2) "test") (= (.-conclusion c2) "FAILURE")) "Failing check must be detected with conclusion FAILURE")
      (assert (= (.-target-url c2) "https://ci.example.com/test/2") "Target URL must be extracted correctly from check record")
      (assert (= (gh/github-ci-rollup checks) ":failure") "Rollup verdict must be :failure when any check has failed")
      (let [(success-only (gh/github-ci-parse "[{\"name\": \"unit\", \"status\": \"COMPLETED\", \"conclusion\": \"SUCCESS\", \"targetUrl\": \"\"}]"))
            (empty-checks (gh/github-ci-parse "[]"))]
        (assert (and (= (gh/github-ci-rollup success-only) ":success") (= (gh/github-ci-rollup empty-checks) ":success")) "Rollup must report :success on all green and empty suites without nil deref")
        true))))

(df test-issue-and-comment-parsing [] -> Bool
  :d "Verifies parsing of GitHub issue payloads, assignees, labels, and comment counts."
  (let [(issue-json (str "{\"number\": 101, \"title\": \"Support compact GitHub projections\", "
                         "\"author\": {\"login\": \"octocat\"}, \"state\": \"OPEN\", "
                         "\"labels\": [{\"name\": \"p2\"}, {\"name\": \"cli\"}], "
                         "\"assignees\": [{\"login\": \"alice\"}, {\"login\": \"bob\"}], "
                         "\"commentsCount\": 3, \"body\": \"Implement token-compact projections for GitHub issues.\"}\n"))
        (issues (gh/github-issue-parse issue-json))]
    (assert (= (list-length issues) 1) "Issue JSON must parse into exactly 1 GitHubIssue record")
    (let [(iss (option-or (list-get issues 0) (gh/GitHubIssue :number 0 :title "" :author "" :state "" :labels (list) :assignees (list) :comments-count 0 :body "")))]
      (assert (= (.-number iss) 101) "Issue number must be parsed as 101")
      (assert (and (= (.-title iss) "Support compact GitHub projections") (= (.-body iss) "Implement token-compact projections for GitHub issues.")) "Issue title and body text must match fixture")
      (assert (= (.-comments-count iss) 3) "Issue comments count must equal 3")
      (assert (and (= (list-length (.-labels iss)) 2) (= (list-length (.-assignees iss)) 2)) "Labels and assignees must normalize into lists of strings")
      true)))

(df test-error-handling-and-resilience [] -> Bool
  :d "Verifies error resilience against empty strings, truncated JSON, sparse fields, and 1000+ line truncation."
  (let [(empty-res (gh/github-pr-parse ""))
        (empty-arr (gh/github-pr-parse "[]"))
        (malformed-res (gh/github-pr-parse "{\"number\": 12, \"title\": incomplete"))
        (sparse-json "{\"number\": 404}")
        (sparse-prs (gh/github-pr-parse sparse-json))]
    (assert (= (list-length empty-res) 0) "Empty JSON string must return empty list without error")
    (assert (= (list-length empty-arr) 0) "Empty JSON array must return empty list without error")
    (assert (= (list-length malformed-res) 0) "Malformed unclosed JSON must fallback cleanly to empty list")
    (assert (= (list-length sparse-prs) 1) "Sparse PR payload with omitted fields must parse cleanly")
    (let [(sparse-pr (option-or (list-get sparse-prs 0) (gh/GitHubPrSummary :number 0 :title "" :author "" :head "" :base "" :state "" :labels (list) :additions 0 :deletions 0)))]
      (assert (and (= (.-number sparse-pr) 404) (and (= (.-title sparse-pr) "") (list-empty? (.-labels sparse-pr)))) "Missing optional fields must default safely to zero values")
      (let [(big-body (str (string-join (map (fn [(n Int64)] -> String (str "line " (string-from-int64 n))) (range 1 1005)) "\n") "\n"))
            (big-issue-json (str "{\"number\": 999, \"title\": \"Big issue\", \"body\": \"" (string-replace big-body "\n" "\\n") "\"}"))
            (big-issues (gh/github-issue-parse big-issue-json))]
        (let [(big-iss (option-or (list-get big-issues 0) (gh/GitHubIssue :number 0 :title "" :author "" :state "" :labels (list) :assignees (list) :comments-count 0 :body "")))]
          (assert (string-contains? (.-body big-iss) "... [truncated,") "Large issue body exceeding 1000 lines must be capped with truncation pointer")
          true)))))

(df run-tests [] -> Bool
  :d "Runs all falsifiable test suites for pure ASL GitHub projections."
  (and (test-pr-listing-and-projections)
       (and (test-diff-compaction-and-token-reduction)
            (and (test-ci-status-and-check-summaries)
                 (and (test-issue-and-comment-parsing)
                      (test-error-handling-and-resilience))))))

(run-tests)
