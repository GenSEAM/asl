(module asl-syntax/tests/markdown/sectionTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/markdown :a md)
      (asl-syntax/markdownSymbols :a mds)
      (asl-syntax/json :a jcst)
      (asl-json/json :a j)])

fn ! runTests -> Bool
  (do
    (assert (testUniqueHeadings) "unique headings resolved")
    (assert (testDuplicateAmbiguity) "duplicate headings reported ambiguous")
    (assert (testPathDisambiguation) "duplicate headings resolved by path")
    (assert (testMultiLevelHierarchy) "multi-level hierarchy resolved")
    (assert (testDuplicatePathAmbiguity) "duplicate headings with same path reported ambiguous")
    (assert (testNotFoundHeading) "not found heading returns error")
    (assert (testSetextHeadings) "setext headings resolved")
    (assert (testMarkdownOutline) "markdown outline receipt generated")
    (assert (testFenceDelegation) "json fence yields JSON subtree through registry")
    (assert (testTrackedReadme!) "real tracked README.md symbols and sections")
    true)

fn testUniqueHeadings -> Bool
  (let [(doc "# Welcome\nIntroductory text.\n\n## Features\nList of features.\n\n### Speed\nFast execution.\n")
        (r1 (mds/resolveHeadingSymbol doc "Welcome"))
        (r2 (mds/resolveHeadingSymbol doc "# Welcome"))
        (r3 (mds/resolveHeadingSymbol doc "Features"))
        (r4 (mds/resolveHeadingSymbol doc "## Features"))
        (r5 (mds/resolveHeadingSymbol doc "Speed"))
        (r6 (mds/resolveHeadingSymbol doc "### Speed"))
        (readSec (mds/markdownReadSymbol doc "Features"))]
    (do
      (assert (ok? r1) "Welcome resolves")
      (assert (= (sym/symbolName (resultOr r1 (sym/makeSymbolDef "" "" 0 0))) "Welcome") "Welcome name matches")
      (assert (ok? r2) "# Welcome with hash resolves")
      (assert (ok? r3) "Features resolves")
      (assert (ok? r4) "## Features with hash resolves")
      (assert (ok? r5) "Speed resolves")
      (assert (ok? r6) "### Speed with hash resolves")
      (assert (ok? readSec) "Features section read succeeds")
      (assert (stringStartsWith? (resultOr readSec "") "## Features") "Features content starts with heading")
      (assert (stringContains? (resultOr readSec "") "List of features.") "Features content contains body")
      true))

fn testDuplicateAmbiguity -> Bool
  (let [(doc "# Guide\nGuide intro.\n\n## Options\nGuide options.\n\n# Reference\nRef intro.\n\n## Options\nReference options.\n")
        (rAmb (mds/resolveHeadingSymbol doc "Options"))
        (rHashAmb (mds/resolveHeadingSymbol doc "## Options"))
        (rcpt (mds/markdownReadSymbolReceipt "doc.md" doc "Options"))]
    (do
      (assert (err? rAmb) "bare Options is ambiguous")
      (mt rAmb
        ((ok _) (assert false "expected ambiguous error"))
        ((err msg)
         (do
           (assert (stringContains? msg "ambiguous") "error message names ambiguous")
           (assert (stringContains? msg "2 occurrences") "error message names 2 occurrences"))))
      (assert (err? rHashAmb) "## Options is ambiguous")
      (assert (stringContains? rcpt "ERR_AMBIGUOUS_SYMBOL") "receipt error is ERR_AMBIGUOUS_SYMBOL")
      (assert (stringContains? rcpt ":count 2") "receipt contains :count 2")
      true))

fn testPathDisambiguation -> Bool
  (let [(doc "# Guide\nGuide intro.\n\n## Options\nGuide options.\n\n# Reference\nRef intro.\n\n## Options\nReference options.\n")
        (r1 (mds/resolveHeadingSymbol doc "Guide/Options"))
        (r2 (mds/resolveHeadingSymbol doc "Reference/Options"))
        (r3 (mds/resolveHeadingSymbol doc "Guide/## Options"))
        (r4 (mds/resolveHeadingSymbol doc "Reference.Options"))
        (sec1 (resultOr (mds/markdownReadSymbol doc "Guide/Options") ""))
        (sec2 (resultOr (mds/markdownReadSymbol doc "Reference/Options") ""))]
    (do
      (assert (ok? r1) "Guide/Options resolves uniquely")
      (assert (= (sym/symbolContainer (resultOr r1 (sym/makeSymbolDef "" "" 0 0))) "Guide") "Guide/Options container is Guide")
      (assert (ok? r2) "Reference/Options resolves uniquely")
      (assert (= (sym/symbolContainer (resultOr r2 (sym/makeSymbolDef "" "" 0 0))) "Reference") "Reference/Options container is Reference")
      (assert (ok? r3) "Guide/## Options resolves")
      (assert (ok? r4) "Reference.Options dotted path resolves")
      (assert (stringContains? sec1 "Guide options.") "sec1 contains Guide options")
      (assert (stringContains? sec2 "Reference options.") "sec2 contains Reference options")
      true))

fn testMultiLevelHierarchy -> Bool
  (let [(doc "# Section A\nIntro A\n\n## Sub\nSub A\n\n### Detail\nDetail A\n\n# Section B\nIntro B\n\n## Sub\nSub B\n\n### Detail\nDetail B\n")
        (rDetAmb (mds/resolveHeadingSymbol doc "Detail"))
        (rSubAmb (mds/resolveHeadingSymbol doc "Sub"))
        (rA1 (mds/resolveHeadingSymbol doc "Section A/Sub/Detail"))
        (rB1 (mds/resolveHeadingSymbol doc "Section B/Sub/Detail"))
        (rA2 (mds/resolveHeadingSymbol doc "Section A/Detail"))
        (rB2 (mds/resolveHeadingSymbol doc "Section B/Detail"))
        (rASub (mds/resolveHeadingSymbol doc "Section A/Sub"))
        (rBSub (mds/resolveHeadingSymbol doc "Section B/Sub"))]
    (do
      (assert (err? rDetAmb) "bare Detail is ambiguous")
      (assert (err? rSubAmb) "bare Sub is ambiguous")
      (assert (ok? rA1) "Section A/Sub/Detail resolves")
      (assert (ok? rB1) "Section B/Sub/Detail resolves")
      (assert (ok? rA2) "Section A/Detail ancestor path resolves")
      (assert (ok? rB2) "Section B/Detail ancestor path resolves")
      (assert (ok? rASub) "Section A/Sub resolves")
      (assert (ok? rBSub) "Section B/Sub resolves")
      (let [(secA (resultOr (mds/markdownReadSymbol doc "Section A/Sub/Detail") ""))
            (secB (resultOr (mds/markdownReadSymbol doc "Section B/Sub/Detail") ""))]
        (do
          (assert (stringContains? secA "Detail A") "Detail A content matches")
          (assert (stringContains? secB "Detail B") "Detail B content matches")
          true))))

fn testDuplicatePathAmbiguity -> Bool
  (let [(doc "# Chapter 1\nIntro\n\n## Exercise\nFirst exercise\n\n## Exercise\nSecond exercise\n")
        (rDup (mds/resolveHeadingSymbol doc "Chapter 1/Exercise"))]
    (do
      (assert (err? rDup) "Chapter 1/Exercise is ambiguous with 2 matches")
      (mt rDup
        ((ok _) (assert false "expected ambiguous error"))
        ((err msg)
         (do
           (assert (stringContains? msg "ambiguous") "error names ambiguous")
           (assert (stringContains? msg "2 occurrences") "error names 2 occurrences"))))
      true))

fn testNotFoundHeading -> Bool
  (let [(doc "# Overview\nSome text.\n")
        (rNone (mds/resolveHeadingSymbol doc "Nonexistent"))
        (rcpt (mds/markdownReadSymbolReceipt "test.md" doc "Nonexistent"))]
    (do
      (assert (err? rNone) "Nonexistent heading is err")
      (mt rNone
        ((ok _) (assert false "expected not found error"))
        ((err msg) (assert (stringContains? msg "not found") "error names not found")))
      (assert (stringContains? rcpt "ERR_SYMBOL_NOT_FOUND") "receipt error is ERR_SYMBOL_NOT_FOUND")
      true))

fn testSetextHeadings -> Bool
  (let [(doc "Main Title\n==========\nIntro text.\n\nSubtitle\n--------\nSection content.\n")
        (r1 (mds/resolveHeadingSymbol doc "Main Title"))
        (r2 (mds/resolveHeadingSymbol doc "Subtitle"))
        (rPath (mds/resolveHeadingSymbol doc "Main Title/Subtitle"))]
    (do
      (assert (ok? r1) "setext level 1 resolves")
      (assert (ok? r2) "setext level 2 resolves")
      (assert (ok? rPath) "setext Parent/Child path resolves")
      (let [(sec (resultOr (mds/markdownReadSymbol doc "Subtitle") ""))]
        (do
          (assert (stringStartsWith? sec "Subtitle") "Subtitle section starts with Subtitle")
          (assert (stringContains? sec "Section content.") "Subtitle section contains body")
          true))))

fn testMarkdownOutline -> Bool
  (let [(doc "# Intro\nText.\n\n## Features\nMore text.\n\n### Fast\nSuper fast.\n")
        (s (src/sourceFromString "doc.md" doc))
        (root (md/parseMarkdown doc))
        (items (mds/markdownOutlineItems root s doc))
        (receipt (mds/markdownOutlineReceipt "doc.md" doc))]
    (do
      (assert (= (listLength items) 3) "3 outline items")
      (let [(it1 (optionOr (listGet items 0) (out/makeOutlineItem "" "" 0 0)))
            (it2 (optionOr (listGet items 1) (out/makeOutlineItem "" "" 0 0)))
            (it3 (optionOr (listGet items 2) (out/makeOutlineItem "" "" 0 0)))]
        (do
          (assert (= it1.name "Intro") "item 1 name is Intro")
          (assert (= it1.startLine 1) "item 1 start line is 1")
          (assert (= it2.name "Features") "item 2 name is Features")
          (assert (= it2.startLine 4) "item 2 start line is 4")
          (assert (= it3.name "Fast") "item 3 name is Fast")
          (assert (= it3.startLine 7) "item 3 start line is 7")))
      (assert (stringStartsWith? receipt "(:outline :status :ok :file \"doc.md\" :language \"markdown\" :itemsCount 3") "outline receipt format matches")
      (assert (stringContains? receipt ":name \"Intro\"") "receipt contains Intro")
      (assert (stringContains? receipt ":name \"Features\"") "receipt contains Features")
      (assert (stringContains? receipt ":name \"Fast\"") "receipt contains Fast")
      true))

fn testFenceDelegation -> Bool
  (let [(doc "# Architecture\n\n```json\n{\n  \"name\": \"asl-syntax\",\n  \"version\": 1,\n  \"valid\": true\n}\n```\n\nPlain text follows.\n\n```\nraw block\n```\n")
        (root (md/parseMarkdown doc))
        (fences (mds/extractFences root doc))]
    (do
      (assert (= (listLength fences) 2) "found 2 fences")
      (let [(f1 (optionOr (listGet fences 0) (mds/makeMarkdownFence "" "" 0 0 0 0 "" (none))))
            (f2 (optionOr (listGet fences 1) (mds/makeMarkdownFence "" "" 0 0 0 0 "" (none))))]
        (do
          (assert (= f1.info "json") "fence 1 info is json")
          (assert (= f1.language "json") "fence 1 language is json")
          (assert (stringContains? f1.content "\"asl-syntax\"") "fence 1 content has json body")
          (let [(del1 (mds/delegateFence f1))]
            (do
              (assert (mds/hasFenceSubtree? del1) "delegated json fence has subtree")
              (mt del1.subtree
                ((none) (assert false "expected json subtree"))
                ((some sub)
                 (do
                   (assert (= (tr/nodeKind sub) "document") "json subtree is document node")
                   (assert (ok? (tr/checkTilingRoot sub)) "json subtree passes tiling check")
                   (assert (jcst/isValid sub) "json subtree isValid")
                   (let [(lowered (jcst/lower sub f1.content))]
                     (do
                       (assert (ok? lowered) "json subtree lowers to Json")
                       (assert (= lowered (j/jsonParse f1.content)) "lowered equals jsonParse"))))))))
          (assert (= f2.info "") "fence 2 info is empty")
          (assert (= f2.language "") "fence 2 language is empty")
          (let [(del2 (mds/delegateFence f2))]
            (assert (not (mds/hasFenceSubtree? del2)) "empty fence has no subtree"))))
      (let [(delFences (mds/delegateMarkdownFences root doc))
            (firstDel (optionOr (listHead delFences) (mds/makeMarkdownFence "" "" 0 0 0 0 "" (none))))]
        (assert (mds/hasFenceSubtree? firstDel) "delegateMarkdownFences delegates json fence"))
      true))

fn testTrackedReadme! -> Bool
  (mt (fileReadString "README.md")
    ((err e) (do (assert false (str "read error on README.md: " e)) false))
    ((ok content)
     (let [(syms (mds/markdownHeadingSymbols content))
           (receipt (mds/markdownOutlineReceipt "README.md" content))]
       (do
         (assert (> (listLength syms) 0) "README.md has heading symbols")
         (assert (stringContains? receipt ":language \"markdown\"") "receipt language is markdown")
         (assert (stringContains? receipt ":file \"README.md\"") "receipt file is README.md")
         true))))
