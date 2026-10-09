(module aslWebApiSearch/commonCrawl
  :x [CcCapture CcRecord ccByteTable ccLatestCrawl! ccLookup! ccBuildLookupArgs ccRunCurl! rfc3986Encode ccParseCdxLines ccFetchRaw! ccGunzip! ccParseWarc ccFetch! ccQuoteInPage?]
  :i [(asl-json/json :a j)
      (asl-zip/gzip :a gz)
      (asl-proc/coreProcess :a proc)])

(schema CcCapture
  (:f crawl String)
  (:f url String)
  (:f timestamp String)
  (:f status Int64)
  (:f mime String)
  (:f digest String)
  (:f filename String)
  (:f offset Int64)
  (:f length Int64))

(schema CcRecord
  (:f targetUri String)
  (:f warcDate String)
  (:f httpStatus Int64)
  (:f contentType String)
  (:f htmlBody String))

fn jsonGetString obj: j/Json key: String -> String
  (mt (j/jsonGet obj key)
    ((some v)
     (mt v
       ((j/jstr s) s)
       (_ "")))
    ((none) ""))

fn jsonGetInt64 obj: j/Json key: String -> Int64
  (mt (j/jsonGet obj key)
    ((some v)
     (mt v
       ((j/jint i) i)
       ((j/jstr s) (optionOr (stringToInt64 s) 0))
       (_ 0)))
    ((none) 0))

fn parseCdxLineItem line: String crawl: String -> (Result (Option CcCapture) String)
  (let [(cleanLine (stringTrim line))]
    (if (stringEmpty? cleanLine)
      (ok (none))
      (mt (j/jsonParse cleanLine)
        ((err e) (err (str "CDX JSON parse error: " e)))
        ((ok obj)
         (mt (j/jsonGet obj "message")
           ((some m)
            (let [(msg (mt m
                         ((j/jstr s) s)
                         (_ "CDX server error")))]
              (err msg)))
           ((none)
            (mt (j/jsonGet obj "error")
              ((some er)
               (let [(msg (mt er
                            ((j/jstr s) s)
                            (_ "CDX server error")))]
                 (err msg)))
              ((none)
               (ok (some (CcCapture
                           :crawl crawl
                           :url (jsonGetString obj "url")
                           :timestamp (jsonGetString obj "timestamp")
                           :status (jsonGetInt64 obj "status")
                           :mime (jsonGetString obj "mime")
                           :digest (jsonGetString obj "digest")
                           :filename (jsonGetString obj "filename")
                           :offset (jsonGetInt64 obj "offset")
                           :length (jsonGetInt64 obj "length"))))))))))))

fn parseCdxLinesLoop lines: (List String) crawl: String acc: (List CcCapture) -> (Result (List CcCapture) String)
  (mt (listHead lines)
    ((none) (ok (listReverse acc)))
    ((some line)
     (let [(parseRes (parseCdxLineItem line crawl))]
       (mt parseRes
         ((err e) (err e))
         ((ok optCap)
          (mt optCap
            ((some cap) (parseCdxLinesLoop (optionOr (listTail lines) (list)) crawl (cons cap acc)))
            ((none) (parseCdxLinesLoop (optionOr (listTail lines) (list)) crawl acc))))))))

fn ccParseCdxLines text: String crawl: String -> (Result (List CcCapture) String)
  (let [(cleanText (stringTrim (stringReplace text "\r" "")))]
    (if (stringEmpty? cleanText)
      (ok (list))
      (let [(lines (stringSplit cleanText "\n"))]
        (parseCdxLinesLoop lines crawl (list)))))

fn ccLatestCrawl! -> (Result String String)
  (mt (ccRunCurl! (list "-sSL" "--max-time" "15" "https://index.commoncrawl.org/collinfo.json"))
    ((err e) (err (str "curl failed: " e)))
    ((ok res)
     (if (!= res.exitCode 0)
       (err (str "curl failed: " res.stderr))
       (mt (j/jsonParse res.stdout)
         ((err e) (err (str "JSON parse error: " e)))
         ((ok parsed)
          (mt parsed
            ((j/jarr items)
             (mt (listHead items)
               ((none) (err "empty crawl list in collinfo.json"))
               ((some firstItem)
                (mt (j/jsonGet firstItem "id")
                  ((some v)
                   (mt v
                     ((j/jstr id) (ok id))
                     (_ (err "id field is not a string"))))
                  ((none) (err "missing id field in collinfo first item"))))))
            (_ (err "collinfo root is not an array"))))))))

fn processErrorText e: proc/ProcessError -> String
  (mt e
    ((proc/notFound bin) (str "sh: " bin ": command not found"))
    ((proc/timeout ms) (str "process timed out after " (stringFromInt64 ms) "ms"))
    ((proc/permissionDenied path) (str "sh: " path ": Permission denied"))
    ((proc/executionFailed code msg) (str "process failed (" (stringFromInt64 code) "): " msg)))

fn ! ccRunCommand! bin: String args: (List String) -> (Result proc/ProcessOutput String)
  (let [(baseCmd (proc/cmd bin args))
        (cmd (proc/withTimeout baseCmd 35000))]
    (mt (proc/exec! cmd)
      ((ok output) (ok output))
      ((err e) (err (processErrorText e)))))

fn ! ccRunCurl! args: (List String) -> (Result proc/ProcessOutput String)
  (ccRunCommand! "curl" args)

fn ! ccRunCurlWithConfig! args: (List String) config: String -> (Result proc/ProcessOutput String)
  (let [(base (proc/withStdin (proc/cmd "curl" args) config))
        (cmd (proc/withTimeout base 35000))]
    (mt (proc/exec! cmd)
      ((ok output) (ok output))
      ((err e) (err (processErrorText e)))))

fn isUnreservedByte b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
      (or (and (>= b 97) (<= b 122))
          (or (and (>= b 48) (<= b 57))
              (or (= b 45)
                  (or (= b 46)
                      (or (= b 95) (= b 126)))))))

fn rfc3986HexDigits -> String
  "0123456789ABCDEF"

fn rfc3986EncodeLoop tbl: String hex: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))]
      (if (isUnreservedByte b)
        (let [(ch (optionOr (stringSlice tbl b (+ b 1)) ""))]
          (rfc3986EncodeLoop tbl hex bs (+ i 1) n (cons ch acc)))
        (let [(hi (/ b 16))
              (lo (mod b 16))
              (h1 (optionOr (stringSlice hex hi (+ hi 1)) "0"))
              (h2 (optionOr (stringSlice hex lo (+ lo 1)) "0"))
              (tok (str "%" h1 h2))]
          (rfc3986EncodeLoop tbl hex bs (+ i 1) n (cons tok acc))))))

fn rfc3986Encode s: String -> String
  (let [(bs (stringToBytes s))]
    (rfc3986EncodeLoop (ccByteTable) (rfc3986HexDigits) bs 0 (bytesLength bs) (list)))

fn ccBuildLookupArgs crawl: String urlPattern: String limit: Int64 -> (List String)
  (let [(base (if (or (stringStartsWith? crawl "http://") (stringStartsWith? crawl "https://"))
                crawl
                (str "https://index.commoncrawl.org/" crawl "-index")))
        (encodedUrl (rfc3986Encode urlPattern))
        (url (str base "?url=" encodedUrl "&output=json&limit=" (stringFromInt64 limit)))]
    (list "-sSL" "--max-time" "30" url))

fn ccLookup! crawl: String urlPattern: String limit: Int64 -> (Result (List CcCapture) String)
  (mt (ccRunCurl! (ccBuildLookupArgs crawl urlPattern limit))
    ((err e) (err (str "curl failed: " e)))
    ((ok res)
     (if (!= res.exitCode 0)
       (err (str "curl failed: " res.stderr))
       (ccParseCdxLines res.stdout crawl))))

fn ccFetchRaw! c: CcCapture -> (Result Bytes String)
  (mt (ccRunCommand! "mktemp" (list))
    ((err e) (err (str "mktemp failed: " e)))
    ((ok tmpRes)
     (if (!= tmpRes.exitCode 0)
       (err (str "mktemp failed: " tmpRes.stderr))
       (let [(tmpFile (stringTrim tmpRes.stdout))
             (start c.offset)
             (end (- (+ start c.length) 1))
             (rangeHdr (str "Range: bytes=" (stringFromInt64 start) "-" (stringFromInt64 end)))
             (url (str "https://data.commoncrawl.org/" c.filename))
             (curlArgs (list "-sSL" "--max-time" "30" "--config" "-" "-o" tmpFile url))
             (curlConfig (str "header = \"" rangeHdr "\"\n"))
             (curlRes (ccRunCurlWithConfig! curlArgs curlConfig))]
         (mt curlRes
           ((err e)
            (do
              (ccRunCommand! "rm" (list "-f" tmpFile))
              (err (str "curl failed: " e))))
           ((ok output)
            (if (!= output.exitCode 0)
              (do
                (ccRunCommand! "rm" (list "-f" tmpFile))
                (err (str "curl failed: " output.stderr)))
              (let [(readRes (fileReadBytes tmpFile))
                    (cleanup (ccRunCommand! "rm" (list "-f" tmpFile)))]
                (mt readRes
                  ((err e) (err (str "fileReadBytes failed: " e)))
                  ((ok bs)
                   (let [(len (bytesLength bs))]
                     (if (!= len c.length)
                       (err (str "byte count mismatch: expected " (stringFromInt64 c.length) " but got " (stringFromInt64 len)))
                       (ok bs)))))))))))))

fn ccByteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn ccBytesToStringLoop tbl: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))
          (ch (optionOr (stringSlice tbl b (+ b 1)) ""))]
      (ccBytesToStringLoop tbl bs (+ i 1) n (cons ch acc))))

fn ccBytesToString bs: Bytes -> String
  (ccBytesToStringLoop (ccByteTable) bs 0 (bytesLength bs) (list))

fn ccGunzip! raw: Bytes -> (Result String String)
  (mt (gz/gunzip! raw)
    ((err e) (err e))
    ((ok decompressed)
     (ok (ccBytesToString decompressed))))

fn parseHeaderValue line: String prefix: String -> String
  (stringTrim (optionOr (stringSlice line (stringLength prefix) (stringLength line)) ""))

fn findHeaderLine lines: (List String) prefix: String -> String
  (let [(matches (filter (fn [(l String)] -> Bool (stringStartsWith? (stringLower l) prefix)) lines))]
    (optionOr (listHead matches) ""))

fn parseHttpStatus statusLine: String -> Int64
  (let [(tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringTrim statusLine) " ")))]
    (let [(statusToken (optionOr (listGet tokens 1) "0"))]
      (optionOr (stringToInt64 statusToken) 0)))

fn ccParseWarc text: String -> (Result CcRecord String)
  (let [(sep (if (stringContains? text "\r\n\r\n") "\r\n\r\n" "\n\n"))
        (sepLen (stringLength sep))
        (optI1 (stringIndexOf text sep))]
    (mt optI1
      ((none) (err "missing WARC header boundary"))
      ((some i1)
       (let [(warcHdr (optionOr (stringSlice text 0 i1) ""))
             (rest1 (optionOr (stringSlice text (+ i1 sepLen) (stringLength text)) ""))
             (optI2 (stringIndexOf rest1 sep))]
         (mt optI2
           ((none) (err "missing HTTP header boundary"))
           ((some i2)
            (let [(httpHdr (optionOr (stringSlice rest1 0 i2) ""))
                  (htmlBody (optionOr (stringSlice rest1 (+ i2 sepLen) (stringLength rest1)) ""))
                  (wLines (stringSplit (stringReplace warcHdr "\r" "") "\n"))
                  (targetUri (parseHeaderValue (findHeaderLine wLines "warc-target-uri:") "warc-target-uri:"))
                  (warcDate (parseHeaderValue (findHeaderLine wLines "warc-date:") "warc-date:"))
                  (hLines (stringSplit (stringReplace httpHdr "\r" "") "\n"))
                  (statusLine (optionOr (listHead hLines) ""))
                  (httpStatus (parseHttpStatus statusLine))
                  (contentType (parseHeaderValue (findHeaderLine hLines "content-type:") "content-type:"))]
              (ok (CcRecord
                    :targetUri targetUri
                    :warcDate warcDate
                    :httpStatus httpStatus
                    :contentType contentType
                    :htmlBody htmlBody)))))))))

fn ccFetch! c: CcCapture -> (Result CcRecord String)
  (mt (ccFetchRaw! c)
    ((err e) (err e))
    ((ok raw)
     (mt (ccGunzip! raw)
       ((err e) (err e))
       ((ok text) (ccParseWarc text)))))

fn decodeHtmlEntities text: String -> String
  (let [(e1 (stringReplace text "&amp;" "&"))
        (e2 (stringReplace e1 "&lt;" "<"))
        (e3 (stringReplace e2 "&gt;" ">"))
        (e4 (stringReplace e3 "&quot;" "\""))
        (e5 (stringReplace e4 "&#39;" "'"))
        (e6 (stringReplace e5 "&apos;" "'"))]
    e6)

fn normalizeWhitespace text: String -> String
  (let [(w1 (stringReplace text "\r" " "))
        (w2 (stringReplace w1 "\n" " "))
        (w3 (stringReplace w2 "\t" " "))
        (tokens (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit w3 " ")))]
    (stringJoin tokens " "))

fn stripHtmlTags html: String -> String
  (let [(parts (stringSplit html "<"))
        (headText (optionOr (listHead parts) ""))
        (tailParts (optionOr (listTail parts) (list)))
        (extractedTail (map (fn [(p String)] -> String
                              (let [(idx (stringIndexOf p ">"))]
                                (mt idx
                                  ((some i) (optionOr (stringSlice p (+ i 1) (stringLength p)) ""))
                                  ((none) ""))))
                            tailParts))]
    (stringJoin (cons headText extractedTail) " "))

fn ccQuoteInPage? record: CcRecord quote: String -> Bool
  (let [(stripped (stripHtmlTags record.htmlBody))
        (decoded (decodeHtmlEntities stripped))
        (normBody (normalizeWhitespace decoded))
        (normQuote (normalizeWhitespace (decodeHtmlEntities quote)))]
    (if (stringEmpty? normQuote)
      false
      (stringContains? normBody normQuote)))
