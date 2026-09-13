(module asl-sh/gitDiffTest
  :d "Falsifiable test suite for pure ASL unified diff parser and token-optimized ASN diff summary codec."
  :x [runTests]
  :i [(git_diff :a diff)])

(df testSingleFileAndHunks [] -> Bool
  :d "Verifies single-file parsing, hunk coordinates, addition/deletion metrics, and path extraction."
  (let [(diffText (str "diff --git a/src/main.rs b/src/main.rs\n"
                        "index 1234567..89abcdef 100644\n"
                        "--- a/src/main.rs\n"
                        "+++ b/src/main.rs\n"
                        "@@ -10,4 +10,5 @@ fn main() {\n"
                        " context line\n"
                        "-deleted line 1\n"
                        "+added line 1\n"
                        "+added line 2\n"
                        " context line\n"
                        "@@ -20,3 +21,2 @@ fn helper() {\n"
                        "-deleted line 2\n"
                        " context line\n"))
        (files (diff/gitDiffParse diffText))]
    (assert (= (list-length files) 1) "Single file diff must parse into exactly 1 GitDiffFile")
    (let [(f (option-or (list-get files 0) (diff/GitDiffFile :oldPath "" :newPath "" :hunks (list) :additions 0 :deletions 0)))
          (hunks (.-hunks f))]
      (assert (= (.-oldPath f) "src/main.rs") "Old path must be extracted as src/main.rs")
      (assert (= (.-newPath f) "src/main.rs") "New path must be extracted as src/main.rs")
      (assert (= (list-length hunks) 2) "Multi-hunk diff must parse into exactly 2 hunks")
      (let [(h1 (option-or (list-get hunks 0) (diff/GitDiffHunk :oldStart 0 :oldCount 0 :newStart 0 :newCount 0 :lines (list))))
            (h2 (option-or (list-get hunks 1) (diff/GitDiffHunk :oldStart 0 :oldCount 0 :newStart 0 :newCount 0 :lines (list))))]
        (assert (= (.-oldStart h1) 10) "Hunk 1 old-start must match 10")
        (assert (= (.-oldCount h1) 4) "Hunk 1 old-count must match 4")
        (assert (= (.-newStart h1) 10) "Hunk 1 new-start must match 10")
        (assert (= (.-newCount h1) 5) "Hunk 1 new-count must match 5")
        (assert (= (.-oldStart h2) 20) "Hunk 2 old-start must match 20")
        (assert (= (.-newStart h2) 21) "Hunk 2 new-start must match 21")
        (assert (= (.-additions f) 2) "Addition count must match added lines excluding header")
        (assert (= (.-deletions f) 2) "Deletion count must match deleted lines excluding header")
        true))))

(df testEmptyDiff [] -> Bool
  :d "Verifies empty and whitespace-only diff strings parse into empty lists and zeroed ASN summary."
  (let [(files (diff/gitDiffParse ""))
        (summary (diff/gitDiffSummary files))
        (wsFiles (diff/gitDiffParse "   \n\n  \t "))
        (wsSummary (diff/gitDiffSummary wsFiles))]
    (assert (= (list-length files) 0) "Empty diff text must parse into 0 files")
    (assert (= (list-length wsFiles) 0) "Whitespace diff text must parse into 0 files")
    (assert (= summary "(:diff-summary :files 0 :additions 0 :deletions 0 :hunks 0)") "Empty diff summary must report 0 files 0 additions 0 deletions 0 hunks")
    (assert (= wsSummary "(:diff-summary :files 0 :additions 0 :deletions 0 :hunks 0)") "Whitespace diff summary must report 0 files 0 additions 0 deletions 0 hunks")
    true))

(df testMultiFileAndOrdering [] -> Bool
  :d "Verifies multi-file diff parsing, order preservation, and aggregated ASN summary metrics."
  (let [(diffText (str "diff --git a/pkg/a.txt b/pkg/a.txt\n"
                        "--- a/pkg/a.txt\n"
                        "+++ b/pkg/a.txt\n"
                        "@@ -1,3 +1,4 @@\n"
                        " line1\n"
                        "+line2\n"
                        " line3\n"
                        "diff --git a/pkg/b.txt b/pkg/b.txt\n"
                        "--- a/pkg/b.txt\n"
                        "+++ b/pkg/b.txt\n"
                        "@@ -5,2 +5,1 @@\n"
                        "-old line\n"
                        " stay line\n"))
        (files (diff/gitDiffParse diffText))
        (summary (diff/gitDiffSummary files))]
    (assert (= (list-length files) 2) "Multi-file diff must parse into 2 files")
    (let [(f1 (option-or (list-get files 0) (diff/GitDiffFile :oldPath "" :newPath "" :hunks (list) :additions 0 :deletions 0)))
          (f2 (option-or (list-get files 1) (diff/GitDiffFile :oldPath "" :newPath "" :hunks (list) :additions 0 :deletions 0)))]
      (assert (= (.-oldPath f1) "pkg/a.txt") "First file old-path must be pkg/a.txt")
      (assert (= (.-oldPath f2) "pkg/b.txt") "Second file old-path must be pkg/b.txt")
      (assert (= (.-additions f1) 1) "File 1 additions must be 1")
      (assert (= (.-deletions f1) 0) "File 1 deletions must be 0")
      (assert (= (.-additions f2) 0) "File 2 additions must be 0")
      (assert (= (.-deletions f2) 1) "File 2 deletions must be 1")
      (assert (= summary "(:diff-summary :files 2 :additions 1 :deletions 1 :hunks 2)") "Multi-file ASN summary must aggregate file metrics correctly")
      true)))

(df testSingleLineHunkHeader [] -> Bool
  :d "Verifies single-line hunk headers without comma default line counts to 1."
  (let [(diffText (str "--- a/single.txt\n"
                        "+++ b/single.txt\n"
                        "@@ -1 +1 @@\n"
                        "-old\n"
                        "+new\n"))
        (files (diff/gitDiffParse diffText))]
    (assert (= (list-length files) 1) "Single-line hunk diff must parse into 1 file")
    (let [(f (option-or (list-get files 0) (diff/GitDiffFile :oldPath "" :newPath "" :hunks (list) :additions 0 :deletions 0)))
          (hunks (.-hunks f))]
      (assert (= (list-length hunks) 1) "Must contain exactly 1 hunk")
      (let [(h (option-or (list-get hunks 0) (diff/GitDiffHunk :oldStart 0 :oldCount 0 :newStart 0 :newCount 0 :lines (list))))]
        (assert (= (.-oldStart h) 1) "Single-line hunk old-start must be 1")
        (assert (= (.-oldCount h) 1) "Single-line hunk without comma must default old-count to 1")
        (assert (= (.-newStart h) 1) "Single-line hunk new-start must be 1")
        (assert (= (.-newCount h) 1) "Single-line hunk without comma must default new-count to 1")
        (assert (= (.-additions f) 1) "Additions must equal 1")
        (assert (= (.-deletions f) 1) "Deletions must equal 1")
        true))))

(df testNumstatAndCompare [] -> Bool
  :d "Verifies parsing of git diff --numstat lines and formatting of compact :git-compare ASN."
  (let [(rawNumstat (str "12\t5\tsrc/main.asl\n"
                          "40\t0\tnew_module.asl\n"
                          "0\t15\told_file.asl\n"
                          "-\t-\tassets/logo.png\n"))
        (entries (diff/gitNumstatParse rawNumstat))]
    (assert (= (list-length entries) 4) "Numstat parse must yield 4 entries")
    (let [(e1 (option-or (list-get entries 0) (diff/GitNumstatEntry :path "" :additions 0 :deletions 0 :status "")))
          (e2 (option-or (list-get entries 1) (diff/GitNumstatEntry :path "" :additions 0 :deletions 0 :status "")))
          (e3 (option-or (list-get entries 2) (diff/GitNumstatEntry :path "" :additions 0 :deletions 0 :status "")))
          (e4 (option-or (list-get entries 3) (diff/GitNumstatEntry :path "" :additions 0 :deletions 0 :status "")))]
      (assert (= (.-path e1) "src/main.asl") "First entry path must match src/main.asl")
      (assert (= (.-status e1) "modified") "First entry with adds and dels must be modified")
      (assert (= (.-additions e1) 12) "First entry additions must match 12")
      (assert (= (.-deletions e1) 5) "First entry deletions must match 5")
      (assert (= (.-status e2) "added") "Second entry with 0 deletions must be added")
      (assert (= (.-status e3) "deleted") "Third entry with 0 additions must be deleted")
      (assert (= (.-status e4) "binary") "Fourth binary entry with hyphen counts must be binary")
      (let [(cmp (diff/GitBranchCompare
                   :base "main"
                   :target "feature-branch"
                   :mergeBase "abc1234"
                   :ahead 3
                   :behind 1
                   :files entries
                   :totalAdditions 52
                   :totalDeletions 20))
            (fmtFull (diff/gitCompareFormat cmp 0))
            (fmtTrunc (diff/gitCompareFormat cmp 2))]
        (assert (string-contains? fmtFull ":git-compare :base \"main\" :target \"feature-branch\"") "Full compare format must contain base and target")
        (assert (string-contains? fmtFull ":merge-base \"abc1234\" :ahead 3 :behind 1") "Full compare format must contain merge-base and ahead/behind")
        (assert (string-contains? fmtFull ":files-count 4 :+ 52 :- 20") "Full compare format must report correct total file count and metrics")
        (assert (string-contains? fmtTrunc ":truncated true :total-files 4") "Truncated compare format must indicate truncation with total files 4")
        (assert (string-contains? fmtTrunc ":files-count 2") "Truncated compare format files-count must match limit 2")
        true))))

(df runTests [] -> Bool
  :d "Runs all falsifiable test suites for git diff parser and ASN summary formatter."
  (and (testSingleFileAndHunks)
       (and (testEmptyDiff)
            (and (testMultiFileAndOrdering)
                 (and (testSingleLineHunkHeader)
                      (testNumstatAndCompare))))))
