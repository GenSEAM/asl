(module asl-http/httpResponse
  :x [parseHttpResponse parseHttpResponseNext parseHttpResponses parseHeaderBlocks headerValues decodeChunked Chunked]
  :i [(asl-http/http11 :a h)])

; (:m :ref DS-HTTPRESP :do "the client side of HTTP/1.1 (inbox workspace-20261030-httpResponseParser): a status line, headers kept in order with their case (lookup through http11 getHeaderFromHeaders is case-insensitive, duplicates stay as separate entries, an obs-fold continuation line joins the previous value with one space), a body framed by chunked transfer coding (trailers added after the headers) or by Content-Length, none for 1xx, 204 and 304, else everything to the end; every malformed or truncated input is an err whose text starts with an ERR_HTTP_ label, never a trap; offsets are bytes, as Content-Length and chunk sizes are")

(schema Chunked
  (:f body String)
  (:f trailers (List (Pair String String)))
  (:f rest String))

fn sliceFrom s: String i: Int64 -> String
  (optionOr (stringSlice s i (stringLength s)) "")

fn sliceTo s: String i: Int64 -> String
  (optionOr (stringSlice s 0 i) "")

fn allIn? s: String alphabet: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (stringContains? alphabet c)) (stringChars s)))

fn stripCr line: String -> String
  (if (stringEndsWith? line "\r") (sliceTo line (- (stringLength line) 1)) line)

; (:m :ref DS-HTTPRESP :do "where the header section ends: the earliest blank line, CRLF CRLF or a bare LF LF (curl -D output on some platforms), as (index, terminator width)")
fn headEnd raw: String -> (Option (Pair Int64 Int64))
  (let [(crlf (stringIndexOf raw "\r\n\r\n"))
        (lf (stringIndexOf raw "\n\n"))]
    (match crlf
      ((some c) (match lf ((some l) (if (< l c) (some (pair l 2)) (some (pair c 4)))) ((none) (some (pair c 4)))))
      ((none) (match lf ((some l) (some (pair l 2))) ((none) (none))))))

fn headLines head: String -> (List String)
  (map stripCr (stringSplit head "\n"))

; (:m :ref DS-HTTPRESP :do "HTTP-version SP 3DIGIT [SP reason]: the version is HTTP/ then digits and dots (HTTP/1.1, HTTP/1.0, HTTP/2 as curl prints it), the code is 100 to 599")
fn parseStatusLine line: String -> (Result (Pair Int64 String) String)
  (match (stringIndexOf line " ")
    ((none) (err (str "ERR_HTTP_MALFORMED_STATUS_LINE: " line)))
    ((some i)
      (let [(version (sliceTo line i))
            (rest (sliceFrom line (+ i 1)))
            (code (sliceTo rest 3))
            (after (sliceFrom rest 3))]
        (cond
          ((not (and (stringStartsWith? version "HTTP/") (allIn? (sliceFrom version 5) "0123456789."))) (err (str "ERR_HTTP_BAD_VERSION: " line)))
          ((not (and (= (stringLength code) 3) (allIn? code "0123456789"))) (err (str "ERR_HTTP_BAD_STATUS_CODE: " line)))
          ((not (or (stringEmpty? after) (stringStartsWith? after " "))) (err (str "ERR_HTTP_BAD_STATUS_CODE: " line)))
          (else
            (let [(n (optionOr (stringToInt64 code) 0))]
              (if (or (< n 100) (> n 599))
                (err (str "ERR_HTTP_BAD_STATUS_CODE: " line))
                (ok (pair n (stringTrim after))))))))))

; (:m :ref DS-HTTPRESP :do "header lines in order (acc reversed): name: value with the value trimmed; a line starting with SP or HT continues the previous value (obs-fold, joined by one space); a name that is empty or holds a blank, a line without a colon, or a continuation with nothing before it is an err")
fn headerLoop lines: (List String) acc: (List (Pair String String)) -> (Result (List (Pair String String)) String)
  (match (listHead lines)
    ((none) (ok (listReverse acc)))
    ((some l)
      (let [(more (optionOr (listTail lines) (list)))]
        (cond
          ((stringEmpty? l) (headerLoop more acc))
          ((or (stringStartsWith? l " ") (stringStartsWith? l "\t"))
            (match (listHead acc)
              ((none) (err (str "ERR_HTTP_FOLD_WITHOUT_HEADER: " l)))
              ((some prev)
                (let [(joined (stringTrim (str (pairSecond prev) " " (stringTrim l))))]
                  (headerLoop more (cons (pair (pairFirst prev) joined) (optionOr (listTail acc) (list))))))))
          (else
            (match (stringIndexOf l ":")
              ((none) (err (str "ERR_HTTP_HEADER_NO_COLON: " l)))
              ((some i)
                (let [(name (sliceTo l i))]
                  (if (or (stringEmpty? name) (or (stringContains? name " ") (stringContains? name "\t")))
                    (err (str "ERR_HTTP_BAD_HEADER_NAME: " l))
                    (headerLoop more (cons (pair name (stringTrim (sliceFrom l (+ i 1)))) acc)))))))))))

; (:m :ref DS-HTTPRESP :do "every value of a header, case-insensitive on the name, in arrival order (duplicates are separate entries)")
fn headerValues headers: h/HttpHeaders name: String -> (List String)
  (let [(want (stringLower (stringTrim name)))]
    (map pairSecond (filter (fn [(p (Pair String String))] -> Bool (= (stringLower (pairFirst p)) want)) headers.entries)))

fn listTokens values: (List String) -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t)))
          (map stringTrim (fold (fn [(acc (List String)) (v String)] -> (List String) (listAppend acc (stringSplit v ","))) (list) values)))

; (:m :ref DS-HTTPRESP :do "the Content-Length: none when absent; every value (and every comma-separated token) must be decimal digits and all must agree, else ERR_HTTP_BAD_CONTENT_LENGTH or ERR_HTTP_CONFLICTING_CONTENT_LENGTH (RFC 9112 6.3)")
fn contentLength headers: h/HttpHeaders -> (Result (Option Int64) String)
  (let [(tokens (listTokens (headerValues headers "Content-Length")))]
    (cond
      ((listEmpty? tokens) (ok (none)))
      ((not (listAll? (fn [(t String)] -> Bool (and (<= (stringLength t) 15) (allIn? t "0123456789"))) tokens)) (err (str "ERR_HTTP_BAD_CONTENT_LENGTH: " (stringJoin tokens ","))))
      ((listAny? (fn [(t String)] -> Bool (!= t (optionOr (listHead tokens) ""))) tokens) (err (str "ERR_HTTP_CONFLICTING_CONTENT_LENGTH: " (stringJoin tokens ","))))
      (else (ok (stringToInt64 (optionOr (listHead tokens) ""))))))

fn chunkedLast? headers: h/HttpHeaders -> Bool
  (= (stringLower (optionOr (listLast (listTokens (headerValues headers "Transfer-Encoding"))) "")) "chunked")

fn hexValue c: String -> Int64
  (optionOr (stringIndexOf "0123456789abcdef" (stringLower c)) 0)

fn parseHex s: String -> (Option Int64)
  (if (and (<= (stringLength s) 15) (allIn? s "0123456789abcdefABCDEF"))
    (some (fold (fn [(acc Int64) (c String)] -> Int64 (+ (* acc 16) (hexValue c))) 0 (stringChars s)))
    (none))

; (:m :ref DS-HTTPRESP :do "the trailer section after the last chunk: an empty line right away, or trailer header lines up to a blank line; the bytes after it are the rest")
fn trailersOf tail: String body: String -> (Result Chunked String)
  (cond
    ((stringStartsWith? tail "\r\n") (ok (Chunked :body body :trailers (list) :rest (sliceFrom tail 2))))
    ((stringStartsWith? tail "\n") (ok (Chunked :body body :trailers (list) :rest (sliceFrom tail 1))))
    (else
      (match (headEnd tail)
        ((none) (err "ERR_HTTP_TRUNCATED_TRAILERS: no blank line after the last chunk"))
        ((some e)
          (match (headerLoop (headLines (sliceTo tail (pairFirst e))) (list))
            ((err x) (err x))
            ((ok ts) (ok (Chunked :body body :trailers ts :rest (sliceFrom tail (+ (pairFirst e) (pairSecond e)))))))))))

; (:m :ref DS-HTTPRESP :do "one chunk at byte pos: a hex size line (chunk extensions after ; ignored), then that many bytes and CRLF (or LF); size 0 ends the body and the trailers follow; a missing size line, short data or a missing data terminator is an err")
fn chunkLoop s: String pos: Int64 acc: String -> (Result Chunked String)
  (let [(from (sliceFrom s pos))]
    (match (stringIndexOf from "\n")
      ((none) (err (str "ERR_HTTP_TRUNCATED_CHUNKED: no chunk size line at byte " (stringFromInt64 pos))))
      ((some nl)
        (let [(sizeLine (stripCr (sliceTo from nl)))
              (sizeText (stringTrim (match (stringIndexOf sizeLine ";") ((some k) (sliceTo sizeLine k)) ((none) sizeLine))))
              (dataStart (+ pos (+ nl 1)))]
          (match (parseHex sizeText)
            ((none) (err (str "ERR_HTTP_BAD_CHUNK_SIZE: " sizeLine)))
            ((some 0) (trailersOf (sliceFrom s dataStart) acc))
            ((some n)
              (let [(dataEnd (+ dataStart n))
                    (total (stringLength s))]
                (cond
                  ((> dataEnd total) (err (str "ERR_HTTP_TRUNCATED_CHUNK: want " (stringFromInt64 n) " bytes, have " (stringFromInt64 (- total dataStart)))))
                  ((= (optionOr (stringSlice s dataEnd (+ dataEnd 2)) "") "\r\n") (chunkLoop s (+ dataEnd 2) (str acc (optionOr (stringSlice s dataStart dataEnd) ""))))
                  ((= (optionOr (stringSlice s dataEnd (+ dataEnd 1)) "") "\n") (chunkLoop s (+ dataEnd 1) (str acc (optionOr (stringSlice s dataStart dataEnd) ""))))
                  ((< (+ dataEnd 1) total) (err (str "ERR_HTTP_BAD_CHUNK_TERMINATOR: after a chunk of " (stringFromInt64 n) " bytes")))
                  (else (err (str "ERR_HTTP_TRUNCATED_CHUNK: no terminator after a chunk of " (stringFromInt64 n) " bytes")))))))))))

; (:m :ref DS-HTTPRESP :do "a chunked body: the decoded data, the trailer fields and the bytes after the message")
fn decodeChunked s: String -> (Result Chunked String)
  (chunkLoop s 0 "")

fn noBody? code: Int64 -> Bool
  (or (and (>= code 100) (< code 200)) (or (= code 204) (= code 304)))

fn bodyOf code: Int64 headers: h/HttpHeaders rest: String headersOnly: Bool -> (Result Chunked String)
  (cond
    ((or headersOnly (noBody? code)) (ok (Chunked :body "" :trailers (list) :rest rest)))
    ((chunkedLast? headers) (decodeChunked rest))
    ((> (listLength (headerValues headers "Transfer-Encoding")) 0) (ok (Chunked :body rest :trailers (list) :rest "")))
    (else
      (match (contentLength headers)
        ((err e) (err e))
        ((ok (none)) (ok (Chunked :body rest :trailers (list) :rest "")))
        ((ok (some n))
          (if (> n (stringLength rest))
            (err (str "ERR_HTTP_TRUNCATED_BODY: Content-Length " (stringFromInt64 n) ", have " (stringFromInt64 (stringLength rest))))
            (ok (Chunked :body (sliceTo rest n) :trailers (list) :rest (sliceFrom rest n))))))))

fn nextWith raw: String headersOnly: Bool -> (Result (Pair h/HttpResponse String) String)
  (if (stringEmpty? raw)
    (err "ERR_HTTP_EMPTY_RESPONSE")
    (match (headEnd raw)
      ((none) (err "ERR_HTTP_TRUNCATED_HEAD: no blank line ends the header section"))
      ((some e)
        (let [(lines (headLines (sliceTo raw (pairFirst e))))
              (rest (sliceFrom raw (+ (pairFirst e) (pairSecond e))))]
          (match (parseStatusLine (optionOr (listHead lines) ""))
            ((err x) (err x))
            ((ok st)
              (match (headerLoop (optionOr (listTail lines) (list)) (list))
                ((err x) (err x))
                ((ok hs)
                  (let [(headers (h/makeHeaders hs))]
                    (match (bodyOf (pairFirst st) headers rest headersOnly)
                      ((err x) (err x))
                      ((ok c) (ok (pair (h/makeResponse (pairFirst st) (pairSecond st) (h/makeHeaders (listAppend hs c.trailers)) c.body) c.rest)))))))))))))

; (:m :ref DS-HTTPRESP :do "one response from the front of raw and the bytes after it (a pipelined or redirected next response)")
fn parseHttpResponseNext raw: String -> (Result (Pair h/HttpResponse String) String)
  (nextWith raw false)

; (:m :ref DS-HTTPRESP :do "one response; bytes after a framed body are ignored")
fn parseHttpResponse raw: String -> (Result h/HttpResponse String)
  (match (nextWith raw false)
    ((err e) (err e))
    ((ok p) (ok (pairFirst p))))

fn manyLoop raw: String headersOnly: Bool acc: (List h/HttpResponse) -> (Result (List h/HttpResponse) String)
  (if (stringEmpty? (stringTrim raw))
    (ok (listReverse acc))
    (match (nextWith raw headersOnly)
      ((err e) (err (str e " (response " (stringFromInt64 (+ (listLength acc) 1)) ")")))
      ((ok p) (manyLoop (pairSecond p) headersOnly (cons (pairFirst p) acc)))))

; (:m :ref DS-HTTPRESP :do "every response of a stream in order, each framed as parseHttpResponseNext frames it (a 301 then a 200 when a client followed a redirect)")
fn parseHttpResponses raw: String -> (Result (List h/HttpResponse) String)
  (manyLoop raw false (list))

; (:m :ref DS-HTTPRESP :do "curl -D output: one header block per hop, no bodies; each block is a status line and headers, the body is empty")
fn parseHeaderBlocks text: String -> (Result (List h/HttpResponse) String)
  (manyLoop text true (list))
