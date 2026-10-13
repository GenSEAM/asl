(module asl-text/tests/textTest :x [runTests] :i [(text :a txt)])

fn testDecodeEntities -> Bool
  (let [(encoded "Apple &amp; Banana &lt; Orange &gt; &quot;Pear&quot; &#39;Peach&#39;&nbsp;Berry") (decoded (txt/decodeHtmlEntities encoded))] (assert (= decoded "Apple & Banana < Orange > \"Pear\" 'Peach' Berry") "Decoded HTML entities must match expected text") (refute (stringContains? decoded "&amp;") "Decoded HTML entities must not contain raw &amp;") true)

fn testCleanHtml -> Bool
  (let [(raw "<html><head><style>body { color: red; }</style><script>alert(1);</script></head><body><nav><a href=\"/\">Home</a></nav><h1>Header</h1><p>Main body content &amp; facts.</p><!-- comment --><footer>Footer links</footer></body></html>") (cleaned (txt/cleanHtml raw))] (refute (stringContains? cleaned "alert") "Cleaned html must not contain script body") (refute (stringContains? cleaned "color: red") "Cleaned html must not contain style body") (refute (stringContains? cleaned "Home") "Cleaned html must not contain nav body") (refute (stringContains? cleaned "Footer links") "Cleaned html must not contain footer body") (assert (stringContains? cleaned "Main body content & facts.") "Cleaned html must contain body content") true)

fn testExtractHtml -> Bool
  (let [(raw "<title>Test Article</title><p>This is the test content.</p>") (doc (txt/extractHtml raw "https://example.com/article"))] (assert (= doc.title "Test Article") "Doc title must match HTML title") (assert (= doc.format "html") "Doc format must be html") (assert (stringContains? doc.content "This is the test content.") "Doc content must contain body text") true)

fn testExtractMarkdown -> Bool
  (let [(raw "# Title\n\nThis is **bold** text with a [link](https://example.com).") (doc (txt/extractMarkdown raw "readme.md"))] (assert (= doc.format "markdown") "Doc format must be markdown") (assert (stringContains? doc.content "bold text") "Doc content must contain text") (refute (stringContains? doc.content "https://example.com") "Link target must be stripped") true)

fn testExtractJson -> Bool
  (let [(raw "{\"title\": \"API Spec\", \"content\": \"Primary API payload text.\"}") (doc (txt/extractJsonKv raw "payload.json"))] (assert (= doc.title "API Spec") "Doc title must match JSON title") (assert (= doc.content "Primary API payload text.") "Doc content must match JSON content") true)

fn testChunking -> Bool
  (let [(text "The quick brown fox jumps over the lazy dog. AgentScript enables lightweight sandboxed execution.") (chunks (txt/chunkText text 25 5 "doc1"))] (assert (> (listLength chunks) 1) "Chunk count must be greater than 1") (mt (listHead chunks) ((none) (assert false "List head must exist")) ((some c) (assert (= c.index 1) "First chunk index must be 1") (assert (= c.source "doc1") "First chunk source must match doc1"))) true)

fn testRagFormatting -> Bool
  (let [(doc (txt/ExtractedDoc :title "Doc A" :content "Fact statement 1." :format "text" :source "https://example.com" :charCount 17)) (md (txt/formatDocsRag "query test" (list doc)))] (assert (stringContains? md "## Extracted Documents for query: 'query test'") "Markdown must contain header") (assert (stringContains? md "Fact statement 1.") "Markdown must contain fact text") true)

fn testAsnEncoding -> Bool
  (let [(doc (txt/ExtractedDoc :title "Doc ASN" :content "Payload text" :format "text" :source "doc.txt" :charCount 12)) (chunk (txt/ContextChunk :id "c1" :content "Chunk 1" :index 1 :charCount 7 :source "doc.txt")) (asnDoc (txt/docToAsn doc)) (asnChunk (txt/chunkToAsn chunk))] (assert (stringContains? asnDoc "(:doc :title \"Doc ASN\"") "Doc ASN must contain title") (assert (stringContains? asnChunk "(:chunk :id \"c1\"") "Chunk ASN must contain id") true)

fn testContextualClauseBreadcrumb -> Bool
  (let [(clause (txt/ContextualClause :id "clause-101" :docTitle "Security Policy" :sectionPath (list "Security Policy" "Section 4" "Key Management") :clauseText "All private keys must be stored in hardware security modules." :charCount 59 :source "sec-policy.md")) (formatted (txt/formatClauseBreadcrumb clause))] (assert (stringContains? formatted "[Doc: Security Policy | Section: Security Policy > Section 4 > Key Management | ID: clause-101]") "Breadcrumb header must match") (assert (stringContains? formatted "All private keys must be stored in hardware security modules.") "Clause body text must be present") true)

fn testExtractClauses -> Bool
  (let [(rawText "# Overview\nThis is introductory section text.\n\n## Data Protection\nArticle 1\nPersonal data shall be processed lawfully and fairly.\n\nArticle 2\nData subjects have the right to erasure without undue delay.") (doc (txt/ExtractedDoc :title "GDPR Guide" :content rawText :format "markdown" :source "guide.md" :charCount (stringLength rawText))) (clauses (txt/extractClauses doc 10 500))] (assert (> (listLength clauses) 1) "Extracted clauses count must be greater than 1") (mt (listHead clauses) ((none) (assert false "First clause must exist")) ((some c1) (assert (= c1.docTitle "GDPR Guide") "Document title must match") (assert (> (listLength c1.sectionPath) 1) "Section path must contain breadcrumbs") (assert (stringContains? (txt/formatClauseBreadcrumb c1) "GDPR Guide") "Formatted breadcrumb must include doc title"))) true)

fn testTextHelpers -> Bool
  (do (assert (= (txt/stripQuotes "\"hello\"") "hello") "strip-quotes must strip outer quotes") (assert (= (txt/stripQuotes "hello") "hello") "strip-quotes must leave unquoted string intact") (assert (= (txt/stripColon ":action") "action") "strip-colon must strip leading colon") (assert (= (txt/stripColon "action") "action") "strip-colon must leave non-colon symbol intact") (assert (= (txt/estimateTokens "") 0) "estimate-tokens on empty must be 0") (assert (= (txt/estimateTokens "test") 1) "estimate-tokens on 4 chars must be 1") (assert (> (txt/estimateTokens "this is a longer sentence") 3) "estimate-tokens must scale with length") (assert (txt/isNumeric "123") "isNumeric must identify integer") (assert (txt/isNumeric "-45.67") "isNumeric must identify negative float") (refute (txt/isNumeric "abc") "isNumeric must reject non-numeric string") (assert (= (txt/stripComment "foo = 42 # comment" "#") "foo = 42 ") "stripComment must strip trailing comment") (assert (> (txt/calcSavings 100 80) 10.0) "calcSavings must compute token savings") (mt (txt/extractBetween "<a>val</a>" "<a>" "</a>") ((none) (assert false "extractBetween must extract value")) ((some v) (assert (= v "val") "extractBetween must match enclosed value"))) true)

fn testDistillationEngine -> Bool
  (let [(sampleHtml "<html><head><title>Performance Benchmark</title></head><body><h1>Engine Speed</h1><p>Check the <a href=\"https://aslang.dev/docs\">Documentation</a> for details. Repeated <a href=\"https://aslang.dev/docs\">Documentation link</a> should be interned.</p><pre class=\"language-asl\"><code>(fn add a: I64 b: I64 -> I64 (+ a b))</code></pre><table border=\"1\"><tr><th>Engine</th><th>Latency</th></tr><tr><td>ASL</td><td>1.2ms</td></tr><tr><td>Node</td><td>14.8ms</td></tr></table></body></html>")
        (distilled (txt/distillHtml sampleHtml "https://aslang.dev/bench"))
        (asn (txt/distilledDocToAsn distilled))]
    (assert (= distilled.title "Performance Benchmark") "Distilled title must match HTML title")
    (assert (= (listLength distilled.sources) 1) "Distinct interned URLs must be 1")
    (assert (= (listLength distilled.codeBlocks) 1) "Must extract 1 code block")
    (mt (listHead distilled.codeBlocks)
      ((none) (assert false "Code block head must exist"))
      ((some cb)
        (assert (= cb.id "cb-1") "Code block id must be cb-1")
        (assert (= cb.lang "asl") "Code block language must be asl")
        (assert (stringContains? cb.code "(fn add") "Code block content must be preserved")))
    (assert (= (listLength distilled.tables) 1) "Must extract 1 table")
    (mt (listHead distilled.tables)
      ((none) (assert false "Table head must exist"))
      ((some tbl)
        (assert (= tbl.id "tbl-1") "Table id must be tbl-1")
        (assert (= (listLength tbl.cols) 2) "Table must have 2 columns")
        (assert (= (listLength tbl.rows) 2) "Table must have 2 rows")))
    (assert (stringContains? asn "(:distilledDoc") "ASN must contain :distilledDoc root")
    (assert (stringContains? asn "[:srcRef 1]") "ASN must contain interned srcRef")
    (assert (stringContains? asn "(:table :id \"tbl-1\" :cols [\"Engine\" \"Latency\"]") "ASN must contain vectorized table with id")
    (assert (stringContains? asn "(:codeBlock :id \"cb-1\" :lang \"asl\"") "ASN must contain code block with id")
    (assert (stringContains? asn "(:sec :id \"sec-1\"") "ASN must contain section with id")
    (refute distilled.needsRendering "Standard content should not flag needsRendering")
    (let [(spaHtml "<html><head><title>App</title></head><body><div id=\"root\"></div><script src=\"bundle.js\"></script></body></html>")]
      (assert (txt/detectSpaEmptyDom spaHtml) "detectSpaEmptyDom must detect empty React root")
      (let [(spaDistilled (txt/distillHtml spaHtml "https://example.com/spa"))]
        (assert spaDistilled.needsRendering "distillHtml must flag needsRendering for SPA empty shell")))
    true)

fn testHeadingHierarchyAndInequalities -> Bool
  (let [(html "<h1>Chapter 1: Overview</h1><p>Limits: memory < 100MB and cores > 4 and threads <= 16 and cache >= 2MB.</p><h2>Section 1.1: Details</h2><p>Additional empirical benchmarks.</p>")
        (cleaned (txt/cleanHtml html))]
    (assert (stringContains? cleaned "# Chapter 1: Overview") "cleanHtml must convert h1 to markdown prefix")
    (assert (stringContains? cleaned "## Section 1.1: Details") "cleanHtml must convert h2 to markdown prefix")
    (assert (stringContains? cleaned "memory < 100MB") "cleanHtml must preserve < inequality")
    (assert (stringContains? cleaned "cores > 4") "cleanHtml must preserve > inequality")
    (assert (stringContains? cleaned "threads <= 16") "cleanHtml must preserve <= inequality")
    (assert (stringContains? cleaned "cache >= 2MB") "cleanHtml must preserve >= inequality")
    (let [(doc (txt/ExtractedDoc :title "Doc" :content cleaned :format "html" :source "https://example.com" :charCount (stringLength cleaned)))
          (clauses (txt/extractClauses doc 10 500))]
      (assert (> (listLength clauses) 0) "Clauses must be extracted")
      (mt (listHead clauses)
        ((none) (assert false "First clause must exist"))
        ((some c1)
          (assert (stringContains? (stringJoin c1.sectionPath " > ") "Chapter 1: Overview") "Clause breadcrumb must include h1 title"))))
    true)

fn testUniversalDyck1Escaping -> Bool
  (let [(maliciousPayload "test\\\" :injected (evil-code) :fake \\\"")
        (doc (txt/ExtractedDoc :title "Malicious\\\"Doc" :content maliciousPayload :format "html" :source "https://evil.com/\"x" :charCount (stringLength maliciousPayload)))
        (asnDoc (txt/docToAsn doc))
        (chunk (txt/ContextChunk :id "chk\\1" :content maliciousPayload :index 1 :charCount (stringLength maliciousPayload) :source "evil.com"))
        (asnChunk (txt/chunkToAsn chunk))]
    (assert (stringContains? asnDoc "\\\\\\\"") "Double backslash followed by quote must be safely escaped")
    (assert (stringContains? asnChunk "\\\\\\\"") "Chunk content must escape backslash before quote")
    (assert (stringEndsWith? asnDoc "\")") "Doc ASN must end with valid closing string and parenthesis")
    (assert (stringEndsWith? asnChunk "\")") "Chunk ASN must end with valid closing string and parenthesis")
    true)

fn testStackSafeUrlInterningAndTrackingStrip -> Bool
  (let [(dirtyUrl "https://example.com/doc?utm_source=twitter&utm_medium=social&utm_campaign=launch&id=42&fbclid=xyz")
        (sanitized (txt/sanitizeUrlTracking dirtyUrl))]
    (assert (stringContains? sanitized "https://example.com/doc?id=42") "sanitizeUrlTracking must preserve legitimate query parameters")
    (refute (stringContains? sanitized "utm_source") "sanitizeUrlTracking must strip utm_source")
    (refute (stringContains? sanitized "fbclid") "sanitizeUrlTracking must strip fbclid")
    (let [(linkHtml "<p><a href=\"https://example.com/1?utm_source=rss\">Link 1</a> and <a href=\"https://example.com/1?utm_source=web\">Link 1 Repeated</a> and <a href=\"https://example.com/2\">Link 2</a></p>")
          (interned (txt/internUrls linkHtml))]
      (assert (= (listLength interned.sources) 2) "Deduplicated interned sources must be 2 after stripping tracking")
      (assert (stringContains? interned.text "[:srcRef 1]") "Interned text must have srcRef 1")
      (assert (stringContains? interned.text "[:srcRef 2]") "Interned text must have srcRef 2"))
    true)

fn generateLinks count: I64 acc: Str -> Str
  (if (<= count 0)
    acc
    (let [(url (str "https://example.com/item/" (stringFromInt64 count)))
          (linkTag (str "<p><a href=\"" url "\">Item " (stringFromInt64 count) "</a></p>\n"))]
      (generateLinks (- count 1) (str acc linkTag))))

fn testManyLinksInterning -> Bool
  (let [(html50 (generateLinks 50 ""))
        (interned (txt/internUrls html50))]
    (assert (= (listLength interned.sources) 50) "Must intern exactly 50 distinct URLs without truncation")
    (assert (stringContains? interned.text "[:srcRef 50]") "Must have srcRef 50")
    true)

fn runTests -> Bool
  (and (testDecodeEntities) (and (testCleanHtml) (and (testExtractHtml) (and (testExtractMarkdown) (and (testExtractJson) (and (testChunking) (and (testRagFormatting) (and (testAsnEncoding) (and (testContextualClauseBreadcrumb) (and (testExtractClauses) (and (testTextHelpers) (and (testDistillationEngine) (and (testHeadingHierarchyAndInequalities) (and (testUniversalDyck1Escaping) (and (testStackSafeUrlInterningAndTrackingStrip) (testManyLinksInterning))))))))))))))))
