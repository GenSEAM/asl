(module asl-s3/s3Request
  :x [Request request putObject getObject listObjectsV2 deleteObject createMultipartUpload uploadPart completeMultipartUpload parseListResponse parseMultipartResponse parseErrorDocument]
  :i [(asl-s3/sigv4 :a s) (asl-syntax/xml :a xml)])

(schema Request
  (:f method String)
  (:f host String)
  (:f path String)
  (:f query (List s/QueryParam))
  (:f headers (List s/Header))
  (:f body String))
(schema XmlField (:f name String) (:f value String))
(schema S3Error (:f code String) (:f message String))

fn xmlByteStr b: Int64 -> String
  (let [(tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_\x60abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff")]
    (optionOr (stringSlice tbl b (+ b 1)) ""))

fn xmlHexValue value: Int64 -> Int64
  (cond
    ((and (>= value 48) (<= value 57)) (- value 48))
    ((and (>= value 65) (<= value 70)) (+ (- value 65) 10))
    ((and (>= value 97) (<= value 102)) (+ (- value 97) 10))
    (else -1))

fn xmlHexNumberLoop digits: String pos: Int64 value: Int64 -> Int64
  (if (>= pos (stringLength digits)) value
    (let [(character (charCode (optionOr (stringSlice digits pos (+ pos 1)) "")))
          (digit (xmlHexValue character))]
      (if (< digit 0) -1
        (xmlHexNumberLoop digits (+ pos 1) (+ (* value 16) digit)))))

fn xmlEncodeCodepoint codepoint: Int64 -> String
  (cond
    ((< codepoint 128) (xmlByteStr codepoint))
    ((< codepoint 2048)
     (stringConcat (xmlByteStr (| 192 (/ codepoint 64)))
       (xmlByteStr (| 128 (mod codepoint 64)))))
    ((< codepoint 65536)
     (stringConcat
       (stringConcat (xmlByteStr (| 224 (/ codepoint 4096)))
         (xmlByteStr (| 128 (mod (/ codepoint 64) 64))))
       (xmlByteStr (| 128 (mod codepoint 64)))))
    (else
     (stringConcat
       (stringConcat (xmlByteStr (| 240 (/ codepoint 262144)))
         (xmlByteStr (| 128 (mod (/ codepoint 4096) 64))))
       (stringConcat (xmlByteStr (| 128 (mod (/ codepoint 64) 64)))
         (xmlByteStr (| 128 (mod codepoint 64)))))))

fn decodeNumericXmlEntity entity: String -> String
  (let [(marker (optionOr (stringSlice entity 1 2) ""))
        (hexadecimal (or (= marker "x") (= marker "X")))
        (digits (optionOr (stringSlice entity (if hexadecimal 2 1) (stringLength entity)) ""))
        (codepoint (if hexadecimal (xmlHexNumberLoop digits 0 0) (optionOr (stringToInt64 digits) -1)))]
    (if (or (< codepoint 0) (or (> codepoint 1114111) (and (>= codepoint 55296) (<= codepoint 57343))))
      (str "&" entity ";")
      (xmlEncodeCodepoint codepoint)))

fn decodeXmlEntity entity: String -> String
  (cond
    ((= entity "lt") "<")
    ((= entity "gt") ">")
    ((= entity "quot") "\"")
    ((= entity "apos") "'")
    ((= entity "amp") "&")
    ((stringStartsWith? entity "#") (decodeNumericXmlEntity entity))
    (else (str "&" entity ";")))

fn decodeXmlTextLoop text: String cursor: Int64 acc: String -> String
  (let [(tail (optionOr (stringSlice text cursor (stringLength text)) ""))]
    (mt (stringIndexOf tail "&")
      ((none) (str acc tail))
      ((some ampAt)
        (let [(prefix (optionOr (stringSlice tail 0 ampAt) ""))
              (afterAmp (optionOr (stringSlice tail (+ ampAt 1) (stringLength tail)) ""))]
          (mt (stringIndexOf afterAmp ";")
            ((none) (str acc tail))
            ((some endAt)
              (let [(entity (optionOr (stringSlice afterAmp 0 endAt) ""))
                    (next (+ cursor ampAt endAt 2))]
                (decodeXmlTextLoop text next (str acc prefix (decodeXmlEntity entity))))))))))

fn decodeXmlText text: String -> String
  (decodeXmlTextLoop text 0 "")

fn header name: String value: String -> s/Header
  (s/Header :name name :value value)

fn query name: String value: String -> s/QueryParam
  (s/QueryParam :name name :value value)

fn endpointHost endpoint: String bucket: String virtualHosted: Bool -> String
  (if (stringStartsWith? endpoint "http://")
    (if virtualHosted (str bucket "." (optionOr (stringSlice endpoint 7 (stringLength endpoint)) "")) (optionOr (stringSlice endpoint 7 (stringLength endpoint)) ""))
    (if (stringStartsWith? endpoint "https://")
      (if virtualHosted (str bucket "." (optionOr (stringSlice endpoint 8 (stringLength endpoint)) "")) (optionOr (stringSlice endpoint 8 (stringLength endpoint)) ""))
      (if virtualHosted (str bucket "." endpoint) endpoint)))

fn objectPath bucket: String key: String virtualHosted: Bool -> String
  (if virtualHosted (str "/" (stringReplace key "%" "%25"))
    (str "/" (stringReplace bucket "%" "%25") "/" (stringReplace key "%" "%25")))

fn request method: String endpoint: String bucket: String key: String virtualHosted: Bool queryParams: (List s/QueryParam) headers: (List s/Header) body: String -> Request
  (Request :method method :host (endpointHost endpoint bucket virtualHosted) :path (objectPath bucket key virtualHosted) :query queryParams :headers (listAppend (list (header "host" (endpointHost endpoint bucket virtualHosted))) headers) :body body)

fn putObject endpoint: String bucket: String key: String virtualHosted: Bool contentType: String body: String -> Request
  (request "PUT" endpoint bucket key virtualHosted (list) (list (header "content-type" contentType)) body)

fn getObject endpoint: String bucket: String key: String virtualHosted: Bool -> Request
  (request "GET" endpoint bucket key virtualHosted (list) (list) "")

fn listObjectsV2 endpoint: String bucket: String virtualHosted: Bool prefix: String continuationToken: String maxKeys: Int64 -> Request
  (Request :method "GET" :host (endpointHost endpoint bucket virtualHosted)
    :path (if virtualHosted "/" (str "/" bucket "/"))
    :query (listAppend (list (query "list-type" "2"))
      (listAppend (if (stringEmpty? prefix) (list) (list (query "prefix" prefix)))
        (listAppend (if (stringEmpty? continuationToken) (list) (list (query "continuation-token" continuationToken)))
          (if (> maxKeys 0) (list (query "max-keys" (stringFromInt64 maxKeys))) (list)))))
    :headers (list (header "host" (endpointHost endpoint bucket virtualHosted))) :body "")

fn deleteObject endpoint: String bucket: String key: String virtualHosted: Bool -> Request
  (request "DELETE" endpoint bucket key virtualHosted (list) (list) "")

fn createMultipartUpload endpoint: String bucket: String key: String virtualHosted: Bool contentType: String -> Request
  (request "POST" endpoint bucket key virtualHosted (list (query "uploads" "")) (list (header "content-type" contentType)) "")

fn uploadPart endpoint: String bucket: String key: String virtualHosted: Bool uploadId: String partNumber: Int64 body: String -> Request
  (request "PUT" endpoint bucket key virtualHosted (list (query "partNumber" (stringFromInt64 partNumber)) (query "uploadId" uploadId)) (list) body)

fn completeMultipartUpload endpoint: String bucket: String key: String virtualHosted: Bool uploadId: String body: String -> Request
  (request "POST" endpoint bucket key virtualHosted (list (query "uploadId" uploadId)) (list (header "content-type" "application/xml")) body)

fn tagText xmlText: String tag: String -> (Option String)
  (let [(opening (str "<" tag ">")) (closing (str "</" tag ">"))]
    (mt (stringIndexOf xmlText opening)
      ((none) (none))
      ((some startAt)
        (let [(valueStart (+ startAt (stringLength opening)))]
          (mt (stringIndexOf (optionOr (stringSlice xmlText valueStart (stringLength xmlText)) "") closing)
            ((none) (none))
            ((some endAt) (some (decodeXmlText (optionOr (stringSlice xmlText valueStart (+ valueStart endAt)) "")))))))))

fn xmlWellFormed xmlText: String -> Bool
  (if (> (stringLength xmlText) 1048576) false
    (mt (xml/parse xmlText) ((err _) false) ((ok _) true)))

fn parseErrorDocument xmlText: String -> (Result S3Error S3Error)
  (if (not (xmlWellFormed xmlText)) (err (S3Error :code "MalformedXML" :message "malformed XML error document"))
    (mt (tagText xmlText "Code")
      ((none) (err (S3Error :code "MalformedError" :message "missing Error/Code")))
      ((some code) (mt (tagText xmlText "Message")
        ((none) (err (S3Error :code "MalformedError" :message "missing Error/Message")))
        ((some message) (err (S3Error :code code :message message)))))))

fn collectTag xmlText: String tag: String cursor: Int64 out: (List String) -> (List String)
  (let [(opening (str "<" tag ">")) (closing (str "</" tag ">"))
        (tail (optionOr (stringSlice xmlText cursor (stringLength xmlText)) ""))]
    (mt (stringIndexOf tail opening)
      ((none) out)
      ((some relativeStart)
        (let [(start (+ cursor relativeStart (stringLength opening)))]
          (mt (stringIndexOf (optionOr (stringSlice xmlText start (stringLength xmlText)) "") closing)
            ((none) out)
            ((some relativeEnd)
              (collectTag xmlText tag (+ start relativeEnd (stringLength closing))
                (listAppend out (list (decodeXmlText (optionOr (stringSlice xmlText start (+ start relativeEnd)) "")))))))))))

fn keyFields values: (List String) -> (List XmlField)
  (mt (listHead values)
    ((none) (list))
    ((some value) (listAppend (list (XmlField :name "Key" :value value)) (keyFields (optionOr (listTail values) (list))))))

fn parseListResponse xmlText: String -> (Result (List XmlField) String)
  (if (not (xmlWellFormed xmlText)) (err "malformed XML list response")
    (ok (listAppend
      (mt (tagText xmlText "Name") ((none) (list)) ((some v) (list (XmlField :name "Name" :value v))))
      (listAppend
        (mt (tagText xmlText "Prefix") ((none) (list)) ((some v) (list (XmlField :name "Prefix" :value v))))
        (listAppend
          (mt (tagText xmlText "IsTruncated") ((none) (list)) ((some v) (list (XmlField :name "IsTruncated" :value v))))
          (keyFields (collectTag xmlText "Key" 0 (list))))))))

fn parseMultipartResponse xmlText: String -> (Result (List XmlField) String)
  (if (not (xmlWellFormed xmlText)) (err "malformed XML multipart response")
    (ok (listAppend
      (mt (tagText xmlText "Bucket") ((none) (list)) ((some v) (list (XmlField :name "Bucket" :value v))))
      (listAppend
        (mt (tagText xmlText "Key") ((none) (list)) ((some v) (list (XmlField :name "Key" :value v))))
        (mt (tagText xmlText "UploadId") ((none) (list)) ((some v) (list (XmlField :name "UploadId" :value v))))))))
