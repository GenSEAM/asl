(module asl-syntax/tests/xml/xmlTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/core/outline :a out)
      (asl-syntax/core/corpus :a crp)
      (asl-syntax/xml :a xml)])

fn verifyWf text: String -> Bool
  (let [(root (xml/parseXml text))
        (len (stringLength text))
        (tilingRes (tr/checkTiling root len))
        (printed (pr/printTreeString text root))]
    (assert (ok? tilingRes) "tiling check succeeds on WF XML")
    (assert (= printed text) "print is byte-exact on WF XML")
    (assert (xml/isWellFormed root) "isWellFormed returns true on WF XML")
    (assert (not (sym/hasErrorNode root)) "hasErrorNode is false on WF XML")
    true)

fn verifyNotWf text: String -> Bool
  (let [(root (xml/parseXml text))
        (len (stringLength text))
        (tilingRes (tr/checkTiling root len))
        (printed (pr/printTreeString text root))]
    (assert (ok? tilingRes) "tiling check succeeds on Not-WF XML")
    (assert (= printed text) "print is byte-exact on Not-WF XML")
    (assert (not (xml/isWellFormed root)) "isWellFormed returns false on Not-WF XML")
    (assert (sym/hasErrorNode root) "hasErrorNode is true on Not-WF XML")
    true)

fn testW3CWellFormedMinimal -> Bool
  (do
    (verifyWf "<doc/>")
    (verifyWf "<doc></doc>")
    (verifyWf "  <doc/>  \n")
    true)

fn testW3CWellFormedProlog -> Bool
  (do
    (verifyWf "<?xml version=\"1.0\"?>\n<doc/>")
    (verifyWf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<doc/>")
    (verifyWf "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?>\n<doc/>")
    (verifyWf "<?xml version='1.0' encoding='ISO-8859-1' standalone='no'?>\n<doc/>")
    true)

fn testW3CWellFormedComments -> Bool
  (do
    (verifyWf "<!-- comment -->\n<doc/>")
    (verifyWf "<doc><!-- inside comment --></doc>")
    (verifyWf "<doc><!-- a - b - c --></doc>")
    (verifyWf "<doc/>\n<!-- trailing comment -->\n")
    true)

fn testW3CWellFormedPI -> Bool
  (do
    (verifyWf "<?target some instructions?>\n<doc/>")
    (verifyWf "<doc><?pi in element?></doc>")
    (verifyWf "<doc/>\n<?tail pi?>")
    true)

fn testW3CWellFormedCData -> Bool
  (do
    (verifyWf "<doc><![CDATA[<foo> & ' \" test]]></doc>")
    (verifyWf "<doc><![CDATA[]]></doc>")
    (verifyWf "<doc><![CDATA[nested [ [ ] ] brackets]]></doc>")
    true)

fn testW3CWellFormedEntities -> Bool
  (do
    (verifyWf "<doc>&amp; &lt; &gt; &apos; &quot;</doc>")
    (verifyWf "<doc>&#65; &#x41; &#X42;</doc>")
    (verifyWf "<doc a=\"&quot;quoted&amp;attr&apos;\"/>")
    true)

fn testW3CWellFormedDoctype -> Bool
  (do
    (verifyWf "<!DOCTYPE doc SYSTEM \"doc.dtd\">\n<doc/>")
    (verifyWf "<!DOCTYPE doc PUBLIC \"-//W3C//DTD XML 1.0//EN\" \"doc.dtd\">\n<doc/>")
    (verifyWf "<!DOCTYPE doc [\n  <!ELEMENT doc (#PCDATA)>\n]>\n<doc/>")
    true)

fn testW3CWellFormedAttributes -> Bool
  (do
    (verifyWf "<doc a=\"1\" b='2' c=\"test\"/>")
    (verifyWf "<doc empty=\"\"/>")
    (verifyWf "<ns:doc xmlns:ns=\"http://example.com\" ns:attr=\"value\"><ns:child/></ns:doc>")
    true)

fn testW3CWellFormedNestingAndContent -> Bool
  (do
    (verifyWf "<root><a id=\"first\"><b/></a><c id=\"second\"/></root>")
    (verifyWf "<p>Hello <b>bold</b> and <i>italic</i> world</p>")
    (verifyWf "<a><b><c><d><e/></d></c></b></a>")
    true)

fn testW3CNotWfMismatchedTag -> Bool
  (do
    (verifyNotWf "<foo></bar>")
    (verifyNotWf "<root><child></root></child>")
    true)

fn testW3CNotWfUnclosedTag -> Bool
  (do
    (verifyNotWf "<foo>")
    (verifyNotWf "<root><child></root>")
    true)

fn testW3CNotWfStrayEndTag -> Bool
  (do
    (verifyNotWf "</foo>")
    (verifyNotWf "<doc></doc></doc>")
    true)

fn testW3CNotWfMultipleRoots -> Bool
  (do
    (verifyNotWf "<a/><b/>")
    (verifyNotWf "<doc/> <doc/>")
    true)

fn testW3CNotWfTextOutsideRoot -> Bool
  (do
    (verifyNotWf "stray text <doc/>")
    (verifyNotWf "<doc/> stray text")
    true)

fn testW3CNotWfDuplicateAttr -> Bool
  (do
    (verifyNotWf "<doc a=\"1\" a=\"2\"/>")
    (verifyNotWf "<doc id=\"x\" id=\"y\"></doc>")
    true)

fn testW3CNotWfLtInAttr -> Bool
  (do
    (verifyNotWf "<doc a=\"<\"/>")
    (verifyNotWf "<doc a='<'/>")
    true)

fn testW3CNotWfUnquotedAttr -> Bool
  (do
    (verifyNotWf "<doc a=value/>")
    (verifyNotWf "<doc a=>")
    true)

fn testW3CNotWfCommentErrors -> Bool
  (do
    (verifyNotWf "<!-- bad -- comment -->\n<doc/>")
    (verifyNotWf "<!-- bad --->\n<doc/>")
    (verifyNotWf "<!-- unclosed comment\n<doc/>")
    true)

fn testW3CNotWfCDataErrors -> Bool
  (do
    (verifyNotWf "<doc><![CDATA[ unclosed </doc>")
    (verifyNotWf "<doc>bad ]]> in text</doc>")
    true)

fn testW3CNotWfPIErrors -> Bool
  (do
    (verifyNotWf "<? unclosed PI\n<doc/>")
    (verifyNotWf "<doc><?xml notAtStart?></doc>")
    true)

fn testW3CNotWfBadTagNames -> Bool
  (do
    (verifyNotWf "<123/>")
    (verifyNotWf "<.badName/>")
    true)


fn filterOutUpstream files: (List String) acc: (List String) -> (List String)
  (if (listEmpty? files)
    (listReverse acc)
    (let [(head (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))]
      (if (stringContains? head "fixtures/upstream")
        (filterOutUpstream tail acc)
        (filterOutUpstream tail (cons head acc)))))

fn testRoundTripTrackedCorpus! -> Bool
  (let [(svgFiles (resultOr (crp/gitTrackedFiles! "svg") (list)))
        (rawXmlFiles (resultOr (crp/gitTrackedFiles! "xml") (list)))
        (xmlFiles (filterOutUpstream rawXmlFiles (list)))
        (allFiles (listAppend svgFiles xmlFiles))
        (totalFiles (listLength allFiles))]
    (assert (= (listLength svgFiles) 34) "tracked svg count is exactly 34")
    (assert (= (listLength xmlFiles) 2) "tracked xml count is exactly 2")
    (assert (= totalFiles 36) "total tracked svg + xml count is exactly 36")
    (let [(pipeline (fn [(bs Bytes)] -> (Result Bytes String)
                      (let [(root (xml/parseXmlBytes bs))]
                        (mt (tr/checkTiling root (bytesLength bs))
                          ((err msg) (err (str "tiling error: " msg)))
                          ((ok _) (ok (pr/printTreeBytes! bs root)))))))
          (report (crp/runCorpusOnFiles! pipeline allFiles))]
      (assert (= (crp/reportFiles report) 36) "corpus processed all 36 files")
      (assert (= (crp/reportMismatchCount report) 0) "corpus has 0 print mismatches")
      (assert (crp/reportSuccess? report) "corpus round-trip passes on all 36 files")
      true))

fn testTrackedTruncatedSvgDetectedAsNotWf! -> Bool
  (let [(trunc1 "harness/results/svg/compare/synthwaveBaseTruncated.svg")
        (trunc2 "harness/results/svg/compare/isometricBaseTruncated.svg")]
    (mt (fileReadString trunc1)
      ((err _) (assert false "failed to read synthwaveBaseTruncated.svg"))
      ((ok text1)
       (let [(root1 (xml/parseXml text1))]
         (assert (not (xml/isWellFormed root1)) "synthwaveBaseTruncated is not well-formed")
         (assert (sym/hasErrorNode root1) "synthwaveBaseTruncated has error node")
         (assert (= (pr/printTreeString text1 root1) text1) "synthwaveBaseTruncated round trips"))))
    (mt (fileReadString trunc2)
      ((err _) (assert false "failed to read isometricBaseTruncated.svg"))
      ((ok text2)
       (let [(root2 (xml/parseXml text2))]
         (assert (not (xml/isWellFormed root2)) "isometricBaseTruncated is not well-formed")
         (assert (sym/hasErrorNode root2) "isometricBaseTruncated has error node")
         (assert (= (pr/printTreeString text2 root2) text2) "isometricBaseTruncated round trips"))))
    true)

fn testIdAndPathSymbols -> Bool
  (let [(doc "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\n  <defs>\n    <linearGradient id=\"tailGrad\" x1=\"20%\" y1=\"10%\" x2=\"80%\" y2=\"90%\">\n      <stop offset=\"0%\" stop-color=\"#d8b4fe\" />\n    </linearGradient>\n  </defs>\n  <path id=\"tail\" d=\"M 10 10 L 90 90\" />\n</svg>")
        (root (xml/parseXml doc))
        (syms (xml/extractSymbols root))]
    (assert (> (listLength syms) 0) "extracted symbols is non-empty")
    (assert (some? (sym/findSymbol syms "tailGrad")) "find id symbol tailGrad")
    (assert (some? (sym/findSymbol syms "tail")) "find id symbol tail")
    (assert (some? (sym/findSymbol syms "svg.defs.linearGradient")) "find dotted path svg.defs.linearGradient")
    (assert (some? (sym/findSymbol syms "svg.path")) "find dotted path svg.path")
    (let [(tailSym (optionOr (sym/findSymbol syms "tail") (sym/makeSymbolDef "" "" 0 0)))]
      (assert (= (sym/symbolKind tailSym) "id") "tail symbol kind is id")
      (assert (= (sym/symbolName tailSym) "tail") "tail symbol name is tail"))
    (let [(pathSym (optionOr (sym/findSymbol syms "svg.path") (sym/makeSymbolDef "" "" 0 0)))]
      (assert (= (sym/symbolKind pathSym) "element") "path symbol kind is element")
      (assert (= (sym/symbolName pathSym) "path") "path symbol name is path"))
    (let [(s (src/sourceFromString "test.svg" doc))
          (receipt (out/formatOutlineReceipt "test.svg" "xml" syms s))]
      (assert (stringContains? receipt ":itemsCount") "receipt has itemsCount")
      (assert (stringContains? receipt "tailGrad") "receipt contains tailGrad")
      (assert (stringContains? receipt "tail") "receipt contains tail"))
    true)

fn testReparseGuard -> Bool
  (let [(cleanXml "<doc><item id=\"one\"/></doc>")
        (parseFn (fn [(t String)] -> (Result tr/Node String) (ok (xml/parseXml t))))
        (cleanRes (sym/applySpanEdit cleanXml 15 18 "two" parseFn))]
    (assert (ok? cleanRes) "reparse guard succeeds on clean edit")
    (mt cleanRes
      ((ok editRes)
       (do
         (assert (= editRes.newText "<doc><item id=\"two\"/></doc>") "new text matches clean edit")
         (assert (not (sym/hasErrorNode editRes.root)) "reparsed tree has no error node")))
      ((err _) (assert false "expected ok clean edit")))
    (let [(badRes (sym/applySpanEdit cleanXml 15 18 "two</broken" parseFn))]
      (assert (err? badRes) "reparse guard rejects edit introducing Error node")
      (mt badRes
        ((ok _) (assert false "expected error for bad edit"))
        ((err msg) (assert (stringContains? msg "Error node") "error names Error node"))))
    true)

fn testXmlBenchPerf! -> Bool
  (let [(svgFiles (resultOr (crp/gitTrackedFiles! "svg") (list)))
        (rawXmlFiles (resultOr (crp/gitTrackedFiles! "xml") (list)))
        (xmlFiles (filterOutUpstream rawXmlFiles (list)))
        (allFiles (listAppend svgFiles xmlFiles))
        (t0 (monotonicNs))
        (_ (fold (fn [(acc Unit) (f String)] -> Unit
                   (mt (fileReadBytes f)
                     ((err _) ())
                     ((ok bs)
                      (let [(root (xml/parseXmlBytes bs))]
                        ()))))
                 ()
                 allFiles))
        (elapsedNs (- (monotonicNs) t0))
        (elapsedMs (/ elapsedNs 1000000))]
    (assert (< elapsedMs 2000) "parsing all 36 files took less than 2s")
    true)

fn testElementNodeAndTokenSpans -> Bool
  (do
    (let [(docElem "<root><item>content</item></root>")
          (rootElem (xml/parseXml docElem))
          (rootElemOpt (xml/documentRootElement rootElem))]
      (assert (some? rootElemOpt) "found root element")
      (let [(re (optionOr rootElemOpt (tr/makeNode "" 0 0 (list))))]
        (assert (= (tr/nodeKind re) "element:root") "root elem kind is element:root")
        (assert (= (tr/nodeStart re) 0) "root elem start is 0")
        (assert (= (tr/nodeEnd re) 33) "root elem end is 33")
        (let [(children (xml/elementChildren re))]
          (assert (= (listLength children) 1) "root has 1 element child")
          (let [(itemElem (optionOr (listHead children) (tr/makeNode "" 0 0 (list))))]
            (assert (= (tr/nodeKind itemElem) "element:item") "child kind is element:item")
            (assert (= (tr/nodeStart itemElem) 6) "child elem start is 6")
            (assert (= (tr/nodeEnd itemElem) 26) "child elem end is 26"))))
      (let [(toks (xml/tokenize docElem))]
        (assert (= (listLength toks) 9) "docElem token count is 9")
        (let [(t0 (optionOr (listGet toks 0) (tr/makeToken "" 0 0)))
              (t4 (optionOr (listGet toks 4) (tr/makeToken "" 0 0)))
              (t5 (optionOr (listGet toks 5) (tr/makeToken "" 0 0)))]
          (assert (= (tr/tokenKind t0) "tagOpen") "tok 0 is tagOpen")
          (assert (= (tr/tokenStart t0) 0) "tok 0 start 0")
          (assert (= (tr/tokenEnd t0) 5) "tok 0 end 5")
          (assert (= (tr/tokenKind t4) "text") "tok 4 is text")
          (assert (= (tr/tokenStart t4) 12) "tok 4 start 12")
          (assert (= (tr/tokenEnd t4) 19) "tok 4 end 19")
          (assert (= (tr/tokenKind t5) "endTagOpen") "tok 5 is endTagOpen")
          (assert (= (tr/tokenStart t5) 19) "tok 5 start 19")
          (assert (= (tr/tokenEnd t5) 25) "tok 5 end 25"))))
    true)

fn testAttributeNodeAndTokenSpans -> Bool
  (do
    (let [(docAttr "<doc key=\"val\" flag=\"true\"/>")
          (rootAttr (xml/parseXml docAttr))
          (elemOpt (xml/documentRootElement rootAttr))]
      (assert (some? elemOpt) "found doc element")
      (let [(elem (optionOr elemOpt (tr/makeNode "" 0 0 (list))))
            (attrs (xml/elementAttributes elem))]
        (assert (= (listLength attrs) 2) "element has 2 attributes")
        (let [(a1 (optionOr (listGet attrs 0) (xml/makeXmlAttr "" "" 0 0)))
              (a2 (optionOr (listGet attrs 1) (xml/makeXmlAttr "" "" 0 0)))]
          (assert (= (xml/attrName a1) "key") "a1 name is key")
          (assert (= (xml/attrValue a1) "val") "a1 val is val")
          (assert (= (xml/attrStart a1) 5) "a1 start is 5")
          (assert (= (xml/attrEnd a1) 14) "a1 end is 14")
          (assert (= (xml/attrName a2) "flag") "a2 name is flag")
          (assert (= (xml/attrValue a2) "true") "a2 val is true")
          (assert (= (xml/attrStart a2) 15) "a2 start is 15")
          (assert (= (xml/attrEnd a2) 26) "a2 end is 26")))
      (let [(toks (xml/tokenize docAttr))]
        (assert (= (listLength toks) 10) "docAttr token count is 10")
        (let [(tName1 (optionOr (listGet toks 2) (tr/makeToken "" 0 0)))
              (tEq1 (optionOr (listGet toks 3) (tr/makeToken "" 0 0)))
              (tVal1 (optionOr (listGet toks 4) (tr/makeToken "" 0 0)))]
          (assert (= (tr/tokenKind tName1) "attrName") "token is attrName")
          (assert (= (tr/tokenStart tName1) 5) "attrName start 5")
          (assert (= (tr/tokenEnd tName1) 8) "attrName end 8")
          (assert (= (tr/tokenKind tEq1) "equals") "token is equals")
          (assert (= (tr/tokenStart tEq1) 8) "equals start 8")
          (assert (= (tr/tokenEnd tEq1) 9) "equals end 9")
          (assert (= (tr/tokenKind tVal1) "attrValue") "token is attrValue")
          (assert (= (tr/tokenStart tVal1) 9) "attrValue start 9")
          (assert (= (tr/tokenEnd tVal1) 14) "attrValue end 14"))))
    true)

fn testCommentNodeAndTokenSpans -> Bool
  (do
    (let [(docComment "<!-- a comment -->\n<doc/>")
          (rootComment (xml/parseXml docComment))
          (kids (tr/nodeChildren rootComment))]
      (assert (> (listLength kids) 0) "rootComment has kids")
      (let [(firstElem (optionOr (listHead kids) (tr/elemToken (tr/makeToken "" 0 0))))]
        (mt firstElem
          ((elemToken _) (assert false "expected comment node"))
          ((elemNode n)
           (do
             (assert (= (tr/nodeKind n) "comment") "node kind is comment")
             (assert (= (tr/nodeStart n) 0) "comment node start is 0")
             (assert (= (tr/nodeEnd n) 18) "comment node end is 18")))))
      (let [(toks (xml/tokenize docComment))
            (t0 (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
        (assert (= (tr/tokenKind t0) "comment") "tok 0 is comment")
        (assert (= (tr/tokenStart t0) 0) "comment tok start 0")
        (assert (= (tr/tokenEnd t0) 18) "comment tok end 18")))
    true)

fn testCDataNodeAndTokenSpans -> Bool
  (do
    (let [(docCData "<doc><![CDATA[raw & <data> here]]></doc>")
          (rootCData (xml/parseXml docCData))
          (elem (optionOr (xml/documentRootElement rootCData) (tr/makeNode "" 0 0 (list))))
          (elemKids (tr/nodeChildren elem))]
      (assert (= (listLength elemKids) 3) "elem has 3 children")
      (let [(cdataElem (optionOr (listGet elemKids 1) (tr/elemToken (tr/makeToken "" 0 0))))]
        (mt cdataElem
          ((elemToken _) (assert false "expected cdata node"))
          ((elemNode n)
           (do
             (assert (= (tr/nodeKind n) "cdata") "node kind is cdata")
             (assert (= (tr/nodeStart n) 5) "cdata node start 5")
             (assert (= (tr/nodeEnd n) 34) "cdata node end 34")))))
      (let [(toks (xml/tokenize docCData))
            (tCdata (optionOr (listGet toks 2) (tr/makeToken "" 0 0)))]
        (assert (= (tr/tokenKind tCdata) "cdata") "token is cdata")
        (assert (= (tr/tokenStart tCdata) 5) "cdata token start 5")
        (assert (= (tr/tokenEnd tCdata) 34) "cdata token end 34")))
    true)

fn testPINodeAndTokenSpans -> Bool
  (do
    (let [(docPI "<?my-target some payload?>\n<doc/>")
          (rootPI (xml/parseXml docPI))
          (piKids (tr/nodeChildren rootPI))
          (firstElem (optionOr (listHead piKids) (tr/elemToken (tr/makeToken "" 0 0))))]
      (mt firstElem
        ((elemToken _) (assert false "expected pi node"))
        ((elemNode n)
         (do
           (assert (= (tr/nodeKind n) "pi") "node kind is pi")
           (assert (= (tr/nodeStart n) 0) "pi node start is 0")
           (assert (= (tr/nodeEnd n) 26) "pi node end is 26")))))
    (let [(toks (xml/tokenize "<?my-target some payload?>\n<doc/>"))
          (t0 (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (assert (= (tr/tokenKind t0) "pi") "token is pi")
      (assert (= (tr/tokenStart t0) 0) "pi token start 0")
      (assert (= (tr/tokenEnd t0) 26) "pi token end 26"))
    (let [(docProlog "<?xml version=\"1.0\"?>\n<doc/>")
          (rootProlog (xml/parseXml docProlog))
          (prologKids (tr/nodeChildren rootProlog))
          (firstElem (optionOr (listHead prologKids) (tr/elemToken (tr/makeToken "" 0 0))))]
      (mt firstElem
        ((elemToken _) (assert false "expected prolog node"))
        ((elemNode n)
         (do
           (assert (= (tr/nodeKind n) "prolog") "node kind is prolog")
           (assert (= (tr/nodeStart n) 0) "prolog node start is 0")
           (assert (= (tr/nodeEnd n) 21) "prolog node end is 21")))))
    (let [(toksProlog (xml/tokenize "<?xml version=\"1.0\"?>\n<doc/>"))
          (t0 (optionOr (listHead toksProlog) (tr/makeToken "" 0 0)))]
      (assert (= (tr/tokenKind t0) "prolog") "token is prolog")
      (assert (= (tr/tokenStart t0) 0) "prolog token start 0")
      (assert (= (tr/tokenEnd t0) 21) "prolog token end 21"))
    true)

fn testDoctypeNodeAndTokenSpans -> Bool
  (do
    (let [(docDTD "<!DOCTYPE root SYSTEM \"rules.dtd\">\n<root/>")
          (rootDTD (xml/parseXml docDTD))
          (dtdKids (tr/nodeChildren rootDTD))
          (firstElem (optionOr (listHead dtdKids) (tr/elemToken (tr/makeToken "" 0 0))))]
      (mt firstElem
        ((elemToken _) (assert false "expected doctype node"))
        ((elemNode n)
         (do
           (assert (= (tr/nodeKind n) "doctype") "node kind is doctype")
           (assert (= (tr/nodeStart n) 0) "doctype node start is 0")
           (assert (= (tr/nodeEnd n) 34) "doctype node end is 34")))))
    (let [(toks (xml/tokenize "<!DOCTYPE root SYSTEM \"rules.dtd\">\n<root/>"))
          (t0 (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (assert (= (tr/tokenKind t0) "doctype") "token is doctype")
      (assert (= (tr/tokenStart t0) 0) "doctype token start 0")
      (assert (= (tr/tokenEnd t0) 34) "doctype token end 34"))
    true)

fn testParseAndParseBytes -> Bool
  (let [(goodXml "<root><child key=\"val\">text</child></root>")
        (badXml "<root><child key=\"val\">text</unclosed></root>")
        (resGood (xml/parse goodXml))
        (resBad (xml/parse badXml))
        (goodBytes (stringToBytes goodXml))
        (badBytes (stringToBytes badXml))
        (resGoodBytes (xml/parseBytes goodBytes))
        (resBadBytes (xml/parseBytes badBytes))]
    (assert (ok? resGood) "parse returns ok on well-formed XML")
    (assert (err? resBad) "parse returns err on not-wf XML")
    (mt resBad
      ((ok _) (assert false "expected err on not-wf XML"))
      ((err msg)
       (do
         (assert (stringContains? msg "offset") "error message specifies offset")
         (assert (stringContains? msg "6") "error offset is 6"))))
    (assert (ok? resGoodBytes) "parseBytes returns ok on well-formed XML")
    (assert (err? resBadBytes) "parseBytes returns err on not-wf XML")
    (mt resBadBytes
      ((ok _) (assert false "expected err on not-wf XML bytes"))
      ((err msgBytes)
       (do
         (assert (stringContains? msgBytes "offset") "bytes error message specifies offset")
         (assert (stringContains? msgBytes "6") "bytes error offset is 6"))))
    true)


fn pad3 idx: Int64 -> String
  (if (< idx 10)
    (str "00" (stringFromInt64 idx))
    (if (< idx 100)
      (str "0" (stringFromInt64 idx))
      (stringFromInt64 idx)))

fn validExclusions -> (List (Pair Int64 String))
  (list
    (pair 49 "UTF-16 little-endian encoding with BOM (parser expects UTF-8 byte stream)")
    (pair 50 "UTF-16 little-endian encoding with BOM (parser expects UTF-8 byte stream)"))

fn notWfExclusions -> (List (Pair Int64 String))
  (list
    (pair 3 "Processing instruction target name is required (empty target <? ?>)")
    (pair 20 "Attribute value contains bare unescaped ampersand (<doc a1=\"A & B\">)")
    (pair 21 "Attribute value contains bare unescaped ampersand (<doc a1=\"a&b\">)")
    (pair 22 "Character reference in attribute value ends with colon instead of semicolon (&#123:)")
    (pair 30 "Form feed control character (0x0C) in text content is not legal XML character")
    (pair 31 "Form feed control character (0x0C) in processing instruction is not legal XML character")
    (pair 32 "Form feed control character (0x0C) in comment is not legal XML character")
    (pair 33 "Escape control character (0x1B) in text content is not legal XML character")
    (pair 48 "CDATA section after document root element is not permitted")
    (pair 50 "Empty document with no root element"))

fn findExclusionReason cases: (List (Pair Int64 String)) target: Int64 -> (Option String)
  (if (listEmpty? cases)
    (none)
    (let [(head (optionOr (listHead cases) (pair 0 "")))
          (tail (optionOr (listTail cases) (list)))]
      (if (= (pairFirst head) target)
        (some (pairSecond head))
        (findExclusionReason tail target))))

fn isExcluded cases: (List (Pair Int64 String)) target: Int64 -> Bool
  (some? (findExclusionReason cases target))

fn printExclusions! prefix: String cases: (List (Pair Int64 String)) -> Bool
  (if (listEmpty? cases)
    true
    (let [(head (optionOr (listHead cases) (pair 0 "")))
          (tail (optionOr (listTail cases) (list)))]
      (do
        (println (str "  " prefix " excluded case " (stringFromInt64 (pairFirst head)) ": " (pairSecond head)))
        (printExclusions! prefix tail))))

fn checkUpstreamValid! idx: Int64 total: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (> idx total)
    (do
      (println (str "W3C xmltest valid/sa: " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printExclusions! "valid/sa" (validExclusions))
      (assert (= (+ passCount excludedCount) total) "all valid cases accounted for")
      (assert (= passCount 48) "48 valid upstream cases verified well-formed")
      (assert (= excludedCount 2) "2 valid upstream cases excluded with documented reasons")
      true)
    (if (isExcluded (validExclusions) idx)
      (checkUpstreamValid! (+ idx 1) total passCount (+ excludedCount 1))
      (let [(path (str "asl/packages/asl-syntax/tests/fixtures/upstream/xmlts/valid/sa/" (pad3 idx) ".xml.sample"))
            (readRes (fileReadBytes path))]
        (do
          (assert (ok? readRes) (str "valid file readable: " path))
          (let [(bs (resultOr readRes (stringToBytes "")))
                (root (xml/parseXmlBytes bs))
                (parseRes (xml/parseBytes bs))
                (len (bytesLength bs))
                (toks (xml/tokenizeBytes bs))]
            (do
              (assert (xml/isWellFormed root) (str "upstream case valid/sa/" (pad3 idx) " is well-formed"))
              (assert (ok? parseRes) (str "parseBytes succeeds on valid/sa/" (pad3 idx)))
              (assert (ok? (tr/checkTokensTiling toks len)) (str "tokens tile valid/sa/" (pad3 idx)))
              (checkUpstreamValid! (+ idx 1) total (+ passCount 1) excludedCount)))))))

fn checkUpstreamNotWf! idx: Int64 total: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (> idx total)
    (do
      (println (str "W3C xmltest not-wf/sa: " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printExclusions! "not-wf/sa" (notWfExclusions))
      (assert (= (+ passCount excludedCount) total) "all not-wf cases accounted for")
      (assert (= passCount 40) "40 not-wf upstream cases verified not well-formed")
      (assert (= excludedCount 10) "10 not-wf upstream cases excluded with documented reasons")
      true)
    (if (isExcluded (notWfExclusions) idx)
      (checkUpstreamNotWf! (+ idx 1) total passCount (+ excludedCount 1))
      (let [(path (str "asl/packages/asl-syntax/tests/fixtures/upstream/xmlts/not-wf/sa/" (pad3 idx) ".xml.sample"))
            (readRes (fileReadBytes path))]
        (do
          (assert (ok? readRes) (str "not-wf file readable: " path))
          (let [(bs (resultOr readRes (stringToBytes "")))
                (root (xml/parseXmlBytes bs))
                (parseRes (xml/parseBytes bs))]
            (do
              (assert (not (xml/isWellFormed root)) (str "upstream case not-wf/sa/" (pad3 idx) " is not well-formed"))
              (assert (err? parseRes) (str "parseBytes returns err on not-wf/sa/" (pad3 idx)))
              (checkUpstreamNotWf! (+ idx 1) total (+ passCount 1) excludedCount)))))))

fn testUpstreamSuite! -> Bool
  (let [(indexPath "asl/packages/asl-syntax/tests/fixtures/upstream/xmlts/index.asn.sample")
        (readRes (fileReadBytes indexPath))]
    (do
      (assert (ok? readRes) "xmlts index.asn readable")
      (let [(bs (resultOr readRes (stringToBytes "")))
            (actualSha (bytesSha256 bs))
            (expectedSha "1e8b6762f701c8377b4a1c714a482d03a5525ef53f6ee92ae6538f02dede5eb1")]
        (do
          (assert (= actualSha expectedSha) "xmlts index.asn sha256 matches manifest")
          (let [(entry (crp/makeUpstreamEntry
                         "https://www.w3.org/XML/Test/xmlts20130923.zip"
                         "2013-09-23"
                         expectedSha
                         "W3C-Software-and-Document-Notice-and-License"
                         indexPath))]
            (assert (ok? (crp/verifyUpstreamEntry! entry)) "xmlts index entry verified"))
          (let [(indexRes (crp/verifyUpstreamManifestFile! indexPath))]
            (assert (ok? indexRes) "all 100 vendored xmlts files verified against index sha256"))))
      (assert (checkUpstreamValid! 1 50 0 0) "all 50 valid/sa cases run")
      (assert (checkUpstreamNotWf! 1 50 0 0) "all 50 not-wf/sa cases run")
      true))

fn ! runTests -> Bool
  (let [(r1 (testW3CWellFormedMinimal))
        (r2 (testW3CWellFormedProlog))
        (r3 (testW3CWellFormedComments))
        (r4 (testW3CWellFormedPI))
        (r5 (testW3CWellFormedCData))
        (r6 (testW3CWellFormedEntities))
        (r7 (testW3CWellFormedDoctype))
        (r8 (testW3CWellFormedAttributes))
        (r9 (testW3CWellFormedNestingAndContent))
        (r10 (testW3CNotWfMismatchedTag))
        (r11 (testW3CNotWfUnclosedTag))
        (r12 (testW3CNotWfStrayEndTag))
        (r13 (testW3CNotWfMultipleRoots))
        (r14 (testW3CNotWfTextOutsideRoot))
        (r15 (testW3CNotWfDuplicateAttr))
        (r16 (testW3CNotWfLtInAttr))
        (r17 (testW3CNotWfUnquotedAttr))
        (r18 (testW3CNotWfCommentErrors))
        (r19 (testW3CNotWfCDataErrors))
        (r20 (testW3CNotWfPIErrors))
        (r21 (testW3CNotWfBadTagNames))
        (r22 (testRoundTripTrackedCorpus!))
        (r23 (testTrackedTruncatedSvgDetectedAsNotWf!))
        (r24 (testIdAndPathSymbols))
        (r25 (testReparseGuard))
        (r26 (testXmlBenchPerf!))
        (r27 (testParseAndParseBytes))
        (r28 (testElementNodeAndTokenSpans))
        (r29 (testAttributeNodeAndTokenSpans))
        (r30 (testCommentNodeAndTokenSpans))
        (r31 (testCDataNodeAndTokenSpans))
        (r32 (testPINodeAndTokenSpans))
        (r33 (testDoctypeNodeAndTokenSpans))
        (r34 (testUpstreamSuite!))]
    (and r1
    (and r2
    (and r3
    (and r4
    (and r5
    (and r6
    (and r7
    (and r8
    (and r9
    (and r10
    (and r11
    (and r12
    (and r13
    (and r14
    (and r15
    (and r16
    (and r17
    (and r18
    (and r19
    (and r20
    (and r21
    (and r22
    (and r23
    (and r24
    (and r25
    (and r26
    (and r27
    (and r28
    (and r29
    (and r30
    (and r31
    (and r32
    (and r33
         r34))))))))))))))))))))))))))))))))))
