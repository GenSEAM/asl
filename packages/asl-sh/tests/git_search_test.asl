(module asl-sh/git-search-test
  :d "Falsifiable test suite for pure AgentScript cross-branch search parser, match formatter, and branch catalog codec."
  :x [run-tests]
  :i [(git_search :a search)])

(df test-git-search-parse-and-format [] -> Bool
  :d "Verifies multi-ref git grep line parsing, colon preservation, and ASN formatting with and without truncation."
  (let [(raw-text (str "main:src/index.ts:42:console.log(\"hello\");\n"
                       "feature/x:README.md:5:# Features\n"
                       "v1.0.0:config/app.json:15:  \"host\": \"localhost:8080\"\n"
                       "local/file.asl:100:(df test [] -> Bool)\n"))
        (matches (search/git-search-parse raw-text "HEAD"))]
    (assert (= (list-length matches) 4) "Raw search output must parse into exactly 4 GitSearchMatch records")
    (let [(m1 (option-or (list-get matches 0) (search/GitSearchMatch :ref "" :file "" :line 0 :content "")))
          (m2 (option-or (list-get matches 1) (search/GitSearchMatch :ref "" :file "" :line 0 :content "")))
          (m3 (option-or (list-get matches 2) (search/GitSearchMatch :ref "" :file "" :line 0 :content "")))
          (m4 (option-or (list-get matches 3) (search/GitSearchMatch :ref "" :file "" :line 0 :content "")))]
      (assert (= (.-ref m1) "main") "Match 1 ref must be main")
      (assert (= (.-file m1) "src/index.ts") "Match 1 file must be src/index.ts")
      (assert (= (.-line m1) 42) "Match 1 line must be 42")
      (assert (= (.-content m1) "console.log(\"hello\");") "Match 1 content must preserve string")

      (assert (= (.-ref m2) "feature/x") "Match 2 ref must be feature/x")
      (assert (= (.-file m2) "README.md") "Match 2 file must be README.md")
      (assert (= (.-line m2) 5) "Match 2 line must be 5")

      (assert (= (.-ref m3) "v1.0.0") "Match 3 ref must be v1.0.0")
      (assert (= (.-file m3) "config/app.json") "Match 3 file must be config/app.json")
      (assert (= (.-line m3) 15) "Match 3 line must be 15")
      (assert (= (.-content m3) "  \"host\": \"localhost:8080\"") "Match 3 content must preserve colons in value")

      (assert (= (.-ref m4) "HEAD") "Match 4 local grep line must use default ref HEAD")
      (assert (= (.-file m4) "local/file.asl") "Match 4 file must be local/file.asl")
      (assert (= (.-line m4) 100) "Match 4 line must be 100")
      (assert (= (.-content m4) "(df test [] -> Bool)") "Match 4 content must be (df test [] -> Bool)")

      (let [(fmt-full (search/git-search-format matches "query-test" 0))
            (fmt-trunc (search/git-search-format matches "query-test" 2))]
        (assert (string-contains? fmt-full ":git-search-results :query \"query-test\" :count 4") "Full search format must contain query and count 4")
        (assert (string-contains? fmt-full ":ref \"main\" :file \"src/index.ts\" :line 42") "Full search format must contain match 1 details")
        (assert (string-contains? fmt-trunc ":git-search-results :query \"query-test\" :count 2") "Truncated search format must report count 2")
        (assert (string-contains? fmt-trunc ":truncated true :total-matches 4") "Truncated search format must indicate truncation with total matches 4")
        true))))

(df test-git-search-local-fallback [] -> Bool
  :d "Verifies local 3-part file:line:content git grep output fallback with default ref."
  (let [(local-text "src/main.rs:88:fn execute() -> Result<()> {\n")
        (matches (search/git-search-parse local-text "my-branch"))]
    (assert (= (list-length matches) 1) "3-part grep line must parse into 1 match")
    (let [(m (option-or (list-get matches 0) (search/GitSearchMatch :ref "" :file "" :line 0 :content "")))]
      (assert (= (.-ref m) "my-branch") "3-part grep line must use default ref")
      (assert (= (.-file m) "src/main.rs") "3-part grep line must extract file")
      (assert (= (.-line m) 88) "3-part grep line must extract line number 88")
      (assert (= (.-content m) "fn execute() -> Result<()> {") "3-part grep line must extract content")
      true)))

(df test-git-search-empty [] -> Bool
  :d "Verifies empty string and blank inputs parse to 0 matches and clean empty ASN envelope."
  (let [(m-empty (search/git-search-parse "" "HEAD"))
        (m-ws (search/git-search-parse "   \n\n  " "HEAD"))
        (fmt-empty (search/git-search-format m-empty "missing" 10))]
    (assert (= (list-length m-empty) 0) "Empty search string must yield 0 matches")
    (assert (= (list-length m-ws) 0) "Whitespace search string must yield 0 matches")
    (assert (= fmt-empty "(:git-search-results :query \"missing\" :count 0 :matches ())") "Empty search envelope must match expected structure")
    true))

(df test-git-branches-parse-and-format [] -> Bool
  :d "Verifies multi-line git branch listing parser, symbolic ref filtering, and ASN envelope formatting."
  (let [(raw-branches (str "* main                d23588d [origin/main] Initial commit\n"
                           "  feature/rpc         a1b2c3d [origin/feature/rpc: ahead 1] Add rpc ops\n"
                           "  remotes/origin/HEAD -> origin/main\n"
                           "  remotes/origin/main d23588d Initial commit\n"
                           "  remotes/origin/v1.0 9988776 Release 1.0\n"))
        (branches (search/git-branches-parse raw-branches))]
    (assert (= (list-length branches) 4) "Branch output must parse into 4 records ignoring symbolic HEAD arrow")
    (let [(b1 (option-or (list-get branches 0) (search/GitBranchRecord :name "" :commit "" :upstream "" :current false :remote false)))
          (b2 (option-or (list-get branches 1) (search/GitBranchRecord :name "" :commit "" :upstream "" :current false :remote false)))
          (b3 (option-or (list-get branches 2) (search/GitBranchRecord :name "" :commit "" :upstream "" :current false :remote false)))
          (b4 (option-or (list-get branches 3) (search/GitBranchRecord :name "" :commit "" :upstream "" :current false :remote false)))]
      (assert (= (.-name b1) "main") "Branch 1 name must be main")
      (assert (= (.-commit b1) "d23588d") "Branch 1 commit must be d23588d")
      (assert (= (.-upstream b1) "origin/main") "Branch 1 upstream must be origin/main")
      (assert (.-current b1) "Branch 1 must be marked current")
      (assert (not (.-remote b1)) "Branch 1 must not be remote")

      (assert (= (.-name b2) "feature/rpc") "Branch 2 name must be feature/rpc")
      (assert (= (.-commit b2) "a1b2c3d") "Branch 2 commit must be a1b2c3d")
      (assert (= (.-upstream b2) "origin/feature/rpc") "Branch 2 upstream must be origin/feature/rpc")
      (assert (not (.-current b2)) "Branch 2 must not be current")
      (assert (not (.-remote b2)) "Branch 2 must not be remote")

      (assert (= (.-name b3) "origin/main") "Branch 3 name must be origin/main without remotes prefix")
      (assert (= (.-commit b3) "d23588d") "Branch 3 commit must be d23588d")
      (assert (= (.-upstream b3) "") "Branch 3 remote tracking branch has no separate upstream")
      (assert (not (.-current b3)) "Branch 3 must not be current")
      (assert (.-remote b3) "Branch 3 must be marked remote")

      (assert (= (.-name b4) "origin/v1.0") "Branch 4 name must be origin/v1.0")
      (assert (.-remote b4) "Branch 4 must be marked remote")

      (let [(fmt (search/git-branches-format branches))]
        (assert (string-contains? fmt "(:git-branches :count 4 :branches (") "Branch format must start with count 4")
        (assert (string-contains? fmt "(:branch :name \"main\" :commit \"d23588d\" :current true :upstream \"origin/main\")") "Branch 1 formatted entry matches")
        (assert (string-contains? fmt "(:branch :name \"feature/rpc\" :commit \"a1b2c3d\" :upstream \"origin/feature/rpc\")") "Branch 2 formatted entry matches")
        (assert (string-contains? fmt "(:branch :name \"origin/main\" :commit \"d23588d\" :remote true)") "Branch 3 formatted entry matches")
        (assert (string-contains? fmt "(:branch :name \"origin/v1.0\" :commit \"9988776\" :remote true)") "Branch 4 formatted entry matches")
        true))))

(df run-tests [] -> Bool
  :d "Runs all falsifiable test suites for git search parser, formatter, and branch catalog."
  (and (test-git-search-parse-and-format)
       (and (test-git-search-local-fallback)
            (and (test-git-search-empty)
                 (test-git-branches-parse-and-format)))))
