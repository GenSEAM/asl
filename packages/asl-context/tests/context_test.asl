(module asl-context/test
  :d "Unit tests for pure AgentScript context engine"
  :x [run-tests]
  :i [(context :a ctx)])

(df test-decode-entities [] -> Bool
  :d "Verifies HTML entity decoding."
  (let [(encoded "Apple &amp; Banana &lt; Orange &gt; &quot;Pear&quot; &#39;Peach&#39;&nbsp;Berry")
        (decoded (ctx/decode-html-entities encoded))]
    (= decoded "Apple & Banana < Orange > \"Pear\" 'Peach' Berry")))

(df test-clean-html [] -> Bool
  :d "Verifies script, style, nav, comment, and tag stripping."
  (let [(raw "<html><head><style>body { color: red; }</style><script>alert(1);</script></head><body><nav><a href=\"/\">Home</a></nav><h1>Header</h1><p>Main body content &amp; facts.</p><!-- comment --><footer>Footer links</footer></body></html>")
        (cleaned (ctx/clean-html raw))]
    (and (not (string-contains? cleaned "alert"))
         (and (not (string-contains? cleaned "color: red"))
              (and (not (string-contains? cleaned "Home"))
                   (and (not (string-contains? cleaned "Footer links"))
                        (string-contains? cleaned "Main body content & facts.")))))))

(df test-extract-html [] -> Bool
  :d "Verifies HTML document extraction."
  (let [(raw "<title>Test Article</title><p>This is the test content.</p>")
        (doc (ctx/extract-html raw "https://example.com/article"))]
    (and (= (.-title doc) "Test Article")
         (and (= (.-format doc) "html")
              (string-contains? (.-content doc) "This is the test content.")))))

(df test-extract-markdown [] -> Bool
  :d "Verifies markdown document extraction."
  (let [(raw "# Title\n\nThis is **bold** text with a [link](https://example.com).")
        (doc (ctx/extract-markdown raw "readme.md"))]
    (and (= (.-format doc) "markdown")
         (and (string-contains? (.-content doc) "bold text")
              (not (string-contains? (.-content doc) "https://example.com"))))))

(df test-extract-json [] -> Bool
  :d "Verifies JSON payload extraction."
  (let [(raw "{\"title\": \"API Spec\", \"content\": \"Primary API payload text.\"}")
        (doc (ctx/extract-json-kv raw "payload.json"))]
    (and (= (.-title doc) "API Spec")
         (= (.-content doc) "Primary API payload text."))))

(df test-chunking [] -> Bool
  :d "Verifies sliding-window chunk step and indexing."
  (let [(text "The quick brown fox jumps over the lazy dog. AgentScript enables lightweight sandboxed execution.")
        (chunks (ctx/chunk-text text 25 5 "doc1"))]
    (and (> (list-length chunks) 1)
         (mt (list-head chunks)
           ((none) false)
           ((some c)
            (and (= (.-index c) 1)
                 (= (.-source c) "doc1")))))))

(df test-rag-formatting [] -> Bool
  :d "Verifies markdown RAG prompt context generation."
  (let [(doc (ctx/ExtractedDoc :title "Doc A" :content "Fact statement 1." :format "text" :source "https://example.com" :char-count 17))
        (md (ctx/format-docs-rag "query test" (list doc)))]
    (and (string-contains? md "## Extracted Documents for query: 'query test'")
         (string-contains? md "Fact statement 1."))))

(df run-tests [] -> Bool
  :d "Runs all asl-context unit tests."
  (if (not (test-decode-entities)) false
    (if (not (test-clean-html)) false
      (if (not (test-extract-html)) false
        (if (not (test-extract-markdown)) false
          (if (not (test-extract-json)) false
            (if (not (test-chunking)) false
              (test-rag-formatting))))))))
