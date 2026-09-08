(module asl-sh/git-diff-test
  :d "Falsifiable test suite for pure ASL unified diff parser and token-optimized ASN diff summary codec."
  :x [run-tests]
  :i [(git_diff :a diff)])

(df test-single-file-and-hunks [] -> Bool
  :d "Verifies single-file parsing, hunk coordinates, addition/deletion metrics, and path extraction."
  (let [(diff-text (str "diff --git a/src/main.rs b/src/main.rs\n"
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
        (files (diff/git-diff-parse diff-text))]
    (assert (= (list-length files) 1) "Single file diff must parse into exactly 1 GitDiffFile")
    (let [(f (option-or (list-get files 0) (diff/GitDiffFile :old-path "" :new-path "" :hunks (list) :additions 0 :deletions 0)))
          (hunks (.-hunks f))]
      (assert (= (.-old-path f) "src/main.rs") "Old path must be extracted as src/main.rs")
      (assert (= (.-new-path f) "src/main.rs") "New path must be extracted as src/main.rs")
      (assert (= (list-length hunks) 2) "Multi-hunk diff must parse into exactly 2 hunks")
      (let [(h1 (option-or (list-get hunks 0) (diff/GitDiffHunk :old-start 0 :old-count 0 :new-start 0 :new-count 0 :lines (list))))
            (h2 (option-or (list-get hunks 1) (diff/GitDiffHunk :old-start 0 :old-count 0 :new-start 0 :new-count 0 :lines (list))))]
        (assert (= (.-old-start h1) 10) "Hunk 1 old-start must match 10")
        (assert (= (.-old-count h1) 4) "Hunk 1 old-count must match 4")
        (assert (= (.-new-start h1) 10) "Hunk 1 new-start must match 10")
        (assert (= (.-new-count h1) 5) "Hunk 1 new-count must match 5")
        (assert (= (.-old-start h2) 20) "Hunk 2 old-start must match 20")
        (assert (= (.-new-start h2) 21) "Hunk 2 new-start must match 21")
        (assert (= (.-additions f) 2) "Addition count must match added lines excluding header")
        (assert (= (.-deletions f) 2) "Deletion count must match deleted lines excluding header")
        true))))

(df test-empty-diff [] -> Bool
  :d "Verifies empty and whitespace-only diff strings parse into empty lists and zeroed ASN summary."
  (let [(files (diff/git-diff-parse ""))
        (summary (diff/git-diff-summary files))
        (ws-files (diff/git-diff-parse "   \n\n  \t "))
        (ws-summary (diff/git-diff-summary ws-files))]
    (assert (= (list-length files) 0) "Empty diff text must parse into 0 files")
    (assert (= (list-length ws-files) 0) "Whitespace diff text must parse into 0 files")
    (assert (= summary "(:diff-summary :files 0 :additions 0 :deletions 0 :hunks 0)") "Empty diff summary must report 0 files 0 additions 0 deletions 0 hunks")
    (assert (= ws-summary "(:diff-summary :files 0 :additions 0 :deletions 0 :hunks 0)") "Whitespace diff summary must report 0 files 0 additions 0 deletions 0 hunks")
    true))

(df test-multi-file-and-ordering [] -> Bool
  :d "Verifies multi-file diff parsing, order preservation, and aggregated ASN summary metrics."
  (let [(diff-text (str "diff --git a/pkg/a.txt b/pkg/a.txt\n"
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
        (files (diff/git-diff-parse diff-text))
        (summary (diff/git-diff-summary files))]
    (assert (= (list-length files) 2) "Multi-file diff must parse into 2 files")
    (let [(f1 (option-or (list-get files 0) (diff/GitDiffFile :old-path "" :new-path "" :hunks (list) :additions 0 :deletions 0)))
          (f2 (option-or (list-get files 1) (diff/GitDiffFile :old-path "" :new-path "" :hunks (list) :additions 0 :deletions 0)))]
      (assert (= (.-old-path f1) "pkg/a.txt") "First file old-path must be pkg/a.txt")
      (assert (= (.-old-path f2) "pkg/b.txt") "Second file old-path must be pkg/b.txt")
      (assert (= (.-additions f1) 1) "File 1 additions must be 1")
      (assert (= (.-deletions f1) 0) "File 1 deletions must be 0")
      (assert (= (.-additions f2) 0) "File 2 additions must be 0")
      (assert (= (.-deletions f2) 1) "File 2 deletions must be 1")
      (assert (= summary "(:diff-summary :files 2 :additions 1 :deletions 1 :hunks 2)") "Multi-file ASN summary must aggregate file metrics correctly")
      true)))

(df test-single-line-hunk-header [] -> Bool
  :d "Verifies single-line hunk headers without comma default line counts to 1."
  (let [(diff-text (str "--- a/single.txt\n"
                        "+++ b/single.txt\n"
                        "@@ -1 +1 @@\n"
                        "-old\n"
                        "+new\n"))
        (files (diff/git-diff-parse diff-text))]
    (assert (= (list-length files) 1) "Single-line hunk diff must parse into 1 file")
    (let [(f (option-or (list-get files 0) (diff/GitDiffFile :old-path "" :new-path "" :hunks (list) :additions 0 :deletions 0)))
          (hunks (.-hunks f))]
      (assert (= (list-length hunks) 1) "Must contain exactly 1 hunk")
      (let [(h (option-or (list-get hunks 0) (diff/GitDiffHunk :old-start 0 :old-count 0 :new-start 0 :new-count 0 :lines (list))))]
        (assert (= (.-old-start h) 1) "Single-line hunk old-start must be 1")
        (assert (= (.-old-count h) 1) "Single-line hunk without comma must default old-count to 1")
        (assert (= (.-new-start h) 1) "Single-line hunk new-start must be 1")
        (assert (= (.-new-count h) 1) "Single-line hunk without comma must default new-count to 1")
        (assert (= (.-additions f) 1) "Additions must equal 1")
        (assert (= (.-deletions f) 1) "Deletions must equal 1")
        true))))

(df run-tests [] -> Bool
  :d "Runs all falsifiable test suites for git diff parser and ASN summary formatter."
  (and (test-single-file-and-hunks)
       (and (test-empty-diff)
            (and (test-multi-file-and-ordering)
                 (test-single-line-hunk-header)))))

(run-tests)
