(module asl-http/http11
  :d "Pure AgentScript Streaming HTTP/1.1 Protocol Engine and Wire Codec"
  :x [HttpHeaders
      HttpRequest
      HttpResponse
      makeHeaders
      getHeader
      getHeaderFromHeaders
      makeRequest
      makeResponse
      parseHttpRequest
      getQueryParam
      formatHttpResponse])

(dfs HttpHeaders
  (:f entries (List (Pair String String))))

(dfs HttpRequest
  (:f method String)
  (:f path String)
  (:f version String)
  (:f headers HttpHeaders)
  (:f body String)
  (:f query String))

(dfs HttpResponse
  (:f statusCode Int64)
  (:f reasonPhrase String)
  (:f headers HttpHeaders)
  (:f body String))

(df makeHeaders [(pairs (List (Pair String String)))] -> HttpHeaders
  :d "Constructs HttpHeaders container from key-value pairs"
  (HttpHeaders :entries pairs))

(df findHeaderInPairs [(pairs (List (Pair String String))) (targetKeyLower String)] -> (Option String)
  :d "Searches header entries case-insensitively"
  (if (list-empty? pairs)
    (none)
    (let [(p (option-or (list-head pairs) (pair "" "")))]
      (if (= (string-lower (fst p)) targetKeyLower)
        (some (snd p))
        (findHeaderInPairs (option-or (list-tail pairs) (list)) targetKeyLower)))))

(df getHeaderFromHeaders [(headers HttpHeaders) (name String)] -> (Option String)
  :d "Looks up header by name case-insensitively from HttpHeaders"
  (findHeaderInPairs (.-entries headers) (string-lower (string-trim name))))

(df getHeader [(target Any) (name String)] -> (Option String)
  :d "Looks up header by name case-insensitively from HttpRequest or HttpHeaders"
  (let [(entries (if (nil? (.-headers target))
                   (.-entries target)
                   (.-entries (.-headers target))))]
    (findHeaderInPairs entries (string-lower (string-trim name)))))

(df makeRequest [(method String) (path String) (headers HttpHeaders) (body String) (version String)] -> HttpRequest
  :d "Constructs HttpRequest with automatic query decomposition"
  (let [(qPos (string-index-of path "?"))]
    (mt qPos
      ((some idx)
       (let [(p (option-or (string-slice path 0 idx) path))
             (q (option-or (string-slice path (+ idx 1) (string-length path)) ""))]
         (HttpRequest :method method :path p :version version :headers headers :body body :query q)))
      ((none)
       (HttpRequest :method method :path path :version version :headers headers :body body :query "")))))

(df makeResponse [(statusCode Int64) (reasonPhrase String) (headers HttpHeaders) (body String)] -> HttpResponse
  :d "Constructs HttpResponse message representation"
  (HttpResponse :statusCode statusCode :reasonPhrase reasonPhrase :headers headers :body body))

(df findQueryParamInPairs [(pairs (List (Pair String String))) (targetKey String)] -> (Option String)
  :d "Finds matching query parameter value by key"
  (if (list-empty? pairs)
    (none)
    (let [(p (option-or (list-head pairs) (pair "" "")))]
      (if (= (fst p) targetKey)
        (some (snd p))
        (findQueryParamInPairs (option-or (list-tail pairs) (list)) targetKey)))))

(df parseQueryPair [(item String)] -> (Pair String String)
  :d "Splits key=value item into Pair"
  (let [(eqPos (string-index-of item "="))]
    (mt eqPos
      ((some idx)
       (let [(k (option-or (string-slice item 0 idx) ""))
             (v (option-or (string-slice item (+ idx 1) (string-length item)) ""))]
         (pair k v)))
      ((none)
       (pair item "")))))

(df parseQueryString [(query String)] -> (List (Pair String String))
  :d "Splits query string by & into key-value pairs"
  (if (string-empty? query)
    (list)
    (let [(items (string-split query "&"))]
      (map (fn [(item String)] -> (Pair String String) (parseQueryPair item)) items))))

(df getQueryParam [(req HttpRequest) (key String)] -> (Option String)
  :d "Retrieves query parameter value from HttpRequest"
  (let [(pairs (parseQueryString (.-query req)))]
    (findQueryParamInPairs pairs key)))

(df hexCharToInt [(c String)] -> (Option Int64)
  :d "Converts single hex character to integer value"
  (cond
    ((= c "0") (some 0))
    ((= c "1") (some 1))
    ((= c "2") (some 2))
    ((= c "3") (some 3))
    ((= c "4") (some 4))
    ((= c "5") (some 5))
    ((= c "6") (some 6))
    ((= c "7") (some 7))
    ((= c "8") (some 8))
    ((= c "9") (some 9))
    ((or (= c "a") (= c "A")) (some 10))
    ((or (= c "b") (= c "B")) (some 11))
    ((or (= c "c") (= c "C")) (some 12))
    ((or (= c "d") (= c "D")) (some 13))
    ((or (= c "e") (= c "E")) (some 14))
    ((or (= c "f") (= c "F")) (some 15))
    (:else (none))))

(df parseHexLoop [(chars (List String)) (acc Int64)] -> (Option Int64)
  :d "Accumulates hex digits into integer"
  (if (list-empty? chars)
    (some acc)
    (let [(ch (option-or (list-head chars) ""))
          (digitOpt (hexCharToInt ch))]
      (mt digitOpt
        ((some d) (parseHexLoop (option-or (list-tail chars) (list)) (+ (* acc 16) d)))
        ((none) (none))))))

(df parseHexInt [(s String)] -> (Option Int64)
  :d "Parses hexadecimal string to Int64"
  (let [(trimmed (string-trim s))]
    (if (string-empty? trimmed)
      (none)
      (parseHexLoop (string-chars trimmed) 0))))

(df parseChunkLoop [(bodyStr String) (pos Int64) (acc String)] -> (Result String String)
  :d "Recursively parses RFC 9112 chunked transfer encoding byte stream"
  (let [(totalLen (string-length bodyStr))]
    (if (>= pos totalLen)
      (ok acc)
      (let [(remaining (option-or (string-slice bodyStr pos totalLen) ""))
            (crlfPos (string-index-of remaining "\r\n"))]
        (mt crlfPos
          ((some idx)
           (let [(sizeLine (string-trim (option-or (string-slice remaining 0 idx) "")))
                 (cleanSize (let [(semiPos (string-index-of sizeLine ";"))]
                              (mt semiPos
                                ((some sIdx) (string-trim (option-or (string-slice sizeLine 0 sIdx) "")))
                                ((none) sizeLine))))
                 (hexOpt (parseHexInt cleanSize))]
             (mt hexOpt
               ((none) (err "ERR_HTTP_INVALID_CHUNK_SIZE"))
               ((some 0) (ok acc))
               ((some chunkSize)
                (let [(dataStart (+ pos (+ idx 2)))
                      (dataEnd (+ dataStart chunkSize))]
                  (if (> dataEnd totalLen)
                    (err "ERR_HTTP_TRUNCATED_CHUNK")
                    (let [(chunkData (option-or (string-slice bodyStr dataStart dataEnd) ""))
                          (nextPos (if (and (<= (+ dataEnd 2) totalLen)
                                            (= (option-or (string-slice bodyStr dataEnd (+ dataEnd 2)) "") "\r\n"))
                                     (+ dataEnd 2)
                                     dataEnd))]
                      (parseChunkLoop bodyStr nextPos (str acc chunkData)))))))))
          ((none)
           (if (string-empty? (string-trim remaining))
             (ok acc)
             (err "ERR_HTTP_INVALID_CHUNK_TERMINATION"))))))))

(df parseChunkedBody [(bodyStr String)] -> (Result String String)
  :d "Decodes chunked transfer encoding payload"
  (parseChunkLoop bodyStr 0 ""))

(df parseHeaderLine [(line String)] -> (Result (Pair String String) String)
  :d "Parses single header line enforcing colon delimiter"
  (let [(colonPos (string-index-of line ":"))]
    (mt colonPos
      ((some idx)
       (let [(k (string-trim (option-or (string-slice line 0 idx) "")))
             (v (string-trim (option-or (string-slice line (+ idx 1) (string-length line)) "")))]
         (if (string-empty? k)
           (err "ERR_HTTP_EMPTY_HEADER_NAME")
           (ok (pair k v)))))
      ((none)
       (err "ERR_HTTP_HEADER_NO_COLON")))))

(df parseHeaderLinesLoop [(lines (List String)) (acc (List (Pair String String)))] -> (Result (List (Pair String String)) String)
  :d "Recursively parses list of header lines"
  (if (list-empty? lines)
    (ok (list-reverse acc))
    (let [(line (string-trim (option-or (list-head lines) "")))]
      (if (string-empty? line)
        (parseHeaderLinesLoop (option-or (list-tail lines) (list)) acc)
        (let [(pRes (parseHeaderLine line))]
          (if (is-err? pRes)
            (err (unwrap-err pRes))
            (parseHeaderLinesLoop (option-or (list-tail lines) (list))
                                  (list-cons (unwrap-ok pRes) acc))))))))

(df splitTokens [(s String)] -> (List String)
  :d "Splits whitespace-delimited tokens"
  (let [(rawTokens (string-split s " "))]
    (filter (fn [(t String)] -> Bool (not (string-empty? (string-trim t)))) rawTokens)))

(df parseHttpRequest [(raw String)] -> (Result HttpRequest String)
  :d "Streaming parser for HTTP/1.1 wire requests"
  (if (string-empty? raw)
    (err "ERR_HTTP_EMPTY_REQUEST")
    (let [(headerEndCrlf (string-index-of raw "\r\n\r\n"))]
      (mt headerEndCrlf
        ((some endIdx)
         (let [(headerSection (option-or (string-slice raw 0 endIdx) ""))
               (bodySection (option-or (string-slice raw (+ endIdx 4) (string-length raw)) ""))
               (normalizedHeaders (string-replace headerSection "\r\n" "\n"))
               (lines (string-split normalizedHeaders "\n"))]
           (if (list-empty? lines)
             (err "ERR_HTTP_EMPTY_REQUEST_LINE")
             (let [(reqLine (string-trim (option-or (list-head lines) "")))
                   (tokens (splitTokens reqLine))
                   (tokenCount (list-length tokens))]
               (cond
                 ((< tokenCount 2) (err "ERR_HTTP_MALFORMED_REQUEST_LINE"))
                 ((= tokenCount 2)
                  (let [(t1 (option-or (list-head (option-or (list-tail tokens) (list))) ""))]
                    (if (string-starts-with? t1 "HTTP/")
                      (err "ERR_HTTP_MISSING_TARGET")
                      (err "ERR_HTTP_MISSING_VERSION"))))
                 ((> tokenCount 3) (err "ERR_HTTP_MALFORMED_REQUEST_LINE"))
                 (:else
                  (let [(method (option-or (list-head tokens) ""))
                        (tokensTail (option-or (list-tail tokens) (list)))
                        (rawTarget (option-or (list-head tokensTail) ""))
                        (version (option-or (list-head (option-or (list-tail tokensTail) (list))) ""))]
                    (if (not (string-starts-with? version "HTTP/"))
                      (err "ERR_HTTP_INVALID_VERSION")
                      (let [(headerLines (option-or (list-tail lines) (list)))
                            (headersRes (parseHeaderLinesLoop headerLines (list)))]
                        (if (is-err? headersRes)
                          (err (unwrap-err headersRes))
                          (let [(parsedHeaders (makeHeaders (unwrap-ok headersRes)))
                                (contentLenOpt (getHeaderFromHeaders parsedHeaders "Content-Length"))
                                (transferEncodingOpt (getHeaderFromHeaders parsedHeaders "Transfer-Encoding"))]
                            (let [(validLenRes (mt contentLenOpt
                                                 ((none) (ok true))
                                                 ((some lenStr)
                                                  (let [(parsedInt (string-to-int64 (string-trim lenStr)))]
                                                    (mt parsedInt
                                                      ((none) (err "ERR_HTTP_INVALID_CONTENT_LENGTH"))
                                                      ((some n) (if (< n 0) (err "ERR_HTTP_INVALID_CONTENT_LENGTH") (ok true))))))))]
                              (if (is-err? validLenRes)
                                (err (unwrap-err validLenRes))
                                (if (= (string-lower (option-or transferEncodingOpt "")) "chunked")
                                  (let [(chunkRes (parseChunkedBody bodySection))]
                                    (if (is-err? chunkRes)
                                      (err (unwrap-err chunkRes))
                                      (ok (makeRequest method rawTarget parsedHeaders (unwrap-ok chunkRes) version))))
                                  (ok (makeRequest method rawTarget parsedHeaders bodySection version))))))))))))))))
        ((none)
         (err "ERR_HTTP_MISSING_HEADER_TERMINATOR"))))))

(df formatHeaderEntries [(entries (List (Pair String String)))] -> String
  :d "Formats header pairs into wire lines"
  (if (list-empty? entries)
    ""
    (let [(p (option-or (list-head entries) (pair "" "")))
          (line (str (fst p) ": " (snd p) "\r\n"))
          (rest (formatHeaderEntries (option-or (list-tail entries) (list))))]
      (str line rest))))

(df formatHttpResponse [(res HttpResponse)] -> String
  :d "Serializes HttpResponse record to HTTP/1.1 wire representation"
  (let [(statusLine (str "HTTP/1.1 " (string-from-int64 (.-statusCode res)) " " (.-reasonPhrase res) "\r\n"))
        (headerLines (formatHeaderEntries (.-entries (.-headers res))))
        (delim "\r\n")
        (body (.-body res))]
    (str statusLine headerLines delim body)))
