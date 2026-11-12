(module asl/packages/asl-http/tests/httpResponseTest
  :x [runTests]
  :i [(asl-http/http11 :a h) (asl-http/httpResponse :a hr)])

; (:m :ref DS-HTTPRESP :do "the HTTP/1.1 response parser on literal fixtures: status line, header case, obs-fold, duplicates, Content-Length and chunked framing with trailers, a 301 then 200 stream, curl -D header blocks, labelled errs for malformed and truncated input, and every proper prefix of a framed response is an err, never a trap")

fn errOf r: (Result h/HttpResponse String) -> String
  (match r ((ok _) "") ((err e) e))

fn codeOf r: (Result h/HttpResponse String) -> Int64
  (match r ((ok x) x.statusCode) ((err _) -1))

fn bodyOf r: (Result h/HttpResponse String) -> String
  (match r ((ok x) x.body) ((err _) "<err>"))

fn headerOf r: (Result h/HttpResponse String) name: String -> String
  (match r ((ok x) (optionOr (h/getHeaderFromHeaders x.headers name) "<none>")) ((err _) "<err>"))

fn valuesOf r: (Result h/HttpResponse String) name: String -> (List String)
  (match r ((ok x) (hr/headerValues x.headers name)) ((err _) (list)))

fn labelled? e: String label: String -> Bool
  (stringStartsWith? e (str label ":"))

fn chunkedText -> String
  "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5;ext=1\r\nhello\r\n6\r\n world\r\nA\r\n0123456789\r\n0\r\nX-Trailer: done\r\n\r\n"

fn lengthText -> String
  "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"

; (:m :do "every proper prefix of text parses to an err; a trap would end the run")
fn prefixErrs text: String -> Int64
  (listLength (filter (fn [(n Int64)] -> Bool (not (stringEmpty? (errOf (hr/parseHttpResponse (optionOr (stringSlice text 0 n) "")))))) (range 0 (stringLength text))))

fn ! runTests -> Bool
  (let [(cl (hr/parseHttpResponseNext (str (lengthText) "EXTRA")))
        (clResp (match cl ((ok p) (ok (pairFirst p))) ((err e) (err e))))
        (clRest (match cl ((ok p) (pairSecond p)) ((err _) "<err>")))
        (lf (hr/parseHttpResponse "HTTP/1.0 404 Not Found\nContent-Length: 2\n\nno"))
        (folded (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nX-Long: a\r\n  b\r\n\tc\r\nContent-Length: 0\r\n\r\n"))
        (dups (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nSet-Cookie: a=1\r\nset-cookie: b=2\r\nContent-Length: 0\r\n\r\n"))
        (sameLen (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nContent-Length: 2, 2\r\nContent-Length: 2\r\n\r\nokXX"))
        (conflict (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\nokX"))
        (badLen (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n"))
        (chunked (hr/parseHttpResponse (chunkedText)))
        (chunkedNoTrailer (hr/parseHttpResponse "HTTP/1.1 200 OK\r\ntransfer-encoding: gzip, Chunked\r\n\r\n2\r\nhi\r\n0\r\n\r\n"))
        (toClose (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nall of it"))
        (stream (hr/parseHttpResponses "HTTP/1.1 301 Moved Permanently\r\nLocation: https://example.invalid/b\r\nContent-Length: 0\r\n\r\nHTTP/1.1 204 No Content\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"))
        (streamCodes (match stream ((ok rs) (map (fn [(x h/HttpResponse)] -> Int64 x.statusCode) rs)) ((err _) (list))))
        (streamLoc (match stream ((ok rs) (optionOr (h/getHeaderFromHeaders (optionOr (listHead rs) (h/makeResponse 0 "" (h/makeHeaders (list)) "")).headers "location") "")) ((err _) "")))
        (streamBody (match stream ((ok rs) (optionOr (listLast (map (fn [(x h/HttpResponse)] -> String x.body) rs)) "")) ((err _) "")))
        (blocks (hr/parseHeaderBlocks "HTTP/1.1 301 Moved Permanently\r\nLocation: /b\r\nContent-Length: 120\r\n\r\nHTTP/2 200\r\ncontent-type: text/html\r\n\r\n"))
        (blockCodes (match blocks ((ok rs) (map (fn [(x h/HttpResponse)] -> Int64 x.statusCode) rs)) ((err _) (list))))
        (blockReasons (match blocks ((ok rs) (map (fn [(x h/HttpResponse)] -> String x.reasonPhrase) rs)) ((err _) (list))))
        (badCode (errOf (hr/parseHttpResponse "HTTP/1.1 2x0 OK\r\n\r\n")))
        (lowCode (errOf (hr/parseHttpResponse "HTTP/1.1 099 Low\r\n\r\n")))
        (badVersion (errOf (hr/parseHttpResponse "HTTX/1.1 200 OK\r\n\r\n")))
        (noSpace (errOf (hr/parseHttpResponse "garbage\r\n\r\n")))
        (noColon (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nNoColonHere\r\n\r\n")))
        (badName (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nBad Name: x\r\n\r\n")))
        (foldFirst (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\n  orphan\r\n\r\n")))
        (empty (errOf (hr/parseHttpResponse "")))
        (noHead (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n")))
        (shortBody (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc")))
        (shortChunk (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhel")))
        (noLast (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n")))
        (badSize (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nhello\r\n0\r\n\r\n")))
        (badTerm (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhiXX0\r\n\r\n")))
        (shortTrailers (errOf (hr/parseHttpResponse "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nX-T: 1\r\n")))
        (chunkPrefixes (prefixErrs (chunkedText)))
        (lengthPrefixes (prefixErrs (lengthText)))]
    (do
      (assert (and (= (codeOf clResp) 200) (= (bodyOf clResp) "hello") (= clRest "EXTRA")) (str "Content-Length frames the body and the bytes after it are the rest: " (bodyOf clResp) " / " clRest))
      (assert (= (match clResp ((ok x) x.reasonPhrase) ((err _) "")) "OK") "the reason phrase follows the code")
      (assert (and (= (headerOf clResp "content-type") "text/plain") (= (headerOf clResp "CONTENT-TYPE") "text/plain")) "header lookup is case-insensitive")
      (assert (= (match clResp ((ok x) (map pairFirst x.headers.entries)) ((err _) (list))) (list "Content-Type" "Content-Length")) "header names keep their case and order")
      (assert (and (= (codeOf lf) 404) (= (bodyOf lf) "no")) (str "LF-only line ends parse too: " (errOf lf)))
      (assert (= (headerOf folded "X-Long") "a b c") (str "an obs-fold continuation joins the previous value with one space: " (headerOf folded "X-Long") (errOf folded)))
      (assert (= (valuesOf dups "SET-COOKIE") (list "a=1" "b=2")) (str "duplicate headers stay separate, in order, under any case: " (stringJoin (valuesOf dups "Set-Cookie") "|")))
      (assert (= (bodyOf sameLen) "ok") (str "repeated equal Content-Length values are one length: " (errOf sameLen)))
      (assert (labelled? (errOf conflict) "ERR_HTTP_CONFLICTING_CONTENT_LENGTH") (str "differing Content-Length values are an err: " (errOf conflict)))
      (assert (labelled? (errOf badLen) "ERR_HTTP_BAD_CONTENT_LENGTH") (str "a non-digit Content-Length is an err: " (errOf badLen)))
      (assert (= (bodyOf chunked) "hello world0123456789") (str "chunked data is decoded, extensions ignored, hex sizes in any case: " (bodyOf chunked) (errOf chunked)))
      (assert (= (headerOf chunked "x-trailer") "done") (str "trailer fields join the headers: " (headerOf chunked "x-trailer")))
      (assert (= (bodyOf chunkedNoTrailer) "hi") (str "chunked as the last coding in any case is decoded: " (bodyOf chunkedNoTrailer) (errOf chunkedNoTrailer)))
      (assert (= (bodyOf toClose) "all of it") "without framing the body runs to the end")
      (assert (and (= streamCodes (list 301 204 200)) (= streamLoc "https://example.invalid/b") (= streamBody "ok")) (str "a 301 then 204 then 200 stream gives three responses: " (stringJoin (map stringFromInt64 streamCodes) ",") " " (match stream ((err e) e) ((ok _) ""))))
      (assert (and (= blockCodes (list 301 200)) (= blockReasons (list "Moved Permanently" ""))) (str "curl -D header blocks split per hop, bodies not read even with a Content-Length: " (stringJoin (map stringFromInt64 blockCodes) ",") " " (match blocks ((err e) e) ((ok _) ""))))
      (assert (and (labelled? badCode "ERR_HTTP_BAD_STATUS_CODE") (labelled? lowCode "ERR_HTTP_BAD_STATUS_CODE")) (str "a non-digit or out-of-range code is a labelled err: " badCode " / " lowCode))
      (assert (labelled? badVersion "ERR_HTTP_BAD_VERSION") (str "a status line not starting HTTP/ is a labelled err: " badVersion))
      (assert (labelled? noSpace "ERR_HTTP_MALFORMED_STATUS_LINE") (str "a status line without a space is a labelled err: " noSpace))
      (assert (and (labelled? noColon "ERR_HTTP_HEADER_NO_COLON") (labelled? badName "ERR_HTTP_BAD_HEADER_NAME") (labelled? foldFirst "ERR_HTTP_FOLD_WITHOUT_HEADER")) (str "bad header lines are labelled errs: " noColon " / " badName " / " foldFirst))
      (assert (and (= empty "ERR_HTTP_EMPTY_RESPONSE") (labelled? noHead "ERR_HTTP_TRUNCATED_HEAD") (labelled? shortBody "ERR_HTTP_TRUNCATED_BODY")) (str "empty input, a header section cut short and a short body are errs: " noHead " / " shortBody))
      (assert (and (labelled? shortChunk "ERR_HTTP_TRUNCATED_CHUNK") (stringContains? shortChunk "want 5 bytes, have 3") (labelled? noLast "ERR_HTTP_TRUNCATED_CHUNKED") (labelled? shortTrailers "ERR_HTTP_TRUNCATED_TRAILERS")) (str "a cut chunk, a missing last chunk and cut trailers are errs: " shortChunk " / " noLast " / " shortTrailers))
      (assert (and (labelled? badSize "ERR_HTTP_BAD_CHUNK_SIZE") (labelled? badTerm "ERR_HTTP_BAD_CHUNK_TERMINATOR")) (str "a bad chunk size and a missing data terminator are errs: " badSize " / " badTerm))
      (assert (= chunkPrefixes (stringLength (chunkedText))) (str "every proper prefix of a chunked response is an err: " (stringFromInt64 chunkPrefixes) " of " (stringFromInt64 (stringLength (chunkedText)))))
      (assert (= lengthPrefixes (stringLength (lengthText))) (str "every proper prefix of a Content-Length response is an err: " (stringFromInt64 lengthPrefixes) " of " (stringFromInt64 (stringLength (lengthText)))))
      true))
