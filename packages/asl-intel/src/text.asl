(module asl-intel/text
  :x [byteAt spaceLen isSpaceByte utf8Len cpAt cpStartBefore isWordCp wordBefore? wordAt? isWordByteAscii
      cpLength cpPrefix concatAll joinWith padRight padLeft lowerAscii upperAscii
      pyStrip stripSet lstripSet pySplit splitLinesPy sliceStr charStr
      pyReprStr pyReprList intStr floatStr pyRound fmtFixed pow10
      normPath joinPath baseName dirName relPath splitExtRoot absPath
      bytesIndexOf containsAt? hasSub? countSub takeN dropN foldIndexOf wordHits wordHas? skipSpace trimSpaceBack cpOffset]
  :i [])

fn byteAt b: Bytes n: Int64 i: Int64 -> Int64
  (if (or (< i 0) (>= i n)) -1 (bytesGet b i))

fn isSpaceByte c: Int64 -> Bool
  (or (and (>= c 9) (<= c 13)) (or (= c 32) (and (>= c 28) (<= c 31))))

fn spaceLen b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (byteAt b n i))]
    (cond
      ((< c 0) 0)
      ((< c 128) (if (isSpaceByte c) 1 0))
      ((= c 194) (let [(d (byteAt b n (+ i 1)))] (if (or (= d 133) (= d 160)) 2 0)))
      ((= c 225) (if (and (= (byteAt b n (+ i 1)) 154) (= (byteAt b n (+ i 2)) 128)) 3 0))
      ((= c 226)
        (let [(d (byteAt b n (+ i 1))) (e (byteAt b n (+ i 2)))]
          (cond
            ((= d 128) (if (or (and (>= e 128) (<= e 138)) (or (= e 168) (or (= e 169) (= e 175)))) 3 0))
            ((= d 129) (if (= e 159) 3 0))
            (else 0))))
      ((= c 227) (if (and (= (byteAt b n (+ i 1)) 128) (= (byteAt b n (+ i 2)) 128)) 3 0))
      (else 0)))

fn utf8Len c: Int64 -> Int64
  (cond
    ((< c 192) 1)
    ((< c 224) 2)
    ((< c 240) 3)
    (else 4))

fn contBits b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (byteAt b n i))]
    (if (and (>= c 128) (< c 192)) (- c 128) -1))

fn cpAt b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (byteAt b n i))]
    (cond
      ((< c 128) c)
      ((< c 192) c)
      ((< c 224) (let [(x (contBits b n (+ i 1)))] (if (< x 0) c (+ (* (- c 192) 64) x))))
      ((< c 240)
        (let [(x (contBits b n (+ i 1))) (y (contBits b n (+ i 2)))]
          (if (or (< x 0) (< y 0)) c (+ (* (- c 224) 4096) (+ (* x 64) y)))))
      (else
        (let [(x (contBits b n (+ i 1))) (y (contBits b n (+ i 2))) (z (contBits b n (+ i 3)))]
          (if (or (< x 0) (or (< y 0) (< z 0))) c
            (+ (* (- c 240) 262144) (+ (* x 4096) (+ (* y 64) z))))))))

fn cpStartBefore b: Bytes i: Int64 -> Int64
  (if (<= i 0) -1 (cpBackLoop b (- i 1) (max 0 (- i 4))))

fn cpBackLoop b: Bytes j: Int64 floor: Int64 -> Int64
  (if (<= j floor) j
    (let [(c (bytesGet b j))]
      (if (and (>= c 128) (< c 192)) (cpBackLoop b (- j 1) floor) j)))

fn isWordByteAscii c: Int64 -> Bool
  (or (and (>= c 97) (<= c 122)) (or (and (>= c 65) (<= c 90)) (or (and (>= c 48) (<= c 57)) (= c 95))))

fn isWordCp cp: Int64 -> Bool
  (cond
    ((< cp 128) (isWordByteAscii cp))
    ((< cp 256)
      (or (= cp 170) (or (= cp 178) (or (= cp 179) (or (= cp 181) (or (= cp 185) (or (= cp 186)
        (or (and (>= cp 188) (<= cp 190)) (or (and (>= cp 192) (<= cp 214)) (or (and (>= cp 216) (<= cp 246)) (>= cp 248)))))))))))
    ((<= cp 705) true)
    ((<= cp 879) (or (and (>= cp 710) (<= cp 721)) (or (and (>= cp 736) (<= cp 740)) (or (= cp 748) (= cp 750)))))
    ((<= cp 1327) (not (or (= cp 885) (or (= cp 894) (or (= cp 903) (or (= cp 1014) (and (>= cp 1154) (<= cp 1161))))))))
    ((<= cp 1423) (or (and (>= cp 1329) (<= cp 1366)) (and (>= cp 1376) (<= cp 1416))))
    ((<= cp 1535) (and (>= cp 1488) (<= cp 1522)))
    ((<= cp 1791) (or (and (>= cp 1568) (<= cp 1610)) (or (and (>= cp 1632) (<= cp 1641)) (and (>= cp 1646) (<= cp 1747)))))
    ((<= cp 7679) false)
    ((<= cp 8191) (not (or (= cp 8125) (or (and (>= cp 8127) (<= cp 8129)) (or (and (>= cp 8141) (<= cp 8143)) (or (and (>= cp 8157) (<= cp 8159)) (or (and (>= cp 8173) (<= cp 8175)) (>= cp 8189))))))))
    ((<= cp 8303) false)
    ((<= cp 8351) (or (= cp 8304) (or (= cp 8305) (or (and (>= cp 8308) (<= cp 8313)) (or (= cp 8319) (or (and (>= cp 8320) (<= cp 8329)) (and (>= cp 8336) (<= cp 8348))))))))
    ((<= cp 8527) (or (= cp 8450) (or (= cp 8455) (or (and (>= cp 8458) (<= cp 8467)) (or (= cp 8469) (or (and (>= cp 8473) (<= cp 8477)) (or (= cp 8484) (or (= cp 8486) (or (= cp 8488) (or (and (>= cp 8490) (<= cp 8493)) (or (and (>= cp 8495) (<= cp 8505)) (and (>= cp 8508) (<= cp 8511)))))))))))))
    ((<= cp 8585) true)
    ((<= cp 9311) false)
    ((<= cp 9371) true)
    ((<= cp 9449) false)
    ((<= cp 9471) true)
    ((<= cp 10101) false)
    ((<= cp 10131) true)
    ((<= cp 12287) false)
    ((<= cp 12351) (or (= cp 12293) (or (= cp 12294) (or (= cp 12295) (or (and (>= cp 12321) (<= cp 12329)) (or (and (>= cp 12337) (<= cp 12341)) (and (>= cp 12344) (<= cp 12348))))))))
    ((<= cp 12543) (not (or (= cp 12352) (or (= cp 12439) (or (= cp 12440) (or (= cp 12441) (or (= cp 12442) (or (= cp 12443) (or (= cp 12444) (or (= cp 12448) (= cp 12539)))))))))))
    ((<= cp 13311) (or (and (>= cp 12549) (<= cp 12591)) (or (and (>= cp 12593) (<= cp 12686)) (or (and (>= cp 12690) (<= cp 12693)) (and (>= cp 12704) (<= cp 12735))))))
    ((<= cp 19903) true)
    ((<= cp 19967) false)
    ((<= cp 40959) true)
    ((<= cp 42191) true)
    ((<= cp 44031) (or (and (>= cp 42192) (<= cp 42237)) (or (and (>= cp 42240) (<= cp 42508)) (or (and (>= cp 42512) (<= cp 42539)) (or (and (>= cp 42560) (<= cp 42606)) (or (and (>= cp 42623) (<= cp 42653)) (or (and (>= cp 42656) (<= cp 42735)) (or (and (>= cp 42775) (<= cp 42783)) (or (and (>= cp 42786) (<= cp 42888)) (and (>= cp 42891) (<= cp 43007)))))))))))
    ((<= cp 55203) true)
    ((<= cp 63743) false)
    ((<= cp 64255) true)
    ((<= cp 65295) false)
    ((<= cp 65305) true)
    ((<= cp 65312) false)
    ((<= cp 65338) true)
    ((<= cp 65344) false)
    ((<= cp 65370) true)
    ((<= cp 65381) false)
    ((<= cp 65500) true)
    ((<= cp 65535) false)
    ((<= cp 66047) (not (or (and (>= cp 65792) (<= cp 65798)) (or (and (>= cp 65847) (<= cp 65855)) (and (>= cp 65913) (<= cp 65999))))))
    ((<= cp 119807) false)
    ((<= cp 120831) (not (or (= cp 120513) (or (= cp 120539) (or (= cp 120571) (or (= cp 120597) (or (= cp 120629) (or (= cp 120655) (or (= cp 120687) (or (= cp 120713) (or (= cp 120745) (or (= cp 120771) (and (>= cp 120780) (<= cp 120781))))))))))))))
    ((<= cp 131071) false)
    ((<= cp 201551) true)
    (else false))

fn wordBefore? b: Bytes n: Int64 i: Int64 -> Bool
  (if (<= i 0) false
    (let [(c (bytesGet b (- i 1)))]
      (if (< c 128) (isWordByteAscii c)
        (let [(s (cpStartBefore b i))] (if (< s 0) false (isWordCp (cpAt b n s)))))))

fn wordAt? b: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n) false
    (let [(c (bytesGet b i))]
      (if (< c 128) (isWordByteAscii c) (isWordCp (cpAt b n i)))))

fn cpLength s: String -> Int64
  (let [(b (stringToBytes s)) (n (bytesLength b))]
    (cpCountLoop b 0 n 0))

fn cpCountLoop b: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc
    (let [(c (bytesGet b i))]
      (cpCountLoop b (+ i 1) n (if (and (>= c 128) (< c 192)) acc (+ acc 1)))))

fn cpOffset b: Bytes n: Int64 i: Int64 k: Int64 -> Int64
  (if (or (>= i n) (<= k 0)) (min i n)
    (cpOffset b n (min n (+ i (utf8Len (bytesGet b i)))) (- k 1)))

fn cpPrefix s: String k: Int64 -> String
  (let [(b (stringToBytes s)) (n (bytesLength b))]
    (sliceStr s 0 (cpOffset b n 0 k)))

fn sliceStr s: String i: Int64 j: Int64 -> String
  (let [(n (stringLength s)) (a (max 0 (min i n))) (e (max 0 (min j n)))]
    (if (>= a e) "" (optionOr (stringSlice s a e) "")))

fn charStr c: Int64 -> String
  (optionOr (stringSlice " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" (- c 32) (- c 31)) "")

fn concatPass xs: (List String) acc: (List String) -> (List String)
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some a)
      (let [(rest (optionOr (listTail xs) (list)))]
        (mt (listHead rest)
          ((none) (listReverse (cons a acc)))
          ((some b2) (concatPass (optionOr (listTail rest) (list)) (cons (stringConcat a b2) acc)))))))

fn concatAll xs: (List String) -> String
  (cond
    ((listEmpty? xs) "")
    ((= (listLength xs) 1) (optionOr (listHead xs) ""))
    (else (concatAll (concatPass xs (list)))))

fn joinWith xs: (List String) sep: String -> String
  (concatAll (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String)
                                  (if (listEmpty? acc) (list x) (cons x (cons sep acc))))
                                (list) xs)))

fn padRight s: String w: Int64 -> String
  (let [(k (- w (cpLength s)))] (if (<= k 0) s (str s (stringRepeat " " k))))

fn padLeft s: String w: Int64 -> String
  (let [(k (- w (cpLength s)))] (if (<= k 0) s (str (stringRepeat " " k) s)))

fn caseLoop s: String b: Bytes n: Int64 i: Int64 start: Int64 lo: Int64 hi: Int64 delta: Int64 acc: (List String) -> String
  (if (>= i n)
    (concatAll (listReverse (cons (sliceStr s start n) acc)))
    (let [(c (bytesGet b i))]
      (if (and (>= c lo) (<= c hi))
        (caseLoop s b n (+ i 1) (+ i 1) lo hi delta (cons (charStr (+ c delta)) (cons (sliceStr s start i) acc)))
        (caseLoop s b n (+ i 1) start lo hi delta acc))))

fn lowerAscii s: String -> String
  (let [(b (stringToBytes s))] (caseLoop s b (bytesLength b) 0 0 65 90 32 (list)))

fn upperAscii s: String -> String
  (let [(b (stringToBytes s))] (caseLoop s b (bytesLength b) 0 0 97 122 -32 (list)))

fn skipSpace b: Bytes n: Int64 i: Int64 -> Int64
  (let [(k (spaceLen b n i))] (if (> k 0) (skipSpace b n (+ i k)) i))

fn trimSpaceBack b: Bytes n: Int64 lo: Int64 j: Int64 -> Int64
  (if (<= j lo) lo
    (let [(s (cpStartBefore b j))]
      (if (and (>= s lo) (= (+ s (spaceLen b n s)) j) (> (spaceLen b n s) 0))
        (trimSpaceBack b n lo s)
        j)))

fn pyStrip s: String -> String
  (let [(b (stringToBytes s)) (n (bytesLength b)) (i (skipSpace b n 0)) (j (trimSpaceBack b n i n))]
    (sliceStr s i j))

fn inSet? c: Int64 set: Bytes k: Int64 i: Int64 -> Bool
  (cond
    ((>= i k) false)
    ((= (bytesGet set i) c) true)
    (else (inSet? c set k (+ i 1))))

fn stripSet s: String chars: String -> String
  (let [(b (stringToBytes s)) (n (bytesLength b)) (cs (stringToBytes chars)) (k (bytesLength cs))
        (i (stripFwd b n cs k 0)) (j (stripBack b cs k i n))]
    (sliceStr s i j))

fn lstripSet s: String chars: String -> String
  (let [(b (stringToBytes s)) (n (bytesLength b)) (cs (stringToBytes chars)) (k (bytesLength cs))]
    (sliceStr s (stripFwd b n cs k 0) n))

fn stripFwd b: Bytes n: Int64 cs: Bytes k: Int64 i: Int64 -> Int64
  (if (and (< i n) (inSet? (bytesGet b i) cs k 0)) (stripFwd b n cs k (+ i 1)) i)

fn stripBack b: Bytes cs: Bytes k: Int64 lo: Int64 j: Int64 -> Int64
  (if (and (> j lo) (inSet? (bytesGet b (- j 1)) cs k 0)) (stripBack b cs k lo (- j 1)) j)

fn pySplit s: String -> (List String)
  (let [(b (stringToBytes s)) (n (bytesLength b))]
    (listReverse (splitWsLoop s b n 0 (list))))

fn splitWsLoop s: String b: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [(a (skipSpace b n i))]
    (if (>= a n) acc
      (let [(e (tokenEnd b n a))]
        (splitWsLoop s b n e (cons (sliceStr s a e) acc)))))

fn tokenEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (> (spaceLen b n i) 0)) i
    (tokenEnd b n (+ i (utf8Len (bytesGet b i)))))

fn lineBreakLen b: Bytes n: Int64 i: Int64 -> Int64
  (let [(c (byteAt b n i))]
    (cond
      ((= c 10) 1)
      ((= c 13) (if (= (byteAt b n (+ i 1)) 10) 2 1))
      ((or (= c 11) (= c 12)) 1)
      ((and (>= c 28) (<= c 30)) 1)
      ((= c 194) (if (= (byteAt b n (+ i 1)) 133) 2 0))
      ((= c 226) (if (and (= (byteAt b n (+ i 1)) 128) (or (= (byteAt b n (+ i 2)) 168) (= (byteAt b n (+ i 2)) 169))) 3 0))
      (else 0)))

fn splitLinesPy b: Bytes n: Int64 -> (List (Pair Int64 Int64))
  (listReverse (linesLoop b n 0 0 (list)))

fn linesLoop b: Bytes n: Int64 start: Int64 i: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (if (> n start) (cons (pair start n) acc) acc)
    (let [(k (lineBreakLen b n i))]
      (if (> k 0)
        (linesLoop b n (+ i k) (+ i k) (cons (pair start i) acc))
        (linesLoop b n start (+ i 1) acc))))

fn hex2 c: Int64 -> String
  (let [(d "0123456789abcdef")]
    (str (sliceStr d (/ c 16) (+ (/ c 16) 1)) (sliceStr d (mod c 16) (+ (mod c 16) 1))))

fn reprEscape cp: Int64 q: Int64 -> String
  (cond
    ((= cp 92) "\\\\")
    ((= cp q) (str "\\" (charStr q)))
    ((= cp 10) "\\n")
    ((= cp 13) "\\r")
    ((= cp 9) "\\t")
    ((or (< cp 32) (= cp 127)) (str "\\x" (hex2 cp)))
    ((or (and (>= cp 128) (<= cp 160)) (= cp 173)) (str "\\x" (hex2 cp)))
    ((or (= cp 8232) (= cp 8233)) (str "\\u" (hex2 (/ cp 256)) (hex2 (mod cp 256))))
    (else ""))

fn pyReprStr s: String -> String
  (let [(q (if (and (stringContains? s "'") (not (stringContains? s "\""))) 34 39))
        (b (stringToBytes s)) (n (bytesLength b))]
    (str (charStr q) (reprLoop s b n 0 0 q (list)) (charStr q)))

fn reprLoop s: String b: Bytes n: Int64 i: Int64 start: Int64 q: Int64 acc: (List String) -> String
  (if (>= i n)
    (concatAll (listReverse (cons (sliceStr s start n) acc)))
    (let [(cp (cpAt b n i)) (k (utf8Len (bytesGet b i))) (e (reprEscape cp q))]
      (if (stringEmpty? e)
        (reprLoop s b n (+ i k) start q acc)
        (reprLoop s b n (+ i k) (+ i k) q (cons e (cons (sliceStr s start i) acc))))))

fn pyReprList xs: (List String) -> String
  (str "[" (joinWith (map pyReprStr xs) ", ") "]")

fn intStr n: Int64 -> String
  (stringFromInt64 n)

fn floatStr x: Float -> String
  (stringFromFloat64 x)

fn pow10 k: Int64 -> Int64
  (if (<= k 0) 1 (* 10 (pow10 (- k 1))))

fn pow2 k: Int64 -> Int64
  (if (<= k 0) 1 (* 2 (pow2 (- k 1))))

fn floatParts x: Float -> (List Int64)
  (let [(buf (bytesAlloc 8))
        (u (bytesSetFloat64 buf 0 x))
        (b7 (bytesGet buf 7)) (b6 (bytesGet buf 6))
        (expo (+ (* (mod b7 128) 16) (/ b6 16)))
        (mant (+ (* (mod b6 16) 281474976710656)
                 (+ (* (bytesGet buf 5) 1099511627776) (+ (* (bytesGet buf 4) 4294967296)
                 (+ (* (bytesGet buf 3) 16777216) (+ (* (bytesGet buf 2) 65536) (+ (* (bytesGet buf 1) 256) (bytesGet buf 0))))))))]
    (list (if (>= b7 128) 1 0) expo mant))

fn scaledHalfEven x: Float nd: Int64 -> Int64
  (let [(parts (floatParts x))
        (expo (optionOr (listGet parts 1) 0))
        (mant (optionOr (listGet parts 2) 0))
        (m (if (= expo 0) mant (+ mant 4503599627370496)))
        (e2 (if (= expo 0) -1074 (- expo 1075)))
        (big (* m (pow10 nd)))]
    (cond
      ((>= e2 0) -1)
      ((>= (- 0 e2) 64) 0)
      ((= (- 0 e2) 63) (if (> big 4611686018427387904) 1 0))
      (else
        (let [(p (pow2 (- 0 e2))) (q (/ big p)) (r (mod big p)) (half (/ p 2))]
          (cond
            ((> r half) (+ q 1))
            ((= r half) (+ q (mod q 2)))
            (else q))))))

fn pyRound x: Float nd: Int64 -> Float
  (if (or (!= x x) (= x 0.0)) x
    (let [(neg (< x 0.0)) (ax (if neg (- 0.0 x) x)) (q (scaledHalfEven ax nd))]
      (if (< q 0) x
        (let [(r (/ (int64ToFloat64 q) (int64ToFloat64 (pow10 nd))))]
          (if neg (- 0.0 r) r)))))

fn fmtFixed x: Float nd: Int64 -> String
  (let [(neg (< x 0.0)) (ax (if neg (- 0.0 x) x)) (q0 (scaledHalfEven ax nd))
        (q (if (< q0 0) (* (mt (float64ToInt64 ax) ((some i) i) ((none) 0)) (pow10 nd)) q0))
        (p (pow10 nd)) (ip (/ q p)) (fp (mod q p))
        (fs (intStr fp))
        (body (if (= nd 0) (intStr ip) (str (intStr ip) "." (stringRepeat "0" (- nd (stringLength fs))) fs)))]
    (if neg (str "-" body) body))

fn pathParts p: String -> (List String)
  (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (stringSplit p "/"))

fn normPath p: String -> String
  (if (stringEmpty? p) "."
    (let [(abs (stringStartsWith? p "/"))
          (lead (if (and (stringStartsWith? p "//") (not (stringStartsWith? p "///"))) "//" (if abs "/" "")))
          (comps (listReverse (fold (fn [(acc (List String)) (c String)] -> (List String)
                                      (cond
                                        ((= c ".") acc)
                                        ((= c "..")
                                          (cond
                                            ((and (not (listEmpty? acc)) (!= (optionOr (listHead acc) "") "..")) (optionOr (listTail acc) (list)))
                                            (abs acc)
                                            (else (cons c acc))))
                                        (else (cons c acc))))
                                    (list) (pathParts p))))
          (joined (str lead (joinWith comps "/")))]
      (if (stringEmpty? joined) "." joined)))

fn joinPath a: String b: String -> String
  (cond
    ((stringStartsWith? b "/") b)
    ((or (stringEmpty? a) (stringEndsWith? a "/")) (str a b))
    (else (str a "/" b)))

fn lastSlash b: Bytes i: Int64 -> Int64
  (cond
    ((< i 0) -1)
    ((= (bytesGet b i) 47) i)
    (else (lastSlash b (- i 1))))

fn baseName p: String -> String
  (let [(b (stringToBytes p)) (n (bytesLength b))]
    (sliceStr p (+ (lastSlash b (- n 1)) 1) n))

fn dirName p: String -> String
  (let [(b (stringToBytes p)) (n (bytesLength b)) (k (lastSlash b (- n 1)))]
    (if (< k 0) ""
      (let [(head (sliceStr p 0 (+ k 1))) (hb (stringToBytes head))]
        (if (= (stripBack hb (stringToBytes "/") 1 0 (bytesLength hb)) 0) head
          (sliceStr head 0 (stripBack hb (stringToBytes "/") 1 0 (bytesLength hb)))))))

fn absPath p: String cwd: String -> String
  (normPath (if (stringStartsWith? p "/") p (joinPath cwd p)))

fn dropCommon a: (List String) b: (List String) -> (Pair (List String) (List String))
  (if (and (not (listEmpty? a)) (and (not (listEmpty? b)) (= (listHead a) (listHead b))))
    (dropCommon (optionOr (listTail a) (list)) (optionOr (listTail b) (list)))
    (pair a b))

fn relPath p: String start: String cwd: String -> String
  (let [(pa (pathParts (absPath p cwd))) (sa (pathParts (absPath start cwd)))
        (d (dropCommon pa sa))
        (ups (map (fn [(x String)] -> String "..") (pairSecond d)))
        (all (listAppend ups (pairFirst d)))]
    (if (listEmpty? all) "." (joinWith all "/")))

fn splitExtRoot p: String -> String
  (let [(base (baseName p)) (b (stringToBytes base)) (n (bytesLength b))
        (lead (stripFwd b n (stringToBytes ".") 1 0))
        (dot (lastDot b (- n 1) lead))]
    (if (< dot 0) p (sliceStr p 0 (- (stringLength p) (- n dot)))))

fn lastDot b: Bytes i: Int64 lo: Int64 -> Int64
  (cond
    ((< i lo) -1)
    ((= (bytesGet b i) 46) i)
    (else (lastDot b (- i 1) lo)))

fn containsAt? b: Bytes n: Int64 i: Int64 t: Bytes k: Int64 j: Int64 -> Bool
  (cond
    ((>= j k) true)
    ((>= (+ i j) n) false)
    ((!= (bytesGet b (+ i j)) (bytesGet t j)) false)
    (else (containsAt? b n i t k (+ j 1))))

fn bytesIndexOf b: Bytes n: Int64 t: Bytes k: Int64 i: Int64 -> Int64
  (cond
    ((> (+ i k) n) -1)
    ((containsAt? b n i t k 0) i)
    (else (bytesIndexOf b n t k (+ i 1))))

fn hasSub? s: String t: String -> Bool
  (stringContains? s t)

fn countSub s: String t: String -> Int64
  (let [(b (stringToBytes s)) (tb (stringToBytes t)) (k (bytesLength tb))]
    (if (= k 0) (+ (cpLength s) 1) (countSubLoop b (bytesLength b) tb k 0 0)))

fn countSubLoop b: Bytes n: Int64 t: Bytes k: Int64 i: Int64 acc: Int64 -> Int64
  (let [(j (bytesIndexOf b n t k i))]
    (if (< j 0) acc (countSubLoop b n t k (+ j k) (+ acc 1))))

fn takeN xs: (List T) k: Int64 -> (List T)
  (takeLoop xs k (list))

fn takeLoop xs: (List T) k: Int64 acc: (List T) -> (List T)
  (if (<= k 0) (listReverse acc)
    (mt (listHead xs)
      ((none) (listReverse acc))
      ((some x) (takeLoop (optionOr (listTail xs) (list)) (- k 1) (cons x acc)))))

fn dropN xs: (List T) k: Int64 -> (List T)
  (if (<= k 0) xs
    (mt (listTail xs)
      ((none) (list))
      ((some r) (dropN r (- k 1)))))

fn foldB c: Int64 -> Int64
  (if (and (>= c 65) (<= c 90)) (+ c 32) c)

fn foldAt? b: Bytes i: Int64 t: Bytes k: Int64 j: Int64 -> Bool
  (cond
    ((>= j k) true)
    ((!= (foldB (bytesGet b (+ i j))) (foldB (bytesGet t j))) false)
    (else (foldAt? b i t k (+ j 1))))

fn foldIndexOf b: Bytes n: Int64 t: Bytes k: Int64 i: Int64 -> Int64
  (cond
    ((> (+ i k) n) -1)
    ((= k 0) i)
    ((and (= (foldB (bytesGet b i)) (foldB (bytesGet t 0))) (foldAt? b i t k 1)) i)
    (else (foldIndexOf b n t k (+ i 1))))

fn wordHits b: Bytes n: Int64 w: Bytes k: Int64 i: Int64 limit: Int64 acc: Int64 -> Int64
  (if (>= acc limit) acc
    (let [(j (bytesIndexOf b n w k i))]
      (cond
        ((< j 0) acc)
        ((and (!= (wordBefore? b n j) (wordAt? b n j)) (!= (wordBefore? b n (+ j k)) (wordAt? b n (+ j k))))
          (wordHits b n w k (+ j (max k 1)) limit (+ acc 1)))
        (else (wordHits b n w k (+ j 1) limit acc)))))

fn wordHas? s: String w: String -> Bool
  (let [(b (stringToBytes s)) (wb (stringToBytes w))]
    (> (wordHits b (bytesLength b) wb (bytesLength wb) 0 1 0) 0))
