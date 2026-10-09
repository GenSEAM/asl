(module asl-http/http11 :x [HttpHeaders HttpRequest HttpResponse makeHeaders getHeader getHeaderFromHeaders makeRequest makeResponse parseHttpRequest getQueryParam formatHttpResponse])

(schema HttpHeaders (:f entries (List (pair String String))))

(schema HttpRequest (:f method String) (:f path String) (:f version String) (:f headers HttpHeaders) (:f body String) (:f query String))

(schema HttpResponse (:f statusCode Int64) (:f reasonPhrase String) (:f headers HttpHeaders) (:f body String))

fn makeHeaders pairs: (List (Pair String String)) -> HttpHeaders
  (HttpHeaders :entries pairs)

fn findHeaderInPairs pairs: (List (Pair String String)) targetKeyLower: String -> (Option String)
  (if (listEmpty? pairs) (none) (let [(p (optionOr (listHead pairs) (pair "" "")))] (if (= (stringLower (pairFirst p)) targetKeyLower) (some (pairSecond p)) (findHeaderInPairs (optionOr (listTail pairs) (list)) targetKeyLower))))

fn getHeaderFromHeaders headers: HttpHeaders name: String -> (Option String)
  (findHeaderInPairs headers.entries (stringLower (stringTrim name)))

fn getHeader target: HttpRequest name: String -> (Option String)
  (getHeaderFromHeaders target.headers name)

fn makeRequest method: String path: String headers: HttpHeaders body: String version: String -> HttpRequest
  (let [(qPos (stringIndexOf path "?"))] (mt qPos ((some idx) (let [(p (optionOr (stringSlice path 0 idx) path)) (q (optionOr (stringSlice path (+ idx 1) (stringLength path)) ""))] (HttpRequest :method method :path p :version version :headers headers :body body :query q))) ((none) (HttpRequest :method method :path path :version version :headers headers :body body :query ""))))

fn makeResponse statusCode: Int64 reasonPhrase: String headers: HttpHeaders body: String -> HttpResponse
  (HttpResponse :statusCode statusCode :reasonPhrase reasonPhrase :headers headers :body body)

fn findQueryParamInPairs pairs: (List (Pair String String)) targetKey: String -> (Option String)
  (if (listEmpty? pairs) (none) (let [(p (optionOr (listHead pairs) (pair "" "")))] (if (= (pairFirst p) targetKey) (some (pairSecond p)) (findQueryParamInPairs (optionOr (listTail pairs) (list)) targetKey))))

fn parseQueryPair item: String -> (Pair String String)
  (let [(eqPos (stringIndexOf item "="))] (mt eqPos ((some idx) (let [(k (optionOr (stringSlice item 0 idx) "")) (v (optionOr (stringSlice item (+ idx 1) (stringLength item)) ""))] (pair k v))) ((none) (pair item ""))))

fn parseQueryString query: String -> (List (Pair String String))
  (if (stringEmpty? query) (list) (let [(items (stringSplit query "&"))] (map (fn [(item String)] -> (Pair String String) (parseQueryPair item)) items)))

fn getQueryParam req: HttpRequest key: String -> (Option String)
  (let [(pairs (parseQueryString req.query))] (findQueryParamInPairs pairs key))

fn hexCharToInt c: String -> (Option Int64)
  (cond ((= c "0") (some 0)) ((= c "1") (some 1)) ((= c "2") (some 2)) ((= c "3") (some 3)) ((= c "4") (some 4)) ((= c "5") (some 5)) ((= c "6") (some 6)) ((= c "7") (some 7)) ((= c "8") (some 8)) ((= c "9") (some 9)) ((or (= c "a") (= c "A")) (some 10)) ((or (= c "b") (= c "B")) (some 11)) ((or (= c "c") (= c "C")) (some 12)) ((or (= c "d") (= c "D")) (some 13)) ((or (= c "e") (= c "E")) (some 14)) ((or (= c "f") (= c "F")) (some 15)) (else (none)))

fn parseHexLoop chars: (List String) acc: Int64 -> (Option Int64)
  (if (listEmpty? chars) (some acc) (let [(ch (optionOr (listHead chars) "")) (digitOpt (hexCharToInt ch))] (mt digitOpt ((some d) (parseHexLoop (optionOr (listTail chars) (list)) (+ (* acc 16) d))) ((none) (none)))))

fn parseHexInt s: String -> (Option Int64)
  (let [(trimmed (stringTrim s))] (if (stringEmpty? trimmed) (none) (parseHexLoop (stringChars trimmed) 0)))

fn parseChunkLoop bodyStr: String pos: Int64 acc: String -> (Result String String)
  (let [(totalLen (stringLength bodyStr))] (if (>= pos totalLen) (ok acc) (let [(remaining (optionOr (stringSlice bodyStr pos totalLen) "")) (crlfPos (stringIndexOf remaining "\r\n"))] (mt crlfPos ((some idx) (let [(sizeLine (stringTrim (optionOr (stringSlice remaining 0 idx) ""))) (cleanSize (let [(semiPos (stringIndexOf sizeLine ";"))] (mt semiPos ((some sIdx) (stringTrim (optionOr (stringSlice sizeLine 0 sIdx) ""))) ((none) sizeLine)))) (hexOpt (parseHexInt cleanSize))] (mt hexOpt ((none) (err "ERR_HTTP_INVALID_CHUNK_SIZE")) ((some chunkSize) (if (= chunkSize 0) (ok acc) (let [(dataStart (+ pos (+ idx 2))) (dataEnd (+ dataStart chunkSize))] (if (> dataEnd totalLen) (err "ERR_HTTP_TRUNCATED_CHUNK") (let [(chunkData (optionOr (stringSlice bodyStr dataStart dataEnd) "")) (nextPos (if (and (<= (+ dataEnd 2) totalLen) (= (optionOr (stringSlice bodyStr dataEnd (+ dataEnd 2)) "") "\r\n")) (+ dataEnd 2) dataEnd))] (parseChunkLoop bodyStr nextPos (str acc chunkData)))))))))) ((none) (if (stringEmpty? (stringTrim remaining)) (ok acc) (err "ERR_HTTP_INVALID_CHUNK_TERMINATION")))))))

fn parseChunkedBody bodyStr: String -> (Result String String)
  (parseChunkLoop bodyStr 0 "")

fn parseHeaderLine line: String -> (Result (Pair String String) String)
  (let [(colonPos (stringIndexOf line ":"))] (mt colonPos ((some idx) (let [(k (stringTrim (optionOr (stringSlice line 0 idx) ""))) (v (stringTrim (optionOr (stringSlice line (+ idx 1) (stringLength line)) "")))] (if (stringEmpty? k) (err "ERR_HTTP_EMPTY_HEADER_NAME") (ok (pair k v))))) ((none) (err "ERR_HTTP_HEADER_NO_COLON"))))

fn parseHeaderLinesLoop lines: (List String) acc: (List (Pair String String)) -> (Result (List (Pair String String)) String)
  (if (listEmpty? lines) (ok (listReverse acc)) (let [(line (stringTrim (optionOr (listHead lines) "")))] (if (stringEmpty? line) (parseHeaderLinesLoop (optionOr (listTail lines) (list)) acc) (let [(pRes (parseHeaderLine line))] (mt pRes ((err e) (err e)) ((ok hdr) (parseHeaderLinesLoop (optionOr (listTail lines) (list)) (cons hdr acc))))))))

fn splitTokens s: String -> (List String)
  (let [(rawTokens (stringSplit s " "))] (filter (fn [(t String)] -> Bool (not (stringEmpty? (stringTrim t)))) rawTokens))

fn parseHttpRequest raw: String -> (Result HttpRequest String)
  (if (stringEmpty? raw) (err "ERR_HTTP_EMPTY_REQUEST") (let [(headerEndCrlf (stringIndexOf raw "\r\n\r\n"))] (mt headerEndCrlf ((some endIdx) (let [(headerSection (optionOr (stringSlice raw 0 endIdx) "")) (bodySection (optionOr (stringSlice raw (+ endIdx 4) (stringLength raw)) "")) (normalizedHeaders (stringReplace headerSection "\r\n" "\n")) (lines (stringSplit normalizedHeaders "\n"))] (if (listEmpty? lines) (err "ERR_HTTP_EMPTY_REQUEST_LINE") (let [(reqLine (stringTrim (optionOr (listHead lines) ""))) (tokens (splitTokens reqLine)) (tokenCount (listLength tokens))] (cond ((< tokenCount 2) (err "ERR_HTTP_MALFORMED_REQUEST_LINE")) ((= tokenCount 2) (let [(t1 (optionOr (listHead (optionOr (listTail tokens) (list))) ""))] (if (stringStartsWith? t1 "HTTP/") (err "ERR_HTTP_MISSING_TARGET") (err "ERR_HTTP_MISSING_VERSION")))) ((> tokenCount 3) (err "ERR_HTTP_MALFORMED_REQUEST_LINE")) (else (let [(method (optionOr (listHead tokens) "")) (tokensTail (optionOr (listTail tokens) (list))) (rawTarget (optionOr (listHead tokensTail) "")) (version (optionOr (listHead (optionOr (listTail tokensTail) (list))) ""))] (if (not (stringStartsWith? version "HTTP/")) (err "ERR_HTTP_INVALID_VERSION") (let [(headerLines (optionOr (listTail lines) (list))) (headersRes (parseHeaderLinesLoop headerLines (list)))] (mt headersRes ((err e) (err e)) ((ok headerPairs) (let [(parsedHeaders (makeHeaders headerPairs)) (contentLenOpt (getHeaderFromHeaders parsedHeaders "Content-Length")) (transferEncodingOpt (getHeaderFromHeaders parsedHeaders "Transfer-Encoding"))] (let [(validLenRes (mt contentLenOpt ((none) (ok true)) ((some lenStr) (let [(parsedInt (stringToInt64 (stringTrim lenStr)))] (mt parsedInt ((none) (err "ERR_HTTP_INVALID_CONTENT_LENGTH")) ((some n) (if (< n 0) (err "ERR_HTTP_INVALID_CONTENT_LENGTH") (ok true))))))))] (mt validLenRes ((err e) (err e)) ((ok _) (if (= (stringLower (optionOr transferEncodingOpt "")) "chunked") (mt (parseChunkedBody bodySection) ((err e) (err e)) ((ok decoded) (ok (makeRequest method rawTarget parsedHeaders decoded version)))) (ok (makeRequest method rawTarget parsedHeaders bodySection version)))))))))))))))))) ((none) (err "ERR_HTTP_MISSING_HEADER_TERMINATOR")))))

fn formatHeaderEntries entries: (List (Pair String String)) -> String
  (if (listEmpty? entries) "" (let [(p (optionOr (listHead entries) (pair "" ""))) (line (str (pairFirst p) ": " (pairSecond p) "\r\n")) (rest (formatHeaderEntries (optionOr (listTail entries) (list))))] (str line rest)))

fn formatHttpResponse res: HttpResponse -> String
  (let [(statusLine (str "HTTP/1.1 " (stringFromInt64 res.statusCode) " " res.reasonPhrase "\r\n")) (headerLines (formatHeaderEntries res.headers.entries)) (delim "\r\n") (body res.body)] (str statusLine headerLines delim body))
