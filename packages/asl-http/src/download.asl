(module asl-http/download
  :x [HttpDownload curlTimeout httpDownload httpHead]
  :i [(asl-proc/process :a proc)])

(schema HttpDownload
  (:f status Int64)
  (:f bytes Int64)
  (:f contentLength Int64)
  (:f sha256 String))

fn curlTimeout timeoutMs: Int64 -> String
  (let [(remainder (- timeoutMs (* (/ timeoutMs 1000) 1000)))
        (ms (stringFromInt64 remainder))]
    (str (stringFromInt64 (/ timeoutMs 1000)) "."
       (cond ((< remainder 10) (str "00" ms))
               ((< remainder 100) (str "0" ms))
               (else ms))))

fn headerInfoLines lines: (List String) status: Int64 length: Int64 -> (Result (Pair Int64 Int64) String)
  (mt (listHead lines)
    ((none) (if (or (<= status 0) (< length 0)) (err "ERR_HTTP_INCOMPLETE_HEADERS") (ok (pair status length))))
    ((some raw)
      (let [(line (stringTrim raw))
            (lower (stringLower (stringTrim raw)))
            (rest (optionOr (listTail lines) (list)))]
        (cond
          ((stringStartsWith? lower "http/")
            (let [(parts (stringSplit line " "))]
              (mt (listGet parts 1)
                ((none) (err "ERR_HTTP_STATUS_HEADER"))
                ((some codeText)
                  (mt (stringToInt64 codeText)
                    ((none) (err "ERR_HTTP_STATUS_HEADER"))
                    ((some code) (headerInfoLines rest code -1)))))))
          ((stringStartsWith? lower "content-length:")
            (mt (stringToInt64 (stringTrim (optionOr (stringSlice line 15 (stringLength line)) "")))
              ((none) (err "ERR_HTTP_CONTENT_LENGTH"))
              ((some n) (headerInfoLines rest status n))))
          (else (headerInfoLines rest status length))))))

fn headerInfo headers: String -> (Result (Pair Int64 Int64) String)
  (headerInfoLines (stringSplit headers "\n") 0 -1)

fn removeIfPresent! path: String -> (Result Unit String)
  (mt (fileStat path)
    ((err e) (if (stringStartsWith? e "notFound") (ok ()) (err e)))
    ((ok _) (pathRemove path)))

fn curl! argv: (List String) -> (Result Int64 String)
  (mt (listHead argv)
    ((none) (err "ERR_CURL_SPAWN: empty argv"))
    ((some bin)
      (mt (proc/exec! (proc/withTimeout (proc/cmd bin (optionOr (listSlice argv 1 (listLength argv)) (list))) 300000))
        ((err e) (err (str "ERR_CURL_SPAWN: " e)))
        ((ok output) (if (= output.exitCode 0) (ok 0)
          (err (str "ERR_HTTP_CURL: " (stringFromInt64 output.exitCode) ": " output.stderr)))))))

fn headCleanupError! headers: String cause: String -> (Result (Pair Int64 Int64) String)
  (mt (removeIfPresent! headers)
    ((err cleanup) (err (str "ERR_HTTP_HEADERS_CLEANUP: " cleanup)))
    ((ok _) (err cause)))

fn downloadCleanupError! tmp: String headers: String cause: String -> (Result HttpDownload String)
  (mt (removeIfPresent! headers)
    ((err cleanup) (err (str "ERR_HTTP_HEADERS_CLEANUP: " cleanup)))
    ((ok _) (mt (removeIfPresent! tmp)
      ((err cleanup) (err (str "ERR_HTTP_TEMP_CLEANUP: " cleanup)))
      ((ok _) (err cause)))))

fn downloadTempCleanupError! tmp: String cause: String -> (Result HttpDownload String)
  (mt (removeIfPresent! tmp)
    ((err cleanup) (err (str "ERR_HTTP_TEMP_CLEANUP: " cleanup)))
    ((ok _) (err cause)))

fn shaFile! path: String -> (Result String String)
  (mt (fileReadBytes path)
    ((err e) (err (str "ERR_SHA256_READ: " e)))
    ((ok bytes) (ok (bytesSha256 bytes))))

fn ! httpHead url: String timeoutMs: Int64 -> (Result (Pair Int64 Int64) String)
  (if (<= timeoutMs 0)
    (err "ERR_TIMEOUT_RANGE")
    (let [(headers (str (optionOr (envGet "TMPDIR") "/tmp") "/asl_http_head_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)) ".headers"))]
      (mt (curl! (list "curl" "-sS" "-I" "-L" "--fail" "--max-time" (curlTimeout timeoutMs)
                       "-D" headers "-o" "/dev/null" "--url" url))
        ((err e) (headCleanupError! headers e))
        ((ok _)
            (mt (fileReadString headers)
              ((err e) (headCleanupError! headers (str "ERR_HTTP_HEADERS: " e)))
              ((ok text)
                (mt (removeIfPresent! headers)
                  ((err e) (err (str "ERR_HTTP_HEADERS_CLEANUP: " e)))
                  ((ok _)
                  (mt (headerInfo text)
                    ((err e) (err e))
                    ((ok info)
                      (if (or (<= (pairFirst info) 0) (< (pairSecond info) 0))
                        (err "ERR_HTTP_INCOMPLETE_HEADERS")
                        (ok info))))))))))))

fn ! httpDownload url: String path: String timeoutMs: Int64 -> (Result HttpDownload String)
  (if (<= timeoutMs 0)
    (err "ERR_TIMEOUT_RANGE")
    (let [(suffix (str (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs))))
          (tmp (str path ".asl-http-" suffix ".part"))
          (headers (str path ".asl-http-" suffix ".headers"))
          (args (list "curl" "-sS" "-L" "--fail" "--max-time" (curlTimeout timeoutMs)
                      "-D" headers "-o" tmp "--url" url))]
      (mt (curl! args)
        ((err e) (downloadCleanupError! tmp headers e))
        ((ok _)
            (let [(headerText (fileReadString headers))
                  (stat (fileStat tmp))]
              (mt (removeIfPresent! headers)
                ((err e) (downloadTempCleanupError! tmp (str "ERR_HTTP_HEADERS_CLEANUP: " e)))
                ((ok _) (mt headerText
                ((err e) (downloadTempCleanupError! tmp (str "ERR_HTTP_HEADERS: " e)))
                ((ok text)
                  (mt stat
                    ((err e) (downloadTempCleanupError! tmp (str "ERR_HTTP_TEMP: " e)))
                    ((ok file)
                      (mt (headerInfo text)
                        ((err e) (downloadTempCleanupError! tmp e))
                        ((ok info)
                          (if (or (<= (pairFirst info) 0) (< (pairSecond info) 0))
                            (downloadTempCleanupError! tmp "ERR_HTTP_INCOMPLETE_HEADERS")
                            (if (!= file.size (pairSecond info))
                              (downloadTempCleanupError! tmp "ERR_HTTP_CONTENT_LENGTH_MISMATCH")
                              (mt (shaFile! tmp)
                                ((err e) (downloadTempCleanupError! tmp e))
                                ((ok hash)
                                  (mt (pathRename tmp path)
                                    ((err e) (downloadTempCleanupError! tmp (str "ERR_HTTP_RENAME: " e)))
                                    ((ok _) (ok (HttpDownload :status (pairFirst info) :bytes file.size
                                                               :contentLength (pairSecond info) :sha256 hash)))))))))))))))))))))
