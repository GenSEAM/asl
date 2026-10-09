(module ws/asl/tools/observe/session
  :x [JVal jsonParse pyStr truthy? fnmatch? ownsCover? ownsMeet readJournal observeSession!]
  :i [(ws/asl/tools/observe/common :a c)])

fn staleAfter -> Int64
  1800

fn pathsCap -> Int64
  8

fn alnum? k: Int64 -> Bool
  (or (and (>= k 48) (<= k 57)) (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)))

fn alpha? k: Int64 -> Bool
  (or (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)))

fn sessionId? s: String -> Bool
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (and (> n 0) (alnum? (bytesGet bs 0))
         (listAll? (fn [(i Int64)] -> Bool (let [(k (bytesGet bs i))] (or (alnum? k) (= k 46) (= k 95) (= k 45)))) (range 1 n))))

(enum JVal
  (:c jNull [])
  (:c jBool [(b Bool)])
  (:c jInt [(digits String)])
  (:c jFloat [(x Float64)])
  (:c jStr [(s String)])
  (:c jArr [(xs (List JVal))])
  (:c jObj [(kvs (List (Pair String JVal)))]))

(schema JP (:f v JVal) (:f at Int64))

fn byteAt bs: Bytes i: Int64 n: Int64 -> Int64
  (if (< i n) (bytesGet bs i) -1)

fn skipWs bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(b (byteAt bs i n))]
    (if (or (= b 32) (= b 9) (= b 10) (= b 13)) (skipWs bs (+ i 1) n) i))

fn sliceOf s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn digitsEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(b (byteAt bs i n))] (if (and (>= b 48) (<= b 57)) (digitsEnd bs (+ i 1) n) i))

fn hexVal b: Int64 -> Int64
  (cond ((and (>= b 48) (<= b 57)) (- b 48)) ((and (>= b 97) (<= b 102)) (- b 87)) ((and (>= b 65) (<= b 70)) (- b 55)) (else -1))

fn hex4 bs: Bytes i: Int64 n: Int64 -> Int64
  (if (> (+ i 4) n)
    -1
    (let [(a (hexVal (bytesGet bs i))) (b (hexVal (bytesGet bs (+ i 1)))) (d (hexVal (bytesGet bs (+ i 2)))) (e (hexVal (bytesGet bs (+ i 3))))]
      (if (or (< a 0) (< b 0) (< d 0) (< e 0)) -1 (+ (* a 4096) (* b 256) (* d 16) e))))

fn byteStr k: Int64 -> String
  (optionOr (stringSlice (byteTable) k (+ k 1)) "")

fn byteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn utf8Of cp: Int64 -> String
  (cond
    ((< cp 128) (byteStr cp))
    ((< cp 2048) (str (byteStr (+ 192 (/ cp 64))) (byteStr (+ 128 (mod cp 64)))))
    ((< cp 65536) (str (byteStr (+ 224 (/ cp 4096))) (byteStr (+ 128 (mod (/ cp 64) 64))) (byteStr (+ 128 (mod cp 64)))))
    (else (str (byteStr (+ 240 (/ cp 262144))) (byteStr (+ 128 (mod (/ cp 4096) 64))) (byteStr (+ 128 (mod (/ cp 64) 64))) (byteStr (+ 128 (mod cp 64))))))

fn strBody s: String bs: Bytes i: Int64 n: Int64 start: Int64 acc: (List String) -> (Result JP String)
  (let [(b (byteAt bs i n))]
    (cond
      ((< b 0) (err "Unterminated string"))
      ((= b 34) (ok (JP :v (jStr (c/catAll (listReverse (cons (sliceOf s start i) acc)))) :at (+ i 1))))
      ((< b 32) (err "Invalid control character"))
      ((= b 92)
        (let [(e (byteAt bs (+ i 1) n)) (pre (cons (sliceOf s start i) acc))]
          (cond
            ((= e 34) (strBody s bs (+ i 2) n (+ i 2) (cons "\"" pre)))
            ((= e 92) (strBody s bs (+ i 2) n (+ i 2) (cons "\\" pre)))
            ((= e 47) (strBody s bs (+ i 2) n (+ i 2) (cons "/" pre)))
            ((= e 98) (strBody s bs (+ i 2) n (+ i 2) (cons "\x08" pre)))
            ((= e 102) (strBody s bs (+ i 2) n (+ i 2) (cons "\x0c" pre)))
            ((= e 110) (strBody s bs (+ i 2) n (+ i 2) (cons "\n" pre)))
            ((= e 114) (strBody s bs (+ i 2) n (+ i 2) (cons "\r" pre)))
            ((= e 116) (strBody s bs (+ i 2) n (+ i 2) (cons "\t" pre)))
            ((= e 117)
              (let [(u (hex4 bs (+ i 2) n))]
                (cond
                  ((< u 0) (err "Invalid \\uXXXX escape"))
                  ((and (>= u 55296) (<= u 56319) (= (byteAt bs (+ i 6) n) 92) (= (byteAt bs (+ i 7) n) 117))
                    (let [(lo (hex4 bs (+ i 8) n))]
                      (if (and (>= lo 56320) (<= lo 57343))
                        (strBody s bs (+ i 12) n (+ i 12) (cons (utf8Of (+ 65536 (* (- u 55296) 1024) (- lo 56320))) pre))
                        (strBody s bs (+ i 6) n (+ i 6) (cons (utf8Of u) pre)))))
                  (else (strBody s bs (+ i 6) n (+ i 6) (cons (utf8Of u) pre))))))
            (else (err "Invalid \\escape")))))
      (else (strBody s bs (+ i 1) n start acc))))

fn numberAt s: String bs: Bytes i: Int64 n: Int64 -> (Result JP String)
  (let [(neg (= (byteAt bs i n) 45))
        (j (if neg (+ i 1) i))
        (b (byteAt bs j n))]
    (cond
      ((and neg (= b 73) (= (sliceOf s j (+ j 8)) "Infinity")) (ok (JP :v (jFloat (floatNegInf)) :at (+ j 8))))
      ((not (and (>= b 48) (<= b 57))) (err "Expecting value"))
      (else
        (let [(intEnd (if (= b 48) (+ j 1) (digitsEnd bs j n)))
              (fracEnd (if (and (= (byteAt bs intEnd n) 46) (let [(d (byteAt bs (+ intEnd 1) n))] (and (>= d 48) (<= d 57)))) (digitsEnd bs (+ intEnd 1) n) intEnd))
              (e (byteAt bs fracEnd n))
              (expStart (if (or (= e 101) (= e 69)) (let [(sg (byteAt bs (+ fracEnd 1) n))] (if (or (= sg 43) (= sg 45)) (+ fracEnd 2) (+ fracEnd 1))) -1))
              (expEnd (if (and (>= expStart 0) (let [(d (byteAt bs expStart n))] (and (>= d 48) (<= d 57)))) (digitsEnd bs expStart n) fracEnd))
              (text (sliceOf s i expEnd))]
          (if (and (= fracEnd intEnd) (= expEnd fracEnd))
            (let [(mag (c/lstripChars (sliceOf s j intEnd) "0"))]
              (ok (JP :v (jInt (if (stringEmpty? mag) "0" (if neg (str "-" mag) mag))) :at expEnd)))
            (mt (stringToFloat64 text)
              ((some f) (ok (JP :v (jFloat f) :at expEnd)))
              ((none) (err "Invalid number"))))))))

fn valueAt s: String bs: Bytes i: Int64 n: Int64 depth: Int64 -> (Result JP String)
  (let [(b (byteAt bs i n))]
    (cond
      ((> depth 900) (err "RecursionError"))
      ((= b 34) (strBody s bs (+ i 1) n (+ i 1) (list)))
      ((= b 123) (objectAt s bs (skipWs bs (+ i 1) n) n depth (list) true))
      ((= b 91) (arrayAt s bs (skipWs bs (+ i 1) n) n depth (list) true))
      ((= (sliceOf s i (+ i 4)) "null") (ok (JP :v (jNull) :at (+ i 4))))
      ((= (sliceOf s i (+ i 4)) "true") (ok (JP :v (jBool true) :at (+ i 4))))
      ((= (sliceOf s i (+ i 5)) "false") (ok (JP :v (jBool false) :at (+ i 5))))
      ((= (sliceOf s i (+ i 3)) "NaN") (ok (JP :v (jFloat (floatNan)) :at (+ i 3))))
      ((= (sliceOf s i (+ i 8)) "Infinity") (ok (JP :v (jFloat (floatInf)) :at (+ i 8))))
      (else (numberAt s bs i n))))

fn arrayAt s: String bs: Bytes i: Int64 n: Int64 depth: Int64 acc: (List JVal) first: Bool -> (Result JP String)
  (if (and first (= (byteAt bs i n) 93))
    (ok (JP :v (jArr (list)) :at (+ i 1)))
    (mt (valueAt s bs i n (+ depth 1))
      ((err e) (err e))
      ((ok p)
        (let [(j (skipWs bs p.at n)) (b (byteAt bs j n)) (acc2 (cons p.v acc))]
          (cond
            ((= b 93) (ok (JP :v (jArr (listReverse acc2)) :at (+ j 1))))
            ((= b 44) (arrayAt s bs (skipWs bs (+ j 1) n) n depth acc2 false))
            (else (err "Expecting ',' delimiter")))))))

fn putKey kvs: (List (Pair String JVal)) k: String v: JVal -> (List (Pair String JVal))
  (if (listAny? (fn [(p (Pair String JVal))] -> Bool (= (pairFirst p) k)) kvs)
    (map (fn [(p (Pair String JVal))] -> (Pair String JVal) (if (= (pairFirst p) k) (pair k v) p)) kvs)
    (listAppend kvs (list (pair k v))))

fn objectAt s: String bs: Bytes i: Int64 n: Int64 depth: Int64 acc: (List (Pair String JVal)) first: Bool -> (Result JP String)
  (let [(b (byteAt bs i n))]
    (cond
      ((and first (= b 125)) (ok (JP :v (jObj (list)) :at (+ i 1))))
      ((!= b 34) (err "Expecting property name enclosed in double quotes"))
      (else
        (mt (strBody s bs (+ i 1) n (+ i 1) (list))
          ((err e) (err e))
          ((ok kp)
            (let [(j (skipWs bs kp.at n))]
              (if (!= (byteAt bs j n) 58)
                (err "Expecting ':' delimiter")
                (mt (valueAt s bs (skipWs bs (+ j 1) n) n (+ depth 1))
                  ((err e) (err e))
                  ((ok vp)
                    (let [(key (mt kp.v ((jStr k) k) (_ "")))
                          (acc2 (putKey acc key vp.v))
                          (m (skipWs bs vp.at n))
                          (d (byteAt bs m n))]
                      (cond
                        ((= d 125) (ok (JP :v (jObj acc2) :at (+ m 1))))
                        ((= d 44) (objectAt s bs (skipWs bs (+ m 1) n) n depth acc2 false))
                        (else (err "Expecting ',' delimiter")))))))))))))

fn jsonParse s: String -> (Result JVal String)
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (if (and (>= n 3) (= (bytesGet bs 0) 239) (= (bytesGet bs 1) 187) (= (bytesGet bs 2) 191))
      (err "Unexpected UTF-8 BOM")
      (mt (valueAt s bs (skipWs bs 0 n) n 0)
        ((err e) (err e))
        ((ok p) (if (= (skipWs bs p.at n) n) (ok p.v) (err "Extra data"))))))

fn truthy? v: JVal -> Bool
  (mt v
    ((jNull) false)
    ((jBool b) b)
    ((jInt d) (!= d "0"))
    ((jFloat x) (not (= x 0.0)))
    ((jStr s) (not (stringEmpty? s)))
    ((jArr xs) (not (listEmpty? xs)))
    ((jObj kvs) (not (listEmpty? kvs))))

fn hexN n: Int64 width: Int64 -> String
  (if (<= width 0) "" (str (hexN (/ n 16) (- width 1)) (optionOr (stringSlice "0123456789abcdef" (mod n 16) (+ (mod n 16) 1)) "0")))

fn pyReprStr s: String -> String
  (let [(q (if (and (stringContains? s "'") (not (stringContains? s "\""))) "\"" "'"))
        (parts (map (fn [(cp (Pair Int64 Int64))] -> String
                      (let [(k (pairFirst cp)) (at (pairSecond cp))]
                        (cond
                          ((= k 92) "\\\\")
                          ((and (= k 39) (= q "'")) "\\'")
                          ((and (= k 34) (= q "\"")) "\\\"")
                          ((= k 10) "\\n") ((= k 13) "\\r") ((= k 9) "\\t")
                          ((or (< k 32) (= k 127) (and (>= k 128) (<= k 160)) (= k 173)) (str "\\x" (hexN k 2)))
                          ((or (= k 5760) (and (>= k 8192) (<= k 8207)) (and (>= k 8232) (<= k 8239)) (and (>= k 8287) (<= k 8292)) (= k 12288) (= k 65279)
                               (and (>= k 55296) (<= k 57343)))
                            (str "\\u" (hexN k 4)))
                          (else (let [(bs (stringToBytes s))] (sliceOf s at (+ at (cpLen bs at))))))))
                    (c/charCodes s)))]
    (str q (c/joinWith parts "") q))

fn cpLen bs: Bytes at: Int64 -> Int64
  (let [(b (bytesGet bs at))] (cond ((< b 128) 1) ((< b 224) 2) ((< b 240) 3) (else 4)))

fn pyRepr v: JVal -> String
  (mt v
    ((jStr s) (pyReprStr s))
    ((jArr xs) (str "[" (c/joinWith (map pyRepr xs) ", ") "]"))
    ((jObj kvs) (str "{" (c/joinWith (map (fn [(p (Pair String JVal))] -> String (str (pyReprStr (pairFirst p)) ": " (pyRepr (pairSecond p)))) kvs) ", ") "}"))
    (_ (pyStr v)))

fn pyStr v: JVal -> String
  (mt v
    ((jNull) "None")
    ((jBool b) (if b "True" "False"))
    ((jInt d) d)
    ((jFloat x) (stringFromFloat64 x))
    ((jStr s) s)
    (_ (pyRepr v)))

fn typeName v: JVal -> String
  (mt v ((jNull) "NoneType") ((jBool _) "bool") ((jInt _) "int") ((jFloat _) "float") ((jStr _) "str") ((jArr _) "list") ((jObj _) "dict"))

fn objGet kvs: (List (Pair String JVal)) k: String -> (Option JVal)
  (mt (listHead (filter (fn [(p (Pair String JVal))] -> Bool (= (pairFirst p) k)) kvs)) ((some p) (some (pairSecond p))) ((none) (none)))

fn vfsRoot! root: String ctx: c/Ctx -> (Option String)
  (let [(envDir (optionOr (c/ctxEnv ctx "ASL_VFS_DIR") ""))
        (wsAsl (c/joinPath root ".asl"))
        (d (cond
             ((not (stringEmpty? envDir)) envDir)
             ((and (c/isDir? wsAsl) (not (c/isLink? wsAsl))) (c/joinPath wsAsl "vfs"))
             (else (c/joinPath (c/ctxHome ctx) (str ".cache/asl/vfs/" (hashOf (c/realPathLoose! root ctx.cwd)))))))
        (abs (c/joinPath ctx.cwd d))]
    (if (c/isDir? abs) (some abs) (none)))

fn hashOf s: String -> String
  (optionOr (stringSlice (bytesSha256 (stringToBytes s)) 0 16) "")

fn errClass e: String -> String
  (cond ((stringContains? e "notFound") "FileNotFoundError") ((stringContains? e "permission") "PermissionError") ((stringContains? e "isDir") "IsADirectoryError") (else "OSError"))

fn validUtf8? s: String -> Bool
  (not (listAny? (fn [(cp (Pair Int64 Int64))] -> Bool (< (pairFirst cp) 0)) (c/charCodes s)))

fn stagedPaths! store: String -> (Result (Pair (List String) Int64) String)
  (mt (dirList store)
    ((err e) (err (str (errClass e) ": " e)))
    ((ok names)
      (fold (fn [(acc (Result (Pair (List String) Int64) String)) (name String)] -> (Result (Pair (List String) Int64) String)
              (mt acc
                ((err e) (err e))
                ((ok st)
                  (let [(full (c/joinPath store name))]
                    (if (or (not (stringEndsWith? name ".meta")) (not (c/isFile? full)))
                      (ok st)
                      (let [(mtime (mt (fileStat full) ((ok s) s.mtime) ((err _) 0)))
                            (newest (max (pairSecond st) mtime))]
                        (mt (fileReadString full)
                          ((err e) (ok (pair (cons (str name " (unreadable meta: " (errClass e) ")") (pairFirst st)) newest)))
                          ((ok text)
                            (if (not (validUtf8? text))
                              (ok (pair (cons (str name " (unreadable meta: UnicodeDecodeError)") (pairFirst st)) newest))
                              (mt (jsonParse text)
                                ((err e) (if (= e "RecursionError")
                                           (err "RecursionError: maximum recursion depth exceeded")
                                           (ok (pair (cons (str name " (unreadable meta: JSONDecodeError)") (pairFirst st)) newest))))
                                ((ok v)
                                  (mt v
                                    ((jObj kvs)
                                      (let [(pick (fn [(k String)] -> (Option JVal) (mt (objGet kvs k) ((some x) (if (truthy? x) (some x) (none))) ((none) (none)))))
                                            (rel (mt (pick "rel") ((some x) (pyStr x)) ((none) (mt (pick "path") ((some x) (pyStr x)) ((none) name)))))]
                                        (ok (pair (cons rel (pairFirst st)) newest))))
                                    (_ (err (str "AttributeError: '" (typeName v) "' object has no attribute 'get'")))))))))))))))
            (ok (pair (list) 0)) names)))

(schema Journal (:f mode String) (:f owns (List String)) (:f turns String) (:f result (Option String)))

fn spaceAt? bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    0
    (let [(b (bytesGet bs i))]
      (cond
        ((< b 128) (if (c/pyIsSpaceCode b) 1 0))
        (else (let [(cp (pairFirst (codeAt3 bs i n)))] (if (and (>= cp 0) (c/pyIsSpaceCode cp)) (pairSecond (codeAt3 bs i n)) 0))))))

fn codeAt3 bs: Bytes i: Int64 n: Int64 -> (Pair Int64 Int64)
  (let [(b0 (bytesGet bs i))]
    (cond
      ((and (>= b0 194) (< b0 224) (< (+ i 1) n)) (pair (+ (* (- b0 192) 64) (- (bytesGet bs (+ i 1)) 128)) 2))
      ((and (>= b0 224) (< b0 240) (< (+ i 2) n)) (pair (+ (* (- b0 224) 4096) (* (- (bytesGet bs (+ i 1)) 128) 64) (- (bytesGet bs (+ i 2)) 128)) 3))
      (else (pair -1 1))))

fn spaces1 bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(k (spaceAt? bs i n))] (if (= k 0) -1 (spaces0 bs (+ i k) n)))

fn spaces0 bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(k (spaceAt? bs i n))] (if (= k 0) i (spaces0 bs (+ i k) n)))

fn digits1 bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(e (digitsEnd bs i n))] (if (= e i) -1 e))

fn letters1 bs: Bytes i: Int64 n: Int64 -> Int64
  (let [(e (lettersEnd bs i n))] (if (= e i) -1 e))

fn lettersEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (alpha? (bytesGet bs i))) (lettersEnd bs (+ i 1) n) i)

fn litAt s: String i: Int64 lit: String -> Int64
  (if (= (sliceOf s i (+ i (stringLength lit))) lit) (+ i (stringLength lit)) -1)

fn turnDigits line: String -> (Option String)
  (let [(bs (stringToBytes line)) (n (bytesLength bs)) (a (litAt line 0 "(:turn"))]
    (if (< a 0) (none)
      (let [(b (spaces1 bs a n))]
        (if (< b 0) (none) (let [(d (digits1 bs b n))] (if (< d 0) (none) (some (sliceOf line b d))))))))

fn deliverOf line: String -> (Option String)
  (let [(bs (stringToBytes line)) (n (bytesLength bs))
        (steps (fn [(i Int64)] -> Int64
                 (let [(a (spaces1 bs i n))]
                   (if (< a 0) -1
                     (let [(b (digits1 bs a n))]
                       (if (< b 0) -1
                         (let [(c1 (spaces1 bs b n))]
                           (if (< c1 0) -1
                             (let [(d (litAt line c1 ":intent"))]
                               (if (< d 0) -1
                                 (let [(e (spaces1 bs d n))]
                                   (if (< e 0) -1
                                     (let [(f (litAt line e ":deliver"))]
                                       (if (< f 0) -1 (spaces1 bs f n)))))))))))))))
        (a (litAt line 0 "(:turn"))]
    (if (< a 0) (none)
      (let [(g (steps a))]
        (if (< g 0) (none) (let [(h (letters1 bs g n))] (if (< h 0) (none) (some (sliceOf line g h))))))))

fn quotedEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    -1
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 34) (+ i 1))
        ((= b 92) (if (and (< (+ i 1) n) (!= (bytesGet bs (+ i 1)) 10)) (quotedEnd bs (+ i 2) n) -1))
        (else (quotedEnd bs (+ i 1) n)))))

fn dropTasks line: String bs: Bytes i: Int64 n: Int64 start: Int64 acc: (List String) -> String
  (if (>= i n)
    (c/catAll (listReverse (cons (sliceOf line start n) acc)))
    (let [(a (litAt line i ":task"))
          (m (if (< a 0) -1 (let [(b (spaces1 bs a n))] (if (or (< b 0) (!= (byteAt bs b n) 34)) -1 (quotedEnd bs (+ b 1) n)))))]
      (if (< m 0)
        (dropTasks line bs (+ i 1) n start acc)
        (dropTasks line bs m n m (cons (sliceOf line start i) acc)))))

fn searchFrom line: String i: Int64 matcher: (fn [Int64] -> (Option String)) -> (Option String)
  (if (> i (stringLength line))
    (none)
    (mt (matcher i) ((some v) (some v)) ((none) (searchFrom line (+ i 1) matcher))))

fn quotedLetters line: String bs: Bytes n: Int64 key: String noAuto: Bool -> (fn [Int64] -> (Option String))
  (fn [(i Int64)] -> (Option String)
    (let [(a (litAt line i key))]
      (if (< a 0) (none)
        (let [(b (spaces1 bs a n))]
          (if (or (< b 0) (!= (byteAt bs b n) 34)) (none)
            (let [(d (letters1 bs (+ b 1) n))]
              (if (or (< d 0) (!= (byteAt bs d n) 34)) (none)
                (let [(word (sliceOf line (+ b 1) d))]
                  (if (and noAuto (= word "auto")) (none) (some word))))))))))

fn kwLetters line: String bs: Bytes n: Int64 key: String -> (fn [Int64] -> (Option String))
  (fn [(i Int64)] -> (Option String)
    (let [(a (litAt line i key))]
      (if (< a 0) (none)
        (let [(b (spaces1 bs a n))]
          (if (or (< b 0) (!= (byteAt bs b n) 58)) (none)
            (let [(d (letters1 bs (+ b 1) n))]
              (if (< d 0) (none) (some (sliceOf line (+ b 1) d)))))))))

fn ownsGroup line: String bs: Bytes n: Int64 -> (fn [Int64] -> (Option String))
  (fn [(i Int64)] -> (Option String)
    (let [(a (litAt line i ":owns"))]
      (if (< a 0) (none)
        (let [(b (spaces1 bs a n))]
          (if (or (< b 0) (!= (byteAt bs b n) 40)) (none)
            (mt (stringIndexOf (sliceOf line (+ b 1) n) ")")
              ((none) (none))
              ((some k) (some (sliceOf line (+ b 1) (+ b 1 k))))))))))

fn findQuoted g: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (if (= (bytesGet bs i) 34)
      (let [(e (quotedEnd bs (+ i 1) n))]
        (if (< e 0) (findQuoted g bs (+ i 1) n acc) (findQuoted g bs e n (cons (sliceOf g (+ i 1) (- e 1)) acc))))
      (findQuoted g bs (+ i 1) n acc)))

fn unescapeOwn o: String -> String
  (stringReplace (stringReplace o "\\\"" "\"") "\\\\" "\\")

fn maxDigits a: String b: String -> String
  (let [(na (let [(t (c/lstripChars a "0"))] (if (stringEmpty? t) "0" t)))
        (nb (let [(t (c/lstripChars b "0"))] (if (stringEmpty? t) "0" t)))]
    (cond ((> (stringLength nb) (stringLength na)) nb) ((< (stringLength nb) (stringLength na)) na) ((> nb na) nb) (else na)))

(schema JState (:f j Journal) (:f deliver (Option String)))

fn journalLine st: JState line: String -> JState
  (let [(j st.j)]
    (cond
      ((stringStartsWith? line "(:turn ")
        (let [(t (mt (turnDigits line) ((some d) (maxDigits j.turns d)) ((none) j.turns)))
              (dv (mt (deliverOf line) ((some d) (some d)) ((none) st.deliver)))]
          (JState :j (Journal :mode j.mode :owns j.owns :turns t :result j.result) :deliver dv)))
      ((stringStartsWith? line "(:session ")
        (let [(lb (stringToBytes line))
              (head (dropTasks line lb 0 (bytesLength lb) 0 (list)))
              (bs (stringToBytes head)) (n (bytesLength bs))
              (mode (mt (searchFrom head 0 (quotedLetters head bs n ":modeHint" false))
                      ((some m) (some m))
                      ((none) (mt (searchFrom head 0 (quotedLetters head bs n ":intent" true))
                                ((some m) (some m))
                                ((none) (searchFrom head 0 (kwLetters head bs n ":mode")))))))
              (owns (mt (searchFrom head 0 (ownsGroup head bs n))
                      ((some g) (map unescapeOwn (let [(gb (stringToBytes g))] (findQuoted g gb 0 (bytesLength gb) (list)))))
                      ((none) j.owns)))]
          (with st :j (Journal :mode (optionOr mode j.mode) :owns owns :turns j.turns :result j.result))))
      ((stringStartsWith? line "(:result ")
        (let [(bs (stringToBytes line))
              (status (optionOr (searchFrom line 0 (kwLetters line bs (bytesLength bs) ":status")) "unknown"))]
          (with st :j (Journal :mode j.mode :owns j.owns :turns j.turns :result (some status)))))
      (else st)))

fn readJournal text: String -> Journal
  (let [(norm (c/universalNewlines (c/utf8Replace text)))
        (st (fold journalLine (JState :j (Journal :mode "unknown" :owns (list) :turns "0" :result (none)) :deliver (none)) (c/keepEndsLines norm)))
        (j st.j)]
    (mt st.deliver
      ((some d) (Journal :mode d :owns j.owns :turns j.turns :result j.result))
      ((none) j)))

(enum Glob (:c gStar []) (:c gAny []) (:c gLit [(k Int64)]) (:c gClass [(neg Bool) (chars (List Int64)) (ranges (List (Pair Int64 Int64)))]))

fn codesOf s: String -> (List Int64)
  (map (fn [(cp (Pair Int64 Int64))] -> Int64 (pairFirst cp)) (c/charCodes s))

fn listFind xs: (List Int64) i: Int64 target: Int64 -> Int64
  (mt (listGet xs i) ((none) -1) ((some x) (if (= x target) i (listFind xs (+ i 1) target))))

fn sub xs: (List Int64) a: Int64 b: Int64 -> (List Int64)
  (optionOr (listSlice xs a (max a b)) (list))

fn chunkLoop pat: (List Int64) i: Int64 k: Int64 j: Int64 acc: (List (List Int64)) -> (Pair (List (List Int64)) Int64)
  (let [(f (if (>= k j) -1 (let [(r (listFind (sub pat 0 j) k 45))] r)))]
    (if (< f 0)
      (pair acc i)
      (chunkLoop pat (+ f 1) (+ f 3) j (listAppend acc (list (sub pat i f))))))

fn lastOf xs: (List Int64) -> Int64
  (optionOr (listLast xs) -1)

fn mergeRanges chunks: (List (List Int64)) k: Int64 -> (List (List Int64))
  (if (< k 1)
    chunks
    (let [(a (optionOr (listGet chunks (- k 1)) (list))) (b (optionOr (listGet chunks k) (list)))]
      (if (> (lastOf a) (optionOr (listHead b) -1))
        (let [(merged (listAppend (sub a 0 (- (listLength a) 1)) (sub b 1 (listLength b))))
              (next (listAppend (sub2 chunks 0 (- k 1)) (cons merged (sub2 chunks (+ k 1) (listLength chunks)))))]
          (mergeRanges next (- k 1)))
        (mergeRanges chunks (- k 1)))))

fn sub2 xs: (List (List Int64)) a: Int64 b: Int64 -> (List (List Int64))
  (optionOr (listSlice xs a (max a b)) (list))

fn classOf pat: (List Int64) i: Int64 j: Int64 -> Glob
  (let [(stuff (sub pat i j))
        (chunks (if (not (listContains? stuff 45))
                  (list stuff)
                  (let [(cl (chunkLoop pat i (if (= (optionOr (listGet pat i) -1) 33) (+ i 2) (+ i 1)) j (list)))
                        (last (sub pat (pairSecond cl) j))]
                    (if (listEmpty? last)
                      (let [(cs (pairFirst cl))] (listAppend (sub2 cs 0 (- (listLength cs) 1)) (list (listAppend (optionOr (listLast cs) (list)) (list 45)))))
                      (listAppend (pairFirst cl) (list last))))))
        (merged (mergeRanges chunks (- (listLength chunks) 1)))
        (flat (fold (fn [(acc (List Int64)) (ch (List Int64))] -> (List Int64) (listAppend acc ch)) (list) merged))
        (neg (= (optionOr (listHead flat) -1) 33))
        (body (if neg (optionOr (listTail flat) (list)) flat))
        (ranges (map (fn [(k Int64)] -> (Pair Int64 Int64) (pair (lastOf (optionOr (listGet merged (- k 1)) (list))) (optionOr (listHead (optionOr (listGet merged k) (list))) -1)))
                     (range 1 (listLength merged))))]
    (gClass neg body ranges))

fn compileGlob pat: (List Int64) i: Int64 acc: (List Glob) -> (List Glob)
  (mt (listGet pat i)
    ((none) (listReverse acc))
    ((some ch)
      (cond
        ((= ch 42) (compileGlob pat (+ i 1) (if (mt (listHead acc) ((some g) (mt g ((gStar) true) (_ false))) ((none) false)) acc (cons (gStar) acc))))
        ((= ch 63) (compileGlob pat (+ i 1) (cons (gAny) acc)))
        ((= ch 91)
          (let [(n (listLength pat))
                (j0 (+ i 1))
                (j1 (if (and (< j0 n) (= (optionOr (listGet pat j0) -1) 33)) (+ j0 1) j0))
                (j2 (if (and (< j1 n) (= (optionOr (listGet pat j1) -1) 93)) (+ j1 1) j1))
                (j (let [(f (listFind pat j2 93))] (if (< f 0) n f)))]
            (if (>= j n)
              (compileGlob pat (+ i 1) (cons (gLit 91) acc))
              (compileGlob pat (+ j 1) (cons (classOf pat (+ i 1) j) acc)))))
        (else (compileGlob pat (+ i 1) (cons (gLit ch) acc))))))

fn classHit? neg: Bool chars: (List Int64) ranges: (List (Pair Int64 Int64)) k: Int64 -> Bool
  (let [(hit (or (listContains? chars k) (listAny? (fn [(r (Pair Int64 Int64))] -> Bool (and (>= k (pairFirst r)) (<= k (pairSecond r)))) ranges)))]
    (cond
      ((and neg (listEmpty? chars) (listEmpty? ranges)) true)
      (neg (not hit))
      (else hit)))

fn globMatch ps: (List Glob) ts: (List Int64) -> Bool
  (mt (listHead ps)
    ((none) (listEmpty? ts))
    ((some p)
      (let [(prest (optionOr (listTail ps) (list)))]
        (mt p
          ((gStar) (or (globMatch prest ts) (and (not (listEmpty? ts)) (globMatch ps (optionOr (listTail ts) (list))))))
          (_ (mt (listHead ts)
               ((none) false)
               ((some t)
                 (and (mt p
                        ((gAny) true)
                        ((gLit k) (= k t))
                        ((gClass neg chars ranges) (classHit? neg chars ranges t))
                        ((gStar) true))
                      (globMatch prest (optionOr (listTail ts) (list)))))))))))

fn fnmatch? name: String pat: String -> Bool
  (globMatch (compileGlob (codesOf pat) 0 (list)) (codesOf name))

fn ownsCover? pattern: String path: String -> Bool
  (let [(pat (c/lstripChars (c/pyStrip pattern) "./")) (rel (c/lstripChars path "./"))]
    (or (= rel pat) (stringStartsWith? rel (str (c/rstripChars pat "/") "/"))
        (and (or (stringContains? pat "*") (stringContains? pat "?") (stringContains? pat "[")) (fnmatch? rel pat))))

fn ownsMeet a: (List String) b: (List String) -> (List String)
  (c/sortUnique
    (fold (fn [(acc (List String)) (x String)] -> (List String)
            (fold (fn [(acc2 (List String)) (y String)] -> (List String)
                    (cond ((ownsCover? x y) (cons y acc2)) ((ownsCover? y x) (cons x acc2)) (else acc2)))
                  acc b))
          (list) a))

fn pathList paths: (List String) -> String
  (let [(shown (listTake paths (pathsCap))) (more (- (listLength paths) (min (pathsCap) (listLength paths))))]
    (str "(" (c/joinWith (map c/quoted shown) " ") (if (> more 0) (str " :more " (stringFromInt64 more)) "") ")"))

(schema Sess (:f id String) (:f mode String) (:f owns (List String)) (:f turns String) (:f result (Option String))
             (:f staged (List String)) (:f at Int64) (:f ago Int64) (:f status String))

fn newSess sid: String -> Sess
  (Sess :id sid :mode "unknown" :owns (list) :turns "0" :result (none) :staged (list) :at 0 :ago 0 :status "")

fn findSess ss: (List Sess) sid: String -> (Option Sess)
  (listHead (filter (fn [(s Sess)] -> Bool (= s.id sid)) ss))

fn putSess ss: (List Sess) s: Sess -> (List Sess)
  (if (some? (findSess ss s.id))
    (map (fn [(x Sess)] -> Sess (if (= x.id s.id) s x)) ss)
    (listAppend ss (list s)))

fn journalSessions! jdir: String -> (Result (List Sess) String)
  (if (not (c/isDir? jdir))
    (ok (list))
    (mt (dirList jdir)
      ((err e) (err (str (errClass e) ": " e)))
      ((ok names)
        (fold (fn [(acc (Result (List Sess) String)) (name String)] -> (Result (List Sess) String)
                (mt acc
                  ((err e) (err e))
                  ((ok ss)
                    (let [(sid (sliceOf name 0 (- (stringLength name) 8))) (full (c/joinPath jdir name))]
                      (if (or (not (stringEndsWith? name ".journal")) (not (sessionId? sid)) (not (c/isFile? full)))
                        (ok ss)
                        (mt (fileReadString full)
                          ((err e) (err (str (errClass e) ": " e)))
                          ((ok text)
                            (let [(j (readJournal text))
                                  (s0 (optionOr (findSess ss sid) (newSess sid)))
                                  (mtime (mt (fileStat full) ((ok st) st.mtime) ((err _) 0)))]
                              (ok (putSess ss (Sess :id sid :mode j.mode :owns j.owns :turns j.turns :result j.result
                                                    :staged s0.staged :at (max s0.at mtime) :ago 0 :status "")))))))))))
              (ok (list)) names))))

fn storeSessions! store: String ss0: (List Sess) -> (Result (List Sess) String)
  (mt (dirList store)
    ((err e) (err (str (errClass e) ": " e)))
    ((ok names)
      (fold (fn [(acc (Result (List Sess) String)) (sid String)] -> (Result (List Sess) String)
              (mt acc
                ((err e) (err e))
                ((ok ss)
                  (let [(full (c/joinPath store sid))]
                    (if (or (not (c/isDir? full)) (not (sessionId? sid)))
                      (ok ss)
                      (mt (stagedPaths! full)
                        ((err e) (err e))
                        ((ok sp)
                          (let [(paths (listSort (pairFirst sp)))]
                            (if (and (listEmpty? paths) (none? (findSess ss sid)))
                              (ok ss)
                              (let [(s0 (optionOr (findSess ss sid) (newSess sid)))]
                                (ok (putSess ss (Sess :id sid :mode s0.mode :owns s0.owns :turns s0.turns :result s0.result
                                                      :staged paths :at (max s0.at (pairSecond sp)) :ago 0 :status "")))))))))))))
            (ok ss0) names)))

fn withStatus now: Int64 s: Sess -> Sess
  (let [(ago (max 0 (- now s.at)))
        (status (cond ((some? s.result) "finished") ((< ago (staleAfter)) "running") (else "stale")))]
    (with s :ago ago :status status))

fn porcelainPaths recs: (List String) acc: (List String) -> (List String)
  (mt (listHead recs)
    ((none) (listReverse acc))
    ((some rec)
      (let [(rest (optionOr (listTail recs) (list)))]
        (if (< (stringLength rec) 4)
          (porcelainPaths rest acc)
          (let [(acc2 (cons (sliceOf rec 3 (stringLength rec)) acc)) (x (sliceOf rec 0 1))]
            (porcelainPaths (if (or (= x "R") (= x "C")) (optionOr (listTail rest) (list)) rest) acc2))))))

fn overlapForms running: (List Sess) -> (List String)
  (mt (listHead running)
    ((none) (list))
    ((some a)
      (let [(rest (optionOr (listTail running) (list)))]
        (listAppend
          (fold (fn [(acc (List String)) (b Sess)] -> (List String)
                  (let [(on (ownsMeet a.owns b.owns))]
                    (if (listEmpty? on) acc (listAppend acc (list (str "(:a " (c/quoted a.id) " :b " (c/quoted b.id) " :on " (pathList on) ")"))))))
                (list) rest)
          (overlapForms rest)))))

fn sessForm dirty: (List String) s: Sess -> String
  (let [(mine (listSort (filter (fn [(p String)] -> Bool (listAny? (fn [(o String)] -> Bool (ownsCover? o p)) s.owns)) dirty)))]
    (str "(:id " (c/quoted s.id) " :mode :" s.mode " :owns " (pathList s.owns) " :staged " (pathList s.staged)
         " :dirty " (pathList mine) " :turns " s.turns " :lastTurnAgo " (stringFromInt64 s.ago)
         " :status :" s.status " :result " (mt s.result ((some r) (str ":" r)) ((none) "none")) ")"))

fn countStatus ss: (List Sess) st: String -> Int64
  (listLength (filter (fn [(s Sess)] -> Bool (= s.status st)) ss))

fn fitSessions head: String forms: (List String) shown: Int64 -> (Result String String)
  (let [(receipt (str head " :sessions (" (c/joinWith (listTake forms shown) " ") ") :more " (stringFromInt64 (- (listLength forms) shown)) ")"))]
    (cond
      ((< (c/byteLen receipt) (c/receiptMax)) (ok receipt))
      ((= shown 0) (err (c/rejectLine "ERR_RECEIPT_TOO_LARGE" (str "session receipt exceeds " (stringFromInt64 (c/receiptMax)) " bytes with no session shown") "")))
      (else (fitSessions head forms (- shown 1)))))

fn dirtyPaths! root: String owns: (List String) ctx: c/Ctx -> (Result (List String) String)
  (if (listEmpty? owns)
    (ok (list))
    (mt (c/git! (listAppend (list "status" "--porcelain" "-z" "--untracked-files=all" "--") owns) root ctx)
      ((err e) (err e))
      ((ok p) (if (!= (pairFirst p) 0)
                (err (c/rejectLine "ERR_GIT" (str "git status failed in " root) ""))
                (ok (porcelainPaths (c/splitByte (pairSecond p) 0) (list)))))))

fn ! observeSession! root: String limit: Int64 ctx: c/Ctx -> (Result String String)
  (mt (journalSessions! (c/joinPath root ".asl/run/agentLoop"))
    ((err e) (err e))
    ((ok js)
      (mt (mt (vfsRoot! root ctx) ((some store) (storeSessions! store js)) ((none) (ok js)))
        ((err e) (err e))
        ((ok ss)
          (let [(stated (map (fn [(s Sess)] -> Sess (withStatus ctx.now s)) ss))
                (ordered (listSortBy (fn [(s Sess)] -> Int64 (- 0 s.at)) (listSortBy (fn [(s Sess)] -> String s.id) stated)))
                (ownsAll (c/sortUnique (fold (fn [(acc (List String)) (s Sess)] -> (List String) (listAppend acc s.owns)) (list) ordered)))]
            (mt (dirtyPaths! root ownsAll ctx)
              ((err e) (err e))
              ((ok dirty)
                (mt (c/shortRev! root ctx)
                  ((err e) (err e))
                  ((ok rev)
                    (let [(running (filter (fn [(s Sess)] -> Bool (= s.status "running")) ordered))
                          (own (optionOr (c/ctxEnv ctx "ASL_SESSION") ""))
                          (head (str "(:observe :dim session :v 1 :rev " rev " :staleAfter " (stringFromInt64 (staleAfter))
                                     (if (stringEmpty? own) "" (str " :self " (c/quoted own)))
                                     " :count (:running " (stringFromInt64 (listLength running))
                                     " :finished " (stringFromInt64 (countStatus ordered "finished"))
                                     " :stale " (stringFromInt64 (countStatus ordered "stale")) ")"
                                     " :overlaps (" (c/joinWith (overlapForms running) " ") ")"))
                          (forms (map (fn [(s Sess)] -> String (sessForm dirty s)) ordered))]
                      (fitSessions head forms (min limit (listLength ordered)))))))))))))
