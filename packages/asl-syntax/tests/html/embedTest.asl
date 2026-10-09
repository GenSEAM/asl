(module asl-syntax/tests/html/embedTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/html/lex :a hlx)
      (asl-syntax/html/tree :a htr)
      (asl-syntax/html/embed :a emb)])

fn findEmbeddedSymbol syms: (List emb/EmbeddedSymbol) name: String -> (Option emb/EmbeddedSymbol)
  (mt (listHead syms)
    ((none) (none))
    ((some s)
     (if (= (emb/embeddedSymbolName s) name)
       (some s)
       (findEmbeddedSymbol (optionOr (listTail syms) (list)) name))))

fn findFirstElementByTag elems: (List tr/TreeElement) tag: String -> (Option tr/Node)
  (mt (listHead elems)
    ((none) (none))
    ((some elem)
     (mt elem
       ((elemToken _) (findFirstElementByTag (optionOr (listTail elems) (list)) tag))
       ((elemNode n)
        (if (= (htr/elementName n) tag)
          (some n)
          (mt (findFirstElementByTag (tr/nodeChildren n) tag)
            ((some found) (some found))
            ((none) (findFirstElementByTag (optionOr (listTail elems) (list)) tag))))))))

fn testBrokenScriptContentStaysErrorNode -> Bool
  (let [(textA "<!DOCTYPE html><html><head><script>function ( { let x = ;</script></head><body><p>Hello world</p></body></html>")
        (lenA (stringLength textA))
        (rootA (emb/parseHtmlWithEmbedded textA))
        (tilingA (tr/checkTiling rootA lenA))
        (printedA (pr/printTreeString textA rootA))
        (hasErrA (sym/hasErrorNode rootA))
        (scriptNodeOptA (findFirstElementByTag (tr/nodeChildren rootA) "script"))
        (pNodeOptA (findFirstElementByTag (tr/nodeChildren rootA) "p"))]
    (do
      (assert (ok? tilingA) "tiling succeeds on broken script in textA")
      (assert (= printedA textA) "lossless print on broken script in textA")
      (assert hasErrA "broken script content contains Error node in textA")
      (assert (some? scriptNodeOptA) "script node found in textA")
      (let [(scriptNode (optionOr scriptNodeOptA (tr/makeNode "" 0 0 (list))))]
        (assert (sym/hasErrorNode scriptNode) "script element contains Error node child in textA"))
      (assert (some? pNodeOptA) "p element intact after broken script in textA")
      (let [(pNode (optionOr pNodeOptA (tr/makeNode "" 0 0 (list))))]
        (assert (= (htr/elementTextContent pNode textA) "Hello world") "p element text intact in textA"))
      true))

fn testBrokenScriptSyntaxError -> Bool
  (let [(textB "<html><body><script>const x = ;</script><div>content</div></body></html>")
        (lenB (stringLength textB))
        (rootB (emb/parseHtmlWithEmbedded textB))
        (tilingB (tr/checkTiling rootB lenB))
        (printedB (pr/printTreeString textB rootB))
        (hasErrB (sym/hasErrorNode rootB))
        (divOptB (findFirstElementByTag (tr/nodeChildren rootB) "div"))]
    (do
      (assert (ok? tilingB) "tiling succeeds on broken const in textB")
      (assert (= printedB textB) "lossless print on broken const in textB")
      (assert hasErrB "broken const script contains Error node in textB")
      (assert (some? divOptB) "div element intact after broken script in textB")
      true))

fn testMultipleScriptsOneBrokenOneValid! -> Bool
  (let [(textC "<html><head><script>function goodFn() { return 1; }</script><script>let bad = ;</script></head><body></body></html>")
        (lenC (stringLength textC))
        (rootC (emb/parseHtmlWithEmbedded textC))
        (tilingC (tr/checkTiling rootC lenC))
        (printedC (pr/printTreeString textC rootC))
        (hasErrC (sym/hasErrorNode rootC))
        (symsC (emb/extractEmbeddedSymbols! rootC textC))
        (goodOpt (findEmbeddedSymbol symsC "goodFn"))]
    (do
      (assert (ok? tilingC) "tiling succeeds on multiple scripts in textC")
      (assert (= printedC textC) "lossless print on multiple scripts in textC")
      (assert hasErrC "multiple scripts tree reports Error node in textC")
      (assert (some? goodOpt) "symbol goodFn found in valid script of textC")
      true))

fn testDiagramWorkbenchScriptSymbols! -> Bool
  (let [(path "docs/diagrams/DiagramWorkbench.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing DiagramWorkbench.html: " e)))
      ((ok text)
       (let [(len (stringLength text))
             (root (emb/parseHtmlWithEmbedded text))
             (tiling (tr/checkTiling root len))
             (printed (pr/printTreeString text root))
             (syms (emb/extractEmbeddedSymbols! root text))
             (sFile (src/sourceFromString path text))
             (renderOpt (findEmbeddedSymbol syms "renderCurrent"))
             (transformOpt (findEmbeddedSymbol syms "setTransform"))]
         (do
           (assert (ok? tiling) "DiagramWorkbench tiles cleanly with embedded scripts")
           (assert (= printed text) "DiagramWorkbench round-trips losslessly with embedded scripts")
           (assert (some? renderOpt) "DiagramWorkbench renderCurrent symbol found in script")
           (assert (some? transformOpt) "DiagramWorkbench setTransform symbol found in script")
           (let [(renderSym (optionOr renderOpt (emb/makeEmbeddedSymbol "" "" 0 0 0 0 "" 0 "")))
                 (transformSym (optionOr transformOpt (emb/makeEmbeddedSymbol "" "" 0 0 0 0 "" 0 "")))]
             (do
               (assert (= (emb/embeddedSymbolStartLine renderSym) 261) "renderCurrent carries file line 261 in DiagramWorkbench")
               (assert (= (emb/embeddedSymbolStartLine transformSym) 292) "setTransform carries file line 292 in DiagramWorkbench")
               (assert (= (emb/embeddedSymbolStartLine renderSym) (optionOr (src/sourceLineAt sFile (emb/embeddedSymbolStart renderSym)) 0))
                       "renderCurrent startLine matches sourceLineAt file offset")
               (assert (= (emb/embeddedSymbolStartLine transformSym) (optionOr (src/sourceLineAt sFile (emb/embeddedSymbolStart transformSym)) 0))
                       "setTransform startLine matches sourceLineAt file offset")
               (assert (>= (emb/embeddedSymbolEndLine renderSym) (emb/embeddedSymbolStartLine renderSym))
                       "renderCurrent endLine >= startLine")
               (assert (>= (emb/embeddedSymbolEndLine transformSym) (emb/embeddedSymbolStartLine transformSym))
                       "setTransform endLine >= startLine")
               true)))))))

fn testOrchestrationTopologyScriptSymbols! -> Bool
  (let [(path "docs/diagrams/OrchestrationTopology.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing OrchestrationTopology.html: " e)))
      ((ok text)
       (let [(len (stringLength text))
             (root (emb/parseHtmlWithEmbedded text))
             (tiling (tr/checkTiling root len))
             (printed (pr/printTreeString text root))
             (syms (emb/extractEmbeddedSymbols! root text))
             (sFile (src/sourceFromString path text))
             (transformOpt (findEmbeddedSymbol syms "setTransform"))]
         (do
           (assert (ok? tiling) "OrchestrationTopology tiles cleanly with embedded scripts")
           (assert (= printed text) "OrchestrationTopology round-trips losslessly with embedded scripts")
           (assert (some? transformOpt) "OrchestrationTopology setTransform symbol found in script")
           (let [(transformSym (optionOr transformOpt (emb/makeEmbeddedSymbol "" "" 0 0 0 0 "" 0 "")))]
             (do
               (assert (= (emb/embeddedSymbolStartLine transformSym) 128) "setTransform carries file line 128 in OrchestrationTopology")
               (assert (= (emb/embeddedSymbolStartLine transformSym) (optionOr (src/sourceLineAt sFile (emb/embeddedSymbolStart transformSym)) 0))
                       "setTransform startLine matches sourceLineAt file offset")
               (assert (>= (emb/embeddedSymbolEndLine transformSym) (emb/embeddedSymbolStartLine transformSym))
                       "setTransform endLine >= startLine")
               true)))))))

fn testWebIndexHtmlFile! -> Bool
  (let [(path "asl/web/index.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing asl/web/index.html: " e)))
      ((ok text)
       (let [(len (stringLength text))
             (root (emb/parseHtmlWithEmbedded text))
             (tiling (tr/checkTiling root len))
             (printed (pr/printTreeString text root))]
         (do
           (assert (ok? tiling) "asl/web/index.html tiles cleanly with embedded scripts")
           (assert (= printed text) "asl/web/index.html round-trips losslessly with embedded scripts")
           true)))))

fn testPopupHtmlFile! -> Bool
  (let [(path "asl/packages/asl-browser-plugin/src/popup.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing popup.html: " e)))
      ((ok text)
       (let [(len (stringLength text))
             (root (emb/parseHtmlWithEmbedded text))
             (tiling (tr/checkTiling root len))
             (printed (pr/printTreeString text root))
             (syms (emb/extractEmbeddedSymbols! root text))
             (sFile (src/sourceFromString path text))
             (bodyOpt (findEmbeddedSymbol syms "body"))
             (headerOpt (findEmbeddedSymbol syms ".header"))]
         (do
           (assert (ok? tiling) "popup.html tiles cleanly")
           (assert (= printed text) "popup.html round-trips losslessly")
           (assert (some? bodyOpt) "popup.html body selector found")
           (assert (some? headerOpt) "popup.html .header selector found")
           (let [(bodySym (optionOr bodyOpt (emb/makeEmbeddedSymbol "" "" 0 0 0 0 "" 0 "")))
                 (headerSym (optionOr headerOpt (emb/makeEmbeddedSymbol "" "" 0 0 0 0 "" 0 "")))]
             (do
               (assert (= (emb/embeddedSymbolStartLine bodySym) 7) "body selector carries file line 7 in popup.html")
               (assert (= (emb/embeddedSymbolStartLine headerSym) 16) ".header selector carries file line 16 in popup.html")
               (assert (= (emb/embeddedSymbolStartLine bodySym) (optionOr (src/sourceLineAt sFile (emb/embeddedSymbolStart bodySym)) 0))
                       "body selector startLine matches sourceLineAt file offset")
               true))
           (let [(scriptSyms (filter (fn [(s emb/EmbeddedSymbol)] -> Bool (= (emb/embeddedSymbolLang s) "javascript")) syms))]
             (do
               (assert (= (listLength scriptSyms) 0) "popup.html has 0 inline script symbols")
               true)))))))

fn testReviewHtmlFile! -> Bool
  (let [(path "editorial-matrix/assets/review/index.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing review index.html: " e)))
      ((ok text)
       (let [(len (stringLength text))
             (root (emb/parseHtmlWithEmbedded text))
             (tiling (tr/checkTiling root len))
             (printed (pr/printTreeString text root))
             (syms (emb/extractEmbeddedSymbols! root text))
             (sFile (src/sourceFromString path text))
             (bodyOpt (findEmbeddedSymbol syms "body"))
             (h1Opt (findEmbeddedSymbol syms "h1"))]
         (do
           (assert (ok? tiling) "review index.html tiles cleanly")
           (assert (= printed text) "review index.html round-trips losslessly")
           (assert (some? bodyOpt) "review index.html body selector found")
           (assert (some? h1Opt) "review index.html h1 selector found")
           (let [(bodySym (optionOr bodyOpt (emb/makeEmbeddedSymbol "" "" 0 0 0 0 "" 0 "")))
                 (h1Sym (optionOr h1Opt (emb/makeEmbeddedSymbol "" "" 0 0 0 0 "" 0 "")))]
             (do
               (assert (= (emb/embeddedSymbolStartLine bodySym) 7) "body selector carries file line 7 in review index.html")
               (assert (= (emb/embeddedSymbolStartLine h1Sym) 18) "h1 selector carries file line 18 in review index.html")
               (assert (= (emb/embeddedSymbolStartLine bodySym) (optionOr (src/sourceLineAt sFile (emb/embeddedSymbolStart bodySym)) 0))
                       "body selector startLine matches sourceLineAt file offset")
               true))
           (let [(scriptSyms (filter (fn [(s emb/EmbeddedSymbol)] -> Bool (= (emb/embeddedSymbolLang s) "javascript")) syms))]
             (do
               (assert (= (listLength scriptSyms) 0) "review index.html has 0 inline script symbols")
               true)))))))

fn testUnifiedExtractSymbolsIncludesHtmlAndEmbedded! -> Bool
  (let [(path "docs/diagrams/DiagramWorkbench.html")]
    (mt (fileReadString path)
      ((err e) (assert false (str "missing DiagramWorkbench.html: " e)))
      ((ok text)
       (let [(root (emb/parseHtmlWithEmbedded text))
             (syms (emb/extractSymbols! root text))
             (viewportOpt (sym/findSymbol syms "viewport"))
             (renderOpt (sym/findSymbol syms "renderCurrent"))
             (receipt (emb/formatOutline! path text))]
         (do
           (assert (some? viewportOpt) "HTML id symbol viewport found in unified symbols")
           (assert (some? renderOpt) "Embedded JS symbol renderCurrent found in unified symbols")
           (assert (stringContains? receipt "renderCurrent") "outline receipt contains renderCurrent")
           (assert (stringContains? receipt "viewport") "outline receipt contains viewport")
           (assert (stringContains? receipt ":status :ok") "outline receipt has status ok")
           true)))))

fn checkSingleTrackedHtmlFile! path: String -> Bool
  (mt (fileReadString path)
    ((err e) (assert false (str "missing tracked file: " path " err: " e)))
    ((ok text)
     (let [(len (stringLength text))
           (root (emb/parseHtmlWithEmbedded text))
           (tiling (tr/checkTiling root len))
           (printed (pr/printTreeString text root))]
       (do
         (assert (ok? tiling) (str path " tiles cleanly in corpus sweep"))
         (assert (= printed text) (str path " round-trips losslessly in corpus sweep"))
         true))))

fn testAllFiveTrackedFilesLosslessRoundTrip! -> Bool
  (do
    (checkSingleTrackedHtmlFile! "asl/web/index.html")
    (checkSingleTrackedHtmlFile! "asl/packages/asl-browser-plugin/src/popup.html")
    (checkSingleTrackedHtmlFile! "docs/diagrams/DiagramWorkbench.html")
    (checkSingleTrackedHtmlFile! "docs/diagrams/OrchestrationTopology.html")
    (checkSingleTrackedHtmlFile! "editorial-matrix/assets/review/index.html")
    true)

fn ! runTests -> Bool
  (do
    (testBrokenScriptContentStaysErrorNode)
    (testBrokenScriptSyntaxError)
    (testMultipleScriptsOneBrokenOneValid!)
    (testDiagramWorkbenchScriptSymbols!)
    (testOrchestrationTopologyScriptSymbols!)
    (testWebIndexHtmlFile!)
    (testPopupHtmlFile!)
    (testReviewHtmlFile!)
    (testUnifiedExtractSymbolsIncludesHtmlAndEmbedded!)
    (testAllFiveTrackedFilesLosslessRoundTrip!)
    true)
