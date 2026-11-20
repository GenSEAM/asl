(module asl-http/client
  :x [httpRequest! httpRequestAllowFile! httpWritePrivate! httpHeaderFileText httpRequestArgv httpReplyFromCurl httpRedact httpCurlError]
  :i [(asl-proc/process :a proc) (asl-http/http11 :a h) (asl-http/httpResponse :a hr) (asl-http/download :a d)])

; (:m :ref HTTP-CLIENT-INTERIM :do "interim HTTP client over curl until native TCP and TLS land (NET-DNS-TCP, NET-TLS) or libcurl is bound (EXTERN-02); retire this module then. Not for wasm targets. Every failure is an err text starting ERR_HTTP_; no secret from a header value or a URL userinfo is ever put in an err")

fn badChars? s: String -> Bool
  (or (stringContains? s "\r") (stringContains? s "\n"))

fn methodOk? method: String -> Bool
  (and (not (stringEmpty? method)) (listAll? (fn [(c String)] -> Bool (stringContains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" c)) (stringChars method)))

fn headerOk? p: (Pair String String) -> Bool
  (let [(name (pairFirst p)) (value (pairSecond p))]
    (and (not (stringEmpty? name))
         (and (not (stringContains? name ":"))
              (and (not (stringContains? name " ")) (and (not (badChars? name)) (not (badChars? value)))))))

; (:m :ref HTTP-CLIENT-INTERIM :do "the header file curl reads through -H @file: one Name: value line per header, so no header value is in argv and none shows in ps")
fn httpHeaderFileText headers: (List (Pair String String)) -> String
  (fold (fn [(acc String) (p (Pair String String))] -> String (str acc (pairFirst p) ": " (pairSecond p) "\n")) "" headers)

fn fileUrl? url: String -> Bool
  (stringStartsWith? (stringLower url) "file://")

fn methodArgs method: String -> (List String)
  (cond ((= method "GET") (list "-L"))
        ((= method "HEAD") (list "--head" "-L"))
        (else (list "-X" method)))

; (:m :ref HTTP-CLIENT-INTERIM :do "the curl argv, pure: -q first so no curlrc is read, --proto =http,https (file only when allowFile), response headers by -D dumpPath and the body by -o outPath (curl then decodes chunked itself and the parser sees headers only), --max-time and --connect-timeout from milliseconds, GET and HEAD follow redirects and every other method does not, request headers by -H @headersPath and the body by --data-binary @bodyPath so neither is in argv, --globoff, the URL last behind --url")
fn httpRequestArgv method: String url: String headers: (List (Pair String String)) headersPath: String bodyPath: (Option String) dumpPath: String outPath: String allowFile: Bool connectMs: Int64 totalMs: Int64 -> (List String)
  (listAppend
    (listAppend
      (listAppend
        (list "curl" "-q" "-sS" "--proto" (if allowFile "=http,https,file" "=http,https") "-D" dumpPath "-o" outPath)
        (list "--globoff" "--max-time" (d/curlTimeout totalMs) "--connect-timeout" (d/curlTimeout connectMs)))
      (listAppend (methodArgs method) (if (listEmpty? headers) (list) (list "-H" (str "@" headersPath)))))
    (listAppend (match bodyPath ((some p) (list "--data-binary" (str "@" p))) ((none) (list))) (list "--url" url)))

fn urlUserinfo url: String -> Option String
  (match (stringIndexOf url "://")
    ((none) (none))
    ((some i)
      (let [(rest (optionOr (stringSlice url (+ i 3) (stringLength url)) ""))
            (authority (match (stringIndexOf rest "/") ((some j) (optionOr (stringSlice rest 0 j) "")) ((none) rest)))]
        (match (stringIndexOf authority "@")
          ((none) (none))
          ((some k) (some (optionOr (stringSlice authority 0 k) "")))))))

fn secretsOf url: String headers: (List (Pair String String)) -> (List String)
  (let [(values (filter (fn [(v String)] -> Bool (>= (stringLength v) 8)) (map (fn [(p (Pair String String))] -> String (pairSecond p)) headers)))]
    (match (urlUserinfo url)
      ((some u) (if (stringEmpty? u) values (cons u values)))
      ((none) values)))

; (:m :ref HTTP-CLIENT-INTERIM :do "text with every secret (a header value, a URL userinfo) replaced by <redacted>, longest first so a value that contains another is hidden whole")
fn httpRedact text: String url: String headers: (List (Pair String String)) -> String
  (fold (fn [(acc String) (s String)] -> String (stringReplace acc s "<redacted>")) text (listSortBy (fn [(a String)] -> Int64 (- 0 (stringLength a))) (secretsOf url headers)))

; (:m :ref HTTP-CLIENT-INTERIM :do "a failed curl as an err: ERR_HTTP_CURL_<exit code>: <redacted stderr>; the code is curl's (6 resolve, 7 connect, 28 timeout, 35 tls, 37 file)")
fn httpCurlError code: Int64 stderr: String url: String headers: (List (Pair String String)) -> String
  (str "ERR_HTTP_CURL_" (stringFromInt64 code) ": " (httpRedact (stringTrim stderr) url headers))

fn lastOf rs: (List h/HttpResponse) -> (Result h/HttpResponse String)
  (match (listLast rs) ((some r) (ok r)) ((none) (err "ERR_HTTP_EMPTY_RESPONSE")))

; (:m :ref HTTP-CLIENT-INTERIM :do "the final response from curl's -D header dump and -o body file: one header block per hop, the last block is the response and the body is the file as curl decoded it (chunked already decoded, so it is never decoded twice); HEAD has an empty body; a file:// URL has no HTTP framing (curl dumps pseudo headers), its bytes are the body of a synthetic 200")
fn httpReplyFromCurl method: String url: String headerText: String body: String -> (Result h/HttpResponse String)
  (cond
    ((fileUrl? url) (ok (h/makeResponse 200 "OK" (h/makeHeaders (list)) body)))
    ((stringEmpty? (stringTrim headerText)) (err "ERR_HTTP_EMPTY_RESPONSE"))
    (else
      (match (hr/parseHeaderBlocks headerText)
        ((err e) (err e))
        ((ok rs)
          (match (lastOf rs)
            ((err e) (err e))
            ((ok r) (ok (h/makeResponse r.statusCode r.reasonPhrase r.headers (if (= method "HEAD") "" body)))))))))

fn removeQuiet! path: String -> Unit
  (match (pathRemove path) ((err _) ()) ((ok _) ()))

fn tempStem -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/asl_http_req_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)))

; (:m :ref HTTP-CLIENT-INTERIM :do "a file only its owner can read: created with fileCreateExclusive (O_EXCL, so an existing file or a symlink at the name is an err and nothing behind it is touched), empty, then chmod 0600 (384), then filled; ok is the path")
fn ! httpWritePrivate! path: String text: String -> (Result String String)
  (match (fileCreateExclusive path "")
    ((err e) (err e))
    ((ok _)
      (match (fileChmod path 384)
        ((err e) (do (removeQuiet! path) (err e)))
        ((ok _)
          (if (stringEmpty? text)
            (ok path)
            (match (fileWrite path text)
              ((err e) (do (removeQuiet! path) (err e)))
              ((ok _) (ok path))))))))

fn spawnError e: String url: String headers: (List (Pair String String)) -> String
  (if (stringContains? (stringLower e) "timeout")
    "ERR_HTTP_TIMEOUT: curl did not finish inside the total timeout plus 5 s"
    (str "ERR_CURL_SPAWN: " (httpRedact e url headers)))

fn finishCurl! method: String url: String headers: (List (Pair String String)) argv: (List String) totalMs: Int64 dumpPath: String outPath: String -> (Result h/HttpResponse String)
  (match (listHead argv)
    ((none) (err "ERR_CURL_SPAWN: empty argv"))
    ((some bin)
      (match (proc/exec! (proc/withTimeout (proc/cmd bin (optionOr (listTail argv) (list))) (+ totalMs 5000)))
        ((err e) (err (spawnError (str e) url headers)))
        ((ok o)
          (if (!= o.exitCode 0)
            (err (httpCurlError o.exitCode o.stderr url headers))
            (match (fileReadString dumpPath)
              ((err e) (err (str "ERR_HTTP_HEADERS: " e)))
              ((ok headerText)
                (match (fileReadString outPath)
                  ((err e) (err (str "ERR_HTTP_BODY_FILE: " e)))
                  ((ok body) (httpReplyFromCurl method url headerText body))))))))))

fn noBody? method: String -> Bool
  (or (= method "GET") (= method "HEAD"))

fn requestCore! allowFile: Bool method: String url: String headers: (List (Pair String String)) body: (Option String) connectMs: Int64 totalMs: Int64 -> (Result h/HttpResponse String)
  (cond
    ((not (methodOk? method)) (err "ERR_HTTP_ARGUMENT: method must be uppercase letters"))
    ((or (stringEmpty? url) (badChars? url)) (err "ERR_HTTP_ARGUMENT: url is empty or holds a control character"))
    ((and (fileUrl? url) (not allowFile)) (err "ERR_HTTP_ARGUMENT: file:// is not allowed here"))
    ((not (listAll? headerOk? headers)) (err "ERR_HTTP_ARGUMENT: header name or value is malformed"))
    ((and (noBody? method) (match body ((some _) true) ((none) false))) (err "ERR_HTTP_ARGUMENT: GET and HEAD take no body"))
    ((or (<= connectMs 0) (<= totalMs 0)) (err "ERR_TIMEOUT_RANGE"))
    (else
      (let [(stem (tempStem))
            (hpath (str stem ".reqh"))
            (bpath (str stem ".reqb"))
            (dpath (str stem ".resh"))
            (opath (str stem ".resb"))]
        (let [(r (match (if (listEmpty? headers) (ok hpath) (httpWritePrivate! hpath (httpHeaderFileText headers)))
                   ((err e) (err (str "ERR_HTTP_HEADER_FILE: " e)))
                   ((ok _) (match (match body ((some text) (match (httpWritePrivate! bpath text) ((ok p) (ok (some p))) ((err e) (err e)))) ((none) (ok (none))))
                     ((err e) (err (str "ERR_HTTP_BODY_FILE: " e)))
                     ((ok bp) (match (httpWritePrivate! dpath "")
                       ((err e) (err (str "ERR_HTTP_HEADERS: " e)))
                       ((ok _) (match (httpWritePrivate! opath "")
                         ((err e) (err (str "ERR_HTTP_BODY_FILE: " e)))
                         ((ok _) (finishCurl! method url headers (httpRequestArgv method url headers hpath bp dpath opath allowFile connectMs totalMs) totalMs dpath opath))))))))))]
          (do (removeQuiet! hpath) (removeQuiet! bpath) (removeQuiet! dpath) (removeQuiet! opath) r)))))

; (:m :ref HTTP-CLIENT-INTERIM :do "any method, headers as name value pairs, an optional body (GET and HEAD take none), connect and total timeouts in milliseconds; ok is the final response (statusCode, reasonPhrase, headers of the last hop, body), an HTTP error status is still ok; err is ERR_HTTP_ARGUMENT, ERR_TIMEOUT_RANGE, ERR_HTTP_CURL_<code>, ERR_HTTP_TIMEOUT or ERR_CURL_SPAWN, never an exception; only http and https; request and response headers and bodies pass through 0600 O_EXCL temp files removed on every path; a URL userinfo is visible in ps while curl runs, so send credentials as headers")
fn ! httpRequest! method: String url: String headers: (List (Pair String String)) body: (Option String) connectMs: Int64 totalMs: Int64 -> (Result h/HttpResponse String)
  (requestCore! false method url headers body connectMs totalMs)

; (:m :ref HTTP-CLIENT-INTERIM :do "httpRequest! that also accepts file:// URLs, for tests that need a real curl without a network")
fn ! httpRequestAllowFile! method: String url: String headers: (List (Pair String String)) body: (Option String) connectMs: Int64 totalMs: Int64 -> (Result h/HttpResponse String)
  (requestCore! true method url headers body connectMs totalMs)
