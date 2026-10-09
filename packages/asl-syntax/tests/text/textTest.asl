(module asl-syntax/tests/text/textTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/text :a txt)])

fn testBinaryRefusal! -> Bool
  (let [(binPath "asl/packages/asl-forms/tests/fixtures/ws/image.png")
        (aslAnchor (resultOr (txt/readAnchorFileReceipt! binPath "PNG" 1 100) ""))]
    (assert (stringContains? aslAnchor "ERR_BINARY") "binary anchor refusal contains ERR_BINARY")
    (assert (stringContains? aslAnchor "png") "binary anchor refusal identifies png kind")
    true)

fn testAmbiguousAnchorRejected -> Bool
  (let [(text "apple banana apple cherry apple")
        (rAmb (txt/readAnchor text "apple" 0 100))
        (rRec (txt/readAnchorReceipt "fruits.txt" text "apple" 0 100))
        (rOcc1 (txt/readAnchor text "apple" 1 100))
        (rOcc2 (txt/readAnchor text "apple" 2 100))
        (rOcc4 (txt/readAnchor text "apple" 4 100))
        (rEdit (txt/textApplyAnchorEdit text "apple" "orange"))
        (rNotFound (txt/readAnchor text "mango" 0 100))]
    (assert (err? rAmb) "ambiguous anchor without occurrence is err")
    (mt rAmb
      ((err msg)
       (do
         (assert (stringContains? msg "ambiguous") "error message names ambiguous")
         (assert (stringContains? msg "3") "error message names 3 occurrences")))
      ((ok _) (assert false "expected ambiguous error")))
    (assert (stringContains? rRec "ERR_AMBIGUOUS_ANCHOR") "receipt reports ERR_AMBIGUOUS_ANCHOR")
    (assert (stringContains? rRec ":count 3") "receipt reports :count 3")
    (assert (ok? rOcc1) "occurrence 1 succeeds")
    (assert (ok? rOcc2) "occurrence 2 succeeds")
    (assert (err? rOcc4) "occurrence 4 out of bounds is err")
    (assert (err? rEdit) "anchor edit on ambiguous anchor rejected")
    (assert (err? rNotFound) "missing anchor is err")
    true)

fn testBlocksAndParagraphs -> Bool
  (let [(text "First paragraph line 1.\nFirst paragraph line 2.\n\nSecond paragraph line 1.\n\n\nThird paragraph line 1.\nThird paragraph line 2.\n")
        (blocks (txt/textBlocks text))
        (paras (txt/textParagraphs text))
        (root (txt/parseText text))
        (tiling (tr/checkTiling root (stringLength text)))
        (printed (pr/printTreeString text root))]
    (assert (= (listLength paras) 3) "found 3 paragraphs")
    (assert (>= (listLength blocks) 5) "found at least 5 blocks incl blank blocks")
    (assert (= root.kind "document") "root node kind is document")
    (assert (= root.start 0) "root node start is 0")
    (assert (= root.end (stringLength text)) "root node end is length")
    (assert (ok? tiling) "tree tiling check passes")
    (assert (= printed text) "lossless print of text tree equals original text")
    true)

fn testHeadingDetection -> Bool
  (let [(text "CHAPTER ONE: BEGINNING\n\nSome intro text.\n\nSetext Title 1\n==============\nParagraph under setext 1.\n\nSetext Title 2\n--------------\nParagraph under setext 2.\n\n1. Numbered Heading\nSome numbered section text.\n\n2.3 Nested Numbered\nMore nested section text.\n\n[database_config]\nhost = 127.0.0.1\n\nauthor: Jane Doe\n")
        (s (src/sourceFromString "headings.txt" text))
        (headings (txt/detectHeadings s text))]
    (assert (= (listLength headings) 7) "detected 7 headings")
    (let [(h0 (optionOr (listGet headings 0) (txt/HeadingInfo :name "" :kind "" :level 0 :line 0 :start 0 :end 0)))
          (h1 (optionOr (listGet headings 1) (txt/HeadingInfo :name "" :kind "" :level 0 :line 0 :start 0 :end 0)))
          (h2 (optionOr (listGet headings 2) (txt/HeadingInfo :name "" :kind "" :level 0 :line 0 :start 0 :end 0)))
          (h3 (optionOr (listGet headings 3) (txt/HeadingInfo :name "" :kind "" :level 0 :line 0 :start 0 :end 0)))
          (h4 (optionOr (listGet headings 4) (txt/HeadingInfo :name "" :kind "" :level 0 :line 0 :start 0 :end 0)))
          (h5 (optionOr (listGet headings 5) (txt/HeadingInfo :name "" :kind "" :level 0 :line 0 :start 0 :end 0)))
          (h6 (optionOr (listGet headings 6) (txt/HeadingInfo :name "" :kind "" :level 0 :line 0 :start 0 :end 0)))]
      (assert (= (txt/headingName h0) "CHAPTER ONE: BEGINNING") "h0 is allcaps name")
      (assert (= (txt/headingLevel h0) 1) "h0 is level 1")
      (assert (= (txt/headingName h1) "Setext Title 1") "h1 is setext 1 name")
      (assert (= (txt/headingLevel h1) 1) "h1 is level 1")
      (assert (= (txt/headingName h2) "Setext Title 2") "h2 is setext 2 name")
      (assert (= (txt/headingLevel h2) 2) "h2 is level 2")
      (assert (stringContains? (txt/headingName h3) "Numbered Heading") "h3 is numbered name")
      (assert (stringContains? (txt/headingName h4) "Nested Numbered") "h4 is nested numbered name")
      (assert (= (txt/headingName h5) "database_config") "h5 is section name")
      (assert (= (txt/headingKind h5) "section") "h5 is section kind")
      (assert (= (txt/headingName h6) "author") "h6 is key name")
      (assert (= (txt/headingKind h6) "key") "h6 is key kind"))
    true)

fn testTextOutlineAndSymbols -> Bool
  (let [(text "DOCUMENT TITLE\n\n[config]\nport: 8080\n")
        (s (src/sourceFromString "doc.txt" text))
        (syms (txt/textSymbols s text))
        (items (txt/textOutlineItems s text))
        (receipt (txt/textOutlineReceipt "doc.txt" text))]
    (assert (= (listLength syms) 3) "symbols count is 3")
    (assert (= (listLength items) 3) "outline items count is 3")
    (assert (stringContains? receipt "(:outline :status :ok :file \"doc.txt\" :language \"text\" :itemsCount 3") "outline receipt matches format")
    (assert (stringContains? receipt ":name \"DOCUMENT TITLE\"") "outline receipt has DOCUMENT TITLE")
    (assert (stringContains? receipt ":name \"config\"") "outline receipt has config")
    (assert (stringContains? receipt ":name \"port\"") "outline receipt has port")
    true)

fn testAnchorEdit -> Bool
  (let [(text "The quick brown fox jumps over the lazy dog.")
        (rEdit (txt/textApplyAnchorEdit text "quick brown fox" "slow white cat"))
        (rWithTree (txt/textApplyAnchorEditWithTree text "lazy dog" "sleepy puppy"))]
    (assert (ok? rEdit) "anchor edit succeeds")
    (assert (= (resultOr rEdit "") "The slow white cat jumps over the lazy dog.") "text replaced correctly")
    (assert (ok? rWithTree) "anchor edit with tree succeeds")
    (mt rWithTree
      ((ok res)
       (do
         (assert (= (sym/editResultNewText res) "The quick brown fox jumps over the sleepy puppy.") "tree edit text matches")
         (assert (not (sym/hasErrorNode (sym/editResultRoot res))) "tree edit has no error node")
         (assert (= (sym/editResultRoot res).kind "document") "tree root is document")))
      ((err _) (assert false "expected ok tree edit")))
    true)

fn testReadRangeDirectContent -> Bool
  (let [(text "line 1\nline 2\nline 3\nline 4\n")
        (r1 (txt/readRange text 2 3 200 12000))
        (rBad (txt/readRange text 10 20 200 12000))]
    (assert (ok? r1) "readRange ok")
    (assert (= (resultOr r1 "") "line 2\nline 3\n") "readRange slices correct lines")
    (assert (err? rBad) "readRange out of bounds is err")
    true)

fn testEmptyAndSingleLineCases -> Bool
  (let [(rootEmpty (txt/parseText ""))
        (blocksEmpty (txt/textBlocks ""))
        (parasEmpty (txt/textParagraphs ""))
        (headingsEmpty (txt/detectHeadings (src/sourceFromString "empty.txt" "") ""))
        (tilingEmpty (tr/checkTiling rootEmpty 0))
        (singleText "Just a single line without newline")
        (rootSingle (txt/parseText singleText))
        (tilingSingle (tr/checkTiling rootSingle (stringLength singleText)))
        (printedSingle (pr/printTreeString singleText rootSingle))
        (blocksSingle (txt/textBlocks singleText))
        (parasSingle (txt/textParagraphs singleText))]
    (assert (= rootEmpty.kind "document") "empty root kind is document")
    (assert (= (listLength blocksEmpty) 0) "empty blocks count is 0")
    (assert (= (listLength parasEmpty) 0) "empty paras count is 0")
    (assert (= (listLength headingsEmpty) 0) "empty headings count is 0")
    (assert (ok? tilingEmpty) "empty tiling passes")
    (assert (= rootSingle.kind "document") "single line root kind is document")
    (assert (= (listLength blocksSingle) 1) "single line has 1 block")
    (assert (= (listLength parasSingle) 1) "single line has 1 paragraph")
    (assert (ok? tilingSingle) "single line tiling passes")
    (assert (= printedSingle singleText) "single line print matches")
    true)

fn testLoneCrTextHandling -> Bool
  (let [(crText "Line A\rLine B\r\rLine C\r")
        (root (txt/parseText crText))
        (tiling (tr/checkTiling root (stringLength crText)))
        (printed (pr/printTreeString crText root))
        (paras (txt/textParagraphs crText))]
    (assert (ok? tiling) "lone cr text tiling passes")
    (assert (= printed crText) "lone cr text printed matches")
    (assert (= (listLength paras) 2) "lone cr text has 2 paragraphs")
    true)

fn ! runTests -> Bool
  (let [(r1 (testBinaryRefusal!))
        (r2 (testAmbiguousAnchorRejected))
        (r3 (testBlocksAndParagraphs))
        (r4 (testHeadingDetection))
        (r5 (testTextOutlineAndSymbols))
        (r6 (testAnchorEdit))
        (r7 (testReadRangeDirectContent))
        (r8 (testEmptyAndSingleLineCases))
        (r9 (testLoneCrTextHandling))]
    (and r1
    (and r2
    (and r3
    (and r4
    (and r5
    (and r6
    (and r7
    (and r8
         r9)))))))))
