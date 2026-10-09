(module asl-json/json
  :x [Json jnull jbool jint jfloat jnum jstr jarr jobj jsonParse jsonEmit jsonGet]
  :i [])

enum Json
  (jnull)
  (jbool b: Bool)
  (jint i: Int64)
  (jfloat f: Float64)
  (jnum n: Float64)
  (jstr s: String)
  (jarr xs: (List Json))
  (jobj kvs: (List (Pair String Json)))

fn byteStr b: Int64 -> String
  (let [(tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff")]
    (optionOr (stringSlice tbl b (+ b 1)) ""))

fn encodeCp cp: Int64 -> String
  (cond
    ((< cp 128) (byteStr cp))
    ((< cp 2048)
     (stringConcat (byteStr (| 192 (/ cp 64)))
                    (byteStr (| 128 (mod cp 64)))))
    ((< cp 65536)
     (stringConcat (stringConcat (byteStr (| 224 (/ cp 4096)))
                                  (byteStr (| 128 (mod (/ cp 64) 64))))
                    (byteStr (| 128 (mod cp 64)))))
    (else
     (stringConcat (stringConcat (byteStr (| 240 (/ cp 262144)))
                                  (byteStr (| 128 (mod (/ cp 4096) 64))))
                    (stringConcat (byteStr (| 128 (mod (/ cp 64) 64)))
                                  (byteStr (| 128 (mod cp 64)))))))

fn hexVal b: Int64 -> Int64
  (cond
    ((and (>= b 48) (<= b 57)) (- b 48))
    ((and (>= b 65) (<= b 70)) (+ (- b 65) 10))
    ((and (>= b 97) (<= b 102)) (+ (- b 97) 10))
    (else -1))

fn parseHex4 bs: Bytes offset: Int64 len: Int64 -> Int64
  (if (> (+ offset 4) len) -1
    (let [(h0 (hexVal (bytesGet bs offset)))
          (h1 (hexVal (bytesGet bs (+ offset 1))))
          (h2 (hexVal (bytesGet bs (+ offset 2))))
          (h3 (hexVal (bytesGet bs (+ offset 3))))]
      (if (or (< h0 0) (or (< h1 0) (or (< h2 0) (< h3 0))))
        -1
        (+ (* h0 4096) (+ (* h1 256) (+ (* h2 16) h3))))))

fn scanString src: String bs: Bytes len: Int64 scanPos: Int64 pieceStart: Int64 pieces: (List String) hasEsc: Bool -> (Result (Pair String Int64) String)
  (if (>= scanPos len)
    (err (str "error at byte " (stringFromInt64 len) ": unterminated string"))
    (let [(b (bytesGet bs scanPos))]
      (cond
        ((< b 32)
         (err (str "error at byte " (stringFromInt64 scanPos) ": unescaped control character in string")))
        ((= b 34)
         (if (not hasEsc)
           (ok (pair (optionOr (stringSlice src pieceStart scanPos) "") (+ scanPos 1)))
           (let [(lastPiece (optionOr (stringSlice src pieceStart scanPos) ""))
                 (allPieces (cons lastPiece pieces))]
             (ok (pair (stringJoin (listReverse allPieces) "") (+ scanPos 1))))))
        ((= b 92)
         (let [(escPos (+ scanPos 1))]
           (if (>= escPos len)
             (err (str "error at byte " (stringFromInt64 len) ": unterminated string escape"))
             (let [(escChar (bytesGet bs escPos))
                   (litPiece (optionOr (stringSlice src pieceStart scanPos) ""))]
               (cond
                 ((= escChar 34) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "\"" (cons litPiece pieces)) true))
                 ((= escChar 92) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "\\" (cons litPiece pieces)) true))
                 ((= escChar 47) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "/" (cons litPiece pieces)) true))
                 ((= escChar 98) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "\x08" (cons litPiece pieces)) true))
                 ((= escChar 102) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "\x0c" (cons litPiece pieces)) true))
                 ((= escChar 110) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "\n" (cons litPiece pieces)) true))
                 ((= escChar 114) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "\r" (cons litPiece pieces)) true))
                 ((= escChar 116) (scanString src bs len (+ escPos 1) (+ escPos 1) (cons "\t" (cons litPiece pieces)) true))
                 ((= escChar 117)
                  (let [(cp1 (parseHex4 bs (+ escPos 1) len))]
                    (if (< cp1 0)
                      (err (str "error at byte " (stringFromInt64 escPos) ": invalid \\u hex escape"))
                      (cond
                        ((and (>= cp1 55296) (<= cp1 56319))
                         (if (or (> (+ escPos 10) len)
                                 (or (!= (bytesGet bs (+ escPos 5)) 92)
                                     (!= (bytesGet bs (+ escPos 6)) 117)))
                           (err (str "error at byte " (stringFromInt64 escPos) ": lone high surrogate in string"))
                           (let [(cp2 (parseHex4 bs (+ escPos 7) len))]
                             (if (or (< cp2 56320) (> cp2 57343))
                               (err (str "error at byte " (stringFromInt64 (+ escPos 5)) ": invalid low surrogate in string"))
                               (let [(fullCp (+ 65536 (+ (* (- cp1 55296) 1024) (- cp2 56320))))
                                     (encoded (encodeCp fullCp))]
                                 (scanString src bs len (+ escPos 11) (+ escPos 11) (cons encoded (cons litPiece pieces)) true))))))
                        ((and (>= cp1 56320) (<= cp1 57343))
                         (err (str "error at byte " (stringFromInt64 escPos) ": lone low surrogate in string")))
                        (else
                         (let [(encoded (encodeCp cp1))]
                           (scanString src bs len (+ escPos 5) (+ escPos 5) (cons encoded (cons litPiece pieces)) true)))))))
                 (else
                  (err (str "error at byte " (stringFromInt64 escPos) ": invalid escape character in string"))))))))
        (else
         (scanString src bs len (+ scanPos 1) pieceStart pieces hasEsc)))))

fn parseJsonString src: String startPos: Int64 -> (Result (Pair String Int64) String)
  (let [(bs (stringToBytes src))
        (len (bytesLength bs))]
    (if (>= startPos len)
      (err (str "error at byte " (stringFromInt64 startPos) ": unexpected end of input"))
      (if (!= (bytesGet bs startPos) 34)
        (err (str "error at byte " (stringFromInt64 startPos) ": expected '\"'"))
        (scanString src bs len (+ startPos 1) (+ startPos 1) (list) false))))

fn scanDigits bs: Bytes pos: Int64 len: Int64 -> Int64
  (if (>= pos len) pos
    (let [(b (bytesGet bs pos))]
      (if (and (>= b 48) (<= b 57))
        (scanDigits bs (+ pos 1) len)
        pos)))

fn scanIntPart bs: Bytes startPos: Int64 len: Int64 -> (Result Int64 String)
  (let [(p0 (if (and (< startPos len) (= (bytesGet bs startPos) 45)) (+ startPos 1) startPos))]
    (if (>= p0 len)
      (err (str "error at byte " (stringFromInt64 startPos) ": expected digit after '-'"))
      (let [(b (bytesGet bs p0))]
        (if (or (< b 48) (> b 57))
          (err (str "error at byte " (stringFromInt64 p0) ": expected digit in number"))
          (if (= b 48)
            (if (and (< (+ p0 1) len) (and (>= (bytesGet bs (+ p0 1)) 48) (<= (bytesGet bs (+ p0 1)) 57)))
              (err (str "error at byte " (stringFromInt64 (+ p0 1)) ": leading zero not allowed"))
              (ok (+ p0 1)))
            (ok (scanDigits bs (+ p0 1) len)))))))

fn scanFracPart bs: Bytes pos: Int64 len: Int64 -> (Result Int64 String)
  (if (or (>= pos len) (!= (bytesGet bs pos) 46))
    (ok pos)
    (if (or (>= (+ pos 1) len) (or (< (bytesGet bs (+ pos 1)) 48) (> (bytesGet bs (+ pos 1)) 57)))
      (err (str "error at byte " (stringFromInt64 pos) ": expected digit after '.'"))
      (ok (scanDigits bs (+ pos 1) len))))

fn scanExpPart bs: Bytes pos: Int64 len: Int64 -> (Result Int64 String)
  (if (or (>= pos len) (and (!= (bytesGet bs pos) 101) (!= (bytesGet bs pos) 69)))
    (ok pos)
    (let [(pE (+ pos 1))
          (pSign (if (and (< pE len) (or (= (bytesGet bs pE) 43) (= (bytesGet bs pE) 45))) (+ pE 1) pE))]
      (if (or (>= pSign len) (or (< (bytesGet bs pSign) 48) (> (bytesGet bs pSign) 57)))
        (err (str "error at byte " (stringFromInt64 pos) ": expected digit in exponent"))
        (ok (scanDigits bs (+ pSign 1) len)))))

fn parseJsonNumber src: String bs: Bytes startPos: Int64 len: Int64 -> (Result (Pair Json Int64) String)
  (mt (scanIntPart bs startPos len)
    ((err e) (err e))
    ((ok pInt)
     (mt (scanFracPart bs pInt len)
       ((err e) (err e))
       ((ok pFrac)
        (mt (scanExpPart bs pFrac len)
          ((err e) (err e))
          ((ok pExp)
           (let [(hasFrac (!= pFrac pInt))
                 (hasExp (!= pExp pFrac))
                 (numStr (optionOr (stringSlice src startPos pExp) ""))]
             (if (or hasFrac hasExp)
               (mt (stringToFloat64 numStr)
                 ((some f) (ok (pair (jfloat f) pExp)))
                 ((none) (err (str "error at byte " (stringFromInt64 startPos) ": malformed number " numStr))))
               (mt (stringToInt64 numStr)
                 ((some i) (ok (pair (jint i) pExp)))
                 ((none) (mt (stringToFloat64 numStr)
                           ((some f) (ok (pair (jfloat f) pExp)))
                           ((none) (err (str "error at byte " (stringFromInt64 startPos) ": malformed number " numStr))))))))))))))

fn skipWs bs: Bytes pos: Int64 len: Int64 -> Int64
  (if (>= pos len) pos
    (let [(b (bytesGet bs pos))]
      (if (or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))
        (skipWs bs (+ pos 1) len)
        pos)))

fn parseArrayElements src: String bs: Bytes pos: Int64 len: Int64 depth: Int64 acc: (List Json) -> (Result (Pair Json Int64) String)
  (let [(pVal (skipWs bs pos len))]
    (if (>= pVal len)
      (err (str "error at byte " (stringFromInt64 len) ": unexpected end of input in array"))
      (mt (parseJsonValue src bs pVal len depth)
        ((err e) (err e))
        ((ok p)
         (let [(val (pairFirst p))
               (pAfter (pairSecond p))
               (pSep (skipWs bs pAfter len))]
           (if (>= pSep len)
             (err (str "error at byte " (stringFromInt64 len) ": unclosed array"))
             (let [(b (bytesGet bs pSep))]
               (cond
                 ((= b 93)
                  (ok (pair (jarr (listReverse (cons val acc))) (+ pSep 1))))
                 ((= b 44)
                  (let [(pNext (skipWs bs (+ pSep 1) len))]
                    (if (>= pNext len)
                      (err (str "error at byte " (stringFromInt64 len) ": unclosed array after comma"))
                      (if (= (bytesGet bs pNext) 93)
                        (err (str "error at byte " (stringFromInt64 pSep) ": trailing comma in array"))
                        (parseArrayElements src bs pNext len depth (cons val acc))))))
                 (else
                  (err (str "error at byte " (stringFromInt64 pSep) ": expected ',' or ']' in array")))))))))))

fn parseJsonArray src: String bs: Bytes pos: Int64 len: Int64 depth: Int64 -> (Result (Pair Json Int64) String)
  (if (> depth 512)
    (err (str "error at byte " (stringFromInt64 pos) ": nesting depth limit 512 exceeded"))
    (let [(pFirst (skipWs bs (+ pos 1) len))]
      (if (>= pFirst len)
        (err (str "error at byte " (stringFromInt64 len) ": unclosed array"))
        (if (= (bytesGet bs pFirst) 93)
          (ok (pair (jarr (list)) (+ pFirst 1)))
          (parseArrayElements src bs pFirst len depth (list))))))

fn parseObjectPairs src: String bs: Bytes pos: Int64 len: Int64 depth: Int64 acc: (List (Pair String Json)) -> (Result (Pair Json Int64) String)
  (let [(pKey (skipWs bs pos len))]
    (if (>= pKey len)
      (err (str "error at byte " (stringFromInt64 len) ": unexpected end of input in object"))
      (if (!= (bytesGet bs pKey) 34)
        (err (str "error at byte " (stringFromInt64 pKey) ": expected string key in object"))
        (mt (parseJsonString src pKey)
          ((err e) (err e))
          ((ok pStr)
           (let [(key (pairFirst pStr))
                 (pKeyEnd (pairSecond pStr))
                 (pColon (skipWs bs pKeyEnd len))]
             (if (>= pColon len)
               (err (str "error at byte " (stringFromInt64 len) ": expected ':' after object key"))
               (if (!= (bytesGet bs pColon) 58)
                 (err (str "error at byte " (stringFromInt64 pColon) ": expected ':' after object key"))
                 (let [(pVal (skipWs bs (+ pColon 1) len))]
                   (if (>= pVal len)
                     (err (str "error at byte " (stringFromInt64 len) ": expected value after ':'"))
                     (mt (parseJsonValue src bs pVal len depth)
                       ((err e) (err e))
                       ((ok pValRes)
                        (let [(val (pairFirst pValRes))
                              (pValEnd (pairSecond pValRes))
                              (pSep (skipWs bs pValEnd len))]
                          (if (>= pSep len)
                            (err (str "error at byte " (stringFromInt64 len) ": unclosed object"))
                            (let [(b (bytesGet bs pSep))]
                              (cond
                                ((= b 125)
                                 (ok (pair (jobj (listReverse (cons (pair key val) acc))) (+ pSep 1))))
                                ((= b 44)
                                 (let [(pNext (skipWs bs (+ pSep 1) len))]
                                   (if (>= pNext len)
                                     (err (str "error at byte " (stringFromInt64 len) ": unclosed object after comma"))
                                     (if (= (bytesGet bs pNext) 125)
                                       (err (str "error at byte " (stringFromInt64 pSep) ": trailing comma in object"))
                                       (parseObjectPairs src bs pNext len depth (cons (pair key val) acc))))))
                                (else
                                 (err (str "error at byte " (stringFromInt64 pSep) ": expected ',' or '}' in object")))))))))))))))))))

fn parseJsonObject src: String bs: Bytes pos: Int64 len: Int64 depth: Int64 -> (Result (Pair Json Int64) String)
  (if (> depth 512)
    (err (str "error at byte " (stringFromInt64 pos) ": nesting depth limit 512 exceeded"))
    (let [(pFirst (skipWs bs (+ pos 1) len))]
      (if (>= pFirst len)
        (err (str "error at byte " (stringFromInt64 len) ": unclosed object"))
        (if (= (bytesGet bs pFirst) 125)
          (ok (pair (jobj (list)) (+ pFirst 1)))
          (parseObjectPairs src bs pFirst len depth (list))))))

fn parseJsonValue src: String bs: Bytes pos: Int64 len: Int64 depth: Int64 -> (Result (Pair Json Int64) String)
  (if (>= pos len)
    (err (str "error at byte " (stringFromInt64 pos) ": unexpected end of input"))
    (let [(b (bytesGet bs pos))]
      (cond
        ((= b 34) (mt (parseJsonString src pos) ((ok p) (ok (pair (jstr (pairFirst p)) (pairSecond p)))) ((err e) (err e))))
        ((= b 123) (parseJsonObject src bs pos len (+ depth 1)))
        ((= b 91) (parseJsonArray src bs pos len (+ depth 1)))
        ((or (= b 45) (and (>= b 48) (<= b 57))) (parseJsonNumber src bs pos len))
        ((and (= b 116) (and (<= (+ pos 4) len) (= (optionOr (stringSlice src pos (+ pos 4)) "") "true")))
         (ok (pair (jbool true) (+ pos 4))))
        ((and (= b 102) (and (<= (+ pos 5) len) (= (optionOr (stringSlice src pos (+ pos 5)) "") "false")))
         (ok (pair (jbool false) (+ pos 5))))
        ((and (= b 110) (and (<= (+ pos 4) len) (= (optionOr (stringSlice src pos (+ pos 4)) "") "null")))
         (ok (pair (jnull) (+ pos 4))))
        (else (err (str "error at byte " (stringFromInt64 pos) ": unexpected character"))))))

fn jsonParse src: String -> (Result Json String)
  (let [(bs (stringToBytes src))
        (len (bytesLength bs))
        (startPos (skipWs bs 0 len))]
    (if (>= startPos len)
      (err "error at byte 0: empty JSON input")
      (mt (parseJsonValue src bs startPos len 0)
        ((err e) (err e))
        ((ok p)
         (let [(val (pairFirst p))
               (nextPos (pairSecond p))
               (endPos (skipWs bs nextPos len))]
           (if (< endPos len)
             (err (str "error at byte " (stringFromInt64 endPos) ": trailing garbage after JSON value"))
             (ok val)))))))

fn findKeyInPairs kvs: (List (Pair String Json)) key: String -> (Option Json)
  (if (listEmpty? kvs) none
    (let [(p (preludeHead kvs))]
      (if (= (pairFirst p) key)
        (some (pairSecond p))
        (findKeyInPairs (preludeTail kvs) key))))

fn jsonGet obj: Json key: String -> (Option Json)
  (mt obj
    ((jobj kvs) (findKeyInPairs kvs key))
    (_ none))

fn hexDigit b: Int64 -> String
  (let [(hex "0123456789abcdef")]
    (optionOr (stringSlice hex b (+ b 1)) ""))

fn escapeControlChar b: Int64 -> String
  (str "\\u00" (hexDigit (/ b 16)) (hexDigit (mod b 16)))

fn scanEmitStr s: String bs: Bytes len: Int64 pos: Int64 start: Int64 pieces: (List String) -> String
  (if (>= pos len)
    (let [(tail (optionOr (stringSlice s start len) ""))
          (all (cons tail pieces))]
      (str "\"" (stringJoin (listReverse all) "") "\""))
    (let [(b (bytesGet bs pos))]
      (cond
        ((= b 34) (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons "\\\"" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 92) (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons "\\\\" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 8)  (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons "\\b" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 9)  (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons "\\t" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 10) (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons "\\n" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 12) (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons "\\f" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((= b 13) (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons "\\r" (cons (optionOr (stringSlice s start pos) "") pieces))))
        ((< b 32) (scanEmitStr s bs len (+ pos 1) (+ pos 1) (cons (escapeControlChar b) (cons (optionOr (stringSlice s start pos) "") pieces))))
        (else (scanEmitStr s bs len (+ pos 1) start pieces)))))

fn emitString s: String -> String
  (let [(bs (stringToBytes s))
        (len (bytesLength bs))]
    (scanEmitStr s bs len 0 0 (list)))

fn emitPair p: (Pair String Json) -> String
  (mt p
    ((pair k v) (str (emitString k) ":" (jsonEmit v))))

fn jsonEmit val: Json -> String
  (mt val
    ((jnull) "null")
    ((jbool b) (if b "true" "false"))
    ((jint i) (stringFromInt64 i))
    ((jfloat f) (stringFromFloat64 f))
    ((jnum n) (stringFromFloat64 n))
    ((jstr s) (emitString s))
    ((jarr xs) (str "[" (stringJoin (map jsonEmit xs) ",") "]"))
    ((jobj kvs) (str "{" (stringJoin (map emitPair kvs) ",") "}")))
