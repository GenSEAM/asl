(module asl-text/text
  :d "Pure AgentScript text engine: HTML parsing, entity decoding, multi-format text extraction, chunking, and ASN structuring."
  :x [ExtractedDoc ContextChunk ContextualClause decode-html-entities strip-enclosed clean-html extract-html extract-markdown extract-plaintext extract-json-kv extract-xml-atom extract-context chunk-text chunk-doc format-chunk-markdown format-context-rag format-docs-rag format-clause-breadcrumb format-contextual-clause extract-clauses extract-contextual-clauses doc-to-asn chunk-to-asn clause-to-asn strip-quotes strip-colon estimate-tokens])

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

(dfs ContextualClause
  (:f id Str "Deterministic clause identifier")
  (:f doc-title Str "Origin document title")
  (:f section-path (List Str) "Breadcrumb hierarchy e.g. ['Doc', 'Section 1', 'Clause a']")
  (:f clause-text Str "Normalized clause body text")
  (:f char-count I64 "Clause character count")
  (:f source Str "Origin document URL, filepath, or citation"))

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

(df format-docs-rag-helper [(docs (List ExtractedDoc)) (idx I64)] -> (List Str)
  (if (list-empty? docs)
      (list)
      (let [(d (option-or (list-head docs) (ExtractedDoc :title "" :content "" :format "" :source "" :char-count 0)))
            (rest (option-or (list-tail docs) (list)))]
        (list-cons (format-doc-summary idx d) (format-docs-rag-helper rest (+ idx 1))))))

(df format-docs-rag [(query Str) (docs (List ExtractedDoc))] -> Str
  :d "Formats multiple extracted documents into an indexed prompt context block."
  (let [(header (str "## Extracted Documents for query: '" query "' (" (string-from-int64 (list-length docs)) " docs)\n\n"))
        (summaries (format-docs-rag-helper docs 1))
        (docs-md (string-join summaries "\n"))]
    (str header docs-md)))
 
(df doc-to-asn [(doc ExtractedDoc)] -> Str
  :d "Encodes an ExtractedDoc into a compact, canonical ASN S-expression."
  (str "(:doc :title \"" (.-title doc)
       "\" :format \"" (.-format doc)
       "\" :source \"" (.-source doc)
       "\" :chars " (string-from-int64 (.-char-count doc))
       " :content \"" (string-replace (.-content doc) "\"" "\\\"") "\")"))

(df chunk-to-asn [(chunk ContextChunk)] -> Str
  :d "Encodes a ContextChunk into a compact, canonical ASN S-expression."
  (str "(:chunk :id \"" (.-id chunk)
       "\" :index " (string-from-int64 (.-index chunk))
       " :source \"" (.-source chunk)
       "\" :chars " (string-from-int64 (.-char-count chunk))
       " :payload \"" (string-replace (.-content chunk) "\"" "\\\"") "\")"))

(dfs HeadingInfo
  (:f level I64 "Heading hierarchy depth level")
  (:f text Str "Heading label text"))

(df format-clause-breadcrumb [(clause ContextualClause)] -> Str
  :d "Formats contextual breadcrumb prefix for RAG ingestion."
  (let [(path-str (string-join (.-section-path clause) " > "))
        (header (str "[Doc: " (.-doc-title clause) " | Section: " path-str " | ID: " (.-id clause) "]\n"))]
    (str header (.-clause-text clause))))

(df format-contextual-clause [(clause ContextualClause)] -> Str
  :d "Alias for format-clause-breadcrumb."
  (format-clause-breadcrumb clause))

(df clause-to-asn [(clause ContextualClause)] -> Str
  :d "Encodes a ContextualClause into a compact, canonical ASN S-expression."
  (let [(path-str (string-join (.-section-path clause) " > "))]
    (str "(:clause :id \"" (.-id clause)
         "\" :doc \"" (.-doc-title clause)
         "\" :section \"" path-str
         "\" :chars " (string-from-int64 (.-char-count clause))
         " :payload \"" (string-replace (.-clause-text clause) "\"" "\\\"") "\")")))

(df detect-heading [(line Str)] -> (Option HeadingInfo)
  :d "Detects heading prefix returning level and text."
  (let [(trimmed (string-trim line))]
    (cond
      ((string-starts-with? trimmed "### ")
       (some (HeadingInfo :level 3 :text (string-trim (option-or (string-slice trimmed 4 (string-length trimmed)) "")))))
      ((string-starts-with? trimmed "## ")
       (some (HeadingInfo :level 2 :text (string-trim (option-or (string-slice trimmed 3 (string-length trimmed)) "")))))
      ((string-starts-with? trimmed "# ")
       (some (HeadingInfo :level 1 :text (string-trim (option-or (string-slice trimmed 2 (string-length trimmed)) "")))))
      ((string-starts-with? trimmed "Article ")
       (some (HeadingInfo :level 2 :text trimmed)))
      ((string-starts-with? trimmed "Section ")
       (some (HeadingInfo :level 3 :text trimmed)))
      (:else (none)))))

(df update-breadcrumb-path [(path (List Str)) (level I64) (heading Str)] -> (List Str)
  :d "Updates section breadcrumb path maintaining hierarchy at level."
  (let [(keep-count (max 1 (min (list-length path) level)))
        (truncated (list-take path keep-count))]
    (list-append truncated (list heading))))

(df emit-clause-record [(doc-title Str) (path (List Str)) (text Str) (source Str) (idx I64)] -> ContextualClause
  (ContextualClause
    :id (str source "#clause-" (string-from-int64 idx))
    :doc-title doc-title
    :section-path path
    :clause-text text
    :char-count (string-length text)
    :source source))

(df extract-clauses-loop [(lines (List Str))
                         (path (List Str))
                         (para-acc (List Str))
                         (doc-title Str)
                         (source Str)
                         (min-chars I64)
                         (max-chars I64)
                         (clause-idx I64)] -> (List ContextualClause)
  (if (list-empty? lines)
      (if (list-empty? para-acc)
          (list)
          (let [(text (string-join para-acc " "))]
            (if (> (string-length (string-trim text)) 0)
                (list (emit-clause-record doc-title path (string-trim text) source clause-idx))
                (list))))
      (let [(line (option-or (list-head lines) ""))
            (rest (option-or (list-tail lines) (list)))
            (trimmed (string-trim line))
            (heading-opt (detect-heading trimmed))]
        (mt heading-opt
          ((some h)
           (let [(h-level (.-level h))
                 (h-text (.-text h))
                 (new-path (update-breadcrumb-path path h-level h-text))]
             (if (list-empty? para-acc)
                 (extract-clauses-loop rest new-path (list) doc-title source min-chars max-chars clause-idx)
                 (let [(para-str (string-trim (string-join para-acc " ")))]
                   (if (> (string-length para-str) 0)
                       (list-cons (emit-clause-record doc-title path para-str source clause-idx)
                                  (extract-clauses-loop rest new-path (list) doc-title source min-chars max-chars (+ clause-idx 1)))
                       (extract-clauses-loop rest new-path (list) doc-title source min-chars max-chars clause-idx))))))
          ((none)
           (if (string-empty? trimmed)
               (if (list-empty? para-acc)
                   (extract-clauses-loop rest path (list) doc-title source min-chars max-chars clause-idx)
                   (let [(para-str (string-trim (string-join para-acc " ")))]
                     (if (>= (string-length para-str) min-chars)
                         (list-cons (emit-clause-record doc-title path para-str source clause-idx)
                                    (extract-clauses-loop rest path (list) doc-title source min-chars max-chars (+ clause-idx 1)))
                         (extract-clauses-loop rest path para-acc doc-title source min-chars max-chars clause-idx))))
               (let [(next-para (list-append para-acc (list trimmed)))
                     (curr-text (string-join next-para " "))]
                 (if (>= (string-length curr-text) max-chars)
                     (list-cons (emit-clause-record doc-title path (string-trim curr-text) source clause-idx)
                                (extract-clauses-loop rest path (list) doc-title source min-chars max-chars (+ clause-idx 1)))
                     (extract-clauses-loop rest path next-para doc-title source min-chars max-chars clause-idx)))))))))

(df extract-clauses [(doc ExtractedDoc) (min-chars I64) (max-chars I64)] -> (List ContextualClause)
  :d "Extracts structured contextual clauses with breadcrumbs from an ExtractedDoc."
  (let [(title (if (string-empty? (string-trim (.-title doc))) "Document" (string-trim (.-title doc))))
        (source (if (string-empty? (string-trim (.-source doc))) "doc" (string-trim (.-source doc))))
        (safe-min (max 1 min-chars))
        (safe-max (max safe-min max-chars))
        (init-path (list title))
        (lines (string-split (.-content doc) "\n"))]
    (extract-clauses-loop lines init-path (list) title source safe-min safe-max 1)))

(df extract-contextual-clauses [(doc ExtractedDoc) (min-chars I64) (max-chars I64)] -> (List ContextualClause)
  :d "Alias for extract-clauses with breadcrumb preservation."
  (extract-clauses doc min-chars max-chars))



(df strip-quotes [(val Str)] -> Str
  :d "Strips outer double quotes from string values if present."
  (let [(len (string-length val))]
    (if (and (>= len 2) (and (string-starts-with? val "\"") (string-ends-with? val "\"")))
      (option-or (string-slice val 1 (- len 1)) "")
      val)))

(df strip-colon [(val Str)] -> Str
  :d "Strips leading colon from keyword or symbol string."
  (if (string-starts-with? val ":")
    (option-or (string-slice val 1 (string-length val)) "")
    val))

(df estimate-tokens [(text Str)] -> I64
  :d "Deterministic BPE token estimation based on character length."
  (let [(len (string-length text))]
    (cond
      ((<= len 0) 0)
      ((<= len 4) 1)
      (:else (/ (+ len 3) 4)))))
