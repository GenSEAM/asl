(module asl-syntax/tests/html/treeTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/html/lex :a hlx)
      (asl-syntax/html/tree :a htr)])

fn verifyValidHtml text: String -> Bool
  (let [(root (htr/parseHtml text))
        (len (stringLength text))
        (tilingRes (tr/checkTiling root len))
        (printed (pr/printTreeString text root))]
    (assert (ok? tilingRes) "tiling check succeeds on valid HTML")
    (assert (= printed text) "print is byte-exact on valid HTML")
    (assert (htr/isWellFormed root) "isWellFormed returns true on valid HTML")
    (assert (not (sym/hasErrorNode root)) "hasErrorNode is false on valid HTML")
    true)

fn verifyRecoveryHtml text: String -> Bool
  (let [(root (htr/parseHtml text))
        (len (stringLength text))
        (tilingRes (tr/checkTiling root len))
        (printed (pr/printTreeString text root))]
    (assert (ok? tilingRes) "tiling check succeeds on broken HTML")
    (assert (= printed text) "print is byte-exact on broken HTML")
    (assert (not (htr/isWellFormed root)) "isWellFormed returns false on broken HTML")
    (assert (sym/hasErrorNode root) "hasErrorNode is true on broken HTML")
    true)

fn testVoidElementsFixtures -> Bool
  (do
    (verifyValidHtml "<br>")
    (verifyValidHtml "<hr>")
    (verifyValidHtml "<img src=\"test.png\" alt=\"image\">")
    (verifyValidHtml "<meta charset=\"utf-8\">")
    (verifyValidHtml "<input type=\"text\" value=\"test\">")
    (verifyValidHtml "<link rel=\"stylesheet\" href=\"style.css\">")
    (verifyValidHtml "<area shape=\"rect\" coords=\"0,0,10,10\">")
    (verifyValidHtml "<base href=\"https://example.com/\">")
    (verifyValidHtml "<col span=\"2\">")
    (verifyValidHtml "<embed src=\"test.swf\">")
    (verifyValidHtml "<param name=\"color\" value=\"blue\">")
    (verifyValidHtml "<source src=\"test.mp4\" type=\"video/mp4\">")
    (verifyValidHtml "<track kind=\"subtitles\" src=\"subs.vtt\">")
    (verifyValidHtml "<wbr>")
    (verifyValidHtml "<input type=\"checkbox\" />")
    (verifyValidHtml "<hr />")
    (let [(s "<div><img src=\"pic.png\"><p>Paragraph text</p></div>")
          (root (htr/parseHtml s))
          (divOpt (htr/documentRootElement root))]
      (assert (some? divOpt) "root element found")
      (mt divOpt
        ((none) false)
        ((some divNode)
         (let [(children (htr/elementChildren divNode))]
           (assert (= (listLength children) 2) "div has exactly 2 element children")
           (let [(c1 (optionOr (listGet children 0) (tr/makeNode "" 0 0 (list))))
                 (c2 (optionOr (listGet children 1) (tr/makeNode "" 0 0 (list))))]
             (assert (= (htr/elementName c1) "img") "first child of div is img")
             (assert (= (htr/elementName c2) "p") "second child of div is p")
             true)))))
    true)

fn testImpliedEndTagsFixtures -> Bool
  (do
    (let [(s1 "<p>First paragraph<p>Second paragraph")
          (root1 (htr/parseHtml s1))
          (elems1 (filter (fn [(n tr/Node)] -> Bool (= (htr/elementName n) "p"))
                          (htr/elementChildren root1)))]
      (verifyValidHtml s1)
      (assert (= (listLength elems1) 2) "p closed by next p yields 2 paragraphs"))
    (let [(s2 "<p>Intro text<div>Block element</div>")
          (root2 (htr/parseHtml s2))
          (elems2 (htr/elementChildren root2))]
      (verifyValidHtml s2)
      (assert (= (listLength elems2) 2) "p closed by div yields 2 siblings")
      (let [(e1 (optionOr (listGet elems2 0) (tr/makeNode "" 0 0 (list))))
            (e2 (optionOr (listGet elems2 1) (tr/makeNode "" 0 0 (list))))]
        (assert (= (htr/elementName e1) "p") "first is p")
        (assert (= (htr/elementName e2) "div") "second is div")))
    (let [(s3 "<ul><li>Item 1<li>Item 2<li>Item 3</ul>")
          (root3 (htr/parseHtml s3))
          (ulOpt (htr/documentRootElement root3))]
      (verifyValidHtml s3)
      (assert (some? ulOpt) "ul found")
      (mt ulOpt
        ((none) (assert false "missing ulNode"))
        ((some ulNode)
         (let [(items (htr/elementChildren ulNode))]
           (assert (= (listLength items) 3) "ul contains 3 li children")))))
    (let [(s4 "<dl><dt>Term 1<dd>Def 1<dt>Term 2<dd>Def 2</dl>")
          (root4 (htr/parseHtml s4))
          (dlOpt (htr/documentRootElement root4))]
      (verifyValidHtml s4)
      (assert (some? dlOpt) "dl found")
      (mt dlOpt
        ((none) (assert false "missing dlNode"))
        ((some dlNode)
         (let [(items (htr/elementChildren dlNode))]
           (assert (= (listLength items) 4) "dl contains 4 dt/dd children")))))
    (let [(s5 "<table><tr><td>Cell 1<td>Cell 2<tr><th>Head 1<td>Cell 3</table>")
          (root5 (htr/parseHtml s5))
          (tblOpt (htr/documentRootElement root5))]
      (verifyValidHtml s5)
      (assert (some? tblOpt) "table found")
      (mt tblOpt
        ((none) (assert false "missing tblNode"))
        ((some tblNode)
         (let [(rows (htr/elementChildren tblNode))]
           (assert (= (listLength rows) 2) "table contains 2 tr rows")
           (let [(r1 (optionOr (listGet rows 0) (tr/makeNode "" 0 0 (list))))
                 (r2 (optionOr (listGet rows 1) (tr/makeNode "" 0 0 (list))))]
             (assert (= (listLength (htr/elementChildren r1)) 2) "row 1 has 2 cells")
             (assert (= (listLength (htr/elementChildren r2)) 2) "row 2 has 2 cells"))))))
    (let [(s6 "<select><option>One<option>Two</select>")
          (root6 (htr/parseHtml s6))
          (selOpt (htr/documentRootElement root6))]
      (verifyValidHtml s6)
      (assert (some? selOpt) "select found")
      (mt selOpt
        ((none) (assert false "missing selNode"))
        ((some selNode)
         (let [(opts (htr/elementChildren selNode))]
           (assert (= (listLength opts) 2) "select contains 2 option children")))))
    true)

fn testRecoveryFixtures -> Bool
  (do
    (let [(s1 "<div>Hello</p>World</div>")]
      (verifyRecoveryHtml s1))
    (let [(s2 "<p>Intro text</div>")]
      (verifyRecoveryHtml s2))
    (let [(s3 "<div><span>unclosed span</div>")]
      (verifyRecoveryHtml s3))
    (let [(s4 "<div><section>unclosed at eof")]
      (verifyRecoveryHtml s4))
    (let [(s5 "<p>Hello</br>World</p>")]
      (verifyRecoveryHtml s5))
    (let [(s6 "<div>unclosed tag at eof<")]
      (verifyRecoveryHtml s6))
    (let [(s7 "<b><i>mismatched tags</b></i>")]
      (verifyRecoveryHtml s7))
    true)

fn testOutlineDiagramWorkbench! -> Bool
  (let [(path "docs/diagrams/DiagramWorkbench.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing DiagramWorkbench.html: " e)))
      ((ok text)
       (let [(len (stringLength text))
             (root (htr/parseHtml text))
             (tiling (tr/checkTiling root len))
             (printed (pr/printTreeString text root))
             (wf (htr/isWellFormed root))
             (syms (htr/extractSymbols root text))
             (srcFile (src/sourceFromString path text))
             (receipt (out/formatOutlineReceipt path "html" syms srcFile))]
         (assert (ok? tiling) "DiagramWorkbench tiles cleanly")
         (assert (= printed text) "DiagramWorkbench round-trips losslessly")
         (assert wf "DiagramWorkbench is well-formed")
         (assert (= (listLength syms) 8) (str "DiagramWorkbench has 8 symbols, found: " (stringFromInt64 (listLength syms))))
         (assert (some? (sym/findSymbol syms "viewport")) "viewport symbol exists")
         (assert (some? (sym/findSymbol syms "style")) "style symbol exists")
         (assert (some? (sym/findSymbol syms "script")) "script symbol exists")
         (assert (some? (sym/findSymbol syms "main-layout")) "main-layout symbol exists")
         (assert (some? (sym/findSymbol syms "diagram-container")) "diagram-container symbol exists")
         (assert (some? (sym/findSymbol syms "editor-drawer")) "editor-drawer symbol exists")
         (assert (some? (sym/findSymbol syms "mermaid-source")) "mermaid-source symbol exists")
         (assert (stringContains? receipt ":status :ok") "receipt has status ok")
         (assert (stringContains? receipt ":itemsCount 8") "receipt has itemsCount 8")
         (assert (stringContains? receipt "mermaid-source") "receipt contains mermaid-source")
         (assert (stringContains? receipt "diagram-container") "receipt contains diagram-container")
         true))))

fn checkTrackedHtmlFile! acc: (Pair Int64 Int64) path: String -> (Pair Int64 Int64)
  (let [(checked (pairFirst acc))
        (mismatches (pairSecond acc))]
    (mt (fileReadString path)
      ((err _) acc)
      ((ok text)
       (let [(len (stringLength text))
             (root (htr/parseHtml text))
             (tilingRes (tr/checkTiling root len))
             (printed (pr/printTreeString text root))
             (syms (htr/extractSymbols root text))
             (isOk (and (ok? tilingRes) (and (= printed text) (> (listLength syms) 0))))]
         (if isOk
           (pair (+ checked 1) mismatches)
           (pair (+ checked 1) (+ mismatches 1)))))))

fn testAllFiveTrackedHtmlFiles! -> Bool
  (let [(files (list "asl/web/index.html"
                     "asl/packages/asl-browser-plugin/src/popup.html"
                     "docs/diagrams/DiagramWorkbench.html"
                     "docs/diagrams/OrchestrationTopology.html"
                     "editorial-matrix/assets/review/index.html"))
        (stats (fold checkTrackedHtmlFile! (pair 0 0) files))
        (totalChecked (pairFirst stats))
        (mismatches (pairSecond stats))]
    (assert (= totalChecked 5) "checked all 5 tracked html files")
    (assert (= mismatches 0) "zero tiling or print mismatches across all 5 tracked html files")
    true)

fn testHeadingsInReviewHtml! -> Bool
  (let [(path "editorial-matrix/assets/review/index.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing review html: " e)))
      ((ok text)
       (let [(root (htr/parseHtml text))
             (syms (htr/extractSymbols root text))
             (headings (filter (fn [(s sym/SymbolDef)] -> Bool (= (sym/symbolKind s) "heading")) syms))]
         (assert (>= (listLength headings) 5) "at least 5 heading symbols found")
         (assert (some? (sym/findSymbol syms "GenSEAM Visual Identity System")) "h1 title found")
         (assert (some? (sym/findSymbol syms "Маскот Леон (Leon)")) "h2 mascot found")
         (assert (some? (sym/findSymbol syms "Схематический хамелеон")) "h2 chameleon found")
         (assert (some? (sym/findSymbol syms "Хвост-скрепка (Концепт А)")) "h2 tail found")
         true))))

fn testReparseGuardSpanEdit -> Bool
  (let [(cleanHtml "<div><div id=\"diagram-container\"></div></div>")
        (parseFn (fn [(t String)] -> (Result tr/Node String) (ok (htr/parseHtml t))))
        (goodEditRes (sym/applySpanEdit cleanHtml 5 39 "<div id=\"diagram-view\"></div>" parseFn))]
    (assert (ok? goodEditRes) "clean edit accepted by reparse guard")
    (let [(badEditRes (sym/applySpanEdit cleanHtml 5 39 "<div id=\"diagram-view\"></div></div>" parseFn))]
      (assert (not (ok? badEditRes)) "edit introducing stray end tag rejected by reparse guard")
      true))

fn testBenchmarkPerformance! -> Bool
  (let [(path "docs/diagrams/DiagramWorkbench.html")]
    (mt (fileReadBytes path)
      ((err e) (assert false (str "missing DiagramWorkbench: " e)))
      ((ok bs)
       (let [(len (bytesLength bs))]
         (assert (> len 10000) "benchmark file is >10 KB")
         (let [(t0 (nowNs))
               (root (htr/parseHtmlBytes bs))
               (outBs (pr/printTreeBytes! bs root))
               (t1 (nowNs))
               (elapsedNs (- t1 t0))
               (elapsedMs (/ elapsedNs 1000000))
               (msPer100Kb (/ (* elapsedMs 102400) len))]
           (assert (= outBs bs) "parseHtmlBytes print matches input bytes")
           (assert (<= msPer100Kb 60) (str "tokenize+CST <= 60 ms per 100 KB, took: " (stringFromInt64 msPer100Kb) " ms"))
           true)))))

fn bytesFromIntList byteVals: (List Int64) -> Bytes
  (let [(len (listLength byteVals))
        (bs (bytesAlloc len))]
    (do
      (fold (fn [(idx Int64) (val Int64)] -> Int64
              (do
                (bytesSet bs idx val)
                (+ idx 1)))
            0
            byteVals)
      bs))

fn testMalformedAndTruncatedBytes! -> Bool
  (do
    (let [(bs1 (stringToBytes "<div"))
          (root1 (htr/parseHtmlBytes bs1))
          (len1 (bytesLength bs1))
          (tiling1 (tr/checkTiling root1 len1))
          (printed1 (pr/printTreeBytes! bs1 root1))]
      (assert (ok? tiling1) "tiling ok on tag cut at eof")
      (assert (= printed1 bs1) "round-trip exact on tag cut at eof")
      (assert (= (tr/nodeKind root1) "document") "kind is document on tag cut at eof")
      (assert (sym/hasErrorNode root1) "error node present on tag cut at eof")
      (assert (not (htr/isWellFormed root1)) "not well-formed on tag cut at eof"))
    (let [(bs1b (stringToBytes "<div><spa"))
          (root1b (htr/parseHtmlBytes bs1b))
          (len1b (bytesLength bs1b))
          (tiling1b (tr/checkTiling root1b len1b))
          (printed1b (pr/printTreeBytes! bs1b root1b))]
      (assert (ok? tiling1b) "tiling ok on child tag cut at eof")
      (assert (= printed1b bs1b) "round-trip exact on child tag cut at eof")
      (assert (= (tr/nodeKind root1b) "document") "kind is document on child tag cut at eof")
      (assert (sym/hasErrorNode root1b) "error node present on child tag cut at eof")
      (assert (not (htr/isWellFormed root1b)) "not well-formed on child tag cut at eof"))
    (let [(bs2 (stringToBytes "<div cla"))
          (root2 (htr/parseHtmlBytes bs2))
          (len2 (bytesLength bs2))
          (tiling2 (tr/checkTiling root2 len2))
          (printed2 (pr/printTreeBytes! bs2 root2))]
      (assert (ok? tiling2) "tiling ok on attr cut mid-name")
      (assert (= printed2 bs2) "round-trip exact on attr cut mid-name")
      (assert (= (tr/nodeKind root2) "document") "kind is document on attr cut mid-name")
      (assert (sym/hasErrorNode root2) "error node present on attr cut mid-name")
      (assert (not (htr/isWellFormed root2)) "not well-formed on attr cut mid-name"))
    (let [(bs2b (stringToBytes "<div><span attr"))
          (root2b (htr/parseHtmlBytes bs2b))
          (len2b (bytesLength bs2b))
          (tiling2b (tr/checkTiling root2b len2b))
          (printed2b (pr/printTreeBytes! bs2b root2b))]
      (assert (ok? tiling2b) "tiling ok on child attr cut mid-name")
      (assert (= printed2b bs2b) "round-trip exact on child attr cut mid-name")
      (assert (= (tr/nodeKind root2b) "document") "kind is document on child attr cut mid-name")
      (assert (sym/hasErrorNode root2b) "error node present on child attr cut mid-name")
      (assert (not (htr/isWellFormed root2b)) "not well-formed on child attr cut mid-name"))
    (let [(bs3 (stringToBytes "<"))
          (root3 (htr/parseHtmlBytes bs3))
          (len3 (bytesLength bs3))
          (tiling3 (tr/checkTiling root3 len3))
          (printed3 (pr/printTreeBytes! bs3 root3))]
      (assert (ok? tiling3) "tiling ok on lone lt")
      (assert (= printed3 bs3) "round-trip exact on lone lt")
      (assert (= (tr/nodeKind root3) "document") "kind is document on lone lt")
      (assert (not (sym/hasErrorNode root3)) "no error node on lone lt text")
      (assert (htr/isWellFormed root3) "well-formed on lone lt text"))
    (let [(bs3b (stringToBytes "<div><"))
          (root3b (htr/parseHtmlBytes bs3b))
          (len3b (bytesLength bs3b))
          (tiling3b (tr/checkTiling root3b len3b))
          (printed3b (pr/printTreeBytes! bs3b root3b))]
      (assert (ok? tiling3b) "tiling ok on lone lt in unclosed elem")
      (assert (= printed3b bs3b) "round-trip exact on lone lt in unclosed elem")
      (assert (= (tr/nodeKind root3b) "document") "kind is document on lone lt in unclosed elem")
      (assert (sym/hasErrorNode root3b) "error node present on lone lt in unclosed elem")
      (assert (not (htr/isWellFormed root3b)) "not well-formed on lone lt in unclosed elem"))
    (let [(bs4 (bytesAlloc 0))
          (root4 (htr/parseHtmlBytes bs4))
          (len4 (bytesLength bs4))
          (tiling4 (tr/checkTiling root4 len4))
          (printed4 (pr/printTreeBytes! bs4 root4))]
      (assert (ok? tiling4) "tiling ok on empty byte input")
      (assert (= printed4 bs4) "round-trip exact on empty byte input")
      (assert (= (tr/nodeKind root4) "document") "kind is document on empty byte input")
      (assert (= (listLength (tr/nodeChildren root4)) 0) "empty byte input has no children")
      (assert (not (sym/hasErrorNode root4)) "no error node on empty byte input")
      (assert (htr/isWellFormed root4) "well-formed on empty byte input"))
    (let [(bs5 (bytesFromIntList (list 60 112 62 255 254 60 47 112 62)))
          (root5 (htr/parseHtmlBytes bs5))
          (len5 (bytesLength bs5))
          (tiling5 (tr/checkTiling root5 len5))
          (printed5 (pr/printTreeBytes! bs5 root5))]
      (assert (ok? tiling5) "tiling ok on invalid utf-8 text")
      (assert (= printed5 bs5) "round-trip exact on invalid utf-8 text")
      (assert (= (tr/nodeKind root5) "document") "kind is document on invalid utf-8 text")
      (assert (not (sym/hasErrorNode root5)) "no error node on closed tag with invalid utf-8 text")
      (assert (htr/isWellFormed root5) "well-formed on closed tag with invalid utf-8 text"))
    (let [(bs5b (bytesFromIntList (list 60 100 105 118 62 255 254 253)))
          (root5b (htr/parseHtmlBytes bs5b))
          (len5b (bytesLength bs5b))
          (tiling5b (tr/checkTiling root5b len5b))
          (printed5b (pr/printTreeBytes! bs5b root5b))]
      (assert (ok? tiling5b) "tiling ok on unclosed elem with invalid utf-8 text")
      (assert (= printed5b bs5b) "round-trip exact on unclosed elem with invalid utf-8 text")
      (assert (= (tr/nodeKind root5b) "document") "kind is document on unclosed elem with invalid utf-8 text")
      (assert (sym/hasErrorNode root5b) "error node present on unclosed elem with invalid utf-8 text")
      (assert (not (htr/isWellFormed root5b)) "not well-formed on unclosed elem with invalid utf-8 text"))
    true)

fn ! runTests -> Bool
  (and (testVoidElementsFixtures)
  (and (testImpliedEndTagsFixtures)
  (and (testRecoveryFixtures)
  (and (testOutlineDiagramWorkbench!)
  (and (testAllFiveTrackedHtmlFiles!)
  (and (testHeadingsInReviewHtml!)
  (and (testReparseGuardSpanEdit)
  (and (testBenchmarkPerformance!)
       (testMalformedAndTruncatedBytes!)))))))))
