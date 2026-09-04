(module asl-context/context
  :d "Pure AgentScript context engine: HTML/DOM boilerplate stripping, multi-format text extraction, chunking, and RAG context compression."
  :x [ExtractedDoc ContextChunk decode-html-entities strip-enclosed clean-html extract-html extract-markdown extract-plaintext extract-json-kv extract-xml-atom extract-context chunk-text chunk-doc format-chunk-markdown format-context-rag format-docs-rag])

(dfs ExtractedDoc
  (:f title Str "Document title or headline")
  (:f content Str "Normalized clean text content")
  (:f format Str "Source format identifier (html, markdown, text, json, xml)")
  (:f source Str "Source URL, filename, or stream identifier")
  (:f char-count I64 "Length in characters"))

(dfs ContextChunk
  (:f id Str "Deterministic chunk identifier")
  (:f content Str "Token-dense chunk text payload")
  (:f index I64 "1-based chunk sequence index")
  (:f char-count I64 "Length of chunk content in characters")
  (:f source Str "Origin document identifier or URL"))

(df decode-html-entities [(text Str)] -> Str
  :d "Decodes common HTML entities to plain text."
  (let [(s1 (string-replace text "&amp;" "&"))
        (s2 (string-replace s1 "&lt;" "<"))
        (s3 (string-replace s2 "&gt;" ">"))
        (s4 (string-replace s3 "&quot;" "\""))
        (s5 (string-replace s4 "&#39;" "'"))
        (s6 (string-replace s5 "&apos;" "'"))]
    (string-replace s6 "&nbsp;" " ")))

(df strip-enclosed [(src Str) (open-delim Str) (close-delim Str)] -> Str
  :d "Recursively removes all content enclosed between open-delim and close-delim."
  (mt (string-index-of src open-delim)
    ((none) src)
    ((some start-idx)
     (let [(prefix (option-or (string-slice src 0 start-idx) ""))
           (tail-start (+ start-idx (string-length open-delim)))
           (tail (option-or (string-slice src tail-start (string-length src)) ""))]
       (mt (string-index-of tail close-delim)
         ((none) prefix)
         ((some close-idx)
          (let [(rem-start (+ close-idx (string-length close-delim)))
                (remainder (option-or (string-slice tail rem-start (string-length tail)) ""))]
            (str prefix (strip-enclosed remainder open-delim close-delim)))))))))

(df collapse-spaces-line [(line Str)] -> Str
  :d "Collapses multiple spaces within a single line."
  (let [(words (filter (fn [(w Str)] -> Bool (not (string-empty? (string-trim w))))
                       (string-split line " ")))]
    (string-join words " ")))

(df normalize-whitespace [(text Str)] -> Str
  :d "Normalizes whitespace and blank lines across text."
  (let [(lines (string-split text "\n"))
        (cleaned-lines (map collapse-spaces-line lines))
        (non-empty (filter (fn [(l Str)] -> Bool (not (string-empty? l))) cleaned-lines))]
    (string-join non-empty "\n")))

(df clean-html [(html-src Str)] -> Str
  :d "Strips non-content tags, comments, HTML tags, unescapes entities, and normalizes text."
  (let [(s1 (strip-enclosed html-src "<style" "</style>"))
        (s2 (strip-enclosed s1 "<script" "</script>"))
        (s3 (strip-enclosed s2 "<nav" "</nav>"))
        (s4 (strip-enclosed s3 "<header" "</header>"))
        (s5 (strip-enclosed s4 "<footer" "</footer>"))
        (s6 (strip-enclosed s5 "<noscript" "</noscript>"))
        (s7 (strip-enclosed s6 "<!--" "-->"))
        (s8 (string-replace (string-replace (string-replace s7 "<br>" "\n") "<p>" "\n") "</div>" "\n"))
        (s9 (strip-enclosed s8 "<" ">"))
        (s10 (decode-html-entities s9))]
    (normalize-whitespace s10)))

(df slice-after-tag [(s Str) (tag Str)] -> (Option Str)
  (mt (string-index-of s tag)
    ((none) (none))
    ((some idx)
     (let [(len (string-length s))]
       (string-slice s idx len)))))

(df slice-tag-body [(s Str)] -> (Option Str)
  (mt (string-index-of s ">")
    ((none) (none))
    ((some open-end)
     (let [(content-start (+ open-end 1))
           (len (string-length s))]
       (string-slice s content-start len)))))

(df slice-before-close [(body Str) (end-tag Str)] -> Str
  (mt (string-index-of body end-tag)
    ((none) (string-trim (decode-html-entities body)))
    ((some close-idx)
     (mt (string-slice body 0 close-idx)
       ((none) "")
       ((some raw-t) (string-trim (decode-html-entities raw-t)))))))

(df extract-title-from-html [(html Str)] -> Str
  :d "Extracts content enclosed inside title tags, or empty string if absent."
  (mt (slice-after-tag html "<title")
    ((some after-open)
     (mt (slice-tag-body after-open)
       ((some body) (slice-before-close body "</title"))
       ((none) "")))
    ((none)
     (mt (slice-after-tag html "<TITLE")
       ((some after-open)
        (mt (slice-tag-body after-open)
          ((some body) (slice-before-close body "</TITLE"))
          ((none) "")))
       ((none) "")))))

(df extract-html [(raw-html Str) (source Str)] -> ExtractedDoc
  :d "Extracts clean article text and title from HTML."
  (let [(t1 (extract-title-from-html raw-html))
        (t2 (if (string-empty? t1) (extract-title-from-html (string-replace (string-replace raw-html "<h1>" "<title>") "</h1>" "</title>")) t1))
        (final-title (if (string-empty? t2) source t2))
        (cleaned-body (clean-html raw-html))]
    (ExtractedDoc
      :title final-title
      :content cleaned-body
      :format "html"
      :source source
      :char-count (string-length cleaned-body))))

(df clean-markdown [(md-src Str)] -> Str
  :d "Normalizes markdown into clean plain text."
  (let [(s1 (strip-enclosed md-src "```" "```"))
        (s2 (string-replace (string-replace s1 "**" "") "*" ""))
        (s3 (string-replace (string-replace s2 "[" "") "]" ""))
        (s4 (strip-enclosed s3 "(" ")"))]
    (normalize-whitespace s4)))

(df extract-markdown [(raw-md Str) (source Str)] -> ExtractedDoc
  :d "Extracts normalized content from markdown text."
  (let [(cleaned (clean-markdown raw-md))]
    (ExtractedDoc
      :title source
      :content cleaned
      :format "markdown"
      :source source
      :char-count (string-length cleaned))))

(df extract-plaintext [(raw-txt Str) (source Str)] -> ExtractedDoc
  :d "Extracts normalized content from plaintext."
  (let [(cleaned (normalize-whitespace raw-txt))]
    (ExtractedDoc
      :title source
      :content cleaned
      :format "text"
      :source source
      :char-count (string-length cleaned))))

(df extract-json-field [(raw-json Str) (field-key Str)] -> Str
  :d "Extracts string value of a field from simple JSON."
  (let [(needle (str "\"" field-key "\": \""))]
    (mt (string-index-of raw-json needle)
      ((none) "")
      ((some idx)
       (let [(tail-start (+ idx (string-length needle)))
             (tail (option-or (string-slice raw-json tail-start (string-length raw-json)) ""))]
         (mt (string-index-of tail "\"")
           ((none) tail)
           ((some end-idx)
            (option-or (string-slice tail 0 end-idx) ""))))))))

(df extract-json-kv [(raw-json Str) (source Str)] -> ExtractedDoc
  :d "Extracts primary text content from common JSON fields."
  (let [(c1 (extract-json-field raw-json "content"))
        (c2 (if (string-empty? c1) (extract-json-field raw-json "text") c1))
        (c3 (if (string-empty? c2) (extract-json-field raw-json "snippet") c2))
        (c4 (if (string-empty? c3) (extract-json-field raw-json "body") c3))
        (final-content (if (string-empty? c4) (normalize-whitespace raw-json) c4))
        (t (extract-json-field raw-json "title"))
        (final-title (if (string-empty? t) source t))]
    (ExtractedDoc
      :title final-title
      :content final-content
      :format "json"
      :source source
      :char-count (string-length final-content))))

(df extract-title-from-tag [(src Str) (open-tag Str) (close-tag Str)] -> Str
  :d "Extracts inner text of a tag if present, else empty string."
  (mt (slice-after-tag src open-tag)
    ((none) "")
    ((some after-open)
     (mt (string-index-of after-open close-tag)
       ((none) "")
       ((some close-idx)
        (let [(raw-t (option-or (string-slice after-open 0 close-idx) ""))]
          (decode-html-entities (string-trim raw-t))))))))

(df extract-xml-atom [(raw-xml Str) (source Str)] -> ExtractedDoc
  :d "Extracts title and summary from XML or Atom feed."
  (let [(t (extract-title-from-tag raw-xml "<title>" "</title>"))
        (s1 (extract-title-from-tag raw-xml "<summary>" "</summary>"))
        (s2 (if (string-empty? s1) (extract-title-from-tag raw-xml "<content>" "</content>") s1))
        (final-content (if (string-empty? s2) (clean-html raw-xml) (clean-html s2)))
        (final-title (if (string-empty? t) source t))]
    (ExtractedDoc
      :title final-title
      :content final-content
      :format "xml"
      :source source
      :char-count (string-length final-content))))

(df extract-context [(raw-content Str) (format Str) (source Str)] -> ExtractedDoc
  :d "Polymorphic format dispatcher for context extraction."
  (cond
    ((= format "html") (extract-html raw-content source))
    ((= format "markdown") (extract-markdown raw-content source))
    ((= format "md") (extract-markdown raw-content source))
    ((= format "json") (extract-json-kv raw-content source))
    ((= format "xml") (extract-xml-atom raw-content source))
    ((= format "atom") (extract-xml-atom raw-content source))
    (:else (extract-plaintext raw-content source))))

(df make-chunk-id [(source Str) (index I64)] -> Str
  :d "Generates deterministic chunk ID."
  (str source "#chunk-" (string-from-int64 index)))

(df chunk-text-helper [(text Str) (max-chars I64) (step I64) (offset I64) (index I64) (source Str)] -> (List ContextChunk)
  :d "Recursive sliding-window helper."
  (let [(total (string-length text))]
    (if (>= offset total)
        (list)
        (let [(end-idx (min total (+ offset max-chars)))
              (slice-text (option-or (string-slice text offset end-idx) ""))
              (chunk (ContextChunk
                       :id (make-chunk-id source index)
                       :content slice-text
                       :index index
                       :char-count (string-length slice-text)
                       :source source))
              (next-offset (+ offset step))]
          (if (>= end-idx total)
              (list chunk)
              (list-cons chunk (chunk-text-helper text max-chars step next-offset (+ index 1) source)))))))

(df chunk-text [(text Str) (max-chars I64) (overlap-chars I64) (source Str)] -> (List ContextChunk)
  :d "Splits text into sliding-window chunks with safe step bounds."
  (let [(safe-max (max 10 max-chars))
        (step (max 1 (- safe-max overlap-chars)))]
    (chunk-text-helper text safe-max step 0 1 source)))

(df chunk-doc [(doc ExtractedDoc) (max-chars I64) (overlap-chars I64)] -> (List ContextChunk)
  :d "Chunks an ExtractedDoc into indexed ContextChunks."
  (chunk-text (.-content doc) max-chars overlap-chars (.-source doc)))

(df format-chunk-markdown [(chunk ContextChunk)] -> Str
  :d "Formats an individual chunk with citation index and source."
  (str "[" (string-from-int64 (.-index chunk)) "] (" (.-source chunk) "):\n"
       (.-content chunk) "\n"))

(df format-context-rag [(query Str) (chunks (List ContextChunk))] -> Str
  :d "Formats a list of context chunks into an indexed prompt context block."
  (let [(header (str "## Context for query: '" query "' (" (string-from-int64 (list-length chunks)) " chunks)\n\n"))
        (chunks-md (string-join (map format-chunk-markdown chunks) "\n"))]
    (str header chunks-md)))

(df format-doc-summary [(index I64) (doc ExtractedDoc)] -> Str
  :d "Formats single document summary."
  (str (string-from-int64 index) ". **[" (.-title doc) "](" (.-source doc) ")** [" (.-format doc) " · " (string-from-int64 (.-char-count doc)) " chars]\n"
       (.-content doc) "\n"))

(df format-docs-rag [(query Str) (docs (List ExtractedDoc))] -> Str
  :d "Formats multiple extracted documents into an indexed prompt context block."
  (let [(header (str "## Extracted Documents for query: '" query "' (" (string-from-int64 (list-length docs)) " docs)\n\n"))
        (indexed (zip (range 1 (+ (list-length docs) 1)) docs))
        (docs-md (string-join (map (fn [(p (Pair I64 ExtractedDoc))] -> Str
                                     (format-doc-summary (.-first p) (.-second p)))
                                   indexed)
                              "\n"))]
    (str header docs-md)))
