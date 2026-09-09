(module asl-text/tests/text-test
  :d "Unit tests for pure AgentScript text extraction, HTML parsing, contextual clauses, and ASN structuring"
  :x [run-tests]
  :i [(text :a txt)])

(df test-decode-entities [] -> Bool
  :d "Verifies HTML entity decoding."
  (let [(encoded "Apple &amp; Banana &lt; Orange &gt; &quot;Pear&quot; &#39;Peach&#39;&nbsp;Berry")
        (decoded (txt/decode-html-entities encoded))]
    (assert (= decoded "Apple & Banana < Orange > \"Pear\" 'Peach' Berry") "Decoded HTML entities must match expected text")
    (assert (not (string-contains? decoded "&amp;")) "Decoded HTML entities must not contain raw &amp;")
    true))

(df test-clean-html [] -> Bool
  :d "Verifies script, style, nav, comment, and tag stripping."
  (let [(raw "<html><head><style>body { color: red; }</style><script>alert(1);</script></head><body><nav><a href=\"/\">Home</a></nav><h1>Header</h1><p>Main body content &amp; facts.</p><!-- comment --><footer>Footer links</footer></body></html>")
        (cleaned (txt/clean-html raw))]
    (assert (not (string-contains? cleaned "alert")) "Cleaned html must not contain script body")
    (assert (not (string-contains? cleaned "color: red")) "Cleaned html must not contain style body")
    (assert (not (string-contains? cleaned "Home")) "Cleaned html must not contain nav body")
    (assert (not (string-contains? cleaned "Footer links")) "Cleaned html must not contain footer body")
    (assert (string-contains? cleaned "Main body content & facts.") "Cleaned html must contain body content")
    true))

(df test-extract-html [] -> Bool
  :d "Verifies HTML document extraction."
  (let [(raw "<title>Test Article</title><p>This is the test content.</p>")
        (doc (txt/extract-html raw "https://example.com/article"))]
    (assert (= (.-title doc) "Test Article") "Doc title must match HTML title")
    (assert (= (.-format doc) "html") "Doc format must be html")
    (assert (string-contains? (.-content doc) "This is the test content.") "Doc content must contain body text")
    true))

(df test-extract-markdown [] -> Bool
  :d "Verifies markdown document extraction."
  (let [(raw "# Title\n\nThis is **bold** text with a [link](https://example.com).")
        (doc (txt/extract-markdown raw "readme.md"))]
    (assert (= (.-format doc) "markdown") "Doc format must be markdown")
    (assert (string-contains? (.-content doc) "bold text") "Doc content must contain text")
    (assert (not (string-contains? (.-content doc) "https://example.com")) "Link target must be stripped")
    true))

(df test-extract-json [] -> Bool
  :d "Verifies JSON payload extraction."
  (let [(raw "{\"title\": \"API Spec\", \"content\": \"Primary API payload text.\"}")
        (doc (txt/extract-json-kv raw "payload.json"))]
    (assert (= (.-title doc) "API Spec") "Doc title must match JSON title")
    (assert (= (.-content doc) "Primary API payload text.") "Doc content must match JSON content")
    true))

(df test-chunking [] -> Bool
  :d "Verifies sliding-window chunk step and indexing."
  (let [(text "The quick brown fox jumps over the lazy dog. AgentScript enables lightweight sandboxed execution.")
        (chunks (txt/chunk-text text 25 5 "doc1"))]
    (assert (> (list-length chunks) 1) "Chunk count must be greater than 1")
    (mt (list-head chunks)
      ((none) (assert false "List head must exist"))
      ((some c)
       (assert (= (.-index c) 1) "First chunk index must be 1")
       (assert (= (.-source c) "doc1") "First chunk source must match doc1")))
    true))

(df test-rag-formatting [] -> Bool
  :d "Verifies markdown RAG prompt context generation."
  (let [(doc (txt/ExtractedDoc :title "Doc A" :content "Fact statement 1." :format "text" :source "https://example.com" :char-count 17))
        (md (txt/format-docs-rag "query test" (list doc)))]
    (assert (string-contains? md "## Extracted Documents for query: 'query test'") "Markdown must contain header")
    (assert (string-contains? md "Fact statement 1.") "Markdown must contain fact text")
    true))

(df test-asn-encoding [] -> Bool
  :d "Verifies encoding of ExtractedDoc and ContextChunk to ASN S-expressions."
  (let [(doc (txt/ExtractedDoc :title "Doc ASN" :content "Payload text" :format "text" :source "doc.txt" :char-count 12))
        (chunk (txt/ContextChunk :id "c1" :content "Chunk 1" :index 1 :char-count 7 :source "doc.txt"))
        (asn-doc (txt/doc-to-asn doc))
        (asn-chunk (txt/chunk-to-asn chunk))]
    (assert (string-contains? asn-doc "(:doc :title \"Doc ASN\"") "Doc ASN must contain title")
    (assert (string-contains? asn-chunk "(:chunk :id \"c1\"") "Chunk ASN must contain id")
    true))

(df test-contextual-clause-breadcrumb [] -> Bool
  :d "Verifies contextual breadcrumb prefix formatting."
  (let [(clause (txt/ContextualClause
                  :id "clause-101"
                  :doc-title "Security Policy"
                  :section-path (list "Security Policy" "Section 4" "Key Management")
                  :clause-text "All private keys must be stored in hardware security modules."
                  :char-count 59
                  :source "sec-policy.md"))
        (formatted (txt/format-clause-breadcrumb clause))]
    (assert (string-contains? formatted "[Doc: Security Policy | Section: Security Policy > Section 4 > Key Management | ID: clause-101]") "Breadcrumb header must match")
    (assert (string-contains? formatted "All private keys must be stored in hardware security modules.") "Clause body text must be present")
    true))

(df test-extract-clauses [] -> Bool
  :d "Verifies structured contextual clause extraction with hierarchical breadcrumbs."
  (let [(raw-text "# Overview\nThis is introductory section text.\n\n## Data Protection\nArticle 1\nPersonal data shall be processed lawfully and fairly.\n\nArticle 2\nData subjects have the right to erasure without undue delay.")
        (doc (txt/ExtractedDoc :title "GDPR Guide" :content raw-text :format "markdown" :source "guide.md" :char-count (string-length raw-text)))
        (clauses (txt/extract-clauses doc 10 500))]
    (assert (> (list-length clauses) 1) "Extracted clauses count must be greater than 1")
    (mt (list-head clauses)
      ((none) (assert false "First clause must exist"))
      ((some c1)
       (assert (= (.-doc-title c1) "GDPR Guide") "Document title must match")
       (assert (> (list-length (.-section-path c1)) 1) "Section path must contain breadcrumbs")
       (assert (string-contains? (txt/format-clause-breadcrumb c1) "GDPR Guide") "Formatted breadcrumb must include doc title")))
    true))

(df run-tests [] -> Bool
  :d "Runs all asl-text unit tests."
  (and (test-decode-entities)
       (and (test-clean-html)
            (and (test-extract-html)
                 (and (test-extract-markdown)
                      (and (test-extract-json)
                           (and (test-chunking)
                                (and (test-rag-formatting)
                                     (and (test-asn-encoding)
                                          (and (test-contextual-clause-breadcrumb)
                                               (test-extract-clauses)))))))))))

