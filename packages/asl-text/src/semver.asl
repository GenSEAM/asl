(module asl-text/semver :x [Version parse compare satisfies] :i [])

(schema Version (:f major Int64) (:f minor Int64) (:f patch Int64) (:f pre (List String)) (:f build (List String)))

(schema RangeSpec (:f major Int64) (:f minor Int64) (:f patch Int64) (:f pre (List String)) (:f count Int64))

fn isDigit c: String -> Bool
  (let [(n (charCode c))]
    (and (>= n 48) (<= n 57)))

fn isIdChar c: String -> Bool
  (let [(n (charCode c))]
    (or (and (>= n 48) (<= n 57))
        (and (>= n 65) (<= n 90))
        (and (>= n 97) (<= n 122))
        (= n 45)))

fn allDigits s: String -> Bool
  (and (not (stringEmpty? s))
       (listAll? isDigit (stringChars s)))

fn validNumId s: String -> Bool
  (and (allDigits s)
       (or (= s "0")
           (not (= (optionOr (stringSlice s 0 1) "") "0"))))

fn validPreId s: String -> Bool
  (and (not (stringEmpty? s))
       (listAll? isIdChar (stringChars s))
       (or (not (allDigits s))
           (validNumId s)))

fn validBuildId s: String -> Bool
  (and (not (stringEmpty? s))
       (listAll? isIdChar (stringChars s)))

fn allValidPre ids: (List String) -> Bool
  (listAll? validPreId ids)

fn allValidBuild ids: (List String) -> Bool
  (listAll? validBuildId ids)

fn parseNum s: String -> (Result Int64 String)
  (match (stringToInt64 s)
    ((some n) (ok n))
    ((none) (err (str "unrepresentable: " s))))

fn validCorePart s: String -> Bool
  (and (allDigits s)
       (or (= s "0")
           (not (= (optionOr (stringSlice s 0 1) "") "0"))))

fn parseCore s: String -> (Result (List Int64) String)
  (let [(parts (stringSplit s "."))]
    (if (= (listLength parts) 3)
      (if (and (validCorePart (optionOr (listGet parts 0) ""))
               (validCorePart (optionOr (listGet parts 1) ""))
               (validCorePart (optionOr (listGet parts 2) "")))
        (let [(m (parseNum (optionOr (listGet parts 0) "")))
              (mi (parseNum (optionOr (listGet parts 1) "")))
              (pa (parseNum (optionOr (listGet parts 2) "")))]
          (if (and (ok? m) (ok? mi) (ok? pa))
            (ok (list (resultOr m 0) (resultOr mi 0) (resultOr pa 0)))
            (err "core overflow")))
        (err (str "invalid core: " s)))
      (err (str "core needs 3 parts: " s))))

fn parse s: String -> (Result Version String)
  (let [(plusPos (stringIndexOf s "+"))
        (left (match plusPos ((some i) (optionOr (stringSlice s 0 i) "")) ((none) s)))
        (buildStr (match plusPos ((some i) (optionOr (stringSlice s (+ i 1) (stringLength s)) "")) ((none) "")))
        (dashPos (stringIndexOf left "-"))
        (coreStr (match dashPos ((some i) (optionOr (stringSlice left 0 i) "")) ((none) left)))
        (preStr (match dashPos ((some i) (optionOr (stringSlice left (+ i 1) (stringLength left)) "")) ((none) "")))]
    (if (match dashPos
          ((some _) (or (stringEmpty? preStr) (not (allValidPre (stringSplit preStr ".")))))
          ((none) false))
      (err (str "invalid prerelease: " preStr))
      (if (match plusPos
            ((some _) (or (stringEmpty? buildStr) (not (allValidBuild (stringSplit buildStr ".")))))
            ((none) false))
        (err (str "invalid build: " buildStr))
        (match (parseCore coreStr)
          ((ok nums)
           (ok (Version :major (optionOr (listGet nums 0) 0)
                        :minor (optionOr (listGet nums 1) 0)
                        :patch (optionOr (listGet nums 2) 0)
                        :pre (if (stringEmpty? preStr) (list) (stringSplit preStr "."))
                        :build (if (stringEmpty? buildStr) (list) (stringSplit buildStr ".")))))
          ((err e) (err e))))))

fn cmpInt a: Int64 b: Int64 -> Int64
  (if (< a b) -1 (if (> a b) 1 0))

fn isNumeric s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? isDigit (stringChars s)))

fn cmpStr a: String b: String i: Int64 la: Int64 lb: Int64 -> Int64
  (cond
    ((and (>= i la) (>= i lb)) 0)
    ((>= i la) -1)
    ((>= i lb) 1)
    (else
      (let [(ca (charCode (optionOr (stringSlice a i (+ i 1)) "")))
            (cb (charCode (optionOr (stringSlice b i (+ i 1)) "")))]
        (if (< ca cb) -1 (if (> ca cb) 1 (cmpStr a b (+ i 1) la lb))))))

fn cmpNumStr a: String b: String -> Int64
  (let [(la (stringLength a))
        (lb (stringLength b))]
    (if (< la lb) -1
      (if (> la lb) 1
        (cmpStr a b 0 la lb))))

fn cmpPreId a: String b: String -> Int64
  (let [(ad (isNumeric a))
        (bd (isNumeric b))]
    (if (and ad bd)
      (cmpNumStr a b)
      (if ad -1 (if bd 1 (cmpStr a b 0 (stringLength a) (stringLength b))))))

fn cmpPreLoop a: (List String) b: (List String) i: Int64 n: Int64 la: Int64 lb: Int64 -> Int64
  (if (>= i n)
    (cmpInt la lb)
    (let [(c (cmpPreId (optionOr (listGet a i) "") (optionOr (listGet b i) "")))]
      (if (= c 0) (cmpPreLoop a b (+ i 1) n la lb) c)))

fn cmpPreLists a: (List String) b: (List String) -> Int64
  (let [(la (listLength a))
        (lb (listLength b))
        (n (min la lb))]
    (cmpPreLoop a b 0 n la lb))

fn compare a: Version b: Version -> Int64
  (let [(cm (cmpInt a.major b.major))]
    (if (not (= cm 0)) cm
      (let [(cn (cmpInt a.minor b.minor))]
        (if (not (= cn 0)) cn
          (let [(cp (cmpInt a.patch b.patch))]
            (if (not (= cp 0)) cp
              (let [(ap (listEmpty? a.pre))
                    (bp (listEmpty? b.pre))]
                (cond
                  ((and ap bp) 0)
                  (ap 1)
                  (bp -1)
                  (else (cmpPreLists a.pre b.pre))))))))))

fn parseRangeVer s: String -> (Result RangeSpec String)
  (let [(plusPos (stringIndexOf s "+"))
        (left (match plusPos ((some i) (optionOr (stringSlice s 0 i) "")) ((none) s)))
        (buildStr (match plusPos ((some i) (optionOr (stringSlice s (+ i 1) (stringLength s)) "")) ((none) "")))
        (dashPos (stringIndexOf left "-"))
        (coreStr (match dashPos ((some i) (optionOr (stringSlice left 0 i) "")) ((none) left)))
        (preStr (match dashPos ((some i) (optionOr (stringSlice left (+ i 1) (stringLength left)) "")) ((none) "")))
        (parts (stringSplit coreStr "."))
        (n (listLength parts))]
    (if (or (< n 1) (> n 3))
      (err (str "bad range: " s))
      (if (match dashPos
            ((some _) (or (stringEmpty? preStr) (not (allValidPre (stringSplit preStr ".")))))
            ((none) false))
        (err (str "bad range pre: " s))
        (if (match plusPos
              ((some _) (or (stringEmpty? buildStr) (not (allValidBuild (stringSplit buildStr ".")))))
              ((none) false))
          (err (str "bad range build: " s))
          (if (not (listAll? validCorePart parts))
            (err (str "bad range core: " s))
            (let [(m (parseNum (optionOr (listGet parts 0) "")))
                  (mi (if (>= n 2) (parseNum (optionOr (listGet parts 1) "")) (ok 0)))
                  (pa (if (>= n 3) (parseNum (optionOr (listGet parts 2) "")) (ok 0)))]
              (if (and (ok? m) (ok? mi) (ok? pa))
                (ok (RangeSpec :major (resultOr m 0) :minor (resultOr mi 0) :patch (resultOr pa 0)
                               :pre (if (stringEmpty? preStr) (list) (stringSplit preStr "."))
                               :count n))
                (err (str "range overflow: " s)))))))))

fn preAllowed v: Version t: Version -> Bool
  (if (listEmpty? v.pre) true
    (if (listEmpty? t.pre) false
      (and (= v.major t.major) (= v.minor t.minor) (= v.patch t.patch))))

fn caretOk v: Version rv: String -> Bool
  (match (parseRangeVer rv)
    ((ok r)
     (let [(lo (Version :major r.major :minor r.minor :patch r.patch :pre r.pre :build (list)))
           (hi (cond
                 ((> r.major 0) (Version :major (+ r.major 1) :minor 0 :patch 0 :pre (list) :build (list)))
                 ((= r.count 1) (Version :major 1 :minor 0 :patch 0 :pre (list) :build (list)))
                 ((> r.minor 0) (Version :major 0 :minor (+ r.minor 1) :patch 0 :pre (list) :build (list)))
                 ((= r.count 2) (Version :major 0 :minor 1 :patch 0 :pre (list) :build (list)))
                 (else (Version :major 0 :minor 0 :patch (+ r.patch 1) :pre (list) :build (list)))))]
       (and (preAllowed v lo)
            (>= (compare v lo) 0)
            (< (compare v hi) 0))))
    ((err e) false))

fn tildeOk v: Version rv: String -> Bool
  (match (parseRangeVer rv)
    ((ok r)
     (let [(lo (Version :major r.major :minor r.minor :patch r.patch :pre r.pre :build (list)))
           (hi (if (= r.count 1)
                 (Version :major (+ r.major 1) :minor 0 :patch 0 :pre (list) :build (list))
                 (Version :major r.major :minor (+ r.minor 1) :patch 0 :pre (list) :build (list))))]
       (and (preAllowed v lo)
            (>= (compare v lo) 0)
            (< (compare v hi) 0))))
    ((err e) false))

fn cmpOp v: Version rv: String op: String -> Bool
  (match (parseRangeVer rv)
    ((ok r)
     (let [(target (Version :major r.major :minor r.minor :patch r.patch :pre r.pre :build (list)))
           (c (compare v target))
           (nextMinor (Version :major r.major :minor (+ r.minor 1) :patch 0 :pre (list) :build (list)))
           (nextMajor (Version :major (+ r.major 1) :minor 0 :patch 0 :pre (list) :build (list)))]
       (cond
         ((and (= op ">") (< r.count 3))
          (let [(b (if (= r.count 1) nextMajor nextMinor))]
            (and (preAllowed v b) (>= (compare v b) 0))))
         ((and (= op "<=") (< r.count 3))
          (let [(b (if (= r.count 1) nextMajor nextMinor))]
            (and (preAllowed v b) (< (compare v b) 0))))
         ((and (= op "=") (< r.count 3)) (tildeOk v rv))
         ((not (preAllowed v target)) false)
         ((= op ">=") (>= c 0))
         ((= op "<=") (<= c 0))
         ((= op ">") (> c 0))
         ((= op "<") (< c 0))
         (else (= c 0)))))
    ((err e) false))

fn satisfies v: Version range: String -> Bool
  (let [(t (stringTrim range))]
    (cond
      ((stringStartsWith? t "^") (caretOk v (stringTrim (optionOr (stringSlice t 1 (stringLength t)) ""))))
      ((stringStartsWith? t "~") (tildeOk v (stringTrim (optionOr (stringSlice t 1 (stringLength t)) ""))))
      ((stringStartsWith? t ">=") (cmpOp v (stringTrim (optionOr (stringSlice t 2 (stringLength t)) "")) ">="))
      ((stringStartsWith? t "<=") (cmpOp v (stringTrim (optionOr (stringSlice t 2 (stringLength t)) "")) "<="))
      ((stringStartsWith? t ">") (cmpOp v (stringTrim (optionOr (stringSlice t 1 (stringLength t)) "")) ">"))
      ((stringStartsWith? t "<") (cmpOp v (stringTrim (optionOr (stringSlice t 1 (stringLength t)) "")) "<"))
      ((stringStartsWith? t "=") (cmpOp v (stringTrim (optionOr (stringSlice t 1 (stringLength t)) "")) "="))
      (else (cmpOp v t "="))))
