(module asl-text/tests/textTest
  :d "Unit tests for pure AgentScript text extraction, HTML parsing, contextual clauses, and ASN structuring"
  :x [runTests]
  :i [(text :a txt)])

(df testDecodeEntities [] -> Bool
  :d "Verifies HTML entity decoding."
  (let [(encoded "Apple &amp; Banana &lt; Orange &gt; &quot;Pear&quot; &#39;Peach&#39;&nbsp;Berry")
        (decoded (txt/decodeHtmlEntities encoded))]
    (assert (= decoded "Apple & Banana < Orange > \"Pear\" 'Peach' Berry") "Decoded HTML entities must match expected text")
    (refute (string-contains? decoded "&amp;") "Decoded HTML entities must not contain raw &amp;")
    true))

(df testCleanHtml [] -> Bool
  :d "Verifies script, style, nav, comment, and tag stripping."
  (let [(raw "<html><head><style>body { color: red; }</style><script>alert(1);</script></head><body><nav><a href=\"/\">Home</a></nav><h1>Header</h1><p>Main body content &amp; facts.</p><!-- comment --><footer>Footer links</footer></body></html>")
        (cleaned (txt/cleanHtml raw))]
    (refute (string-contains? cleaned "alert") "Cleaned html must not contain script body")
    (refute (string-contains? cleaned "color: red") "Cleaned html must not contain style body")
    (refute (string-contains? cleaned "Home") "Cleaned html must not contain nav body")
    (refute (string-contains? cleaned "Footer links") "Cleaned html must not contain footer body")
    (assert (string-contains? cleaned "Main body content & facts.") "Cleaned html must contain body content")
    true))

(df testExtractHtml [] -> Bool
  :d "Verifies HTML document extraction."
  (let [(raw "<title>Test Article</title><p>This is the test content.</p>")
        (doc (txt/extractHtml raw "https://example.com/article"))]
    (assert (= (.-title doc) "Test Article") "Doc title must match HTML title")
    (assert (= (.-format doc) "html") "Doc format must be html")
    (assert (string-contains? (.-content doc) "This is the test content.") "Doc content must contain body text")
    true))

(df testExtractMarkdown [] -> Bool
  :d "Verifies markdown document extraction."
  (let [(raw "# Title\n\nThis is **bold** text with a [link](https://example.com).")
        (doc (txt/extractMarkdown raw "readme.md"))]
    (assert (= (.-format doc) "markdown") "Doc format must be markdown")
    (assert (string-contains? (.-content doc) "bold text") "Doc content must contain text")
    (refute (string-contains? (.-content doc) "https://example.com") "Link target must be stripped")
    true))

(df testExtractJson [] -> Bool
  :d "Verifies JSON payload extraction."
  (let [(raw "{\"title\": \"API Spec\", \"content\": \"Primary API payload text.\"}")
        (doc (txt/extractJsonKv raw "payload.json"))]
    (assert (= (.-title doc) "API Spec") "Doc title must match JSON title")
    (assert (= (.-content doc) "Primary API payload text.") "Doc content must match JSON content")
    true))

(df testChunking [] -> Bool
  :d "Verifies sliding-window chunk step and indexing."
  (let [(text "The quick brown fox jumps over the lazy dog. AgentScript enables lightweight sandboxed execution.")
        (chunks (txt/chunkText text 25 5 "doc1"))]
    (assert (> (list-length chunks) 1) "Chunk count must be greater than 1")
    (mt (list-head chunks)
      ((none) (assert false "List head must exist"))
      ((some c)
       (assert (= (.-index c) 1) "First chunk index must be 1")
       (assert (= (.-source c) "doc1") "First chunk source must match doc1")))
    true))

(df testRagFormatting [] -> Bool
  :d "Verifies markdown RAG prompt context generation."
  (let [(doc (txt/ExtractedDoc :title "Doc A" :content "Fact statement 1." :format "text" :source "https://example.com" :charCount 17))
        (md (txt/formatDocsRag "query test" (list doc)))]
    (assert (string-contains? md "## Extracted Documents for query: 'query test'") "Markdown must contain header")
    (assert (string-contains? md "Fact statement 1.") "Markdown must contain fact text")
    true))

(df testAsnEncoding [] -> Bool
  :d "Verifies encoding of ExtractedDoc and ContextChunk to ASN S-expressions."
  (let [(doc (txt/ExtractedDoc :title "Doc ASN" :content "Payload text" :format "text" :source "doc.txt" :charCount 12))
        (chunk (txt/ContextChunk :id "c1" :content "Chunk 1" :index 1 :charCount 7 :source "doc.txt"))
        (asnDoc (txt/docToAsn doc))
        (asnChunk (txt/chunkToAsn chunk))]
    (assert (string-contains? asnDoc "(:doc :title \"Doc ASN\"") "Doc ASN must contain title")
    (assert (string-contains? asnChunk "(:chunk :id \"c1\"") "Chunk ASN must contain id")
    true))

(df testContextualClauseBreadcrumb [] -> Bool
  :d "Verifies contextual breadcrumb prefix formatting."
  (let [(clause (txt/ContextualClause
                  :id "clause-101"
                  :docTitle "Security Policy"
                  :sectionPath (list "Security Policy" "Section 4" "Key Management")
                  :clauseText "All private keys must be stored in hardware security modules."
                  :charCount 59
                  :source "sec-policy.md"))
        (formatted (txt/formatClauseBreadcrumb clause))]
    (assert (string-contains? formatted "[Doc: Security Policy | Section: Security Policy > Section 4 > Key Management | ID: clause-101]") "Breadcrumb header must match")
    (assert (string-contains? formatted "All private keys must be stored in hardware security modules.") "Clause body text must be present")
    true))

(df testExtractClauses [] -> Bool
  :d "Verifies structured contextual clause extraction with hierarchical breadcrumbs."
  (let [(rawText "# Overview\nThis is introductory section text.\n\n## Data Protection\nArticle 1\nPersonal data shall be processed lawfully and fairly.\n\nArticle 2\nData subjects have the right to erasure without undue delay.")
        (doc (txt/ExtractedDoc :title "GDPR Guide" :content rawText :format "markdown" :source "guide.md" :charCount (string-length rawText)))
        (clauses (txt/extractClauses doc 10 500))]
    (assert (> (list-length clauses) 1) "Extracted clauses count must be greater than 1")
    (mt (list-head clauses)
      ((none) (assert false "First clause must exist"))
      ((some c1)
       (assert (= (.-docTitle c1) "GDPR Guide") "Document title must match")
       (assert (> (list-length (.-sectionPath c1)) 1) "Section path must contain breadcrumbs")
       (assert (string-contains? (txt/formatClauseBreadcrumb c1) "GDPR Guide") "Formatted breadcrumb must include doc title")))
    true))

(df testTextHelpers [] -> Bool
  :d "Verifies strip-quotes, strip-colon, and estimate-tokens foundational primitives."
  (assert (= (txt/stripQuotes "\"hello\"") "hello") "strip-quotes must strip outer quotes")
  (assert (= (txt/stripQuotes "hello") "hello") "strip-quotes must leave unquoted string intact")
  (assert (= (txt/stripColon ":action") "action") "strip-colon must strip leading colon")
  (assert (= (txt/stripColon "action") "action") "strip-colon must leave non-colon symbol intact")
  (assert (= (txt/estimateTokens "") 0) "estimate-tokens on empty must be 0")
  (assert (= (txt/estimateTokens "test") 1) "estimate-tokens on 4 chars must be 1")
  (assert (> (txt/estimateTokens "this is a longer sentence") 3) "estimate-tokens must scale with length")
  true)

(df runTests [] -> Bool
  :d "Runs all asl-text unit tests."
  (and (testDecodeEntities)
       (and (testCleanHtml)
            (and (testExtractHtml)
                 (and (testExtractMarkdown)
                      (and (testExtractJson)
                           (and (testChunking)
                                (and (testRagFormatting)
                                     (and (testAsnEncoding)
                                          (and (testContextualClauseBreadcrumb)
                                               (and (testExtractClauses) (testTextHelpers))))))))))))

