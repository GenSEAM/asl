(module asl-s3/tests/sigv4FixturesTest
  :x [runTests]
  :i [(asl-s3/sigv4 :a s) (asl-json/json :a j)])

(schema Vector
  (:f name String) (:f method String) (:f path String)
  (:f query (List s/QueryParam)) (:f headers (List s/Header))
  (:f bodyHash String) (:f secret String) (:f date String)
  (:f region String) (:f service String) (:f amzDate String)
  (:f canonical String) (:f toSign String) (:f signature String))

fn ! readText path: String -> String
  (mt (fileReadString path) ((ok value) value) ((err _) ""))

fn jsonString object: j/Json key: String -> String
  (mt (j/jsonGet object key)
    ((none) "")
    ((some value) (mt value ((j/jstr text) text) (_ ""))))

fn jsonBool object: j/Json key: String -> Bool
  (mt (j/jsonGet object key)
    ((none) false)
    ((some value) (mt value ((j/jbool flag) flag) (_ false))))

fn parseHeaders lines: (List String) out: (List s/Header) -> (List s/Header)
  (mt (listHead lines)
    ((none) out)
    ((some line)
      (mt (stringIndexOf line ":")
        ((none) (parseHeaders (optionOr (listTail lines) (list)) out))
        ((some colon)
          (parseHeaders (optionOr (listTail lines) (list))
            (listAppend out (list (s/Header
              :name (optionOr (stringSlice line 0 colon) "")
              :value (optionOr (stringSlice line (+ colon 1) (stringLength line)) "")))))))))

fn parseQuery items: (List String) out: (List s/QueryParam) -> (List s/QueryParam)
  (mt (listHead items)
    ((none) out)
    ((some item)
      (let [(parts (stringSplit item "="))]
        (parseQuery (optionOr (listTail items) (list))
          (listAppend out (list (s/QueryParam
            :name (optionOr (listGet parts 0) "")
            :value (optionOr (listGet parts 1) ""))))))))

fn queryFromTarget target: String -> (List s/QueryParam)
  (mt (stringIndexOf target "?")
    ((none) (list))
    ((some qmark)
      (let [(raw (optionOr (stringSlice target (+ qmark 1) (stringLength target)) ""))]
        (if (stringEmpty? raw) (list) (parseQuery (stringSplit raw "&") (list))))))

fn pathFromTarget target: String -> String
  (mt (stringIndexOf target "?")
    ((none) target)
    ((some qmark) (optionOr (stringSlice target 0 qmark) "")))

fn hasSigningDate headers: (List s/Header) -> Bool
  (mt (listHead headers)
    ((none) false)
    ((some item)
      (let [(name (stringLower (stringTrim item.name)))]
        (or (= name "date") (or (= name "x-amz-date")
          (hasSigningDate (optionOr (listTail headers) (list))))))))

fn ! readVector name: String -> Vector
  (let [(base (str "asl/packages/asl-s3/tests/fixtures/sigv4/" name "/"))
        (req (stringReplace (readText (str base "req.txt")) "\r\n" "\n"))
        (lines (stringSplit req "\n"))
        (request (stringSplit (optionOr (listGet lines 0) "") " "))
        (method (optionOr (listGet request 0) ""))
        (target (optionOr (listGet request 1) ""))
        (headers (parseHeaders (optionOr (listSlice lines 1 (listLength lines)) (list)) (list)))
        (contextText (readText (str base "context.json")))
        (context (mt (j/jsonParse contextText) ((ok value) value) ((err _) (j/jobj (list)))))
        (credentials (optionOr (j/jsonGet context "credentials") (j/jobj (list))))
        (secret (jsonString credentials "secret_access_key"))
        (timestamp (stringReplace (stringReplace (jsonString context "timestamp") "-" "") ":" ""))
        (date (optionOr (stringSlice timestamp 0 8) ""))
        (region (jsonString context "region"))
        (service (jsonString context "service"))
        (separator (stringIndexOf req "\n\n"))
        (body (mt separator ((none) "") ((some at) (optionOr (stringSlice req (+ at 2) (stringLength req)) ""))))
        (signBody (jsonBool context "sign_body"))
        (bodyHash (if signBody (s/payloadHash (stringToBytes body)) "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
        (signedHeaders (listAppend headers
          (listAppend (if (hasSigningDate headers) (list) (list (s/Header :name "x-amz-date" :value timestamp)))
            (if signBody (list (s/Header :name "x-amz-content-sha256" :value bodyHash)) (list)))))
        (canonical (s/canonicalRequest method (pathFromTarget target) (queryFromTarget target) signedHeaders bodyHash))
        (scope (str date "/" region "/" service "/aws4_request"))]
    (Vector :name name :method method :path (pathFromTarget target)
      :query (queryFromTarget target) :headers signedHeaders :bodyHash bodyHash
      :secret secret :date date :region region :service service :amzDate timestamp
      :canonical canonical :toSign (s/stringToSign timestamp scope canonical)
      :signature (s/signature secret date region service timestamp canonical)))

fn ! assertVector vector: Vector -> Bool
  (let [(base (str "asl/packages/asl-s3/tests/fixtures/sigv4/" vector.name "/"))]
    (assert (= vector.canonical (readText (str base "creq.txt"))) (str vector.name " canonical request"))
    (assert (= vector.toSign (readText (str base "sts.txt"))) (str vector.name " string to sign"))
    (assert (= vector.signature (readText (str base "authz.txt"))) (str vector.name " signature"))
    true)

fn ! assertVectors vectors: (List Vector) -> Bool
  (mt (listHead vectors)
    ((none) true)
    ((some vector) (and (assertVector vector) (assertVectors (optionOr (listTail vectors) (list))))))

fn ! runTests -> Bool
  (assertVectors (list
    (readVector "get-vanilla")
    (readVector "get-vanilla-query-order-key-case")
    (readVector "get-header-value-trim")
    (readVector "get-utf8")
    (readVector "post-x-www-form-urlencoded")
    (readVector "get-vanilla-query-unreserved")
    (readVector "post-header-key-sort")
    (readVector "get-space")))
