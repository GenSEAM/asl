(module asl-syntax/tests/markdown/markdownTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/corpus :a crp)
      (asl-syntax/markdown :a md)
      (asl-json/json :a j)])

fn fetchCommonMarkSpec! scratchPath: String -> (Result Bool String)
  (let [(_ (dirCreate "scratch"))
        (_ (dirCreate "scratch/commonmark"))
        (_ (dirCreate "scratch/commonmark/0.31.2"))
        (cmd (str "curl -sSfL --connect-timeout 10 https://spec.commonmark.org/0.31.2/spec.json -o " scratchPath))
        (res (processRun cmd))]
    (if (!= res.exitCode 0)
      (err (str "fetch failed (exit " (stringFromInt64 res.exitCode) "): " res.stderr))
      (mt (fileReadBytes scratchPath)
        ((err e) (err (str "read failed after fetch: " e)))
        ((ok bs)
         (let [(actualSha (bytesSha256 bs))
               (expectedSha "d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20")]
           (if (!= actualSha expectedSha)
             (err (str "sha256 mismatch: expected " expectedSha " got " actualSha))
             (ok true)))))))

fn ensureCommonMarkSpec! scratchPath: String -> (Result Bool String)
  (mt (fileReadBytes scratchPath)
    ((ok bs)
     (let [(actualSha (bytesSha256 bs))
           (expectedSha "d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20")]
       (if (= actualSha expectedSha)
         (ok true)
         (fetchCommonMarkSpec! scratchPath))))
    ((err _)
     (fetchCommonMarkSpec! scratchPath)))

fn testCommonMarkSpecFetchAndVerification! scratchPath: String -> Bool
  (mt (ensureCommonMarkSpec! scratchPath)
    ((err msg)
     (do
       (println (str "CommonMark spec 0.31.2 fetch failed (offline: skipped, never passed): " msg))
       (assert false (str "CommonMark spec fetch failed (offline: skipped, never passed): " msg))
       false))
    ((ok _)
     (mt (fileReadBytes scratchPath)
       ((err e) (do (assert false (str "read error on scratch spec: " e)) false))
       ((ok bs)
        (let [(actualSha (bytesSha256 bs))
              (expectedSha "d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20")]
          (do
            (assert (= actualSha expectedSha) "commonmark spec.json sha256 matches pinned hash")
            (let [(entry (crp/makeUpstreamEntry
                           "https://spec.commonmark.org/0.31.2/spec.json"
                           "0.31.2"
                           expectedSha
                           "CC-BY-SA-4.0"
                           scratchPath))]
              (do
                (assert (ok? (crp/verifyUpstreamEntry! entry)) "commonmark entry passes verification")
                (println "CommonMark spec version 0.31.2 license: CC-BY-SA-4.0 (fetched at runtime, not vendored)")
                (assert (= entry.license "CC-BY-SA-4.0") "recorded CommonMark spec license: CC-BY-SA-4.0")
                true))))))))

fn checkFilesLoop! files: (List String) count: Int64 -> Int64
  (if (listEmpty? files)
    count
    (let [(head (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))]
      (mt (fileReadString head)
        ((err e)
         (do
           (assert false (str "read error on " head ": " e))
           (checkFilesLoop! tail count)))
        ((ok content)
         (let [(root (md/parseMarkdown content))
               (len (stringLength content))
               (tiling (tr/checkTiling root len))
               (printed (pr/printTreeString content root))
               (okRound (and (ok? tiling) (= printed content)))]
           (do
             (assert okRound (str "round-trip " head))
             (if okRound
               (checkFilesLoop! tail (+ count 1))
               (checkFilesLoop! tail count))))))))

fn testTrackedMarkdownRoundTrip! -> Bool
  (mt (crp/gitTrackedFiles! "md")
    ((err msg) (do (assert false msg) false))
    ((ok files)
     (let [(total (listLength files))
           (passed (checkFilesLoop! files 0))]
       (do
         (assert (= total 208) (str "pinned tracked md files total == 208: " (stringFromInt64 total)))
         (assert (= passed total) (str "all files passed round-trip: " (stringFromInt64 passed) " / " (stringFromInt64 total)))
         true))))

fn formatSectionLine s: md/MarkdownSection -> String
  (str (stringFromInt64 (md/sectionLevel s)) ":"
       (stringFromInt64 (md/sectionHeadingStart s)) ":"
       (stringFromInt64 (md/sectionHeadingEnd s)) ":"
       (stringFromInt64 (md/sectionStart s)) ":"
       (stringFromInt64 (md/sectionEnd s)) ":"
       (md/sectionTitle s))

fn formatSections secs: (List md/MarkdownSection) acc: (List String) -> String
  (if (listEmpty? secs)
    (stringJoin (listReverse acc) "\n")
    (let [(head (optionOr (listHead secs) (md/MarkdownSection :title "" :level 0 :kind "" :start 0 :end 0 :headingStart 0 :headingEnd 0 :startLine 0 :endLine 0)))
          (rest (optionOr (listTail secs) (list)))
          (line (formatSectionLine head))]
      (formatSections rest (cons line acc))))

fn getAslSections! path: String -> String
  (mt (fileReadString path)
    ((err _) "")
    ((ok content)
     (let [(root (md/parseMarkdown content))
           (secs (md/markdownSections root content))]
       (formatSections secs (list)))))

fn testSectionQueries! -> Bool
  (mt (fileReadString "README.md")
    ((err _) false)
    ((ok content)
     (let [(hr (md/markdownHeadingRange content "Gates"))
           (sr (md/markdownSectionRange content "Gates"))
           (secText (md/markdownReadSection content "Gates"))]
       (do
         (assert (some? hr) "Gates heading range found")
         (assert (some? sr) "Gates section range found")
         (assert (some? secText) "Gates section content found")
         (mt secText
           ((some s)
            (do
              (assert (stringStartsWith? s "## Gates") "section content starts with heading")
              (assert (stringContains? s "./bin/asl audit gates") "section content contains gates text")))
           ((none) (assert false "expected section text")))
         true))))

fn isBlockSection? sec: String -> Bool
  (or (= sec "ATX headings")
  (or (= sec "Setext headings")
  (or (= sec "Thematic breaks")
  (or (= sec "Fenced code blocks")
  (or (= sec "Indented code blocks")
  (or (= sec "HTML blocks")
  (or (= sec "Block quotes")
      (= sec "Blank lines"))))))))

fn getJsonString obj: j/Json key: String -> String
  (mt (j/jsonGet obj key)
    ((some val)
     (mt val
       ((j/jstr s) s)
       (_ "")))
    ((none) ""))

fn getJsonInt obj: j/Json key: String -> Int64
  (mt (j/jsonGet obj key)
    ((some val)
     (mt val
       ((j/jint i) i)
       (_ 0)))
    ((none) 0))

fn checkExamplesLoop items: (List j/Json) totalTested: Int64 passCount: Int64 -> (Pair Int64 Int64)
  (if (listEmpty? items)
    (pair totalTested passCount)
    (let [(head (optionOr (listHead items) (j/jnull)))
          (tail (optionOr (listTail items) (list)))
          (sec (getJsonString head "section"))]
      (if (not (isBlockSection? sec))
        (checkExamplesLoop tail totalTested passCount)
        (let [(exNum (getJsonInt head "example"))
              (mdText (getJsonString head "markdown"))
              (root (md/parseMarkdown mdText))
              (len (stringLength mdText))
              (tiling (tr/checkTiling root len))
              (printed (pr/printTreeString mdText root))
              (okCase (and (ok? tiling) (= printed mdText)))]
          (do
            (assert okCase (str "CommonMark example " (stringFromInt64 exNum) " block structure"))
            (if okCase
              (checkExamplesLoop tail (+ totalTested 1) (+ passCount 1))
              (checkExamplesLoop tail (+ totalTested 1) passCount)))))))

fn testCommonMarkSubset! scratchPath: String -> Bool
  (mt (ensureCommonMarkSpec! scratchPath)
    ((err msg)
     (do
       (println (str "CommonMark spec 0.31.2 unavailable (offline: skipped, never passed): " msg))
       (assert false (str "CommonMark spec unavailable (offline: skipped, never passed): " msg))
       false))
    ((ok _)
     (mt (fileReadString scratchPath)
       ((err e) (do (assert false (str "read error on scratch spec: " e)) false))
       ((ok content)
        (let [(parseRes (j/jsonParse content))]
          (do
            (assert (ok? parseRes) "spec.json parses")
            (mt (resultOr parseRes (j/jnull))
              ((j/jarr items)
               (let [(res (checkExamplesLoop items 0 0))
                     (tested (pairFirst res))
                     (passed (pairSecond res))
                     (excluded 0)]
                 (do
                   (println (str "CommonMark spec block subset: " (stringFromInt64 passed) " run/passed, " (stringFromInt64 excluded) " excluded (0 excluded: full block subset supported)"))
                   (assert (= tested 175) (str "tested 175 block structure examples: " (stringFromInt64 tested)))
                   (assert (= passed 175) (str "passed 175 block structure examples: " (stringFromInt64 passed)))
                   true)))
              (_ false))))))))

fn ! runTests -> Bool
  (let [(scratchPath "scratch/commonmark/0.31.2/spec.json")
        (r1 (testCommonMarkSpecFetchAndVerification! scratchPath))
        (r2 (testTrackedMarkdownRoundTrip!))
        (r3 (testSectionQueries!))
        (r4 (testCommonMarkSubset! scratchPath))]
    (and r1 (and r2 (and r3 r4))))
