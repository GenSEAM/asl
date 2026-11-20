(module asl-http/tests/clientTest
  :x [runTests]
  :i [(asl-http/client :a c) (asl-http/http11 :a h) (asl-tools/fleet/run :a fr)])

; (:m :ref HTTP-CLIENT-INTERIM :do "interim curl client without network: argv per method as a pure fn, canned curl --include output (100 Continue, redirect hops, HEAD blocks), a real curl on file:// and on a closed loopback port 127.0.0.1:1, secrets never in an err, argument errs; the temporary body file is removed")

fn contains? xs: (List String) x: String -> Bool
  (listContains? xs x)

fn hdrs -> (List (Pair String String))
  (list (pair "Authorization" "Bearer s3cr3tTOKEN") (pair "Content-Type" "application/json"))

fn errText r: (Result h/HttpResponse String) -> String
  (match r ((err e) e) ((ok _) ""))

fn testArgv -> Bool
  (let [(get (c/httpRequestArgv "GET" "http://x.test/a" (hdrs) "/tmp/h" (none) "/tmp/d" "/tmp/o" false 2000 10500))
        (head (c/httpRequestArgv "HEAD" "http://x.test/a" (list) "/tmp/h" (none) "/tmp/d" "/tmp/o" false 2000 10500))
        (post (c/httpRequestArgv "POST" "http://x.test/a" (hdrs) "/tmp/h" (some "/tmp/b") "/tmp/d" "/tmp/o" false 2000 10500))
        (del (c/httpRequestArgv "DELETE" "http://x.test/a" (list) "/tmp/h" (none) "/tmp/d" "/tmp/o" false 2000 10500))]
    (do
      (assert (= (listGet get 0) (some "curl")) "argv starts with curl")
      (assert (and (contains? get "-D") (contains? get "/tmp/d")) "response headers dumped by -D")
      (assert (and (contains? get "-o") (contains? get "/tmp/o")) "body written by -o")
      (assert (not (contains? get "--include")) "no --include, curl output is not parsed")
      (assert (= (listGet get 1) (some "-q")) "-q is the first option")
      (assert (contains? get "=http,https") "only http and https by default")
      (assert (contains? (c/httpRequestArgv "GET" "file:///x" (list) "/tmp/h" (none) "/tmp/d" "/tmp/o" true 1000 1000) "=http,https,file") "file only when allowed")
      (assert (contains? get "-L") "GET follows redirects")
      (assert (not (contains? get "-X")) "GET has no -X")
      (assert (contains? get "10.500") "--max-time from 10500 ms is 10.500")
      (assert (contains? get "2.000") "--connect-timeout from 2000 ms is 2.000")
      (assert (contains? get "-H") "headers by -H")
      (assert (contains? get "@/tmp/h") "-H reads the header file")
      (assert (not (listAny? (fn [(a String)] -> Bool (or (stringContains? a "s3cr3tTOKEN") (or (stringContains? a "Authorization") (stringContains? a "application/json")))) get)) "argv holds no header name or value")
      (assert (not (listAny? (fn [(a String)] -> Bool (stringContains? a "s3cr3tTOKEN")) post)) "POST argv holds no header value")
      (assert (= (listLast get) (some "http://x.test/a")) "URL is last")
      (assert (= (listGet get (- (listLength get) 2)) (some "--url")) "URL follows --url")
      (assert (contains? head "--head") "HEAD uses --head")
      (assert (not (contains? head "-X")) "HEAD has no -X")
      (assert (contains? post "POST") "POST names the method")
      (assert (not (contains? post "-L")) "POST does not follow redirects")
      (assert (contains? post "@/tmp/b") "body by file reference")
      (assert (contains? post "--data-binary") "body is --data-binary")
      (assert (contains? del "DELETE") "DELETE names the method")
      (assert (not (contains? del "-L")) "DELETE does not follow redirects")
      true))

fn testCanned -> Bool
  (let [(cont (c/httpReplyFromCurl "POST" "http://x.test/" "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 201 Created\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\nX-A: 1\r\nX-A: 2\r\n\r\n" "ok"))
        (redir (c/httpReplyFromCurl "GET" "http://x.test/" "HTTP/1.1 301 Moved\r\nLocation: /b\r\n\r\nHTTP/2 200\r\nContent-Length: 3\r\n\r\n" "end"))
        (head (c/httpReplyFromCurl "HEAD" "http://x.test/" "HTTP/1.1 200 OK\r\nContent-Length: 99\r\nETag: \"q\"\r\n\r\n" "ignored"))
        (junk (c/httpReplyFromCurl "GET" "http://x.test/" "not http at all" ""))
        (empty (c/httpReplyFromCurl "GET" "http://x.test/" "" "body"))]
    (do
      (match cont
        ((ok r) (do
          (assert (= r.statusCode 201) "100 Continue is skipped, status is 201")
          (assert (= r.reasonPhrase "Created") "reason phrase")
          (assert (= r.body "ok") "the body file is returned as is, not decoded again")
          (assert (= (optionOr (h/getHeaderFromHeaders r.headers "content-type") "") "text/plain") "header lookup is case-insensitive")
          (assert (= (listLength (filter (fn [(p (Pair String String))] -> Bool (= (stringLower (pairFirst p)) "x-a")) r.headers.entries)) 2) "duplicate headers kept")))
        ((err e) (assert false (str "canned continue: " e))))
      (match redir
        ((ok r) (do (assert (= r.statusCode 200) "last hop after a redirect") (assert (= r.body "end") "last hop body")))
        ((err e) (assert false (str "canned redirect: " e))))
      (match head
        ((ok r) (do (assert (= r.statusCode 200) "HEAD status") (assert (= r.body "") "HEAD has no body") (assert (= (optionOr (h/getHeaderFromHeaders r.headers "etag") "") "\"q\"") "HEAD headers")))
        ((err e) (assert false (str "canned head: " e))))
      (assert (stringStartsWith? (errText junk) "ERR_HTTP_") "garbage is an ERR_HTTP_ err")
      (assert (stringStartsWith? (errText empty) "ERR_HTTP_") "empty header dump is an ERR_HTTP_ err")
      true))

fn testRedact -> Bool
  (let [(e (c/httpCurlError 7 "curl: (7) Failed to connect Bearer s3cr3tTOKEN user:pw@host\n" "http://user:pw@host/p" (hdrs)))]
    (do
      (assert (stringStartsWith? e "ERR_HTTP_CURL_7: ") "err names curl's code")
      (assert (not (stringContains? e "s3cr3tTOKEN")) "header value is redacted")
      (assert (not (stringContains? e "user:pw")) "URL userinfo is redacted")
      (assert (stringContains? e "<redacted>") "redaction is visible")
      true))

fn testFile -> Bool
  (let [(path (str (optionOr (envGet "TMPDIR") "/tmp") "/asl_http_client_file_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))]
    (match (fileWrite path "file body 123")
      ((err e) (do (assert false (str "fixture: " e)) false))
      ((ok _)
        (let [(ok1 (c/httpRequestAllowFile! "GET" (str "file://" path) (list) (none) 2000 5000))
              (miss (c/httpRequestAllowFile! "GET" (str "file://" path ".gone") (list) (none) 2000 5000))]
          (do
            (pathRemove path)
            (match ok1
              ((ok r) (do (assert (= r.statusCode 200) "file:// GET status") (assert (= r.body "file body 123") "file:// GET body")))
              ((err e) (assert false (str "file GET: " e))))
            (assert (stringStartsWith? (errText miss) "ERR_HTTP_CURL_37: ") "missing file is curl code 37")
            true)))))

fn testClosedPort -> Bool
  (let [(get (c/httpRequest! "GET" "http://127.0.0.1:1/x" (hdrs) (none) 2000 5000))
        (post (c/httpRequest! "POST" "http://127.0.0.1:1/x" (hdrs) (some "{\"k\":1}") 2000 5000))]
    (do
      (assert (stringStartsWith? (errText get) "ERR_HTTP_CURL_7: ") "refused connection is curl code 7")
      (assert (stringStartsWith? (errText post) "ERR_HTTP_CURL_7: ") "POST with a body fails as an err too")
      (assert (not (stringContains? (errText post) "s3cr3tTOKEN")) "no secret in a transport err")
      true))

fn testArguments -> Bool
  (do
    (assert (stringStartsWith? (errText (c/httpRequest! "GET" "file:///etc/hosts" (list) (none) 1000 1000)) "ERR_HTTP_ARGUMENT") "file:// is refused by httpRequest!")
    (assert (stringStartsWith? (errText (c/httpRequest! "get" "http://x/" (list) (none) 1000 1000)) "ERR_HTTP_ARGUMENT") "lowercase method rejected")
    (assert (stringStartsWith? (errText (c/httpRequest! "GET" "" (list) (none) 1000 1000)) "ERR_HTTP_ARGUMENT") "empty URL rejected")
    (assert (stringStartsWith? (errText (c/httpRequest! "GET" "http://x/" (list (pair "A" "v\r\nX: y")) (none) 1000 1000)) "ERR_HTTP_ARGUMENT") "header injection rejected")
    (assert (stringStartsWith? (errText (c/httpRequest! "GET" "http://x/" (list (pair "A B" "v")) (none) 1000 1000)) "ERR_HTTP_ARGUMENT") "blank in header name rejected")
    (assert (= (errText (c/httpRequest! "GET" "http://x/" (list) (none) 0 1000)) "ERR_TIMEOUT_RANGE") "zero connect timeout rejected")
    true)

fn leftovers -> Int64
  (let [(prefix (str "asl_http_req_" (stringFromInt64 (procSelf)) "_"))]
    (listLength (filter (fn [(n String)] -> Bool (stringStartsWith? n prefix)) (resultOr (dirList (optionOr (envGet "TMPDIR") "/tmp")) (list)))))

fn testPrivateFiles -> Bool
  (let [(path (str (optionOr (envGet "TMPDIR") "/tmp") "/asl_http_priv_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (w (c/httpWritePrivate! path "secret"))]
    (match (fileStat path)
      ((err e) (do (pathRemove path) (assert false (str "stat private file: " e)) false))
      ((ok st) (do
        (assert (= (& st.mode 511) 384) "private file mode is exactly 0600")
        (assert (match (fileReadString path) ((ok t) (= t "secret")) ((err _) false)) "private file holds the content")
        (assert (= (c/httpHeaderFileText (hdrs)) "Authorization: Bearer s3cr3tTOKEN\nContent-Type: application/json\n") "header file text is one line per header")
        (pathRemove path)
        true))))

fn testCleanup -> Bool
  (let [(before (leftovers))
        (okFile (c/httpRequestAllowFile! "GET" (str "file://" "/etc/hosts") (hdrs) (none) 2000 5000))
        (afterOk (leftovers))
        (bad (c/httpRequest! "POST" "http://127.0.0.1:1/x" (hdrs) (some "payload") 2000 5000))
        (afterErr (leftovers))
        (argErr (c/httpRequest! "get" "http://x/" (hdrs) (some "p") 1000 1000))
        (afterArg (leftovers))]
    (do
      (assert (= before 0) "no temp files before")
      (assert (match okFile ((ok _) true) ((err _) false)) "request with headers succeeds on file://")
      (assert (= afterOk 0) "header and body files removed after success")
      (assert (stringStartsWith? (errText bad) "ERR_HTTP_CURL_7") "failing request is an err")
      (assert (= afterErr 0) "header and body files removed after a curl error")
      (assert (stringStartsWith? (errText argErr) "ERR_HTTP_ARGUMENT") "argument err")
      (assert (= afterArg 0) "no files left after an argument err")
      true))

; (:m :ref HTTP-CLIENT-INTERIM :do "loopback fixture: the parent binds the listener, forks a bounded child (fleet run forkLimited!, own process group, 20 s limit, killed in the end) that accepts connections in order and answers each with the canned reply; parent and child never touch the network beyond 127.0.0.1")
fn ! writeAll fd: Int64 data: String -> Bool
  (match (fdWrite fd data) ((err _) false) ((ok _) true))

fn ! answer! listener: Int64 reply: String -> Bool
  (match (sockAccept listener)
    ((err _) false)
    ((ok conn) (do (fdRead conn 4096) (writeAll conn reply) (fdClose conn) true)))

fn ! serveAll! listener: Int64 replies: (List String) -> Int64
  (do (map (fn [(r String)] -> Bool (answer! listener r)) replies) (fdClose listener) 0)

fn ! withServer! replies: (List String) port: Int64 body: (fn [] -> Bool) -> Bool
  (match (tcpListen port)
    ((err e) (do (assert false (str "fixture listen: " e)) false))
    ((ok listener)
      (match (fr/forkLimited! (str (optionOr (envGet "TMPDIR") "/tmp") "/asl_http_fixture_" (stringFromInt64 port) ".log") (fr/limits 20 4) (fn [] -> Int64 (serveAll! listener replies)))
        ((err e) (do (fdClose listener) (assert false (str "fixture fork: " e)) false))
        ((ok child)
          (let [(_ (fdClose listener))
                (ran (body))
                (_ (fr/forkKill! child "testEnd"))]
            (do (pathRemove (str (optionOr (envGet "TMPDIR") "/tmp") "/asl_http_fixture_" (stringFromInt64 port) ".log")) ran))))))

fn fixturePort offset: Int64 -> Int64
  (let [(ticks (/ (nowNs) 1000))]
    (+ 31000 (+ offset (- ticks (* (/ ticks 20000) 20000)))))

fn testChunked -> Bool
  (let [(port (fixturePort 0))
        (url (str "http://127.0.0.1:" (stringFromInt64 port) "/c"))
        (chunked "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")]
    (withServer! (list chunked) port
      (fn [] -> Bool
        (match (c/httpRequest! "GET" url (list) (none) 2000 8000)
          ((ok r) (do (assert (= r.statusCode 200) "chunked response status") (assert (= r.body "hello world") "chunked body is complete once") true))
          ((err e) (do (assert false (str "chunked GET: " e)) false))))))

fn testChunkedRedirect -> Bool
  (let [(port (fixturePort 100))
        (base (str "http://127.0.0.1:" (stringFromInt64 port)))
        (hop (str "HTTP/1.1 301 Moved\r\nLocation: " base "/final\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n3\r\nold\r\n0\r\n\r\n"))
        (fin "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nX-Hop: last\r\nConnection: close\r\n\r\n4\r\nlast\r\n0\r\n\r\n")]
    (withServer! (list hop fin) port
      (fn [] -> Bool
        (match (c/httpRequest! "GET" (str base "/start") (list) (none) 2000 8000)
          ((ok r) (do (assert (= r.statusCode 200) "redirect then chunked: last status") (assert (= r.body "last") "redirect then chunked: last body") (assert (= (optionOr (h/getHeaderFromHeaders r.headers "x-hop") "") "last") "headers are the last hop's") true))
          ((err e) (do (assert false (str "chunked redirect: " e)) false))))))

fn testGetBodyRejected -> Bool
  (do
    (assert (stringStartsWith? (errText (c/httpRequest! "GET" "http://127.0.0.1:1/" (list) (some "x") 1000 1000)) "ERR_HTTP_ARGUMENT") "GET with a body is rejected")
    (assert (stringStartsWith? (errText (c/httpRequest! "HEAD" "http://127.0.0.1:1/" (list) (some "x") 1000 1000)) "ERR_HTTP_ARGUMENT") "HEAD with a body is rejected")
    true)

fn testSymlinkRefused -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/asl_http_sym_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
        (target (str base ".target"))
        (link (str base ".link"))
        (_ (fileWrite target "untouched"))
        (_ (pathSymlink target link))
        (w (c/httpWritePrivate! link "overwritten"))
        (after (fileReadString target))
        (again (c/httpWritePrivate! target "second"))]
    (do
      (pathRemove link)
      (pathRemove target)
      (assert (match w ((err _) true) ((ok _) false)) "a symlink at the name is an err")
      (assert (match after ((ok t) (= t "untouched")) ((err _) false)) "the symlink target is not touched")
      (assert (match again ((err _) true) ((ok _) false)) "an existing file is an err (O_EXCL)")
      true))

fn ! runTests -> Bool
  (do
    (assert (testArgv) "argv per method")
    (assert (testCanned) "canned curl --include output")
    (assert (testRedact) "secrets redacted")
    (assert (testFile) "real curl on file://")
    (assert (testClosedPort) "real curl on a closed loopback port")
    (assert (testArguments) "argument errs")
    (assert (testChunked) "chunked response over loopback")
    (assert (testChunkedRedirect) "301 then chunked over loopback")
    (assert (testGetBodyRejected) "GET and HEAD reject a body")
    (assert (testSymlinkRefused) "O_EXCL private files")
    (assert (testPrivateFiles) "0600 temp files")
    (assert (testCleanup) "temp files removed on every path")
    true)
