(module asl-text/text
  :x [ExtractedDoc ContextChunk ContextualClause TableData CodeBlockData DistilledSection DistilledDoc SourceIndexResult InternResult decodeHtmlEntities stripEnclosed cleanHtml extractHtml extractMarkdown extractPlaintext extractJsonKv extractXmlAtom extractContext chunkText chunkDoc formatChunkMarkdown formatContextRag formatDocsRag formatClauseBreadcrumb formatContextualClause extractClauses extractContextualClauses docToAsn chunkToAsn clauseToAsn stripQuotes stripColon estimateTokens calcSavings extractBetween isNumeric stripComment extractTagContents extractTables tableToAsn extractCodeBlocks codeBlockToAsn internUrls detectSpaEmptyDom distillHtml distilledDocToAsn sanitizeUrlTracking extractTitleFromHtml normalizeWhitespace]
  :i [(escape :a esc)])

schema ExtractedDoc { title: Str content: Str format: Str source: Str charCount: I64 }

schema ContextChunk { id: Str content: Str index: I64 charCount: I64 source: Str }

schema ContextualClause { id: Str docTitle: Str sectionPath: (List Str) clauseText: Str charCount: I64 source: Str }

fn decodeHtmlEntities text: Str -> Str
  (let [(s1 (stringReplace text "&amp;" "&")) (s2 (stringReplace s1 "&lt;" "<")) (s3 (stringReplace s2 "&gt;" ">")) (s4 (stringReplace s3 "&quot;" "\"")) (s5 (stringReplace s4 "&#39;" "'")) (s6 (stringReplace s5 "&apos;" "'"))] (stringReplace s6 "&nbsp;" " "))

fn stripEnclosed src: Str openDelim: Str closeDelim: Str -> Str
  (mt (stringIndexOf src openDelim) ((none) src) ((some startIdx) (let [(prefix (optionOr (stringSlice src 0 startIdx) "")) (tailStart (+ startIdx (stringLength openDelim))) (tail (optionOr (stringSlice src tailStart (stringLength src)) ""))] (mt (stringIndexOf tail closeDelim) ((none) prefix) ((some closeIdx) (let [(remStart (+ closeIdx (stringLength closeDelim))) (remainder (optionOr (stringSlice tail remStart (stringLength tail)) ""))] (str prefix (stripEnclosed remainder openDelim closeDelim))))))))

fn collapseSpacesLine line: Str -> Str
  (let [(words (filter (fn [(w Str)] -> Bool (not (stringEmpty? (stringTrim w)))) (stringSplit line " ")))] (stringJoin words " "))

fn normalizeWhitespace text: Str -> Str
  (let [(lines (stringSplit text "\n")) (cleanedLines (map collapseSpacesLine lines)) (nonEmpty (filter (fn [(l Str)] -> Bool (not (stringEmpty? l))) cleanedLines))] (stringJoin nonEmpty "\n"))

fn cleanHtml htmlSrc: Str -> Str
  (let [(s1 (stripEnclosed htmlSrc "<style" "</style>"))
        (s2 (stripEnclosed s1 "<script" "</script>"))
        (s3 (stripEnclosed s2 "<nav" "</nav>"))
        (s4 (stripEnclosed s3 "<header" "</header>"))
        (s5 (stripEnclosed s4 "<footer" "</footer>"))
        (s6 (stripEnclosed s5 "<noscript" "</noscript>"))
        (s7 (stripEnclosed s6 "<!--" "-->"))
        (s7a (stringReplace (stringReplace (stringReplace (stringReplace s7 "<=" "&lt;=") ">=" "&gt;=") "< " "&lt; ") " >" " &gt;"))
        (s7b (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s7a "<h1" "\n# <h1") "<h2" "\n## <h2") "<h3" "\n### <h3") "<h4" "\n#### <h4") "<h5" "\n##### <h5") "<h6" "\n###### <h6"))
        (s7c (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s7b "</h1" "\n</h1") "</h2" "\n</h2") "</h3" "\n</h3") "</h4" "\n</h4") "</h5" "\n</h5") "</h6" "\n</h6"))
        (s7d (stringReplace (stringReplace (stringReplace s7c "<H1" "\n# <H1") "<H2" "\n## <H2") "<H3" "\n### <H3"))
        (s7e (stringReplace (stringReplace (stringReplace s7d "</H1" "\n</H1") "</H2" "\n</H2") "</H3" "\n</H3"))
        (s8 (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s7e "<br>" "\n") "<br/>" "\n") "<br />" "\n") "<p>" "\n") "</p>" "\n") "</div>" "\n"))
        (s9 (stripEnclosed s8 "<" ">"))
        (s10 (decodeHtmlEntities s9))]
    (normalizeWhitespace s10))

fn sliceAfterTag s: Str tag: Str -> (Option Str)
  (mt (stringIndexOf s tag) ((none) (none)) ((some idx) (let [(len (stringLength s))] (stringSlice s idx len))))

fn sliceTagBody s: Str -> (Option Str)
  (mt (stringIndexOf s ">") ((none) (none)) ((some openEnd) (let [(contentStart (+ openEnd 1)) (len (stringLength s))] (stringSlice s contentStart len))))

fn sliceBeforeClose body: Str endTag: Str -> Str
  (mt (stringIndexOf body endTag) ((none) (stringTrim (decodeHtmlEntities body))) ((some closeIdx) (mt (stringSlice body 0 closeIdx) ((none) "") ((some rawT) (stringTrim (decodeHtmlEntities rawT))))))

fn extractTitleFromHtml html: Str -> Str
  (mt (sliceAfterTag html "<title") ((some afterOpen) (mt (sliceTagBody afterOpen) ((some body) (sliceBeforeClose body "</title")) ((none) ""))) ((none) (mt (sliceAfterTag html "<TITLE") ((some afterOpen) (mt (sliceTagBody afterOpen) ((some body) (sliceBeforeClose body "</TITLE")) ((none) ""))) ((none) ""))))

fn extractHtml rawHtml: Str source: Str -> ExtractedDoc
  (let [(t1 (extractTitleFromHtml rawHtml)) (t2 (if (stringEmpty? t1) (extractTitleFromHtml (stringReplace (stringReplace rawHtml "<h1>" "<title>") "</h1>" "</title>")) t1)) (finalTitle (if (stringEmpty? t2) source t2)) (cleanedBody (cleanHtml rawHtml))] (ExtractedDoc :title finalTitle :content cleanedBody :format "html" :source source :charCount (stringLength cleanedBody)))

fn cleanMarkdown mdSrc: Str -> Str
  (let [(s1 (stripEnclosed mdSrc "```" "```")) (s2 (stringReplace (stringReplace s1 "**" "") "*" "")) (s3 (stringReplace (stringReplace s2 "[" "") "]" "")) (s4 (stripEnclosed s3 "(" ")"))] (normalizeWhitespace s4))

fn extractMarkdown rawMd: Str source: Str -> ExtractedDoc
  (let [(cleaned (cleanMarkdown rawMd))] (ExtractedDoc :title source :content cleaned :format "markdown" :source source :charCount (stringLength cleaned)))

fn extractPlaintext rawTxt: Str source: Str -> ExtractedDoc
  (let [(cleaned (normalizeWhitespace rawTxt))] (ExtractedDoc :title source :content cleaned :format "text" :source source :charCount (stringLength cleaned)))

fn extractJsonField rawJson: Str fieldKey: Str -> Str
  (let [(needle (str "\"" fieldKey "\": \""))] (mt (stringIndexOf rawJson needle) ((none) "") ((some idx) (let [(tailStart (+ idx (stringLength needle))) (tail (optionOr (stringSlice rawJson tailStart (stringLength rawJson)) ""))] (mt (stringIndexOf tail "\"") ((none) tail) ((some endIdx) (optionOr (stringSlice tail 0 endIdx) "")))))))

fn extractJsonKv rawJson: Str source: Str -> ExtractedDoc
  (let [(c1 (extractJsonField rawJson "content")) (c2 (if (stringEmpty? c1) (extractJsonField rawJson "text") c1)) (c3 (if (stringEmpty? c2) (extractJsonField rawJson "snippet") c2)) (c4 (if (stringEmpty? c3) (extractJsonField rawJson "body") c3)) (finalContent (if (stringEmpty? c4) (normalizeWhitespace rawJson) c4)) (t (extractJsonField rawJson "title")) (finalTitle (if (stringEmpty? t) source t))] (ExtractedDoc :title finalTitle :content finalContent :format "json" :source source :charCount (stringLength finalContent)))

fn extractTitleFromTag src: Str openTag: Str closeTag: Str -> Str
  (mt (sliceAfterTag src openTag) ((none) "") ((some afterOpen) (mt (stringIndexOf afterOpen closeTag) ((none) "") ((some closeIdx) (let [(rawT (optionOr (stringSlice afterOpen 0 closeIdx) ""))] (decodeHtmlEntities (stringTrim rawT)))))))

fn extractXmlAtom rawXml: Str source: Str -> ExtractedDoc
  (let [(t (extractTitleFromTag rawXml "<title>" "</title>")) (s1 (extractTitleFromTag rawXml "<summary>" "</summary>")) (s2 (if (stringEmpty? s1) (extractTitleFromTag rawXml "<content>" "</content>") s1)) (finalContent (if (stringEmpty? s2) (cleanHtml rawXml) (cleanHtml s2))) (finalTitle (if (stringEmpty? t) source t))] (ExtractedDoc :title finalTitle :content finalContent :format "xml" :source source :charCount (stringLength finalContent)))

fn extractContext rawContent: Str format: Str source: Str -> ExtractedDoc
  (cond ((= format "html") (extractHtml rawContent source)) ((= format "markdown") (extractMarkdown rawContent source)) ((= format "md") (extractMarkdown rawContent source)) ((= format "json") (extractJsonKv rawContent source)) ((= format "xml") (extractXmlAtom rawContent source)) ((= format "atom") (extractXmlAtom rawContent source)) (else (extractPlaintext rawContent source)))

fn makeChunkId source: Str index: I64 -> Str
  (str source "#chunk-" (stringFromInt64 index))

fn chunkTextHelper text: Str maxChars: I64 step: I64 offset: I64 index: I64 source: Str -> (List ContextChunk)
  (let [(total (stringLength text))] (if (>= offset total) (list) (let [(endIdx (min total (+ offset maxChars))) (sliceText (optionOr (stringSlice text offset endIdx) "")) (chunk (ContextChunk :id (makeChunkId source index) :content sliceText :index index :charCount (stringLength sliceText) :source source)) (nextOffset (+ offset step))] (if (>= endIdx total) (list chunk) (cons chunk (chunkTextHelper text maxChars step nextOffset (+ index 1) source))))))

fn chunkText text: Str maxChars: I64 overlapChars: I64 source: Str -> (List ContextChunk)
  (let [(safeMax (max 10 maxChars)) (step (max 1 (- safeMax overlapChars)))] (chunkTextHelper text safeMax step 0 1 source))

fn chunkDoc doc: ExtractedDoc maxChars: I64 overlapChars: I64 -> (List ContextChunk)
  (chunkText doc.content maxChars overlapChars doc.source)

fn formatChunkMarkdown chunk: ContextChunk -> Str
  (str "[" (stringFromInt64 chunk.index) "] (" chunk.source "):\n" chunk.content "\n")

fn formatContextRag query: Str chunks: (List ContextChunk) -> Str
  (let [(header (str "## Context for query: '" query "' (" (stringFromInt64 (listLength chunks)) " chunks)\n\n")) (chunksMd (stringJoin (map formatChunkMarkdown chunks) "\n"))] (str header chunksMd))

fn formatDocSummary index: I64 doc: ExtractedDoc -> Str
  (str (stringFromInt64 index) ". **[" doc.title "](" doc.source ")** [" doc.format " · " (stringFromInt64 doc.charCount) " chars]\n" doc.content "\n")

fn formatDocsRagHelper docs: (List ExtractedDoc) idx: I64 -> (List Str)
  (if (listEmpty? docs) (list) (let [(d (optionOr (listHead docs) (ExtractedDoc :title "" :content "" :format "" :source "" :charCount 0))) (rest (optionOr (listTail docs) (list)))] (cons (formatDocSummary idx d) (formatDocsRagHelper rest (+ idx 1)))))

fn formatDocsRag query: Str docs: (List ExtractedDoc) -> Str
  (let [(header (str "## Extracted Documents for query: '" query "' (" (stringFromInt64 (listLength docs)) " docs)\n\n")) (summaries (formatDocsRagHelper docs 1)) (docsMd (stringJoin summaries "\n"))] (str header docsMd))

fn docToAsn doc: ExtractedDoc -> Str
  (str "(:doc :title \"" (esc/escapeAsnStr doc.title) "\" :format \"" (esc/escapeAsnStr doc.format) "\" :source \"" (esc/escapeAsnStr doc.source) "\" :chars " (stringFromInt64 doc.charCount) " :content \"" (esc/escapeAsnStr doc.content) "\")")

fn chunkToAsn chunk: ContextChunk -> Str
  (str "(:chunk :id \"" (esc/escapeAsnStr chunk.id) "\" :index " (stringFromInt64 chunk.index) " :source \"" (esc/escapeAsnStr chunk.source) "\" :chars " (stringFromInt64 chunk.charCount) " :payload \"" (esc/escapeAsnStr chunk.content) "\")")

schema HeadingInfo { level: I64 text: Str }

fn formatClauseBreadcrumb clause: ContextualClause -> Str
  (let [(pathStr (stringJoin clause.sectionPath " > ")) (header (str "[Doc: " clause.docTitle " | Section: " pathStr " | ID: " clause.id "]\n"))] (str header clause.clauseText))

fn formatContextualClause clause: ContextualClause -> Str
  (formatClauseBreadcrumb clause)

fn clauseToAsn clause: ContextualClause -> Str
  (let [(pathStr (stringJoin clause.sectionPath " > "))] (str "(:clause :id \"" (esc/escapeAsnStr clause.id) "\" :doc \"" (esc/escapeAsnStr clause.docTitle) "\" :section \"" (esc/escapeAsnStr pathStr) "\" :chars " (stringFromInt64 clause.charCount) " :payload \"" (esc/escapeAsnStr clause.clauseText) "\")"))

fn detectHeading line: Str -> (Option HeadingInfo)
  (let [(trimmed (stringTrim line))] (cond ((stringStartsWith? trimmed "### ") (some (HeadingInfo :level 3 :text (stringTrim (optionOr (stringSlice trimmed 4 (stringLength trimmed)) ""))))) ((stringStartsWith? trimmed "## ") (some (HeadingInfo :level 2 :text (stringTrim (optionOr (stringSlice trimmed 3 (stringLength trimmed)) ""))))) ((stringStartsWith? trimmed "# ") (some (HeadingInfo :level 1 :text (stringTrim (optionOr (stringSlice trimmed 2 (stringLength trimmed)) ""))))) ((stringStartsWith? trimmed "Article ") (some (HeadingInfo :level 2 :text trimmed))) ((stringStartsWith? trimmed "Section ") (some (HeadingInfo :level 3 :text trimmed))) (else (none))))

fn updateBreadcrumbPath path: (List Str) level: I64 heading: Str -> (List Str)
  (let [(keepCount (max 1 (min (listLength path) level))) (truncated (listTake path keepCount))] (listAppend truncated (list heading)))

fn emitClauseRecord docTitle: Str path: (List Str) text: Str source: Str idx: I64 -> ContextualClause
  (ContextualClause :id (str source "#clause-" (stringFromInt64 idx)) :docTitle docTitle :sectionPath path :clauseText text :charCount (stringLength text) :source source)

fn extractClausesLoop lines: (List Str) path: (List Str) paraAcc: (List Str) docTitle: Str source: Str minChars: I64 maxChars: I64 clauseIdx: I64 -> (List ContextualClause)
  (if (listEmpty? lines) (if (listEmpty? paraAcc) (list) (let [(text (stringJoin paraAcc " "))] (if (> (stringLength (stringTrim text)) 0) (list (emitClauseRecord docTitle path (stringTrim text) source clauseIdx)) (list)))) (let [(line (optionOr (listHead lines) "")) (rest (optionOr (listTail lines) (list))) (trimmed (stringTrim line)) (headingOpt (detectHeading trimmed))] (mt headingOpt ((some h) (let [(hLevel h.level) (hText h.text) (newPath (updateBreadcrumbPath path hLevel hText))] (if (listEmpty? paraAcc) (extractClausesLoop rest newPath (list) docTitle source minChars maxChars clauseIdx) (let [(paraStr (stringTrim (stringJoin paraAcc " ")))] (if (> (stringLength paraStr) 0) (cons (emitClauseRecord docTitle path paraStr source clauseIdx) (extractClausesLoop rest newPath (list) docTitle source minChars maxChars (+ clauseIdx 1))) (extractClausesLoop rest newPath (list) docTitle source minChars maxChars clauseIdx)))))) ((none) (if (stringEmpty? trimmed) (if (listEmpty? paraAcc) (extractClausesLoop rest path (list) docTitle source minChars maxChars clauseIdx) (let [(paraStr (stringTrim (stringJoin paraAcc " ")))] (if (>= (stringLength paraStr) minChars) (cons (emitClauseRecord docTitle path paraStr source clauseIdx) (extractClausesLoop rest path (list) docTitle source minChars maxChars (+ clauseIdx 1))) (extractClausesLoop rest path paraAcc docTitle source minChars maxChars clauseIdx)))) (let [(nextPara (listAppend paraAcc (list trimmed))) (currText (stringJoin nextPara " "))] (if (>= (stringLength currText) maxChars) (cons (emitClauseRecord docTitle path (stringTrim currText) source clauseIdx) (extractClausesLoop rest path (list) docTitle source minChars maxChars (+ clauseIdx 1))) (extractClausesLoop rest path nextPara docTitle source minChars maxChars clauseIdx))))))))

fn extractClauses doc: ExtractedDoc minChars: I64 maxChars: I64 -> (List ContextualClause)
  (let [(title (if (stringEmpty? (stringTrim doc.title)) "Document" (stringTrim doc.title))) (source (if (stringEmpty? (stringTrim doc.source)) "doc" (stringTrim doc.source))) (safeMin (max 1 minChars)) (safeMax (max safeMin maxChars)) (initPath (list title)) (lines (stringSplit doc.content "\n"))] (extractClausesLoop lines initPath (list) title source safeMin safeMax 1))

fn extractContextualClauses doc: ExtractedDoc minChars: I64 maxChars: I64 -> (List ContextualClause)
  (extractClauses doc minChars maxChars)

fn stripQuotes val: Str -> Str
  (let [(len (stringLength val))] (if (and (>= len 2) (or (and (stringStartsWith? val "\"") (stringEndsWith? val "\"")) (and (stringStartsWith? val "'") (stringEndsWith? val "'")))) (optionOr (stringSlice val 1 (- len 1)) "") val))

fn stripColon val: Str -> Str
  (if (stringStartsWith? val ":") (optionOr (stringSlice val 1 (stringLength val)) "") val)

fn estimateTokens text: Str -> I64
  (let [(len (stringLength text))] (cond ((<= len 0) 0) ((<= len 4) 1) (else (let [(num (+ len 3)) (rem (mod num 4))] (/ (- num rem) 4)))))

fn calcSavings orig: I64 asn: I64 -> F64
  (if (<= orig 0) 0.0 (let [(diff (- orig asn))] (if (<= diff 0) 0.0 (/ (* (int64ToFloat64 diff) 100.0) (int64ToFloat64 orig)))))

fn extractBetween text: Str prefix: Str suffix: Str -> (Option Str)
  (mt (stringIndexOf text prefix) ((none) (none)) ((some startIdx) (let [(startPos (+ startIdx (stringLength prefix))) (remaining (optionOr (stringSlice text startPos (stringLength text)) ""))] (mt (stringIndexOf remaining suffix) ((none) (none)) ((some endIdx) (stringSlice remaining 0 endIdx))))))

fn isNumeric s: Str -> Bool
  (let [(chars (stringChars s))] (if (listEmpty? chars) false (numericLoop chars true false)))

fn numericLoop chars: (List Str) isFirst: Bool hasDot: Bool -> Bool
  (mt (listHead chars) ((none) true) ((some c) (if (stringContains? "0123456789" c) (numericLoop (optionOr (listTail chars) (list)) false hasDot) (if (and isFirst (= c "-")) (numericLoop (optionOr (listTail chars) (list)) false hasDot) (if (and (not hasDot) (= c ".")) (numericLoop (optionOr (listTail chars) (list)) false true) false)))))

fn stripComment line: Str commentChar: Str -> Str
  (let [(chars (stringChars line))] (stripCommentLoop chars commentChar false ""))

fn stripCommentLoop chars: (List Str) commentChar: Str inQuote: Bool acc: Str -> Str
  (mt (listHead chars) ((none) acc) ((some c) (if inQuote (if (or (= c "\"") (= c "'")) (stripCommentLoop (optionOr (listTail chars) (list)) commentChar false (str acc c)) (stripCommentLoop (optionOr (listTail chars) (list)) commentChar true (str acc c))) (if (or (= c "\"") (= c "'")) (stripCommentLoop (optionOr (listTail chars) (list)) commentChar true (str acc c)) (if (= c commentChar) acc (stripCommentLoop (optionOr (listTail chars) (list)) commentChar false (str acc c)))))))

schema TableData { id: Str cols: (List Str) rows: (List (List Str)) }

schema CodeBlockData { id: Str lang: Str code: Str }

schema DistilledSection { id: Str level: I64 title: Str content: Str }

schema DistilledDoc { title: Str sources: (List Str) sections: (List DistilledSection) tables: (List TableData) codeBlocks: (List CodeBlockData) needsRendering: Bool rawChars: I64 distilledChars: I64 }

schema SourceIndexResult { sources: (List Str) index: I64 }

schema InternResult { text: Str sources: (List Str) }

fn extractTagContents html: Str tagName: Str -> (List Str)
  (let [(needle (str "<" tagName))]
    (mt (stringIndexOf html needle)
      ((none) (list))
      ((some tagIdx)
        (let [(fromTag (optionOr (stringSlice html tagIdx (stringLength html)) ""))]
          (mt (stringIndexOf fromTag ">")
            ((none) (list))
            ((some openBracketEnd)
              (let [(contentStart (+ openBracketEnd 1))
                    (afterOpen (optionOr (stringSlice fromTag contentStart (stringLength fromTag)) ""))
                    (closeNeedle (str "</" tagName ">"))]
                (mt (stringIndexOf afterOpen closeNeedle)
                  ((none) (list))
                  ((some closeIdx)
                    (let [(inner (optionOr (stringSlice afterOpen 0 closeIdx) ""))
                          (remStart (+ closeIdx (stringLength closeNeedle)))
                          (remainder (optionOr (stringSlice afterOpen remStart (stringLength afterOpen)) ""))]
                      (cons inner (extractTagContents remainder tagName))))))))))))

fn cleanCellText raw: Str -> Str
  (let [(stripped (stripEnclosed raw "<" ">"))]
    (normalizeWhitespace (decodeHtmlEntities stripped)))

fn parseTableRow rowHtml: Str -> (List Str)
  (let [(cells (extractTagContents rowHtml "td"))]
    (map cleanCellText cells))

fn parseTableHeader rowHtml: Str -> (List Str)
  (let [(thCells (extractTagContents rowHtml "th"))]
    (if (not (listEmpty? thCells))
      (map cleanCellText thCells)
      (let [(tdCells (extractTagContents rowHtml "td"))]
        (map cleanCellText tdCells))))

fn parseTableInner tableHtml: Str idx: I64 -> TableData
  (let [(tblId (str "tbl-" (stringFromInt64 idx)))
        (rowsHtml (extractTagContents tableHtml "tr"))]
    (if (listEmpty? rowsHtml)
      (let [(cols (map cleanCellText (extractTagContents tableHtml "th")))]
        (TableData :id tblId :cols cols :rows (list)))
      (let [(firstRow (optionOr (listHead rowsHtml) ""))
            (restRows (optionOr (listTail rowsHtml) (list)))
            (hasTh (stringContains? firstRow "<th"))]
        (if hasTh
          (let [(cols (parseTableHeader firstRow))
                (rows (map parseTableRow restRows))]
            (TableData :id tblId :cols cols :rows rows))
          (let [(rows (map parseTableRow rowsHtml))]
            (TableData :id tblId :cols (list) :rows rows))))))

fn extractTablesLoop tablesHtml: (List Str) idx: I64 -> (List TableData)
  (mt (listHead tablesHtml)
    ((none) (list))
    ((some tblHtml)
      (cons (parseTableInner tblHtml idx)
                 (extractTablesLoop (optionOr (listTail tablesHtml) (list)) (+ idx 1)))))

fn extractTables html: Str -> (List TableData)
  (let [(tablesHtml (extractTagContents html "table"))]
    (extractTablesLoop tablesHtml 1))

fn tableToAsn table: TableData -> Str
  (let [(idStr (if (stringEmpty? table.id) "" (str " :id \"" (esc/escapeAsnStr table.id) "\"")))
        (colsAsn (str "[" (stringJoin (map (fn [(c Str)] -> Str (str "\"" (esc/escapeAsnStr c) "\"")) table.cols) " ") "]"))
        (rowsAsnList (map (fn [(r (List Str))] -> Str
                            (str "      [" (stringJoin (map (fn [(cell Str)] -> Str (str "\"" (esc/escapeAsnStr cell) "\"")) r) " ") "]"))
                          table.rows))
        (rowsAsn (if (listEmpty? rowsAsnList) "[]" (str "[\n" (stringJoin rowsAsnList "\n") "\n    ]")))]
    (str "    (:table" idStr " :cols " colsAsn " :rows " rowsAsn ")"))

fn extractLangFromTag tagHeader: Str -> Str
  (mt (extractBetween tagHeader "class=\"language-" "\"")
    ((some lang) lang)
    ((none)
      (mt (extractBetween tagHeader "class=\"lang-" "\"")
        ((some lang2) lang2)
        ((none) ""))))

fn extractCodeBlocksLoop html: Str idx: I64 -> (List CodeBlockData)
  (let [(needle "<pre")]
    (mt (stringIndexOf html needle)
      ((none) (list))
      ((some preIdx)
        (let [(fromPre (optionOr (stringSlice html preIdx (stringLength html)) ""))]
          (mt (stringIndexOf fromPre ">")
            ((none) (list))
            ((some headerEnd)
              (let [(header (optionOr (stringSlice fromPre 0 headerEnd) ""))
                    (afterHeader (optionOr (stringSlice fromPre (+ headerEnd 1) (stringLength fromPre)) ""))
                    (lang (extractLangFromTag header))]
                (mt (stringIndexOf afterHeader "</pre>")
                  ((none) (list))
                  ((some closeIdx)
                    (let [(rawInner (optionOr (stringSlice afterHeader 0 closeIdx) ""))
                          (cleanInner (stripEnclosed (stripEnclosed rawInner "<code" ">") "</code" ">"))
                          (decoded (decodeHtmlEntities cleanInner))
                          (cbId (str "cb-" (stringFromInt64 idx)))
                          (cb (CodeBlockData :id cbId :lang lang :code (stringTrim decoded)))
                          (remStart (+ closeIdx 6))
                          (remainder (optionOr (stringSlice afterHeader remStart (stringLength afterHeader)) ""))]
                      (cons cb (extractCodeBlocksLoop remainder (+ idx 1)))))))))))))

fn extractCodeBlocks html: Str -> (List CodeBlockData)
  (extractCodeBlocksLoop html 1)

fn codeBlockToAsn cb: CodeBlockData -> Str
  (let [(idStr (if (stringEmpty? cb.id) "" (str " :id \"" (esc/escapeAsnStr cb.id) "\"")))
        (langStr (if (stringEmpty? cb.lang) "" (str " :lang \"" (esc/escapeAsnStr cb.lang) "\"")))
        (escCode (esc/escapeAsnStr cb.code))]
    (str "    (:codeBlock" idStr langStr " :code \"" escCode "\")"))

fn sanitizeUrlTracking url: Str -> Str
  (mt (stringIndexOf url "?")
    ((none) url)
    ((some qIdx)
      (let [(base (optionOr (stringSlice url 0 qIdx) ""))
            (query (optionOr (stringSlice url (+ qIdx 1) (stringLength url)) ""))
            (params (stringSplit query "&"))
            (cleanParams (filter (fn [(p Str)] -> Bool
                                   (let [(low (stringLower p))]
                                     (and (not (stringStartsWith? low "utm_"))
                                          (and (not (stringStartsWith? low "fbclid="))
                                               (and (not (stringStartsWith? low "gclid="))
                                                    (and (not (stringStartsWith? low "ref_src="))
                                                         (not (stringStartsWith? low "mc_cid="))))))))
                                 params))]
        (if (listEmpty? cleanParams)
          base
          (str base "?" (stringJoin cleanParams "&"))))))

fn findSourceIndex sources: (List Str) target: Str idx: I64 -> (Option I64)
  (mt (listHead sources)
    ((none) (none))
    ((some h)
      (if (= h target)
        (some idx)
        (findSourceIndex (optionOr (listTail sources) (list)) target (+ idx 1)))))

fn internSource sources: (List Str) rawUrl: Str -> SourceIndexResult
  (let [(cleanUrl (sanitizeUrlTracking (stringTrim rawUrl)))]
    (mt (findSourceIndex sources cleanUrl 1)
      ((some foundIdx)
        (SourceIndexResult :sources sources :index foundIdx))
      ((none)
        (let [(newSources (listAppend sources (list cleanUrl)))]
          (SourceIndexResult :sources newSources :index (listLength newSources))))))

fn internUrlsLoop remainder: Str sources: (List Str) accText: Str remainingBudget: I64 -> InternResult
  (if (<= remainingBudget 0)
    (InternResult :text (str accText remainder) :sources sources)
    (mt (stringIndexOf remainder "<a ")
      ((none)
        (InternResult :text (str accText remainder) :sources sources))
      ((some aIdx)
        (let [(prefix (optionOr (stringSlice remainder 0 aIdx) ""))
              (fromA (optionOr (stringSlice remainder aIdx (stringLength remainder)) ""))]
          (mt (stringIndexOf fromA ">")
            ((none)
              (InternResult :text (str accText remainder) :sources sources))
            ((some tagEnd)
              (let [(header (optionOr (stringSlice fromA 0 tagEnd) ""))
                    (afterTag (optionOr (stringSlice fromA (+ tagEnd 1) (stringLength fromA)) ""))]
                (mt (stringIndexOf afterTag "</a>")
                  ((none)
                    (InternResult :text (str accText remainder) :sources sources))
                  ((some closeIdx)
                    (let [(anchorText (optionOr (stringSlice afterTag 0 closeIdx) ""))
                          (nextRem (optionOr (stringSlice afterTag (+ closeIdx 4) (stringLength afterTag)) ""))
                          (urlOpt (extractBetween header "href=\"" "\""))]
                      (mt urlOpt
                        ((none)
                          (let [(nextAcc (str accText prefix anchorText))]
                            (internUrlsLoop nextRem sources nextAcc (- remainingBudget 1))))
                        ((some url)
                          (let [(sRes (internSource sources url))
                                (refTag (str anchorText " [:srcRef " (stringFromInt64 sRes.index) "]"))
                                (nextAcc (str accText prefix refTag))]
                            (internUrlsLoop nextRem sRes.sources nextAcc (- remainingBudget 1)))))))))))))))

fn internUrlsInHtml html: Str sources: (List Str) -> InternResult
  (internUrlsLoop html sources "" 250)

fn internUrls html: Str -> InternResult
  (internUrlsInHtml html (list))

fn detectSpaEmptyDom html: Str -> Bool
  (let [(clean (cleanHtml html))
        (len (stringLength clean))]
    (and (< len 300)
         (or (stringContains? html "id=\"root\"")
             (or (stringContains? html "id=\"app\"")
                 (or (stringContains? html "id=\"__next\"")
                     (or (stringContains? html "id='root'")
                         (or (stringContains? html "id='app'")
                             (stringContains? html "id='__next'"))))))))

fn makeDistilledSections clauses: (List ContextualClause) idx: I64 -> (List DistilledSection)
  (mt (listHead clauses)
    ((none) (list))
    ((some c)
      (let [(secId (str "sec-" (stringFromInt64 idx)))
            (sec (DistilledSection :id secId :level (listLength c.sectionPath) :title (stringJoin c.sectionPath " > ") :content c.clauseText))]
        (cons sec (makeDistilledSections (optionOr (listTail clauses) (list)) (+ idx 1))))))

fn distillHtml rawHtml: Str sourceUrl: Str -> DistilledDoc
  (let [(title (extractTitleFromHtml rawHtml))
        (finalTitle (if (stringEmpty? title) sourceUrl title))
        (isSpa (detectSpaEmptyDom rawHtml))
        (tables (extractTables rawHtml))
        (codeBlocks (extractCodeBlocks rawHtml))
        (noTables (stripEnclosed rawHtml "<table" "</table>"))
        (noCode (stripEnclosed (stripEnclosed noTables "<pre" "</pre>") "<code" "</code>"))
        (interned (internUrls noCode))
        (cleanedText (cleanHtml interned.text))
        (dummyDoc (ExtractedDoc :title finalTitle :content cleanedText :format "html" :source sourceUrl :charCount (stringLength cleanedText)))
        (clauses (extractClauses dummyDoc 50 1000))
        (sections (makeDistilledSections clauses 1))
        (rawLen (stringLength rawHtml))]
    (DistilledDoc
      :title finalTitle
      :sources interned.sources
      :sections sections
      :tables tables
      :codeBlocks codeBlocks
      :needsRendering isSpa
      :rawChars rawLen
      :distilledChars (stringLength cleanedText)))

fn distilledDocToAsn doc: DistilledDoc -> Str
  (let [(titleEsc (esc/escapeAsnStr doc.title))
        (needsRender (if doc.needsRendering "true" "false"))
        (srcItems (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) doc.sources))
        (srcAsn (str "[" (stringJoin srcItems " ") "]"))
        (tblAsnList (map tableToAsn doc.tables))
        (tblAsn (if (listEmpty? tblAsnList) "[]" (str "[\n" (stringJoin tblAsnList "\n") "\n  ]")))
        (cbAsnList (map codeBlockToAsn doc.codeBlocks))
        (cbAsn (if (listEmpty? cbAsnList) "[]" (str "[\n" (stringJoin cbAsnList "\n") "\n  ]")))
        (secAsnList (map (fn [(s DistilledSection)] -> Str
                           (let [(idEsc (esc/escapeAsnStr s.id))
                                 (tEsc (esc/escapeAsnStr s.title))
                                 (cEsc (esc/escapeAsnStr s.content))]
                             (str "    (:sec :id \"" idEsc "\" :level " (stringFromInt64 s.level) " :title \"" tEsc "\" :content \"" cEsc "\")")))
                         doc.sections))
        (secAsn (if (listEmpty? secAsnList) "[]" (str "[\n" (stringJoin secAsnList "\n") "\n  ]")))
        (savingsPct (calcSavings doc.rawChars doc.distilledChars))
        (savingsStr (str (stringFromFloat64 savingsPct) "%"))]
    (str "(:distilledDoc\n  :title \"" titleEsc "\"\n  :needsRendering " needsRender "\n  :sources " srcAsn "\n  :tables " tblAsn "\n  :codeBlocks " cbAsn "\n  :sections " secAsn "\n  :rawChars " (stringFromInt64 doc.rawChars) "\n  :distilledChars " (stringFromInt64 doc.distilledChars) "\n  :savings \"" savingsStr "\")"))
