(module aslIntel/textScanTest :x [testScanDocOutline testExtractDocSection testSearchDocSnippets testFormatDocOutlineAsn testFormatSectionAsn runTests] :i [(textScan :a ts)])

fn sampleMarkdown -> Str
  (str "# Document Title\n\n" "Intro paragraph explaining the system.\n\n" "## Architecture Principles\n" "We operate under Effective Decision Mode.\n" "Always minimize code diffs.\n\n" "### Sub-Section A\n" "Detail on memory model.\n\n" "## Tool Reference\n" "- Tool 1: asl-intel\n" "- Tool 2: asl-mem\n")

fn testScanDocOutline -> Bool
  (let [(md (sampleMarkdown)) (outline (ts/scanDocOutline md "README.md"))] (assert (= outline.filePath "README.md") "Outline file-path must match README.md") (assert (> outline.totalLines 10) "Outline total lines must exceed 10") (assert (= (listLength outline.sections) 4) "Outline sections count must be 4") true)

fn testExtractDocSection -> Bool
  (let [(md (sampleMarkdown)) (sec (ts/extractDocSection md "Architecture Principles")) (missing (ts/extractDocSection md "Nonexistent Section"))] (assert (mt sec ((none) false) ((some body) (and (stringContains? body "Effective Decision Mode") (not (stringContains? body "Tool Reference"))))) "Section extraction must contain targeted content without trailing chapter") (assert (none? missing) "Missing section must return none") true)

fn testSearchDocSnippets -> Bool
  (let [(md (sampleMarkdown)) (matches (ts/searchDocSnippets md "asl-mem"))] (assert (= (listLength matches) 1) "Snippet search must match exactly 1 line") (assert (= (preludeHead matches).lineNumber 14) "Snippet line number must be 14") true)

fn testFormatDocOutlineAsn -> Bool
  (let [(md (sampleMarkdown)) (outline (ts/scanDocOutline md "TEST.md")) (asnStr (ts/formatDocOutlineAsn outline))] (assert (stringContains? asnStr "(:doc-outline :path \"TEST.md\"") "ASN outline must format :doc-outline path") (assert (stringContains? asnStr "(:h1 :title \"Document Title\"") "ASN outline must format :h1 title") true)

fn testFormatSectionAsn -> Bool
  (let [(res (ts/formatSectionAsn "DOC.md" "Header" "Content body"))] (assert (stringContains? res "(:doc-section :path \"DOC.md\"") "ASN section must format :doc-section path") (assert (stringContains? res ":title \"Header\"") "ASN section must format :title Header") true)

fn runTests -> Bool
  (let [(t1 (testScanDocOutline)) (t2 (testExtractDocSection)) (t3 (testSearchDocSnippets)) (t4 (testFormatDocOutlineAsn)) (t5 (testFormatSectionAsn))] (and t1 (and t2 (and t3 (and t4 t5)))))
