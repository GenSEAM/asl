(module asl-s3/sigv4
  :x [QueryParam Header PresignError uriEncode canonicalUri canonicalQuery canonicalHeaders signedHeaderNames canonicalRequest stringToSign deriveSigningKey signature authorization presign payloadHash]
  :i [(asl-crypto/hmac :a h)])

(schema QueryParam (:f name String) (:f value String))
(schema Header (:f name String) (:f value String))
(schema PresignError (:f actual Int64))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789ABCDEF" n (+ n 1)) "")

fn percentByte b: Int64 -> String
  (str "%" (hexDigit (/ b 16)) (hexDigit (mod b 16)))

fn unreserved b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122))
    (or (and (>= b 48) (<= b 57)) (or (= b 45) (or (= b 46) (or (= b 95) (= b 126))))))

fn hexByte b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 70)) (and (>= b 97) (<= b 102))))

fn uriEncodeLoop bytes: Bytes n: Int64 value: String i: Int64 out: String -> String
  (if (>= i n) out
    (let [(b (bytesGet bytes i))]
      (uriEncodeLoop bytes n value (+ i 1) (str out (if (unreserved b) (optionOr (stringSlice value i (+ i 1)) "") (percentByte b))))))

fn uriEncode value: String -> String
  (let [(bytes (stringToBytes value)) (n (bytesLength bytes))]
    (uriEncodeLoop bytes n value 0 ""))

fn pathEncodeLoop bytes: Bytes n: Int64 value: String i: Int64 out: String -> String
  (if (>= i n) out
    (let [(b (bytesGet bytes i))
          (escaped (and (= b 37) (and (< (+ i 2) n)
            (and (hexByte (bytesGet bytes (+ i 1))) (hexByte (bytesGet bytes (+ i 2)))))))
          (next (if escaped (+ i 3) (+ i 1)))
          (piece (if escaped (stringUpper (optionOr (stringSlice value i next) ""))
            (if (= b 47) "/" (if (unreserved b) (optionOr (stringSlice value i next) "") (percentByte b)))))]
      (pathEncodeLoop bytes n value next (str out piece))))

fn pathEncode value: String -> String
  (let [(bytes (stringToBytes value)) (n (bytesLength bytes))]
    (pathEncodeLoop bytes n value 0 ""))

fn canonicalUri path: String -> String
  (let [(encoded (pathEncode path))]
    (if (stringStartsWith? encoded "/") encoded (str "/" encoded)))

fn queryLine item: QueryParam -> String
  (str (uriEncode item.name) "=" (uriEncode item.value))

fn queryLinesLoop rest: (List QueryParam) out: (List String) -> (List String)
  (mt (listHead rest) ((none) out) ((some item) (queryLinesLoop (optionOr (listTail rest) (list)) (listAppend out (list (queryLine item))))))

fn queryLines query: (List QueryParam) -> (List String)
  (queryLinesLoop query (list))

fn canonicalQuery query: (List QueryParam) -> String
  (stringJoin (listSort (queryLines query)) "&")

fn skipHeaderWhitespace bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len) pos
    (let [(byte (bytesGet bs pos))]
      (if (or (= byte 32) (= byte 9))
        (skipHeaderWhitespace bs len (+ pos 1))
        pos)))

fn collapseHeaderWhitespaceLoop value: String bs: Bytes len: Int64 pos: Int64 start: Int64 out: String -> String
  (if (>= pos len)
    (str out (optionOr (stringSlice value start len) ""))
    (let [(byte (bytesGet bs pos))]
      (if (or (= byte 32) (= byte 9))
        (let [(prefix (optionOr (stringSlice value start pos) ""))
              (next (skipHeaderWhitespace bs len pos))]
          (collapseHeaderWhitespaceLoop value bs len next next
            (str out prefix (if (>= next len) "" " "))))
        (collapseHeaderWhitespaceLoop value bs len (+ pos 1) start out))))

fn collapseHeaderWhitespace value: String -> String
  (let [(trimmed (stringTrim value))
        (bytes (stringToBytes trimmed))
        (len (bytesLength bytes))]
    (collapseHeaderWhitespaceLoop trimmed bytes len 0 0 ""))

fn sortedHeaders headers: (List Header) -> (List Header)
  (listSortBy (fn [item] -> String (stringLower (stringTrim item.name))) headers)

fn canonicalHeaderLine name: String values: (List String) -> String
  (str name ":" (stringJoin values ",") "\n")

fn mergedHeaderLines headers: (List Header) name: String values: (List String) out: (List String) -> (List String)
  (mt (listHead headers)
    ((none) (listAppend out (list (canonicalHeaderLine name values))))
    ((some item)
      (let [(nextName (stringLower (stringTrim item.name)))
            (nextValue (collapseHeaderWhitespace item.value))
            (rest (optionOr (listTail headers) (list)))]
        (if (= nextName name)
          (mergedHeaderLines rest name (listAppend values (list nextValue)) out)
          (mergedHeaderLines rest nextName (list nextValue)
            (listAppend out (list (canonicalHeaderLine name values))))))))

fn headerLines headers: (List Header) -> (List String)
  (let [(sorted (sortedHeaders headers))]
    (mt (listHead sorted)
      ((none) (list))
      ((some item) (mergedHeaderLines (optionOr (listTail sorted) (list))
        (stringLower (stringTrim item.name))
        (list (collapseHeaderWhitespace item.value)) (list)))))

fn headerNamesLoop rest: (List Header) out: (List String) -> (List String)
  (mt (listHead rest) ((none) out) ((some item) (headerNamesLoop (optionOr (listTail rest) (list)) (listAppend out (list (stringLower (stringTrim item.name)))))))

fn headerNames headers: (List Header) -> (List String)
  (headerNamesLoop (sortedHeaders headers) (list))

fn uniqueHeaderNames names: (List String) previous: String started: Bool out: (List String) -> (List String)
  (mt (listHead names)
    ((none) out)
    ((some name)
      (let [(rest (optionOr (listTail names) (list)))]
        (if (and started (= name previous))
          (uniqueHeaderNames rest previous true out)
          (uniqueHeaderNames rest name true (listAppend out (list name)))))))

fn canonicalHeaders headers: (List Header) -> String
  (stringJoin (headerLines headers) "")

fn signedHeaderNames headers: (List Header) -> String
  (stringJoin (uniqueHeaderNames (headerNames headers) "" false (list)) ";")

fn canonicalRequest method: String path: String query: (List QueryParam) headers: (List Header) bodyHash: String -> String
  (str (stringUpper method) "\n" (canonicalUri path) "\n" (canonicalQuery query) "\n"
    (canonicalHeaders headers) "\n" (signedHeaderNames headers) "\n" bodyHash)

fn payloadHash body: Bytes -> String
  (bytesSha256 body)

fn stringToSign amzDate: String scope: String request: String -> String
  (str "AWS4-HMAC-SHA256\n" amzDate "\n" scope "\n" (bytesSha256 (stringToBytes request)))

fn deriveSigningKey secret: String date: String region: String service: String -> Bytes
  (let [(kDate (h/hmacSha256 (stringToBytes (str "AWS4" secret)) (stringToBytes date)))
        (kRegion (h/hmacSha256 kDate (stringToBytes region)))
        (kService (h/hmacSha256 kRegion (stringToBytes service)))]
    (h/hmacSha256 kService (stringToBytes "aws4_request")))

fn signature secret: String date: String region: String service: String amzDate: String request: String -> String
  (let [(scope (str date "/" region "/" service "/aws4_request"))]
    (h/bytesToHex (h/hmacSha256 (deriveSigningKey secret date region service)
      (stringToBytes (stringToSign amzDate scope request)))))

fn authorization accessKey: String secret: String date: String region: String service: String amzDate: String method: String path: String query: (List QueryParam) headers: (List Header) bodyHash: String -> String
  (let [(names (signedHeaderNames headers))
        (scope (str date "/" region "/" service "/aws4_request"))
        (request (canonicalRequest method path query headers bodyHash))
        (sig (signature secret date region service amzDate request))]
    (str "AWS4-HMAC-SHA256 Credential=" accessKey "/" scope ",SignedHeaders=" names ",Signature=" sig))

fn presign accessKey: String secret: String date: String region: String service: String amzDate: String expiry: Int64 method: String path: String query: (List QueryParam) headers: (List Header) bodyHash: String -> (Result String PresignError)
  (if (or (< expiry 1) (> expiry 604800)) (err (PresignError :actual expiry))
    (let [(scope (str date "/" region "/" service "/aws4_request"))
          (base (listAppend query (list (QueryParam :name "X-Amz-Algorithm" :value "AWS4-HMAC-SHA256")
            (QueryParam :name "X-Amz-Credential" :value (str accessKey "/" scope))
            (QueryParam :name "X-Amz-Date" :value amzDate)
            (QueryParam :name "X-Amz-Expires" :value (stringFromInt64 expiry))
            (QueryParam :name "X-Amz-SignedHeaders" :value (signedHeaderNames headers)))))
          (request (canonicalRequest method path base headers bodyHash))
          (sig (signature secret date region service amzDate request))
          (signatureParam (QueryParam :name "X-Amz-Signature" :value sig))]
      (ok (str (canonicalUri path) "?" (canonicalQuery base) "&" (queryLine signatureParam)))))
