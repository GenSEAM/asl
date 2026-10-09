(module aslGateway/pyText
  :x [PyErr pyErr pyErrText byteStr cpEncode treeJoin joinSep sliceB findFrom findFromCi lowerAsciiByte
      cpCount cpPrefix cpSlice cpLenAt cpList isPySpace pyStrip collapseWs pySplitWs pyLower
      decodeReplace strictUtf8 latin1Decode cp1252Decode asciiDecode latin9Decode decodeCharset nativeCharset?
      jsonLoads jsonDumps jsonReprFloat pyStr pyRepr pyTypeName pyTruthy pyEq jget jgetOr jset jlen pyIter pyIndex
      urlQuote urlQuotePlus urlUnquote urlUnquotePlus parseQsl urlencodePairs urlsplit urlparse urlunparse cleanUrlStr cleanUrl
      htmlUnescape stripTagRegex hasSubstr partition asciiLower asciiUpper replaceAll cpLenAt]
  :i [(asl-json/json :a j)
      (htmlEntities :a ent)])

(schema PyErr (:f kind String) (:f msg String))

fn pyErr kind: String msg: String -> PyErr
  (PyErr :kind kind :msg msg)

fn pyErrText e: PyErr -> String
  (str e.kind ": " e.msg)

fn byteStr b: Int64 -> String
  (let [(tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff")]
    (optionOr (stringSlice tbl b (+ b 1)) ""))

fn cpEncode cp: Int64 -> String
  (cond
    ((< cp 128) (byteStr cp))
    ((< cp 2048) (stringConcat (byteStr (| 192 (/ cp 64))) (byteStr (| 128 (mod cp 64)))))
    ((< cp 65536) (str (byteStr (| 224 (/ cp 4096))) (byteStr (| 128 (mod (/ cp 64) 64))) (byteStr (| 128 (mod cp 64)))))
    (else (str (byteStr (| 240 (/ cp 262144))) (byteStr (| 128 (mod (/ cp 4096) 64))) (byteStr (| 128 (mod (/ cp 64) 64))) (byteStr (| 128 (mod cp 64))))))

fn pairUp xs: (List String) acc: (List String) -> (List String)
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some a)
      (let [(r1 (optionOr (listTail xs) (list)))]
        (mt (listHead r1)
          ((none) (listReverse (cons a acc)))
          ((some b) (pairUp (optionOr (listTail r1) (list)) (cons (stringConcat a b) acc)))))))

fn treeJoin xs: (List String) -> String
  (cond
    ((listEmpty? xs) "")
    ((= (listLength xs) 1) (optionOr (listHead xs) ""))
    (else (treeJoin (pairUp xs (list)))))

fn interleave xs: (List String) sep: String acc: (List String) first: Bool -> (List String)
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some x) (interleave (optionOr (listTail xs) (list)) sep (if first (cons x acc) (cons x (cons sep acc))) false)))

fn joinSep xs: (List String) sep: String -> String
  (treeJoin (interleave xs sep (list) true))

fn sliceB s: String a: Int64 b: Int64 -> String
  (if (>= a b) "" (optionOr (stringSlice s a b) ""))

fn matchAt bs: Bytes n: Int64 i: Int64 pat: Bytes m: Int64 k: Int64 -> Bool
  (cond
    ((>= k m) true)
    ((>= (+ i k) n) false)
    ((= (bytesGet bs (+ i k)) (bytesGet pat k)) (matchAt bs n i pat m (+ k 1)))
    (else false))

fn findFrom bs: Bytes n: Int64 pat: Bytes m: Int64 start: Int64 -> Int64
  (cond
    ((> (+ start m) n) -1)
    ((matchAt bs n start pat m 0) start)
    (else (findFrom bs n pat m (+ start 1))))

fn lowerAsciiByte b: Int64 -> Int64
  (if (and (>= b 65) (<= b 90)) (+ b 32) b)

fn matchAtCi bs: Bytes n: Int64 i: Int64 pat: Bytes m: Int64 k: Int64 -> Bool
  (cond
    ((>= k m) true)
    ((>= (+ i k) n) false)
    ((= (lowerAsciiByte (bytesGet bs (+ i k))) (bytesGet pat k)) (matchAtCi bs n i pat m (+ k 1)))
    (else false))

fn findFromCi bs: Bytes n: Int64 pat: Bytes m: Int64 start: Int64 -> Int64
  (cond
    ((> (+ start m) n) -1)
    ((matchAtCi bs n start pat m 0) start)
    (else (findFromCi bs n pat m (+ start 1))))

fn hasSubstr s: String sub: String -> Bool
  (some? (stringIndexOf s sub))

fn isCont b: Int64 -> Bool
  (and (>= b 128) (< b 192))

fn cpCountLoop bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (cpCountLoop bs (+ i 1) n (if (isCont (bytesGet bs i)) acc (+ acc 1))))

fn cpCount s: String -> Int64
  (let [(bs (stringToBytes s))] (cpCountLoop bs 0 (bytesLength bs) 0))

fn cpByteOffset bs: Bytes i: Int64 n: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((isCont (bytesGet bs i)) (cpByteOffset bs (+ i 1) n k))
    ((<= k 0) i)
    (else (cpByteOffset bs (+ i 1) n (- k 1))))

fn cpPrefix s: String k: Int64 -> String
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (if (<= k 0) "" (sliceB s 0 (cpByteOffset bs 0 n k))))

fn cpSlice s: String a: Int64 b: Int64 -> String
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (sliceB s (cpByteOffset bs 0 n a) (cpByteOffset bs 0 n b)))

fn cpLenAt b: Int64 -> Int64
  (cond ((< b 192) 1) ((< b 224) 2) ((< b 240) 3) (else 4))

fn cpAt bs: Bytes n: Int64 i: Int64 -> Int64
  (let [(b0 (bytesGet bs i)) (l (cpLenAt b0))]
    (cond
      ((or (< b0 128) (> (+ i l) n)) b0)
      ((= l 2) (+ (* (& b0 31) 64) (& (bytesGet bs (+ i 1)) 63)))
      ((= l 3) (+ (* (& b0 15) 4096) (+ (* (& (bytesGet bs (+ i 1)) 63) 64) (& (bytesGet bs (+ i 2)) 63))))
      (else (+ (* (& b0 7) 262144) (+ (* (& (bytesGet bs (+ i 1)) 63) 4096) (+ (* (& (bytesGet bs (+ i 2)) 63) 64) (& (bytesGet bs (+ i 3)) 63)))))))

fn cpListLoop bs: Bytes n: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n) (listReverse acc) (cpListLoop bs n (+ i (cpLenAt (bytesGet bs i))) (cons (cpAt bs n i) acc)))

fn cpList s: String -> (List Int64)
  (let [(bs (stringToBytes s))] (cpListLoop bs (bytesLength bs) 0 (list)))

fn isPySpace cp: Int64 -> Bool
  (or (and (>= cp 9) (<= cp 13)) (and (>= cp 28) (<= cp 32)) (= cp 133) (= cp 160) (= cp 5760)
      (and (>= cp 8192) (<= cp 8202)) (= cp 8232) (= cp 8233) (= cp 8239) (= cp 8287) (= cp 12288))

fn stripScan bs: Bytes n: Int64 i: Int64 first: Int64 lastEnd: Int64 -> (Pair Int64 Int64)
  (if (>= i n)
    (pair first lastEnd)
    (let [(l (cpLenAt (bytesGet bs i))) (sp (isPySpace (cpAt bs n i)))]
      (if sp
        (stripScan bs n (+ i l) first lastEnd)
        (stripScan bs n (+ i l) (if (< first 0) i first) (+ i l)))))

fn pyStrip s: String -> String
  (let [(bs (stringToBytes s)) (r (stripScan bs (bytesLength bs) 0 -1 0))]
    (if (< (pairFirst r) 0) "" (sliceB s (pairFirst r) (pairSecond r))))

fn collapseLoop s: String bs: Bytes n: Int64 i: Int64 runStart: Int64 segStart: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (>= runStart 0) (cons " " (cons (sliceB s segStart runStart) acc)) (cons (sliceB s segStart n) acc)))
    (let [(l (cpLenAt (bytesGet bs i))) (sp (isPySpace (cpAt bs n i)))]
      (cond
        ((and sp (< runStart 0)) (collapseLoop s bs n (+ i l) i segStart acc))
        (sp (collapseLoop s bs n (+ i l) runStart segStart acc))
        ((>= runStart 0) (collapseLoop s bs n (+ i l) -1 i (cons " " (cons (sliceB s segStart runStart) acc))))
        (else (collapseLoop s bs n (+ i l) -1 segStart acc)))))

fn collapseWs s: String -> String
  (let [(bs (stringToBytes s))] (treeJoin (collapseLoop s bs (bytesLength bs) 0 -1 0 (list))))

fn splitWsLoop s: String bs: Bytes n: Int64 i: Int64 tokStart: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (>= tokStart 0) (cons (sliceB s tokStart n) acc) acc))
    (let [(l (cpLenAt (bytesGet bs i))) (sp (isPySpace (cpAt bs n i)))]
      (cond
        ((and sp (>= tokStart 0)) (splitWsLoop s bs n (+ i l) -1 (cons (sliceB s tokStart i) acc)))
        (sp (splitWsLoop s bs n (+ i l) -1 acc))
        ((< tokStart 0) (splitWsLoop s bs n (+ i l) i acc))
        (else (splitWsLoop s bs n (+ i l) tokStart acc)))))

fn pySplitWs s: String -> (List String)
  (let [(bs (stringToBytes s))] (splitWsLoop s bs (bytesLength bs) 0 -1 (list)))

fn lowerCp cp: Int64 -> String
  (cond
    ((and (>= cp 65) (<= cp 90)) (byteStr (+ cp 32)))
    ((< cp 128) (byteStr cp))
    ((= cp 8490) "k")
    ((= cp 304) (str "i" (cpEncode 775)))
    ((and (>= cp 192) (<= cp 222) (not (= cp 215))) (cpEncode (+ cp 32)))
    ((and (>= cp 256) (<= cp 311) (not (= cp 304)) (not (= cp 305)) (= (mod cp 2) 0)) (cpEncode (+ cp 1)))
    ((and (>= cp 313) (<= cp 328) (= (mod cp 2) 1)) (cpEncode (+ cp 1)))
    ((and (>= cp 330) (<= cp 375) (= (mod cp 2) 0)) (cpEncode (+ cp 1)))
    ((= cp 376) (cpEncode 255))
    ((and (>= cp 377) (<= cp 382) (= (mod cp 2) 1)) (cpEncode (+ cp 1)))
    ((= cp 902) (cpEncode 940))
    ((and (>= cp 904) (<= cp 906)) (cpEncode (+ cp 37)))
    ((= cp 908) (cpEncode 972))
    ((and (>= cp 910) (<= cp 911)) (cpEncode (+ cp 63)))
    ((and (>= cp 913) (<= cp 937) (not (= cp 930))) (cpEncode (+ cp 32)))
    ((and (>= cp 1040) (<= cp 1071)) (cpEncode (+ cp 32)))
    ((and (>= cp 1024) (<= cp 1039)) (cpEncode (+ cp 80)))
    (else (cpEncode cp)))

fn allAscii bs: Bytes i: Int64 n: Int64 -> Bool
  (cond ((>= i n) true) ((>= (bytesGet bs i) 128) false) (else (allAscii bs (+ i 1) n)))

fn caseLoop s: String bs: Bytes n: Int64 i: Int64 seg: Int64 lo: Int64 hi: Int64 delta: Int64 acc: (List String) -> String
  (if (>= i n)
    (treeJoin (listReverse (cons (sliceB s seg n) acc)))
    (let [(b (bytesGet bs i))]
      (if (and (>= b lo) (<= b hi))
        (caseLoop s bs n (+ i 1) (+ i 1) lo hi delta (cons (byteStr (+ b delta)) (cons (sliceB s seg i) acc)))
        (caseLoop s bs n (+ i 1) seg lo hi delta acc))))

fn asciiLower s: String -> String
  (let [(bs (stringToBytes s))] (caseLoop s bs (bytesLength bs) 0 0 65 90 32 (list)))

fn replaceAll s: String old: String new: String -> String
  (if (hasSubstr s old) (joinSep (stringSplit s old) new) s)

fn asciiUpper s: String -> String
  (let [(bs (stringToBytes s))] (caseLoop s bs (bytesLength bs) 0 0 97 122 -32 (list)))

fn pyLower s: String -> String
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (if (allAscii bs 0 n) (asciiLower s) (treeJoin (map lowerCp (cpList s)))))

fn secondOk b0: Int64 b1: Int64 -> Bool
  (cond
    ((= b0 224) (and (>= b1 160) (<= b1 191)))
    ((= b0 237) (and (>= b1 128) (<= b1 159)))
    ((= b0 240) (and (>= b1 144) (<= b1 191)))
    ((= b0 244) (and (>= b1 128) (<= b1 143)))
    (else (isCont b1)))

fn seqLen b0: Int64 -> Int64
  (cond ((< b0 128) 1) ((< b0 194) 0) ((< b0 224) 2) ((< b0 240) 3) ((< b0 245) 4) (else 0))

fn seqScan bs: Bytes n: Int64 i: Int64 -> (Pair Int64 Bool)
  (let [(b0 (bytesGet bs i)) (l (seqLen b0))]
    (cond
      ((= l 1) (pair 1 true))
      ((= l 0) (pair 1 false))
      ((>= (+ i 1) n) (pair 1 false))
      ((not (secondOk b0 (bytesGet bs (+ i 1)))) (pair 1 false))
      ((= l 2) (pair 2 true))
      ((>= (+ i 2) n) (pair 2 false))
      ((not (isCont (bytesGet bs (+ i 2)))) (pair 2 false))
      ((= l 3) (pair 3 true))
      ((>= (+ i 3) n) (pair 3 false))
      ((not (isCont (bytesGet bs (+ i 3)))) (pair 3 false))
      (else (pair 4 true))))

fn replaceLoop s: String bs: Bytes n: Int64 i: Int64 seg: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (sliceB s seg n) acc))
    (let [(r (seqScan bs n i))]
      (if (pairSecond r)
        (replaceLoop s bs n (+ i (pairFirst r)) seg acc)
        (replaceLoop s bs n (+ i (pairFirst r)) (+ i (pairFirst r)) (cons (cpEncode 65533) (cons (sliceB s seg i) acc))))))

fn decodeReplace raw: String -> String
  (let [(bs (stringToBytes raw))] (treeJoin (replaceLoop raw bs (bytesLength bs) 0 0 (list))))

fn hex2 b: Int64 -> String
  (let [(d "0123456789abcdef")] (str (sliceB d (/ b 16) (+ (/ b 16) 1)) (sliceB d (mod b 16) (+ (mod b 16) 1))))

fn strictLoop bs: Bytes n: Int64 i: Int64 -> (Option String)
  (if (>= i n)
    (none)
    (let [(r (seqScan bs n i)) (k (pairFirst r))]
      (cond
        ((pairSecond r) (strictLoop bs n (+ i k)))
        (else
          (let [(b0 (bytesGet bs i)) (l (seqLen b0))
                (reason (cond ((= l 0) "invalid start byte") ((>= (+ i k) n) "unexpected end of data") (else "invalid continuation byte")))]
            (some (if (= k 1)
                    (str "'utf-8' codec can't decode byte 0x" (hex2 b0) " in position " (stringFromInt64 i) ": " reason)
                    (str "'utf-8' codec can't decode bytes in position " (stringFromInt64 i) "-" (stringFromInt64 (- (+ i k) 1)) ": " reason))))))))

fn strictUtf8 raw: String -> (Result String PyErr)
  (mt (strictLoop (stringToBytes raw) (bytesLength (stringToBytes raw)) 0)
    ((none) (ok raw))
    ((some m) (err (pyErr "UnicodeDecodeError" m))))

fn mapBytes raw: String f: (fn [Int64] -> Int64) -> String
  (let [(bs (stringToBytes raw)) (n (bytesLength bs))]
    (if (allAscii bs 0 n) raw (treeJoin (map (fn [(i Int64)] -> String (cpEncode (f (bytesGet bs i)))) (range 0 n)))))

fn latin1Decode raw: String -> String
  (mapBytes raw (fn [(b Int64)] -> Int64 b))

fn asciiDecode raw: String -> String
  (mapBytes raw (fn [(b Int64)] -> Int64 (if (< b 128) b 65533)))

fn cp1252High b: Int64 -> Int64
  (let [(tbl (list 8364 65533 8218 402 8222 8230 8224 8225 710 8240 352 8249 338 65533 381 65533 65533 8216 8217 8220 8221 8226 8211 8212 732 8482 353 8250 339 65533 382 376))]
    (optionOr (listGet tbl (- b 128)) 65533))

fn cp1252Decode raw: String -> String
  (mapBytes raw (fn [(b Int64)] -> Int64 (if (and (>= b 128) (< b 160)) (cp1252High b) b)))

fn normCharset c: String -> String
  (replaceAll (replaceAll (asciiLower c) "-" "_") " " "_")

fn latin9Decode raw: String -> String
  (mapBytes raw (fn [(b Int64)] -> Int64
    (cond ((= b 164) 8364) ((= b 166) 352) ((= b 168) 353) ((= b 180) 381) ((= b 184) 382) ((= b 188) 338) ((= b 189) 339) ((= b 190) 376) (else b))))

fn utf8SigDecode raw: String -> String
  (decodeReplace (if (stringStartsWith? raw "\uFEFF") (sliceB raw 3 (stringLength raw)) raw))

fn charsetFamily c: String -> String
  (cond
    ((listContains? (list "utf_8" "utf8" "u8" "utf" "cp65001") c) "utf8")
    ((= c "utf_8_sig") "utf8sig")
    ((listContains? (list "latin_1" "latin1" "iso_8859_1" "iso8859_1" "8859" "cp819" "l1" "latin" "iso_ir_100" "csisolatin1" "ibm819" "iso_8859_1:1987") c) "latin1")
    ((listContains? (list "iso8859_15" "iso_8859_15" "l9" "latin9") c) "latin9")
    ((listContains? (list "ascii" "us_ascii" "646" "ansi_x3.4_1968" "ansi_x3_4_1968" "ansi_x3.4_1986" "cp367" "csascii" "ibm367" "iso646_us" "iso_646.irv_1991" "iso_ir_6" "us") c) "ascii")
    ((listContains? (list "cp1252" "windows_1252") c) "cp1252")
    (else ""))

fn nativeCharset? charset: String -> Bool
  (not (stringEmpty? (charsetFamily (normCharset charset))))

fn decodeCharset raw: String charset: String -> (Result String PyErr)
  (let [(f (charsetFamily (normCharset charset)))]
    (cond
      ((= f "utf8") (ok (decodeReplace raw)))
      ((= f "utf8sig") (ok (utf8SigDecode raw)))
      ((= f "latin1") (ok (latin1Decode raw)))
      ((= f "latin9") (ok (latin9Decode raw)))
      ((= f "ascii") (ok (asciiDecode raw)))
      ((= f "cp1252") (ok (cp1252Decode raw)))
      (else (err (pyErr "LookupError" (str "unknown encoding: " charset))))))

fn jsonErrAt bs: Bytes msg: String pos: Int64 -> String
  (let [(cpPos (cpCountLoop bs 0 pos 0))
        (nl (lastNl bs 0 pos -1))
        (line (+ 1 (countNl bs 0 pos 0)))
        (col (if (< nl 0) (+ cpPos 1) (- cpPos (cpCountLoop bs 0 nl 0))))]
    (str msg ": line " (stringFromInt64 line) " column " (stringFromInt64 col) " (char " (stringFromInt64 cpPos) ")"))

fn lastNl bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (lastNl bs (+ i 1) n (if (= (bytesGet bs i) 10) i acc)))

fn countNl bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (countNl bs (+ i 1) n (if (= (bytesGet bs i) 10) (+ acc 1) acc)))

fn jsonWs bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (let [(b (bytesGet bs i))] (or (= b 32) (= b 9) (= b 10) (= b 13)))) (jsonWs bs n (+ i 1)) i)

fn litAt bs: Bytes n: Int64 i: Int64 lit: String -> Bool
  (matchAt bs n i (stringToBytes lit) (stringLength lit) 0)

fn isDigitB b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn digitsEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isDigitB (bytesGet bs i))) (digitsEnd bs n (+ i 1)) i)

fn hexVal b: Int64 -> Int64
  (cond
    ((and (>= b 48) (<= b 57)) (- b 48))
    ((and (>= b 65) (<= b 70)) (- b 55))
    ((and (>= b 97) (<= b 102)) (- b 87))
    (else -1))

fn hex4 bs: Bytes i: Int64 -> Int64
  (let [(a (hexVal (bytesGet bs i))) (b (hexVal (bytesGet bs (+ i 1)))) (c (hexVal (bytesGet bs (+ i 2)))) (d (hexVal (bytesGet bs (+ i 3))))]
    (if (or (< a 0) (< b 0) (< c 0) (< d 0)) -1 (+ (* a 4096) (+ (* b 256) (+ (* c 16) d)))))

fn jexpect bs: Bytes i: Int64 -> PyErr
  (pyErr "JSONDecodeError" (jsonErrAt bs "Expecting value" i))

fn jsonNumber text: String bs: Bytes n: Int64 start: Int64 -> (Result (Pair j/Json Int64) PyErr)
  (let [(i0 (if (= (bytesGet bs start) 45) (+ start 1) start))]
    (if (>= i0 n)
      (err (jexpect bs start))
      (let [(b (bytesGet bs i0))
            (iInt (cond ((and (>= b 49) (<= b 57)) (digitsEnd bs n (+ i0 1))) ((= b 48) (+ i0 1)) (else -1)))]
        (if (< iInt 0)
          (err (jexpect bs start))
          (let [(hasFrac (and (< (+ iInt 1) n) (= (bytesGet bs iInt) 46) (isDigitB (bytesGet bs (+ iInt 1)))))
                (iFrac (if hasFrac (digitsEnd bs n (+ iInt 2)) iInt))
                (hasE (and (< (+ iFrac 1) n) (or (= (bytesGet bs iFrac) 101) (= (bytesGet bs iFrac) 69))))
                (iSign (if (and hasE (< (+ iFrac 2) n) (or (= (bytesGet bs (+ iFrac 1)) 45) (= (bytesGet bs (+ iFrac 1)) 43))) (+ iFrac 2) (+ iFrac 1)))
                (iExpEnd (if hasE (digitsEnd bs n iSign) iFrac))
                (expOk (and hasE (> iExpEnd iSign)))
                (iEnd (if expOk iExpEnd iFrac))
                (lit (sliceB text start iEnd))]
            (if (or hasFrac expOk)
              (mt (stringToFloat64 lit)
                ((some f) (ok (pair (j/jfloat f) iEnd)))
                ((none) (err (jexpect bs start))))
              (mt (stringToInt64 lit)
                ((some v) (ok (pair (j/jint v) iEnd)))
                ((none) (mt (stringToFloat64 lit)
                  ((some f) (ok (pair (j/jfloat f) iEnd)))
                  ((none) (err (jexpect bs start))))))))))))

(schema StrScan (:f pieces (List String)) (:f pos Int64))

fn jsonStrLoop text: String bs: Bytes n: Int64 begin: Int64 seg: Int64 i: Int64 acc: (List String) -> (Result (Pair String Int64) PyErr)
  (if (>= i n)
    (err (pyErr "JSONDecodeError" (jsonErrAt bs "Unterminated string starting at" begin)))
    (let [(c (bytesGet bs i))]
      (cond
        ((= c 34) (ok (pair (treeJoin (listReverse (cons (sliceB text seg i) acc))) (+ i 1))))
        ((= c 92)
          (let [(acc1 (cons (sliceB text seg i) acc)) (nx (+ i 1))]
            (if (>= nx n)
              (err (pyErr "JSONDecodeError" (jsonErrAt bs "Unterminated string starting at" begin)))
              (let [(e (bytesGet bs nx))]
                (if (not (= e 117))
                  (let [(rep (cond ((= e 34) "\"") ((= e 92) "\\") ((= e 47) "/") ((= e 98) (byteStr 8)) ((= e 102) (byteStr 12)) ((= e 110) "\n") ((= e 114) "\r") ((= e 116) "\t") (else "")))]
                    (if (stringEmpty? rep)
                      (err (pyErr "JSONDecodeError" (jsonErrAt bs "Invalid \\escape" i)))
                      (jsonStrLoop text bs n begin (+ nx 1) (+ nx 1) (cons rep acc1))))
                  (let [(h (+ nx 1)) (end (+ h 4))]
                    (if (>= end n)
                      (err (pyErr "JSONDecodeError" (jsonErrAt bs "Invalid \\uXXXX escape" nx)))
                      (let [(c1 (hex4 bs h))]
                        (if (< c1 0)
                          (err (pyErr "JSONDecodeError" (jsonErrAt bs "Invalid \\uXXXX escape" nx)))
                          (if (and (>= c1 55296) (<= c1 56319) (< (+ end 6) n) (= (bytesGet bs end) 92) (= (bytesGet bs (+ end 1)) 117))
                            (let [(c2 (hex4 bs (+ end 2)))]
                              (cond
                                ((< c2 0) (err (pyErr "JSONDecodeError" (jsonErrAt bs "Invalid \\uXXXX escape" (+ end 1)))))
                                ((and (>= c2 56320) (<= c2 57343))
                                  (jsonStrLoop text bs n begin (+ end 6) (+ end 6) (cons (cpEncode (+ 65536 (+ (* (- c1 55296) 1024) (- c2 56320)))) acc1)))
                                (else (jsonStrLoop text bs n begin end end (cons (cpEncode c1) acc1)))))
                            (jsonStrLoop text bs n begin end end (cons (cpEncode c1) acc1))))))))))))
        ((<= c 31) (err (pyErr "JSONDecodeError" (jsonErrAt bs "Invalid control character at" i))))
        (else (jsonStrLoop text bs n begin seg (+ i 1) acc)))))

fn jset obj: j/Json k: String v: j/Json -> j/Json
  (mt obj
    ((j/jobj kvs)
      (if (listAny? (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) k)) kvs)
        (j/jobj (map (fn [(p (Pair String j/Json))] -> (Pair String j/Json) (if (= (pairFirst p) k) (pair k v) p)) kvs))
        (j/jobj (listAppend kvs (list (pair k v))))))
    (_ (j/jobj (list (pair k v)))))

fn jsonValue text: String bs: Bytes n: Int64 i: Int64 -> (Result (Pair j/Json Int64) PyErr)
  (if (>= i n)
    (err (jexpect bs i))
    (let [(c (bytesGet bs i))]
      (cond
        ((= c 34) (mt (jsonStrLoop text bs n i (+ i 1) (+ i 1) (list)) ((ok p) (ok (pair (j/jstr (pairFirst p)) (pairSecond p)))) ((err e) (err e))))
        ((= c 123) (jsonObject text bs n (jsonWs bs n (+ i 1)) (list)))
        ((= c 91) (jsonArray text bs n (jsonWs bs n (+ i 1)) (list)))
        ((and (= c 110) (litAt bs n i "null")) (ok (pair (j/jnull) (+ i 4))))
        ((and (= c 116) (litAt bs n i "true")) (ok (pair (j/jbool true) (+ i 4))))
        ((and (= c 102) (litAt bs n i "false")) (ok (pair (j/jbool false) (+ i 5))))
        ((and (= c 78) (litAt bs n i "NaN")) (ok (pair (j/jfloat (floatNan)) (+ i 3))))
        ((and (= c 73) (litAt bs n i "Infinity")) (ok (pair (j/jfloat (floatInf)) (+ i 8))))
        ((and (= c 45) (litAt bs n i "-Infinity")) (ok (pair (j/jfloat (floatNegInf)) (+ i 9))))
        ((or (= c 45) (isDigitB c)) (jsonNumber text bs n i))
        (else (err (jexpect bs i))))))

fn jsonArray text: String bs: Bytes n: Int64 i: Int64 acc: (List j/Json) -> (Result (Pair j/Json Int64) PyErr)
  (if (and (listEmpty? acc) (< i n) (= (bytesGet bs i) 93))
    (ok (pair (j/jarr (list)) (+ i 1)))
    (mt (jsonValue text bs n i)
      ((err e) (err e))
      ((ok p)
        (let [(acc1 (cons (pairFirst p) acc)) (k (jsonWs bs n (pairSecond p)))]
          (cond
            ((and (< k n) (= (bytesGet bs k) 93)) (ok (pair (j/jarr (listReverse acc1)) (+ k 1))))
            ((or (>= k n) (not (= (bytesGet bs k) 44))) (err (pyErr "JSONDecodeError" (jsonErrAt bs "Expecting ',' delimiter" k))))
            (else
              (let [(k2 (jsonWs bs n (+ k 1)))]
                (if (and (< k2 n) (= (bytesGet bs k2) 93))
                  (err (pyErr "JSONDecodeError" (jsonErrAt bs "Illegal trailing comma before end of array" k)))
                  (jsonArray text bs n k2 acc1)))))))))

fn jsonObject text: String bs: Bytes n: Int64 i: Int64 acc: (List (Pair String j/Json)) -> (Result (Pair j/Json Int64) PyErr)
  (cond
    ((and (listEmpty? acc) (< i n) (= (bytesGet bs i) 125)) (ok (pair (j/jobj (list)) (+ i 1))))
    ((or (>= i n) (not (= (bytesGet bs i) 34))) (err (pyErr "JSONDecodeError" (jsonErrAt bs "Expecting property name enclosed in double quotes" i))))
    (else
      (mt (jsonStrLoop text bs n i (+ i 1) (+ i 1) (list))
        ((err e) (err e))
        ((ok kp)
          (let [(k (jsonWs bs n (pairSecond kp)))]
            (if (or (>= k n) (not (= (bytesGet bs k) 58)))
              (err (pyErr "JSONDecodeError" (jsonErrAt bs "Expecting ':' delimiter" k)))
              (mt (jsonValue text bs n (jsonWs bs n (+ k 1)))
                ((err e) (err e))
                ((ok vp)
                  (let [(acc1 (objPut acc (pairFirst kp) (pairFirst vp))) (m (jsonWs bs n (pairSecond vp)))]
                    (cond
                      ((and (< m n) (= (bytesGet bs m) 125)) (ok (pair (j/jobj acc1) (+ m 1))))
                      ((or (>= m n) (not (= (bytesGet bs m) 44))) (err (pyErr "JSONDecodeError" (jsonErrAt bs "Expecting ',' delimiter" m))))
                      (else
                        (let [(m2 (jsonWs bs n (+ m 1)))]
                          (if (and (< m2 n) (= (bytesGet bs m2) 125))
                            (err (pyErr "JSONDecodeError" (jsonErrAt bs "Illegal trailing comma before end of object" m)))
                            (jsonObject text bs n m2 acc1))))))))))))))

fn objPut kvs: (List (Pair String j/Json)) k: String v: j/Json -> (List (Pair String j/Json))
  (if (listAny? (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) k)) kvs)
    (map (fn [(p (Pair String j/Json))] -> (Pair String j/Json) (if (= (pairFirst p) k) (pair k v) p)) kvs)
    (listAppend kvs (list (pair k v))))

fn jsonLoads text: String -> (Result j/Json PyErr)
  (let [(bs (stringToBytes text)) (n (bytesLength bs))]
    (if (and (>= n 3) (= (bytesGet bs 0) 239) (= (bytesGet bs 1) 187) (= (bytesGet bs 2) 191))
      (err (pyErr "JSONDecodeError" (jsonErrAt bs "Unexpected UTF-8 BOM (decode using utf-8-sig)" 0)))
      (mt (jsonValue text bs n (jsonWs bs n 0))
        ((err e) (err e))
        ((ok p)
          (let [(e (jsonWs bs n (pairSecond p)))]
            (if (= e n) (ok (pairFirst p)) (err (pyErr "JSONDecodeError" (jsonErrAt bs "Extra data" e)))))))))

fn hex4Lower cp: Int64 -> String
  (str (hex2 (/ cp 256)) (hex2 (mod cp 256)))

fn escAsciiCp cp: Int64 -> String
  (cond
    ((= cp 34) "\\\"")
    ((= cp 92) "\\\\")
    ((= cp 10) "\\n")
    ((= cp 13) "\\r")
    ((= cp 9) "\\t")
    ((= cp 8) "\\b")
    ((= cp 12) "\\f")
    ((and (>= cp 32) (<= cp 126)) (byteStr cp))
    ((>= cp 65536) (let [(v (- cp 65536))] (str "\\u" (hex4Lower (+ 55296 (/ v 1024))) "\\u" (hex4Lower (+ 56320 (mod v 1024))))))
    (else (str "\\u" (hex4Lower cp))))

fn plainAscii bs: Bytes i: Int64 n: Int64 -> Bool
  (cond
    ((>= i n) true)
    ((let [(b (bytesGet bs i))] (or (< b 32) (> b 126) (= b 34) (= b 92))) false)
    (else (plainAscii bs (+ i 1) n)))

fn jsonStr s: String -> String
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (if (plainAscii bs 0 n) (str "\"" s "\"") (str "\"" (treeJoin (map escAsciiCp (cpList s))) "\"")))

fn jsonReprFloat f: Float64 -> String
  (cond ((isNan? f) "NaN") ((= f (floatInf)) "Infinity") ((= f (floatNegInf)) "-Infinity") (else (stringFromFloat64 f)))

fn dumpsPieces v: j/Json indent: Int64 level: Int64 acc: (List String) -> (List String)
  (mt v
    ((j/jnull) (cons "null" acc))
    ((j/jbool b) (cons (if b "true" "false") acc))
    ((j/jint i) (cons (stringFromInt64 i) acc))
    ((j/jfloat f) (cons (jsonReprFloat f) acc))
    ((j/jnum f) (cons (jsonReprFloat f) acc))
    ((j/jstr s) (cons (jsonStr s) acc))
    ((j/jarr xs)
      (if (listEmpty? xs)
        (cons "[]" acc)
        (let [(inner (if (< indent 0) "" (str "\n" (stringRepeat " " (* indent (+ level 1))))))
              (sep (if (< indent 0) ", " (str "," inner)))
              (close (if (< indent 0) "]" (str "\n" (stringRepeat " " (* indent level)) "]")))
              (body (fold (fn [(a (Pair (List String) Bool)) (x j/Json)] -> (Pair (List String) Bool)
                            (pair (dumpsPieces x indent (+ level 1) (if (pairSecond a) (pairFirst a) (cons sep (pairFirst a)))) false))
                          (pair (cons inner (cons "[" acc)) true) xs))]
          (cons close (pairFirst body)))))
    ((j/jobj kvs)
      (if (listEmpty? kvs)
        (cons "{}" acc)
        (let [(inner (if (< indent 0) "" (str "\n" (stringRepeat " " (* indent (+ level 1))))))
              (sep (if (< indent 0) ", " (str "," inner)))
              (close (if (< indent 0) "}" (str "\n" (stringRepeat " " (* indent level)) "}")))
              (body (fold (fn [(a (Pair (List String) Bool)) (p (Pair String j/Json))] -> (Pair (List String) Bool)
                            (pair (dumpsPieces (pairSecond p) indent (+ level 1) (cons ": " (cons (jsonStr (pairFirst p)) (if (pairSecond a) (pairFirst a) (cons sep (pairFirst a)))))) false))
                          (pair (cons inner (cons "{" acc)) true) kvs))]
          (cons close (pairFirst body))))))

fn jsonDumps v: j/Json indent: Int64 -> String
  (treeJoin (listReverse (dumpsPieces v indent 0 (list))))

fn pyTypeName v: j/Json -> String
  (mt v ((j/jnull) "NoneType") ((j/jbool _) "bool") ((j/jint _) "int") ((j/jfloat _) "float") ((j/jnum _) "float") ((j/jstr _) "str") ((j/jarr _) "list") ((j/jobj _) "dict"))

fn pyFloatStr f: Float64 -> String
  (cond ((isNan? f) "nan") ((= f (floatInf)) "inf") ((= f (floatNegInf)) "-inf") (else (stringFromFloat64 f)))

fn reprPrintable cp: Int64 -> Bool
  (not (or (< cp 32) (and (>= cp 127) (<= cp 160)) (= cp 173) (= cp 5760) (and (>= cp 8192) (<= cp 8207)) (and (>= cp 8232) (<= cp 8239))
           (and (>= cp 8287) (<= cp 8303)) (= cp 12288) (and (>= cp 55296) (<= cp 63743)) (= cp 65279) (and (>= cp 65529) (<= cp 65531)) (>= cp 983040)
           (= cp 65534) (= cp 65535)))

fn reprCp cp: Int64 q: Int64 -> String
  (cond
    ((= cp q) (str "\\" (byteStr q)))
    ((= cp 92) "\\\\")
    ((= cp 9) "\\t")
    ((= cp 10) "\\n")
    ((= cp 13) "\\r")
    ((reprPrintable cp) (cpEncode cp))
    ((<= cp 255) (str "\\x" (hex2 cp)))
    ((<= cp 65535) (str "\\u" (hex4Lower cp)))
    (else (str "\\U" (hex4Lower (/ cp 65536)) (hex4Lower (mod cp 65536)))))

fn reprStr s: String -> String
  (let [(q (if (and (hasSubstr s "'") (not (hasSubstr s "\""))) 34 39))]
    (str (byteStr q) (treeJoin (map (fn [(cp Int64)] -> String (reprCp cp q)) (cpList s))) (byteStr q)))

fn pyRepr v: j/Json -> String
  (mt v
    ((j/jstr s) (reprStr s))
    (_ (pyStr v)))

fn pyStr v: j/Json -> String
  (mt v
    ((j/jnull) "None")
    ((j/jbool b) (if b "True" "False"))
    ((j/jint i) (stringFromInt64 i))
    ((j/jfloat f) (pyFloatStr f))
    ((j/jnum f) (pyFloatStr f))
    ((j/jstr s) s)
    ((j/jarr xs) (str "[" (joinSep (map pyRepr xs) ", ") "]"))
    ((j/jobj kvs) (str "{" (joinSep (map (fn [(p (Pair String j/Json))] -> String (str (reprStr (pairFirst p)) ": " (pyRepr (pairSecond p)))) kvs) ", ") "}")))

fn pyTruthy v: j/Json -> Bool
  (mt v
    ((j/jnull) false)
    ((j/jbool b) b)
    ((j/jint i) (not (= i 0)))
    ((j/jfloat f) (not (= f 0.0)))
    ((j/jnum f) (not (= f 0.0)))
    ((j/jstr s) (not (stringEmpty? s)))
    ((j/jarr xs) (not (listEmpty? xs)))
    ((j/jobj kvs) (not (listEmpty? kvs))))

fn numOf v: j/Json -> (Option Float64)
  (mt v
    ((j/jbool b) (some (if b 1.0 0.0)))
    ((j/jint i) (some (int64ToFloat64 i)))
    ((j/jfloat f) (some f))
    ((j/jnum f) (some f))
    (_ (none)))

fn listEq xs: (List j/Json) ys: (List j/Json) -> Bool
  (and (= (listLength xs) (listLength ys)) (listAll? (fn [(p (Pair j/Json j/Json))] -> Bool (pyEq (pairFirst p) (pairSecond p))) (zip xs ys)))

fn objEq a: (List (Pair String j/Json)) b: (List (Pair String j/Json)) -> Bool
  (and (= (listLength a) (listLength b))
       (listAll? (fn [(p (Pair String j/Json))] -> Bool (mt (jget (j/jobj b) (pairFirst p)) ((some v) (pyEq (pairSecond p) v)) ((none) false))) a))

fn pyEq a: j/Json b: j/Json -> Bool
  (mt (numOf a)
    ((some x) (mt (numOf b) ((some y) (= x y)) ((none) false)))
    ((none)
      (mt a
        ((j/jnull) (mt b ((j/jnull) true) (_ false)))
        ((j/jstr s) (mt b ((j/jstr t) (= s t)) (_ false)))
        ((j/jarr xs) (mt b ((j/jarr ys) (listEq xs ys)) (_ false)))
        ((j/jobj kvs) (mt b ((j/jobj k2) (objEq kvs k2)) (_ false)))
        (_ false))))

fn jget v: j/Json k: String -> (Option j/Json)
  (mt v
    ((j/jobj kvs) (mt (listHead (filter (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) k)) kvs)) ((some p) (some (pairSecond p))) ((none) (none))))
    (_ (none)))

fn jgetOr v: j/Json k: String d: j/Json -> (Result j/Json PyErr)
  (mt v
    ((j/jobj _) (ok (optionOr (jget v k) d)))
    (_ (err (pyErr "AttributeError" (str "'" (pyTypeName v) "' object has no attribute 'get'")))))

fn jlen v: j/Json -> (Result Int64 PyErr)
  (mt v
    ((j/jstr s) (ok (cpCount s)))
    ((j/jarr xs) (ok (listLength xs)))
    ((j/jobj kvs) (ok (listLength kvs)))
    (_ (err (pyErr "TypeError" (str "object of type '" (pyTypeName v) "' has no len()")))))

fn pyIter v: j/Json -> (Result (List j/Json) PyErr)
  (mt v
    ((j/jarr xs) (ok xs))
    ((j/jobj kvs) (ok (map (fn [(p (Pair String j/Json))] -> j/Json (j/jstr (pairFirst p))) kvs)))
    ((j/jstr s) (ok (map (fn [(cp Int64)] -> j/Json (j/jstr (cpEncode cp))) (cpList s))))
    (_ (err (pyErr "TypeError" (str "'" (pyTypeName v) "' object is not iterable")))))

fn pyIndex v: j/Json i: Int64 -> (Result j/Json PyErr)
  (mt v
    ((j/jarr xs) (mt (listGet xs i) ((some x) (ok x)) ((none) (err (pyErr "IndexError" "list index out of range")))))
    ((j/jstr s) (let [(cps (cpList s))] (mt (listGet cps i) ((some c) (ok (j/jstr (cpEncode c)))) ((none) (err (pyErr "IndexError" "string index out of range"))))))
    ((j/jobj _) (err (pyErr "KeyError" (stringFromInt64 i))))
    (_ (err (pyErr "TypeError" (str "'" (pyTypeName v) "' object is not subscriptable")))))

fn alwaysSafe b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (isDigitB b) (= b 95) (= b 46) (= b 45) (= b 126))

fn hexUpper b: Int64 -> String
  (let [(d "0123456789ABCDEF")] (str "%" (sliceB d (/ b 16) (+ (/ b 16) 1)) (sliceB d (mod b 16) (+ (mod b 16) 1))))

fn quoteLoop s: String bs: Bytes n: Int64 i: Int64 seg: Int64 safe: String plus: Bool acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (sliceB s seg n) acc))
    (let [(b (bytesGet bs i))]
      (cond
        ((or (alwaysSafe b) (and (< b 128) (hasSubstr safe (byteStr b)))) (quoteLoop s bs n (+ i 1) seg safe plus acc))
        ((and plus (= b 32)) (quoteLoop s bs n (+ i 1) (+ i 1) safe plus (cons "+" (cons (sliceB s seg i) acc))))
        (else (quoteLoop s bs n (+ i 1) (+ i 1) safe plus (cons (hexUpper b) (cons (sliceB s seg i) acc)))))))

fn urlQuote s: String safe: String -> String
  (let [(bs (stringToBytes s))] (treeJoin (quoteLoop s bs (bytesLength bs) 0 0 safe false (list))))

fn urlQuotePlus s: String -> String
  (let [(bs (stringToBytes s))] (treeJoin (quoteLoop s bs (bytesLength bs) 0 0 "" true (list))))

fn pctDecodeRun s: String bs: Bytes i: Int64 end: Int64 seg: Int64 acc: (List String) -> (List String)
  (if (>= i end)
    (listReverse (cons (sliceB s seg end) acc))
    (if (and (= (bytesGet bs i) 37) (< (+ i 2) end))
      (let [(hi (hexVal (bytesGet bs (+ i 1)))) (lo (hexVal (bytesGet bs (+ i 2))))]
        (if (and (>= hi 0) (>= lo 0))
          (pctDecodeRun s bs (+ i 3) end (+ i 3) (cons (byteStr (+ (* hi 16) lo)) (cons (sliceB s seg i) acc)))
          (pctDecodeRun s bs (+ i 1) end seg acc)))
      (pctDecodeRun s bs (+ i 1) end seg acc)))

fn asciiRunEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (< (bytesGet bs i) 128)) (asciiRunEnd bs n (+ i 1)) i)

fn nonAsciiRunEnd bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (>= (bytesGet bs i) 128)) (nonAsciiRunEnd bs n (+ i 1)) i)

fn unquoteLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (if (< (bytesGet bs i) 128)
      (let [(e (asciiRunEnd bs n i))]
        (unquoteLoop s bs n e (cons (decodeReplace (treeJoin (pctDecodeRun s bs i e i (list)))) acc)))
      (let [(e (nonAsciiRunEnd bs n i))]
        (unquoteLoop s bs n e (cons (sliceB s i e) acc)))))

fn urlUnquote s: String -> String
  (if (not (hasSubstr s "%"))
    s
    (let [(bs (stringToBytes s))] (treeJoin (unquoteLoop s bs (bytesLength bs) 0 (list)))))

fn urlUnquotePlus s: String -> String
  (urlUnquote (replaceAll s "+" " "))

fn partition s: String sep: String -> (Pair String (Option String))
  (mt (stringIndexOf s sep)
    ((none) (pair s (none)))
    ((some i) (pair (sliceB s 0 i) (some (sliceB s (+ i (stringLength sep)) (stringLength s))))))

fn parseQsl qs: String -> (List (Pair String String))
  (if (stringEmpty? qs)
    (list)
    (fold (fn [(acc (List (Pair String String))) (nv String)] -> (List (Pair String String))
            (if (stringEmpty? nv)
              acc
              (let [(p (partition nv "="))
                    (value (optionOr (pairSecond p) ""))]
                (if (stringEmpty? value) acc (listAppend acc (list (pair (urlUnquotePlus (pairFirst p)) (urlUnquotePlus value))))))))
          (list) (stringSplit qs "&")))

fn urlencodePairs ps: (List (Pair String String)) -> String
  (joinSep (map (fn [(p (Pair String String))] -> String (str (urlQuotePlus (pairFirst p)) "=" (urlQuotePlus (pairSecond p)))) ps) "&")

fn schemeChar b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (isDigitB b) (= b 43) (= b 45) (= b 46))

fn allScheme bs: Bytes i: Int64 n: Int64 -> Bool
  (cond ((>= i n) true) ((schemeChar (bytesGet bs i)) (allScheme bs (+ i 1) n)) (else false))

fn lstripC0 bs: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (<= (bytesGet bs i) 32)) (lstripC0 bs n (+ i 1)) i)

fn isAsciiDigitStr s: String -> Bool
  (let [(bs (stringToBytes s))] (and (> (bytesLength bs) 0) (listAll? (fn [(i Int64)] -> Bool (isDigitB (bytesGet bs i))) (range 0 (bytesLength bs)))))

fn validOctet o: String -> Bool
  (and (isAsciiDigitStr o) (<= (stringLength o) 3) (or (= o "0") (not (stringStartsWith? o "0"))) (<= (optionOr (stringToInt64 o) 999) 255))

fn validIpv4 s: String -> Bool
  (and (not (stringEmpty? s)) (not (hasSubstr s "/")) (let [(os (stringSplit s "."))] (and (= (listLength os) 4) (listAll? validOctet os))))

fn validHextet h: String -> Bool
  (let [(bs (stringToBytes h))]
    (and (> (bytesLength bs) 0) (<= (bytesLength bs) 4) (listAll? (fn [(i Int64)] -> Bool (>= (hexVal (bytesGet bs i)) 0)) (range 0 (bytesLength bs)))))

fn skipIndex parts: (List String) -> (Pair Int64 Int64)
  (fold (fn [(acc (Pair Int64 Int64)) (ip (Pair Int64 String))] -> (Pair Int64 Int64)
          (if (and (> (pairFirst ip) 0) (< (pairFirst ip) (- (listLength parts) 1)) (stringEmpty? (pairSecond ip)))
            (pair (if (< (pairFirst acc) 0) (pairFirst ip) (pairFirst acc)) (+ (pairSecond acc) 1))
            acc))
        (pair -1 0) (enumerate parts))

fn validIpv6Addr s: String -> Bool
  (if (stringEmpty? s)
    false
    (let [(parts0 (stringSplit s ":"))]
      (if (< (listLength parts0) 3)
        false
        (let [(lastP (optionOr (listLast parts0) ""))
              (v4 (hasSubstr lastP "."))
              (parts (if v4 (listAppend (listTake parts0 (- (listLength parts0) 1)) (list "0" "0")) parts0))]
          (if (or (and v4 (not (validIpv4 lastP))) (> (listLength parts) 9))
            false
            (let [(sk (skipIndex parts)) (np (listLength parts))]
              (cond
                ((> (pairSecond sk) 1) false)
                ((>= (pairFirst sk) 0)
                  (let [(si (pairFirst sk))
                        (hi (if (stringEmpty? (optionOr (listHead parts) "")) (- si 1) si))
                        (lo (if (stringEmpty? (optionOr (listLast parts) "")) (- (- np si) 2) (- (- np si) 1)))
                        (headBad (and (stringEmpty? (optionOr (listHead parts) "")) (not (= hi 0))))
                        (tailBad (and (stringEmpty? (optionOr (listLast parts) "")) (not (= lo 0))))]
                    (and (not headBad) (not tailBad) (>= (- 8 (+ hi lo)) 1)
                         (listAll? validHextet (listTake parts hi)) (listAll? validHextet (listDrop parts (- np lo))))))
                (else (and (= np 8) (listAll? validHextet parts))))))))))

fn validIpv6 s: String -> Bool
  (and (not (hasSubstr s "/"))
       (let [(p (partition s "%"))]
         (mt (pairSecond p)
           ((none) (validIpv6Addr s))
           ((some scope) (and (not (stringEmpty? scope)) (not (hasSubstr scope "%")) (validIpv6Addr (pairFirst p)))))))

fn allHex s: String -> Bool
  (let [(bs (stringToBytes s))] (and (> (bytesLength bs) 0) (listAll? (fn [(i Int64)] -> Bool (>= (hexVal (bytesGet bs i)) 0)) (range 0 (bytesLength bs)))))

fn bracketedHostOk h: String -> Bool
  (if (stringStartsWith? h "v")
    (let [(p (partition (sliceB h 1 (stringLength h)) "."))]
      (and (allHex (pairFirst p)) (mt (pairSecond p) ((some rest) (and (not (stringEmpty? rest)) (not (hasSubstr rest "\n")))) ((none) false))))
    (and (not (validIpv4 h)) (validIpv6 h)))

fn minFound a: Int64 b: Int64 -> Int64
  (cond ((< a 0) b) ((< b 0) a) (else (min a b)))

fn urlsplit url0: String -> (Result (List String) PyErr)
  (let [(bs0 (stringToBytes url0))
        (url1 (sliceB url0 (lstripC0 bs0 (bytesLength bs0) 0) (bytesLength bs0)))
        (url2 (replaceAll (replaceAll (replaceAll url1 "\t" "") "\r" "") "\n" ""))
        (bs (stringToBytes url2)) (n (bytesLength bs))
        (ci (optionOr (stringIndexOf url2 ":") -1))
        (hasScheme (and (> ci 0) (let [(b (bytesGet bs 0))] (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))) (allScheme bs 0 ci)))
        (scheme (if hasScheme (asciiLower (sliceB url2 0 ci)) ""))
        (rest (if hasScheme (sliceB url2 (+ ci 1) n) url2))]
    (if (stringStartsWith? rest "//")
      (let [(rb (stringToBytes rest)) (rn (bytesLength rb))
            (d (minFound (minFound (findFrom rb rn (stringToBytes "/") 1 2) (findFrom rb rn (stringToBytes "?") 1 2)) (findFrom rb rn (stringToBytes "#") 1 2)))
            (delim (if (< d 0) rn d))
            (netloc (sliceB rest 2 delim))
            (after (sliceB rest delim rn))
            (ob (hasSubstr netloc "[")) (cb (hasSubstr netloc "]"))]
        (cond
          ((or (and ob (not cb)) (and cb (not ob))) (err (pyErr "ValueError" "Invalid IPv6 URL")))
          ((and ob cb (not (bracketedHostOk (pairFirst (partition (optionOr (pairSecond (partition netloc "[")) "") "]")))))
            (err (pyErr "ValueError" "invalid bracketed host")))
          (else (ok (splitRest scheme netloc after)))))
      (ok (splitRest scheme "" rest))))

fn splitRest scheme: String netloc: String url: String -> (List String)
  (let [(f (partition url "#"))
        (q (partition (pairFirst f) "?"))]
    (list scheme netloc (pairFirst q) (optionOr (pairSecond q) "") (optionOr (pairSecond f) "")))

fn usesParams s: String -> Bool
  (listContains? (list "" "ftp" "hdl" "prospero" "http" "imap" "https" "shttp" "rtsp" "rtsps" "rtspu" "sip" "sips" "mms" "sftp" "tel") s)

fn usesNetloc s: String -> Bool
  (listContains? (list "" "ftp" "http" "gopher" "nntp" "telnet" "imap" "wais" "file" "mms" "https" "shttp" "snews" "prospero" "rtsp" "rtsps" "rtspu" "rsync" "svn" "svn+ssh" "sftp" "nfs" "git" "git+ssh" "ws" "wss" "itms-services") s)

fn rfind bs: Bytes n: Int64 b: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (rfind bs n b (+ i 1) (if (= (bytesGet bs i) b) i acc)))

fn urlparse url: String -> (Result (List String) PyErr)
  (mt (urlsplit url)
    ((err e) (err e))
    ((ok parts)
      (let [(scheme (optionOr (listGet parts 0) "")) (path (optionOr (listGet parts 2) ""))]
        (if (and (usesParams scheme) (hasSubstr path ";"))
          (let [(bs (stringToBytes path)) (n (bytesLength bs))
                (i (if (hasSubstr path "/") (findFrom bs n (stringToBytes ";") 1 (rfind bs n 47 0 -1)) (optionOr (stringIndexOf path ";") -1)))]
            (if (< i 0)
              (ok (list scheme (optionOr (listGet parts 1) "") path "" (optionOr (listGet parts 3) "") (optionOr (listGet parts 4) "")))
              (ok (list scheme (optionOr (listGet parts 1) "") (sliceB path 0 i) (sliceB path (+ i 1) n) (optionOr (listGet parts 3) "") (optionOr (listGet parts 4) "")))))
          (ok (list scheme (optionOr (listGet parts 1) "") path "" (optionOr (listGet parts 3) "") (optionOr (listGet parts 4) "")))))))

fn urlunparse scheme: String netloc: String path0: String params: String query: String fragment: String -> String
  (let [(path (if (stringEmpty? params) path0 (str path0 ";" params)))
        (u (cond
             ((not (stringEmpty? netloc)) (str "//" netloc (if (and (not (stringEmpty? path)) (not (stringStartsWith? path "/"))) (str "/" path) path)))
             ((stringStartsWith? path "//") (str "//" path))
             ((and (not (stringEmpty? scheme)) (usesNetloc scheme) (or (stringEmpty? path) (stringStartsWith? path "/"))) (str "//" path))
             (else path)))
        (u1 (if (stringEmpty? scheme) u (str scheme ":" u)))
        (u2 (if (stringEmpty? query) u1 (str u1 "?" query)))]
    (if (stringEmpty? fragment) u2 (str u2 "#" fragment)))

fn trackingKey k: String -> Bool
  (or (stringStartsWith? k "utm_") (= k "ref") (= k "fbclid") (= k "gclid"))

fn cleanUrlStr url: String -> (Result String PyErr)
  (mt (urlparse url)
    ((err e) (err e))
    ((ok p)
      (let [(g (fn [(i Int64)] -> String (optionOr (listGet p i) "")))
            (kept (filter (fn [(kv (Pair String String))] -> Bool (not (trackingKey (pairFirst kv)))) (parseQsl (g 4))))]
        (ok (urlunparse (g 0) (g 1) (g 2) (g 3) (urlencodePairs kept) (g 5))))))

fn cleanUrl v: j/Json -> j/Json
  (mt v
    ((j/jstr s) (mt (cleanUrlStr s) ((ok r) (j/jstr r)) ((err _) v)))
    (_ (if (pyTruthy v) v (j/jstr ""))))

fn refEnd bs: Bytes n: Int64 i: Int64 f: (fn [Int64] -> Bool) -> Int64
  (if (and (< i n) (f (bytesGet bs i))) (refEnd bs n (+ i 1) f) i)

fn nameCharOk b: Int64 -> Bool
  (not (or (= b 9) (= b 10) (= b 12) (= b 32) (= b 60) (= b 38) (= b 35) (= b 59)))

fn nameEnd bs: Bytes n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((or (>= i n) (>= k 32)) i)
    ((not (nameCharOk (bytesGet bs i))) i)
    (else (nameEnd bs n (+ i (cpLenAt (bytesGet bs i))) (+ k 1))))

fn parseDigitsLoop bs: Bytes n: Int64 i: Int64 radix: Int64 acc: Int64 -> Int64
  (if (>= i n)
    acc
    (let [(v (hexVal (bytesGet bs i)))]
      (if (< v 0) acc (parseDigitsLoop bs n (+ i 1) radix (+ (* acc radix) v)))))

fn parseHexStr h: String -> Int64
  (let [(bs (stringToBytes h))] (parseDigitsLoop bs (bytesLength bs) 0 16 0))

fn hexCpsDecode s: String -> String
  (if (not (hasSubstr s ","))
    (cpEncode (parseHexStr s))
    (treeJoin (map (fn [(h String)] -> String (cpEncode (parseHexStr h))) (stringSplit s ","))))

fn entityLookup name: String -> (Option String)
  (if (stringEmpty? name)
    (none)
    (let [(tbl (ent/entityBucket (sliceB name 0 1))) (key (str "\n" name " "))]
      (mt (stringIndexOf tbl key)
        ((none) (none))
        ((some i)
          (let [(start (+ i (stringLength key))) (rest (sliceB tbl start (min (stringLength tbl) (+ start 64))))]
            (some (hexCpsDecode (pairFirst (partition rest "\n")))))))))

fn isZeroByte b: Int64 -> Bool
  (= b 48)

fn numericCodepoint num: Int64 -> String
  (cond
    ((or (and (>= num 55296) (<= num 57343)) (> num 1114111)) (cpEncode 65533))
    ((invalidCodepoint num) "")
    (else (cpEncode num)))

fn numericRef digits: String radix: Int64 -> String
  (let [(bs (stringToBytes digits)) (n (bytesLength bs))
        (firstNz (refEnd bs n 0 isZeroByte))
        (sig (- n firstNz))
        (num (if (> sig 8) 1114112000 (parseDigitsLoop bs n firstNz radix 0)))]
    (if (or (= num 0) (= num 13) (and (>= num 128) (<= num 159)))
      (let [(inv (ent/invalidCharrefTable))
            (key (str " " (hexOf num) ":"))]
        (mt (stringIndexOf inv key)
          ((some i) (let [(start (+ i (stringLength key)))] (hexCpsDecode (pairFirst (partition (sliceB inv start (stringLength inv)) " ")))))
          ((none) (numericCodepoint num))))
      (numericCodepoint num)))

fn hexOf n: Int64 -> String
  (if (< n 16) (sliceB "0123456789abcdef" n (+ n 1)) (str (hexOf (/ n 16)) (sliceB "0123456789abcdef" (mod n 16) (+ (mod n 16) 1))))

fn invalidCodepoint c: Int64 -> Bool
  (or (and (>= c 1) (<= c 8)) (= c 11) (and (>= c 14) (<= c 31)) (and (>= c 127) (<= c 159)) (and (>= c 64976) (<= c 65007))
      (= (& c 65535) 65534) (= (& c 65535) 65535))

fn prefixLookup s: String cps: (List Int64) x: Int64 -> String
  (if (< x 2)
    (str "&" s)
    (let [(pre (treeJoin (map cpEncode (listTake cps x))))]
      (mt (entityLookup pre)
        ((some v) (str v (treeJoin (map cpEncode (listDrop cps x)))))
        ((none) (prefixLookup s cps (- x 1))))))

fn namedRef s: String -> String
  (mt (entityLookup s)
    ((some v) v)
    ((none) (let [(cps (cpList s))] (prefixLookup s cps (- (listLength cps) 1)))))

fn unescapeLoop s: String bs: Bytes n: Int64 i: Int64 seg: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (if (< seg n) (cons (sliceB s seg n) acc) acc))
    (if (not (= (bytesGet bs i) 38))
      (unescapeLoop s bs n (+ i 1) seg acc)
      (let [(p (+ i 1))
            (isHash (and (< p n) (= (bytesGet bs p) 35)))
            (decEnd (if isHash (refEnd bs n (+ p 1) isDigitB) -1))
            (isHexRef (and isHash (<= decEnd (+ p 1)) (< (+ p 1) n) (or (= (bytesGet bs (+ p 1)) 120) (= (bytesGet bs (+ p 1)) 88))))
            (hexEnd (if isHexRef (refEnd bs n (+ p 2) (fn [(b Int64)] -> Bool (>= (hexVal b) 0))) -1))
            (kind (cond ((and isHash (> decEnd (+ p 1))) 1) ((and isHexRef (> hexEnd (+ p 2))) 2) (isHash 0) (else 3)))
            (bodyEnd (cond ((= kind 1) decEnd) ((= kind 2) hexEnd) ((= kind 3) (nameEnd bs n p 0)) (else p)))
            (matched (and (> kind 0) (> bodyEnd p)))
            (semi (and matched (< bodyEnd n) (= (bytesGet bs bodyEnd) 59)))
            (mEnd (if semi (+ bodyEnd 1) bodyEnd))]
        (if (not matched)
          (unescapeLoop s bs n (+ i 1) seg acc)
          (let [(rep (cond
                       ((= kind 1) (numericRef (sliceB s (+ p 1) bodyEnd) 10))
                       ((= kind 2) (numericRef (sliceB s (+ p 2) bodyEnd) 16))
                       (else (namedRef (sliceB s p mEnd)))))
                (acc1 (if (< seg i) (cons rep (cons (sliceB s seg i) acc)) (cons rep acc)))]
            (unescapeLoop s bs n mEnd mEnd acc1))))))

fn htmlUnescape s: String -> String
  (if (not (hasSubstr s "&"))
    s
    (let [(bs (stringToBytes s))] (treeJoin (unescapeLoop s bs (bytesLength bs) 0 0 (list)))))

fn tagLoop s: String bs: Bytes n: Int64 i: Int64 seg: Int64 rep: String acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (sliceB s seg n) acc))
    (if (not (= (bytesGet bs i) 60))
      (tagLoop s bs n (+ i 1) seg rep acc)
      (let [(gt (findFrom bs n (stringToBytes ">") 1 (+ i 1)))]
        (cond
          ((< gt 0) (listReverse (cons (sliceB s seg n) acc)))
          ((= gt (+ i 1)) (tagLoop s bs n (+ i 1) seg rep acc))
          (else (tagLoop s bs n (+ gt 1) (+ gt 1) rep (cons rep (cons (sliceB s seg i) acc))))))))

fn stripTagRegex s: String rep: String -> String
  (if (not (hasSubstr s "<"))
    s
    (let [(bs (stringToBytes s))] (treeJoin (tagLoop s bs (bytesLength bs) 0 0 rep (list)))))
