(module asl-http/tests/downloadTest
  :x [runTests main]
  :i [(asl-http/download :a d)])

fn ! writeAll fd: Int64 data: String offset: Int64 -> (Result Unit String)
  (if (>= offset (stringLength data)) (ok ())
    (mt (fdWrite fd (optionOr (stringSlice data offset (stringLength data)) ""))
      ((err e) (err e))
      ((ok n) (if (<= n 0) (err "ERR_WRITE_ZERO") (writeAll fd data (+ offset n))))))

fn ! responseBody mode: String -> String
  (if (= mode "small") "small" (if (= mode "cut") (stringRepeat "0123456789abcdef" 98304) (stringRepeat "0123456789abcdef" 196608)))

fn ! serveRedirect port: Int64 -> (Result Int64 String)
  (mt (tcpListen port)
    ((err e) (err e))
    ((ok listener)
      (fdWrite 1 "READY\n")
      (mt (sockAccept listener)
        ((err e) (do (fdClose listener) (err e)))
        ((ok first)
          (do
            (fdRead first 4096)
            (writeAll first (str "HTTP/1.1 302 Found\r\nContent-Length: 3145728\r\nLocation: http://127.0.0.1:" (stringFromInt64 port) "/final\r\nConnection: close\r\n\r\n") 0)
            (fdClose first)
            (mt (sockAccept listener)
              ((err e) (do (fdClose listener) (err e)))
              ((ok final)
                (do
                  (fdRead final 4096)
                  (writeAll final "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" 0)
                  (fdClose final)
                  (fdClose listener)
                  (ok 0)))))))))

fn ! serve mode: String port: Int64 -> (Result Int64 String)
  (mt (tcpListen port)
    ((err e) (err e))
    ((ok listener)
      (fdWrite 1 "READY\n")
      (mt (sockAccept listener)
                ((err e) (do (fdClose listener) (err e)))
                ((ok client)
                  (do
                    (fdRead client 4096)
                    (cond
                      ((= mode "slow") (do (sleepMs 500) (writeAll client "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nsmall" 0)))
                      ((= mode "keepalive") (do (writeAll client "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nsmall" 0) (sleepMs 500)))
                      ((= mode "head") (writeAll client "HTTP/1.1 200 OK\r\nContent-Length: 3145728\r\nConnection: close\r\n\r\n" 0))
                      ((= mode "missing") (writeAll client "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" 0))
                      ((= mode "noheaders") (writeAll client "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nsmall" 0))
                      ((= mode "mismatch") (writeAll client "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n5\r\nsmall\r\n0\r\n\r\n" 0))
                      ((= mode "cut")
                        (let [(body (responseBody mode))]
                          (writeAll client (str "HTTP/1.1 200 OK\r\nContent-Length: 3145728\r\nConnection: close\r\n\r\n" (optionOr (stringSlice body 0 1572864) "")) 0)))
                      (else
                        (let [(body (responseBody mode))]
                          (writeAll client (str "HTTP/1.1 200 OK\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body) 0))))
                    (fdClose client)
                    (fdClose listener)
                    (ok 0))))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (listHead args)
    ((some mode) (if (= mode "server")
      (mt (listGet args 1) ((some behavior) (mt (listGet args 2) ((some p) (mt (stringToInt64 p) ((some port) (if (= behavior "redirect") (serveRedirect port) (serve behavior port))) ((none) (err "ERR_TEST_SERVER_MODE")))) ((none) (err "ERR_TEST_SERVER_MODE")))) ((none) (err "ERR_TEST_SERVER_MODE")))
      (err "ERR_TEST_SERVER_MODE")))
    ((none) (err "ERR_TEST_SERVER_MODE")))

fn ! startServer mode: String -> (Result (Pair SpawnedProc Int64) String)
  (let [(ticks (/ (nowNs) 1000))
        (port (+ 30000 (- ticks (* (/ ticks 30000) 30000))))]
   (mt (procSpawnv (list "./asl/host/out/asl-host" "run" "asl/packages/asl-http/tests/downloadTest.asl" "server" mode (stringFromInt64 port)) (some ".") (none))
    ((err e) (err (str "ERR_TEST_SERVER_SPAWN: " e)))
    ((ok sp)
      (do
        (fdClose sp.stdin)
        (mt (fdRead sp.stdout 6)
          ((err e) (err (str "ERR_TEST_SERVER_READY: " e)))
          ((ok ready)
            (do
              (fdClose sp.stdout)
              (fdClose sp.stderr)
              (if (= ready "READY\n") (ok (pair sp port))
                (mt (procWaitPid sp.pid false)
                  ((err e) (err (str "ERR_TEST_SERVER_WAIT: " e)))
                  ((ok _) (err (str "ERR_TEST_SERVER_NOT_READY: " ready))))))))))))

fn ! finishServer sp: SpawnedProc -> (Result Int64 String)
  (mt (procWaitPid sp.pid false)
      ((err e) (err e))
      ((ok status) (mt status ((some code) (ok code)) ((none) (err "ERR_TEST_SERVER_EXIT")))))

fn ! noDownloadArtifacts! path: String -> Bool
  (noArtifactsIn! "/tmp/" path)

fn ! noArtifactsIn! root: String pattern: String -> Bool
  (mt (procSpawnv (list "find" root "-maxdepth" "1" "-path" (str pattern ".asl-http-*") "-print") (none) (none))
    ((err e) (do (assert false (str "find download artifacts: " e)) false))
    ((ok sp)
      (do
        (fdClose sp.stdin)
        (fdClose sp.stderr)
        (mt (procWaitPid sp.pid false)
          ((err e) (do (fdClose sp.stdout) (assert false (str "wait for artifact scan: " e)) false))
          ((ok status)
            (mt status
              ((none) (do (fdClose sp.stdout) (assert false "artifact scan has no exit status") false))
              ((some code)
                (if (!= code 0)
                  (do (fdClose sp.stdout) (assert false (str "artifact scan exits: " (stringFromInt64 code))) false)
                  (mt (fdRead sp.stdout 4096)
                    ((err e) (do (fdClose sp.stdout) (assert false (str "read artifact scan: " e)) false))
                    ((ok output)
                      (do
                        (fdClose sp.stdout)
                        (= (stringTrim output) ""))))))))))))

fn ! testArtifactScanDetectsLeftovers! -> Bool
  (let [(path (str "/tmp/asl_http_scan_" (stringFromInt64 (nowNs))))
        (artifact (str path ".asl-http-test"))]
    (mt (fileWrite artifact "leftover")
      ((err e) (do (assert false (str "create artifact scan fixture: " e)) false))
      ((ok _)
        (let [(detected (not (noDownloadArtifacts! path)))]
          (mt (pathRemove artifact)
            ((err e) (do (assert false (str "remove artifact scan fixture: " e)) false))
            ((ok _) (do (assert detected "artifact scan detects a matching temporary file") true)))))))

fn ! testBodyDownload! -> Bool
  (mt (startServer "body")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server))
            (port (pairSecond server))
            (path (str "/tmp/asl_http_download_" (stringFromInt64 (nowNs)) ".csv.gz"))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/archive") path 10000))]
        (mt (finishServer sp) ((err e) (assert false (str "server exit: " e))) ((ok code) (assert (= code 0) (str "body server exits cleanly: " (stringFromInt64 code)))))
        (mt result
          ((err e) (do (assert false (str "body download: " e)) false))
          ((ok file)
            (let [(bytes (fileReadBytes path))]
              (pathRemove path)
              (assert (= file.status 200) "HTTP status is 200")
              (assert (= file.bytes 3145728) "downloaded byte count is 3 MiB")
              (assert (= file.bytes file.contentLength) "bytes equal Content-Length")
              (assert (noDownloadArtifacts! path) "successful body download removes temporary files")
              (assert (mt bytes ((ok b) (= (bytesSha256 b) file.sha256)) ((err _) false)) "reported SHA-256 matches downloaded file")
              true))))))

fn ! testDashPathDownload! -> Bool
  (mt (startServer "small")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (name (str "-asl_http_dash_" (stringFromInt64 (nowNs))))
            (path name)
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/small") path 3000))]
        (mt (finishServer sp)
          ((err e) (assert false (str "dash-path server wait: " e)))
          ((ok code) (assert (= code 0) (str "dash-path server exits cleanly: " (stringFromInt64 code)))))
        (mt result
          ((err e) (do (assert false (str "dash-path download: " e)) false))
          ((ok file)
            (let [(bytes (fileReadString path))]
              (pathRemove path)
              (assert (= file.contentLength 5) "dash-path Content-Length is five")
              (assert (mt bytes ((ok body) (= body "small")) ((err _) false)) "dash-path body is intact")
              (assert (noArtifactsIn! "." (str "./" path)) "successful dash-path download removes temporary files")
              true))))))

fn ! testKeepAliveDownload! -> Bool
  (mt (startServer "keepalive")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (path (str "/tmp/asl_http_keepalive_" (stringFromInt64 (nowNs))))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/keepalive") path 200))]
        (mt (finishServer sp)
          ((err e) (assert false (str "keep-alive server wait: " e)))
          ((ok code) (assert (= code 0) (str "keep-alive server exits cleanly: " (stringFromInt64 code)))))
        (mt result
          ((err e) (do (assert false (str "keep-alive download: " e)) false))
          ((ok file)
            (let [(bytes (fileReadString path))]
              (pathRemove path)
              (assert (= file.contentLength 5) "keep-alive Content-Length is five")
              (assert (mt bytes ((ok body) (= body "small")) ((err _) false)) "keep-alive body is intact")
              (assert (noDownloadArtifacts! path) "successful keep-alive download removes temporary files")
              true))))))

fn ! testCurlTimeoutFormat! -> Bool
  (do
    (assert (= (d/curlTimeout 1000) "1.000") "1000 ms formats as 1.000 s")
    (assert (= (d/curlTimeout 1500) "1.500") "1500 ms formats as 1.500 s")
    (assert (= (d/curlTimeout 1005) "1.005") "1005 ms pads to 1.005 s")
    (assert (= (d/curlTimeout 12345) "12.345") "12345 ms formats as 12.345 s")
    (assert (= (d/curlTimeout 200) "0.200") "200 ms formats as 0.200 s")
    (assert (= (d/curlTimeout 10) "0.010") "10 ms pads to 0.010 s")
    true)

fn ! testUrlOption! -> Bool
  (mt (d/httpHead "--help" 1000)
    ((err e)
      (do
        (assert (stringContains? e "ERR_HTTP_CURL") "URL beginning with option syntax is passed as a URL")
        true))
    ((ok _) (do (assert false "option-looking URL is not executed as curl help") false)))

fn ! testClosedPortHead! -> Bool
  (mt (d/httpHead "http://127.0.0.1:1/asl-http-closed-port" 1000)
    ((err e)
      (do
        (assert (stringContains? e "ERR_HTTP_CURL") "closed-port HEAD returns a curl error instead of crashing")
        true))
    ((ok _) (do (assert false "closed-port HEAD unexpectedly succeeded") false)))

fn ! noHeadArtifacts! -> Bool
  (let [(root (optionOr (envGet "TMPDIR") "/tmp"))
        (pattern (str "asl_http_head_" (stringFromInt64 (procSelf)) "_*.headers"))]
    (mt (procSpawnv (list "find" root "-maxdepth" "1" "-name" pattern "-print") (none) (none))
      ((err e) (do (assert false (str "spawn HEAD artifact scan: " e)) false))
      ((ok sp)
        (do
          (fdClose sp.stdin)
          (fdClose sp.stderr)
          (mt (procWaitPid sp.pid false)
            ((err e) (do (fdClose sp.stdout) (assert false (str "wait for HEAD artifact scan: " e)) false))
            ((ok status)
              (mt status
                ((none) (do (fdClose sp.stdout) (assert false "HEAD artifact scan has no exit status") false))
                ((some code)
                  (if (!= code 0)
                    (do (fdClose sp.stdout) (assert false (str "HEAD artifact scan exits: " (stringFromInt64 code))) false)
                    (mt (fdRead sp.stdout 4096)
                      ((err e) (do (fdClose sp.stdout) (assert false (str "read HEAD artifact scan: " e)) false))
                      ((ok output)
                        (do
                          (fdClose sp.stdout)
                          (= (stringTrim output) "")))))))))))))

fn ! testHead! -> Bool
  (mt (startServer "head")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (result (d/httpHead (str "http://127.0.0.1:" (stringFromInt64 port) "/archive") 3000))]
        (mt (finishServer sp) ((err e) (assert false (str "head server exit: " e))) ((ok code) (assert (= code 0) (str "head server exits cleanly: " (stringFromInt64 code)))))
        (mt result
          ((err e) (do (assert false (str "HEAD request: " e)) false))
          ((ok info)
            (assert (= (pairFirst info) 200) "HEAD status is 200")
            (assert (= (pairSecond info) 3145728) "HEAD Content-Length is 3 MiB")
            (assert (noHeadArtifacts!) "HEAD removes its temporary headers file")
            true)))))

fn ! testSmallDownload! -> Bool
  (mt (startServer "small")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (path (str "/tmp/asl_http_small_" (stringFromInt64 (nowNs))))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/small") path 3000))]
        (mt (finishServer sp)
          ((err e) (assert false (str "small server wait: " e)))
          ((ok code) (assert (= code 0) (str "small server exits cleanly: " (stringFromInt64 code)))))
        (mt result
          ((err e) (assert false (str "small download: " e)))
          ((ok file)
            (let [(bytes (fileReadString path))]
              (pathRemove path)
              (assert (= file.contentLength 5) "small response length is reported, not a fixed 3 MiB")
              (assert (mt bytes ((ok body) (= body "small")) ((err _) false)) "small response body is intact")
              (assert (noDownloadArtifacts! path) "successful small download removes temporary files")
              true))))))

fn ! testRedirect! -> Bool
  (mt (startServer "redirect")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (result (d/httpHead (str "http://127.0.0.1:" (stringFromInt64 port) "/redirect") 3000))]
        (mt (finishServer sp)
          ((err e) (assert false (str "redirect server wait: " e)))
          ((ok code) (assert (= code 0) (str "redirect server exits cleanly: " (stringFromInt64 code)))))
        (mt result
          ((err e) (assert (stringContains? e "ERR_HTTP_INCOMPLETE_HEADERS") "redirect Content-Length does not leak into final response"))
          ((ok _) (assert false "redirect without final Content-Length must not reuse redirect length")))
        true)))

fn ! testFailures! -> Bool
  (do
  (mt (startServer "missing")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (path (str "/tmp/asl_http_404_" (stringFromInt64 (nowNs))))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/missing") path 3000))]
        (mt (finishServer sp)
          ((err e) (assert false (str "404 server wait: " e)))
          ((ok code) (assert (= code 0) (str "404 server exits cleanly: " (stringFromInt64 code)))))
        (assert (err? result) "404 is an Err with curl fail enabled")
        (assert (mt result ((err e) (stringContains? e "The requested URL returned error: 404")) ((ok _) false)) "curl failure retains its complete stderr cause")
        (assert (err? (fileStat path)) "404 leaves no destination file")
        (assert (noDownloadArtifacts! path) "404 removes temporary download files")
        true)))
  (mt (startServer "cut")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (path (str "/tmp/asl_http_truncated_" (stringFromInt64 (nowNs))))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/cut") path 3000))]
        (mt (finishServer sp)
          ((err e) (assert false (str "cut server wait: " e)))
          ((ok code) (assert (= code 0) (str "cut server exits cleanly: " (stringFromInt64 code)))))
        (assert (err? result) "truncated Content-Length is Err")
        (assert (err? (fileStat path)) "truncated download leaves no destination file")
        (assert (noDownloadArtifacts! path) "truncated download removes temporary files")
        true)))
  (mt (startServer "slow")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (path (str "/tmp/asl_http_timeout_" (stringFromInt64 (nowNs))))
            (started (nowNs))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/slow") path 100))
            (elapsed (- (nowNs) started))]
        (mt (finishServer sp)
          ((err e) (assert false (str "timeout server wait: " e)))
          ((ok code) (assert (= code 0) (str "timeout server exits cleanly: " (stringFromInt64 code)))))
        (assert (err? result) "100 ms request timeout is Err")
        (assert (< elapsed 450000000) "100 ms timeout completes before the 500 ms server response")
        (assert (err? (fileStat path)) "timeout leaves no destination file")
        (assert (noDownloadArtifacts! path) "timeout removes temporary download files")
        true))))

fn ! testContentLengthMismatch! -> Bool
  (mt (startServer "mismatch")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (path (str "/tmp/asl_http_mismatch_" (stringFromInt64 (nowNs))))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/mismatch") path 3000))]
        (mt (finishServer sp)
          ((err e) (assert false (str "mismatch server wait: " e)))
          ((ok code) (assert (= code 0) (str "mismatch server exits cleanly: " (stringFromInt64 code)))))
        (assert (err? result) "mismatched Content-Length is rejected after curl succeeds")
        (assert (mt result ((err e) (stringContains? e "ERR_HTTP_CONTENT_LENGTH_MISMATCH")) ((ok _) false)) "mismatch reports Content-Length error")
        (assert (err? (fileStat path)) "mismatch leaves no destination file")
        (assert (noDownloadArtifacts! path) "mismatch removes temporary download files")
        true)))

fn ! testMissingHeadersCleanup! -> Bool
  (mt (startServer "noheaders")
    ((err e) (do (assert false e) false))
    ((ok server)
      (let [(sp (pairFirst server)) (port (pairSecond server))
            (path (str "/tmp/asl_http_noheaders_" (stringFromInt64 (nowNs))))
            (result (d/httpDownload (str "http://127.0.0.1:" (stringFromInt64 port) "/noheaders") path 3000))]
        (mt (finishServer sp)
          ((err e) (assert false (str "no-headers server wait: " e)))
          ((ok code) (assert (= code 0) (str "no-headers server exits cleanly: " (stringFromInt64 code)))))
        (assert (err? result) "missing response headers are rejected after curl succeeds")
        (assert (mt result ((err e) (stringContains? e "ERR_HTTP_INCOMPLETE_HEADERS")) ((ok _) false)) "missing headers report incomplete headers")
        (assert (err? (fileStat path)) "missing headers leave no destination file")
        (assert (noDownloadArtifacts! path) "missing headers remove temporary download files")
        true)))

fn ! runTests -> Bool
  (do
    (assert (testClosedPortHead!) "curl stderr Result is handled on a failed HEAD request")
    (assert (testArtifactScanDetectsLeftovers!) "artifact scan detects leftovers")
    (assert (testHead!) "HEAD returns status and Content-Length")
    (assert (testSmallDownload!) "non-fixed Content-Length download")
    (assert (testRedirect!) "redirect headers reset per response")
    (assert (testBodyDownload!) "3 MiB download is exact and hashed")
    (assert (testDashPathDownload!) "sha256sum accepts a destination beginning with a dash")
    (assert (testKeepAliveDownload!) "Content-Length completes a keep-alive download without waiting for close")
    (assert (testCurlTimeoutFormat!) "curl timeout seconds formatting")
    (assert (testUrlOption!) "curl receives option-looking input as URL data")
    (assert (testFailures!) "HTTP and transport failures are rejected and cleaned")
    (assert (testContentLengthMismatch!) "complete body with mismatched Content-Length is rejected and cleaned")
    (assert (testMissingHeadersCleanup!) "curl success with missing headers is rejected and cleaned")
    true)
