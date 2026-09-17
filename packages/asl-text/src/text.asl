(module asl-text/text
  :d "Pure AgentScript text engine: HTML parsing, entity decoding, multi-format text extraction, chunking, and ASN structuring."
  :x [ExtractedDoc ContextChunk ContextualClause decodeHtmlEntities stripEnclosed cleanHtml extractHtml extractMarkdown extractPlaintext extractJsonKv extractXmlAtom extractContext chunkText chunkDoc formatChunkMarkdown formatContextRag formatDocsRag formatClauseBreadcrumb formatContextualClause extractClauses extractContextualClauses docToAsn chunkToAsn clauseToAsn stripQuotes stripColon estimateTokens calcSavings extractBetween isNumeric stripComment])

schema ExtractedDoc { title: Str "Document title or headline" content: Str "Normalized clean text content" format: Str "Source format identifier (html, markdown, text, json, xml)" source: Str "Source URL, filename, or stream identifier" charCount: I64 "Length in characters" }

schema ContextChunk { id: Str "Deterministic chunk identifier" content: Str "Token-dense chunk text payload" index: I64 "1-based chunk sequence index" charCount: I64 "Length of chunk content in characters" source: Str "Origin document identifier or URL" }

schema ContextualClause { id: Str "Deterministic clause identifier" docTitle: Str "Origin document title" sectionPath: (List Str) "Breadcrumb hierarchy e.g. ['Doc', 'Section 1', 'Clause a']" clauseText: Str "Normalized clause body text" charCount: I64 "Clause character count" source: Str "Origin document URL, filepath, or citation" }

fn decodeHtmlEntities text: Str -> Str
  (let [(s1 (string-replace text "&amp;" "&")) (s2 (string-replace s1 "&lt;" "<")) (s3 (string-replace s2 "&gt;" ">")) (s4 (string-replace s3 "&quot;" "\"")) (s5 (string-replace s4 "&#39;" "'")) (s6 (string-replace s5 "&apos;" "'"))] (string-replace s6 "&nbsp;" " "))

fn stripEnclosed src: Str openDelim: Str closeDelim: Str -> Str
  (mt (string-index-of src openDelim) ((none) src) ((some startIdx) (let [(prefix (option-or (string-slice src 0 startIdx) "")) (tailStart (+ startIdx (string-length openDelim))) (tail (option-or (string-slice src tailStart (string-length src)) ""))] (mt (string-index-of tail closeDelim) ((none) prefix) ((some closeIdx) (let [(remStart (+ closeIdx (string-length closeDelim))) (remainder (option-or (string-slice tail remStart (string-length tail)) ""))] (str prefix (stripEnclosed remainder openDelim closeDelim))))))))

fn collapseSpacesLine line: Str -> Str
  (let [(words (filter (fn [(w Str)] -> Bool (not (string-empty? (string-trim w)))) (string-split line " ")))] (string-join words " "))

fn normalizeWhitespace text: Str -> Str
  (let [(lines (string-split text "\n")) (cleanedLines (map collapseSpacesLine lines)) (nonEmpty (filter (fn [(l Str)] -> Bool (not (string-empty? l))) cleanedLines))] (string-join nonEmpty "\n"))

fn cleanHtml htmlSrc: Str -> Str
  (let [(s1 (stripEnclosed htmlSrc "<style" "</style>")) (s2 (stripEnclosed s1 "<script" "</script>")) (s3 (stripEnclosed s2 "<nav" "</nav>")) (s4 (stripEnclosed s3 "<header" "</header>")) (s5 (stripEnclosed s4 "<footer" "</footer>")) (s6 (stripEnclosed s5 "<noscript" "</noscript>")) (s7 (stripEnclosed s6 "<!--" "-->")) (s8 (string-replace (string-replace (string-replace s7 "<br>" "\n") "<p>" "\n") "</div>" "\n")) (s9 (stripEnclosed s8 "<" ">")) (s10 (decodeHtmlEntities s9))] (normalizeWhitespace s10))

fn sliceAfterTag s: Str tag: Str -> (Option Str)
  (mt (string-index-of s tag) ((none) (none)) ((some idx) (let [(len (string-length s))] (string-slice s idx len))))

fn sliceTagBody s: Str -> (Option Str)
  (mt (string-index-of s ">") ((none) (none)) ((some openEnd) (let [(contentStart (+ openEnd 1)) (len (string-length s))] (string-slice s contentStart len))))

fn sliceBeforeClose body: Str endTag: Str -> Str
  (mt (string-index-of body endTag) ((none) (string-trim (decodeHtmlEntities body))) ((some closeIdx) (mt (string-slice body 0 closeIdx) ((none) "") ((some rawT) (string-trim (decodeHtmlEntities rawT))))))

fn extractTitleFromHtml html: Str -> Str
  (mt (sliceAfterTag html "<title") ((some afterOpen) (mt (sliceTagBody afterOpen) ((some body) (sliceBeforeClose body "</title")) ((none) ""))) ((none) (mt (sliceAfterTag html "<TITLE") ((some afterOpen) (mt (sliceTagBody afterOpen) ((some body) (sliceBeforeClose body "</TITLE")) ((none) ""))) ((none) ""))))

fn extractHtml rawHtml: Str source: Str -> ExtractedDoc
  (let [(t1 (extractTitleFromHtml rawHtml)) (t2 (if (string-empty? t1) (extractTitleFromHtml (string-replace (string-replace rawHtml "<h1>" "<title>") "</h1>" "</title>")) t1)) (finalTitle (if (string-empty? t2) source t2)) (cleanedBody (cleanHtml rawHtml))] (ExtractedDoc :title finalTitle :content cleanedBody :format "html" :source source :charCount (string-length cleanedBody)))

fn cleanMarkdown mdSrc: Str -> Str
  (let [(s1 (stripEnclosed mdSrc "```" "```")) (s2 (string-replace (string-replace s1 "**" "") "*" "")) (s3 (string-replace (string-replace s2 "[" "") "]" "")) (s4 (stripEnclosed s3 "(" ")"))] (normalizeWhitespace s4))

fn extractMarkdown rawMd: Str source: Str -> ExtractedDoc
  (let [(cleaned (cleanMarkdown rawMd))] (ExtractedDoc :title source :content cleaned :format "markdown" :source source :charCount (string-length cleaned)))

fn extractPlaintext rawTxt: Str source: Str -> ExtractedDoc
  (let [(cleaned (normalizeWhitespace rawTxt))] (ExtractedDoc :title source :content cleaned :format "text" :source source :charCount (string-length cleaned)))

fn extractJsonField rawJson: Str fieldKey: Str -> Str
  (let [(needle (str "\"" fieldKey "\": \""))] (mt (string-index-of rawJson needle) ((none) "") ((some idx) (let [(tailStart (+ idx (string-length needle))) (tail (option-or (string-slice rawJson tailStart (string-length rawJson)) ""))] (mt (string-index-of tail "\"") ((none) tail) ((some endIdx) (option-or (string-slice tail 0 endIdx) "")))))))

fn extractJsonKv rawJson: Str source: Str -> ExtractedDoc
  (let [(c1 (extractJsonField rawJson "content")) (c2 (if (string-empty? c1) (extractJsonField rawJson "text") c1)) (c3 (if (string-empty? c2) (extractJsonField rawJson "snippet") c2)) (c4 (if (string-empty? c3) (extractJsonField rawJson "body") c3)) (finalContent (if (string-empty? c4) (normalizeWhitespace rawJson) c4)) (t (extractJsonField rawJson "title")) (finalTitle (if (string-empty? t) source t))] (ExtractedDoc :title finalTitle :content finalContent :format "json" :source source :charCount (string-length finalContent)))

fn extractTitleFromTag src: Str openTag: Str closeTag: Str -> Str
  (mt (sliceAfterTag src openTag) ((none) "") ((some afterOpen) (mt (string-index-of afterOpen closeTag) ((none) "") ((some closeIdx) (let [(rawT (option-or (string-slice afterOpen 0 closeIdx) ""))] (decodeHtmlEntities (string-trim rawT)))))))

fn extractXmlAtom rawXml: Str source: Str -> ExtractedDoc
  (let [(t (extractTitleFromTag rawXml "<title>" "</title>")) (s1 (extractTitleFromTag rawXml "<summary>" "</summary>")) (s2 (if (string-empty? s1) (extractTitleFromTag rawXml "<content>" "</content>") s1)) (finalContent (if (string-empty? s2) (cleanHtml rawXml) (cleanHtml s2))) (finalTitle (if (string-empty? t) source t))] (ExtractedDoc :title finalTitle :content finalContent :format "xml" :source source :charCount (string-length finalContent)))

fn extractContext rawContent: Str format: Str source: Str -> ExtractedDoc
  (cond ((= format "html") (extractHtml rawContent source)) ((= format "markdown") (extractMarkdown rawContent source)) ((= format "md") (extractMarkdown rawContent source)) ((= format "json") (extractJsonKv rawContent source)) ((= format "xml") (extractXmlAtom rawContent source)) ((= format "atom") (extractXmlAtom rawContent source)) (:else (extractPlaintext rawContent source)))

fn makeChunkId source: Str index: I64 -> Str
  (str source "#chunk-" (string-from-int64 index))

fn chunkTextHelper text: Str maxChars: I64 step: I64 offset: I64 index: I64 source: Str -> (List ContextChunk)
  (let [(total (string-length text))] (if (>= offset total) (list) (let [(endIdx (min total (+ offset maxChars))) (sliceText (option-or (string-slice text offset endIdx) "")) (chunk (ContextChunk :id (makeChunkId source index) :content sliceText :index index :charCount (string-length sliceText) :source source)) (nextOffset (+ offset step))] (if (>= endIdx total) (list chunk) (list-cons chunk (chunkTextHelper text maxChars step nextOffset (+ index 1) source))))))

fn chunkText text: Str maxChars: I64 overlapChars: I64 source: Str -> (List ContextChunk)
  (let [(safeMax (max 10 maxChars)) (step (max 1 (- safeMax overlapChars)))] (chunkTextHelper text safeMax step 0 1 source))

fn chunkDoc doc: ExtractedDoc maxChars: I64 overlapChars: I64 -> (List ContextChunk)
  (chunkText (.-content doc) maxChars overlapChars (.-source doc))

fn formatChunkMarkdown chunk: ContextChunk -> Str
  (str "[" (string-from-int64 (.-index chunk)) "] (" (.-source chunk) "):\n" (.-content chunk) "\n")

fn formatContextRag query: Str chunks: (List ContextChunk) -> Str
  (let [(header (str "## Context for query: '" query "' (" (string-from-int64 (list-length chunks)) " chunks)\n\n")) (chunksMd (string-join (map formatChunkMarkdown chunks) "\n"))] (str header chunksMd))

fn formatDocSummary index: I64 doc: ExtractedDoc -> Str
  (str (string-from-int64 index) ". **[" (.-title doc) "](" (.-source doc) ")** [" (.-format doc) " · " (string-from-int64 (.-charCount doc)) " chars]\n" (.-content doc) "\n")

fn formatDocsRagHelper docs: (List ExtractedDoc) idx: I64 -> (List Str)
  (if (list-empty? docs) (list) (let [(d (option-or (list-head docs) (ExtractedDoc :title "" :content "" :format "" :source "" :charCount 0))) (rest (option-or (list-tail docs) (list)))] (list-cons (formatDocSummary idx d) (formatDocsRagHelper rest (+ idx 1)))))

fn formatDocsRag query: Str docs: (List ExtractedDoc) -> Str
  (let [(header (str "## Extracted Documents for query: '" query "' (" (string-from-int64 (list-length docs)) " docs)\n\n")) (summaries (formatDocsRagHelper docs 1)) (docsMd (string-join summaries "\n"))] (str header docsMd))

fn docToAsn doc: ExtractedDoc -> Str
  (str "(:doc :title \"" (.-title doc) "\" :format \"" (.-format doc) "\" :source \"" (.-source doc) "\" :chars " (string-from-int64 (.-charCount doc)) " :content \"" (string-replace (.-content doc) "\"" "\\\"") "\")")

fn chunkToAsn chunk: ContextChunk -> Str
  (str "(:chunk :id \"" (.-id chunk) "\" :index " (string-from-int64 (.-index chunk)) " :source \"" (.-source chunk) "\" :chars " (string-from-int64 (.-charCount chunk)) " :payload \"" (string-replace (.-content chunk) "\"" "\\\"") "\")")

schema HeadingInfo { level: I64 "Heading hierarchy depth level" text: Str "Heading label text" }

fn formatClauseBreadcrumb clause: ContextualClause -> Str
  (let [(pathStr (string-join (.-sectionPath clause) " > ")) (header (str "[Doc: " (.-docTitle clause) " | Section: " pathStr " | ID: " (.-id clause) "]\n"))] (str header (.-clauseText clause)))

fn formatContextualClause clause: ContextualClause -> Str
  (formatClauseBreadcrumb clause)

fn clauseToAsn clause: ContextualClause -> Str
  (let [(pathStr (string-join (.-sectionPath clause) " > "))] (str "(:clause :id \"" (.-id clause) "\" :doc \"" (.-docTitle clause) "\" :section \"" pathStr "\" :chars " (string-from-int64 (.-charCount clause)) " :payload \"" (string-replace (.-clauseText clause) "\"" "\\\"") "\")"))

fn detectHeading line: Str -> (Option HeadingInfo)
  (let [(trimmed (string-trim line))] (cond ((string-starts-with? trimmed "### ") (some (HeadingInfo :level 3 :text (string-trim (option-or (string-slice trimmed 4 (string-length trimmed)) ""))))) ((string-starts-with? trimmed "## ") (some (HeadingInfo :level 2 :text (string-trim (option-or (string-slice trimmed 3 (string-length trimmed)) ""))))) ((string-starts-with? trimmed "# ") (some (HeadingInfo :level 1 :text (string-trim (option-or (string-slice trimmed 2 (string-length trimmed)) ""))))) ((string-starts-with? trimmed "Article ") (some (HeadingInfo :level 2 :text trimmed))) ((string-starts-with? trimmed "Section ") (some (HeadingInfo :level 3 :text trimmed))) (:else (none))))

fn updateBreadcrumbPath path: (List Str) level: I64 heading: Str -> (List Str)
  (let [(keepCount (max 1 (min (list-length path) level))) (truncated (list-take path keepCount))] (list-append truncated (list heading)))

fn emitClauseRecord docTitle: Str path: (List Str) text: Str source: Str idx: I64 -> ContextualClause
  (ContextualClause :id (str source "#clause-" (string-from-int64 idx)) :docTitle docTitle :sectionPath path :clauseText text :charCount (string-length text) :source source)

fn extractClausesLoop lines: (List Str) path: (List Str) paraAcc: (List Str) docTitle: Str source: Str minChars: I64 maxChars: I64 clauseIdx: I64 -> (List ContextualClause)
  (if (list-empty? lines) (if (list-empty? paraAcc) (list) (let [(text (string-join paraAcc " "))] (if (> (string-length (string-trim text)) 0) (list (emitClauseRecord docTitle path (string-trim text) source clauseIdx)) (list)))) (let [(line (option-or (list-head lines) "")) (rest (option-or (list-tail lines) (list))) (trimmed (string-trim line)) (headingOpt (detectHeading trimmed))] (mt headingOpt ((some h) (let [(hLevel (.-level h)) (hText (.-text h)) (newPath (updateBreadcrumbPath path hLevel hText))] (if (list-empty? paraAcc) (extractClausesLoop rest newPath (list) docTitle source minChars maxChars clauseIdx) (let [(paraStr (string-trim (string-join paraAcc " ")))] (if (> (string-length paraStr) 0) (list-cons (emitClauseRecord docTitle path paraStr source clauseIdx) (extractClausesLoop rest newPath (list) docTitle source minChars maxChars (+ clauseIdx 1))) (extractClausesLoop rest newPath (list) docTitle source minChars maxChars clauseIdx)))))) ((none) (if (string-empty? trimmed) (if (list-empty? paraAcc) (extractClausesLoop rest path (list) docTitle source minChars maxChars clauseIdx) (let [(paraStr (string-trim (string-join paraAcc " ")))] (if (>= (string-length paraStr) minChars) (list-cons (emitClauseRecord docTitle path paraStr source clauseIdx) (extractClausesLoop rest path (list) docTitle source minChars maxChars (+ clauseIdx 1))) (extractClausesLoop rest path paraAcc docTitle source minChars maxChars clauseIdx)))) (let [(nextPara (list-append paraAcc (list trimmed))) (currText (string-join nextPara " "))] (if (>= (string-length currText) maxChars) (list-cons (emitClauseRecord docTitle path (string-trim currText) source clauseIdx) (extractClausesLoop rest path (list) docTitle source minChars maxChars (+ clauseIdx 1))) (extractClausesLoop rest path nextPara docTitle source minChars maxChars clauseIdx))))))))

fn extractClauses doc: ExtractedDoc minChars: I64 maxChars: I64 -> (List ContextualClause)
  (let [(title (if (string-empty? (string-trim (.-title doc))) "Document" (string-trim (.-title doc)))) (source (if (string-empty? (string-trim (.-source doc))) "doc" (string-trim (.-source doc)))) (safeMin (max 1 minChars)) (safeMax (max safeMin maxChars)) (initPath (list title)) (lines (string-split (.-content doc) "\n"))] (extractClausesLoop lines initPath (list) title source safeMin safeMax 1))

fn extractContextualClauses doc: ExtractedDoc minChars: I64 maxChars: I64 -> (List ContextualClause)
  (extractClauses doc minChars maxChars)

fn stripQuotes val: Str -> Str
  (let [(len (string-length val))] (if (and (>= len 2) (or (and (string-starts-with? val "\"") (string-ends-with? val "\"")) (and (string-starts-with? val "'") (string-ends-with? val "'")))) (option-or (string-slice val 1 (- len 1)) "") val))

fn stripColon val: Str -> Str
  (if (string-starts-with? val ":") (option-or (string-slice val 1 (string-length val)) "") val)

fn estimateTokens text: Str -> I64
  (let [(len (string-length text))] (cond ((<= len 0) 0) ((<= len 4) 1) (:else (let [(num (+ len 3)) (rem (mod num 4))] (/ (- num rem) 4)))))

fn calcSavings orig: I64 asn: I64 -> F64
  (if (<= orig 0) 0.0 (let [(diff (- orig asn))] (if (<= diff 0) 0.0 (/ (* (int64-to-float64 diff) 100.0) (int64-to-float64 orig)))))

fn extractBetween text: Str prefix: Str suffix: Str -> (Option Str)
  (mt (string-index-of text prefix) ((none) (none)) ((some startIdx) (let [(startPos (+ startIdx (string-length prefix))) (remaining (option-or (string-slice text startPos (string-length text)) ""))] (mt (string-index-of remaining suffix) ((none) (none)) ((some endIdx) (string-slice remaining 0 endIdx))))))

fn isNumeric s: Str -> Bool
  (let [(chars (string-chars s))] (if (list-empty? chars) false (numericLoop chars true false)))

fn numericLoop chars: (List Str) isFirst: Bool hasDot: Bool -> Bool
  (mt (list-head chars) ((none) true) ((some c) (if (string-contains? "0123456789" c) (numericLoop (option-or (list-tail chars) (list)) false hasDot) (if (and isFirst (= c "-")) (numericLoop (option-or (list-tail chars) (list)) false hasDot) (if (and (not hasDot) (= c ".")) (numericLoop (option-or (list-tail chars) (list)) false true) false)))))

fn stripComment line: Str commentChar: Str -> Str
  (let [(chars (string-chars line))] (stripCommentLoop chars commentChar false ""))

fn stripCommentLoop chars: (List Str) commentChar: Str inQuote: Bool acc: Str -> Str
  (mt (list-head chars) ((none) acc) ((some c) (if inQuote (if (or (= c "\"") (= c "'")) (stripCommentLoop (option-or (list-tail chars) (list)) commentChar false (str acc c)) (stripCommentLoop (option-or (list-tail chars) (list)) commentChar true (str acc c))) (if (or (= c "\"") (= c "'")) (stripCommentLoop (option-or (list-tail chars) (list)) commentChar true (str acc c)) (if (= c commentChar) acc (stripCommentLoop (option-or (list-tail chars) (list)) commentChar false (str acc c)))))))
