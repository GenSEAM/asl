(module asl-store/wire
  :x [Sx ReadAt sxAtom sxStr sxList sxRead sxShow sxMatch opParse replyShow leafText headOr tailOr]
  :i [(asl-store/types :a ty)])

; (:m :ref VS-CORE :do "the single-line wire form: parenthesised atoms and double-quoted strings with \\ \" \n \t \r escapes, ; comments to end of line; Op rows are positional forms and Reply rows print in the same shape")
(enum Sx (:c sxAtom [(text String)]) (:c sxStr [(text String)]) (:c sxList [(items (List Sx))]))

(schema ReadAt (:f next Int64) (:f sx Sx))

fn slice s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn spaceByte? b: Int64 -> Bool
  (or (= b 32) (or (= b 9) (or (= b 10) (= b 13))))

fn delimiter? b: Int64 -> Bool
  (or (spaceByte? b) (or (= b 40) (or (= b 41) (= b 34))))

fn lineEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 10)) i (lineEnd bs (+ i 1) n))

fn skipWs bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    i
    (let [(b (bytesGet bs i))]
      (cond
        ((spaceByte? b) (skipWs bs (+ i 1) n))
        ((= b 59) (skipWs bs (lineEnd bs i n) n))
        (else i))))

fn atomEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (delimiter? (bytesGet bs i))) i (atomEnd bs (+ i 1) n))

fn unescapeByte b: Int64 -> (Option String)
  (cond
    ((= b 110) (some "\n"))
    ((= b 116) (some "\t"))
    ((= b 114) (some "\r"))
    ((= b 34) (some "\""))
    ((= b 92) (some "\\"))
    (else (none)))

fn readStr s: String bs: Bytes i: Int64 n: Int64 start: Int64 acc: (List String) -> (Result ReadAt String)
  (cond
    ((>= i n) (err "unterminated string"))
    ((= (bytesGet bs i) 34) (ok (ReadAt :next (+ i 1) :sx (sxStr (stringJoin (listReverse (cons (slice s start i) acc)) "")))))
    ((= (bytesGet bs i) 92)
      (if (>= (+ i 1) n)
        (err "dangling escape")
        (match (unescapeByte (bytesGet bs (+ i 1)))
          ((some ch) (readStr s bs (+ i 2) n (+ i 2) (cons ch (cons (slice s start i) acc))))
          ((none) (err (str "bad escape at " (stringFromInt64 i)))))))
    (else (readStr s bs (+ i 1) n start acc)))

fn readForm s: String bs: Bytes i: Int64 n: Int64 -> (Result ReadAt String)
  (if (>= i n)
    (err "unexpected end")
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 40) (readList s bs (+ i 1) n (list)))
        ((= b 41) (err (str "unexpected ) at " (stringFromInt64 i))))
        ((= b 34) (readStr s bs (+ i 1) n (+ i 1) (list)))
        (else (let [(e (atomEnd bs i n))] (ok (ReadAt :next e :sx (sxAtom (slice s i e)))))))))

fn readList s: String bs: Bytes i: Int64 n: Int64 acc: (List Sx) -> (Result ReadAt String)
  (let [(j (skipWs bs i n))]
    (cond
      ((>= j n) (err "unterminated list"))
      ((= (bytesGet bs j) 41) (ok (ReadAt :next (+ j 1) :sx (sxList (listReverse acc)))))
      (else (match (readForm s bs j n)
              ((err e) (err e))
              ((ok r) (readList s bs r.next n (cons r.sx acc)))))))

fn readAll s: String bs: Bytes i: Int64 n: Int64 acc: (List Sx) -> (Result (List Sx) String)
  (let [(j (skipWs bs i n))]
    (if (>= j n)
      (ok (listReverse acc))
      (match (readForm s bs j n)
        ((err e) (err e))
        ((ok r) (readAll s bs r.next n (cons r.sx acc))))))

; (:m :ref VS-CORE :do "every top-level form of src in order, or the first read error")
fn sxRead src: String -> (Result (List Sx) String)
  (readAll src (stringToBytes src) 0 (stringLength src) (list))

fn escapeStr s: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\t" "\\t") "\r" "\\r")

fn sxShow x: Sx -> String
  (match x
    ((sxAtom t) t)
    ((sxStr t) (str "\"" (escapeStr t) "\""))
    ((sxList items) (str "(" (stringJoin (map sxShow items) " ") ")")))

fn leafText x: Sx -> String
  (match x
    ((sxAtom t) t)
    ((sxStr t) t)
    ((sxList _) "\x00"))

fn headOr xs: (List Sx) -> Sx
  (optionOr (listHead xs) (sxList (list)))

fn tailOr xs: (List Sx) -> (List Sx)
  (optionOr (listTail xs) (list))

fn matchAll es: (List Sx) as: (List Sx) -> Bool
  (cond
    ((listEmpty? es) (listEmpty? as))
    ((listEmpty? as) false)
    (else (and (sxMatch (headOr es) (headOr as)) (matchAll (tailOr es) (tailOr as)))))

; (:m :ref VS-CORE :do "an expected leaf _ matches anything, a leaf matches a leaf with the same text whether atom or string, lists match element by element at equal length")
fn sxMatch expect: Sx actual: Sx -> Bool
  (match expect
    ((sxList es) (match actual ((sxList as) (matchAll es as)) (_ false)))
    (_ (or (= (leafText expect) "_") (= (leafText expect) (leafText actual)))))

fn repeatText unit: String count: Int64 -> String
  (stringRepeat unit count)

fn valueText x: Sx -> String
  (match x
    ((sxList items)
      (if (and (= (listLength items) 3) (= (leafText (headOr items)) ":rep"))
        (repeatText (leafText (headOr (tailOr items))) (optionOr (stringToInt64 (leafText (headOr (tailOr (tailOr items))))) 0))
        "\x00"))
    (_ (leafText x)))

fn textAt xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

fn intAt xs: (List String) i: Int64 -> Int64
  (optionOr (stringToInt64 (textAt xs i)) 0)

fn shapeOk? kinds: String xs: (List String) i: Int64 -> Bool
  (cond
    ((>= i (stringLength kinds)) true)
    ((= (slice kinds i (+ i 1)) "i") (and (some? (stringToInt64 (textAt xs i))) (shapeOk? kinds xs (+ i 1))))
    (else (and (not (= (textAt xs i) "\x00")) (shapeOk? kinds xs (+ i 1)))))

fn keyAt xs: (List String) -> ty/Key
  (ty/Key :collection (textAt xs 0) :id (textAt xs 1))

fn build head: String xs: (List String) -> (Result ty/Op String)
  (cond
    ((= head ":get") (ok (ty/opGet (keyAt xs) (intAt xs 2))))
    ((= head ":put") (ok (ty/opPut (keyAt xs) (textAt xs 2) (intAt xs 3) (intAt xs 4))))
    ((= head ":cas") (ok (ty/opCas (keyAt xs) (intAt xs 2) (textAt xs 3) (intAt xs 4) (intAt xs 5))))
    ((= head ":del") (ok (ty/opDel (keyAt xs) (intAt xs 2) (intAt xs 3))))
    ((= head ":scan") (ok (ty/opScan (textAt xs 0) (textAt xs 1) (textAt xs 2) (intAt xs 3) (intAt xs 4))))
    ((= head ":append") (ok (ty/opAppend (textAt xs 0) (textAt xs 1) (intAt xs 2))))
    ((= head ":read") (ok (ty/opRead (textAt xs 0) (intAt xs 1) (intAt xs 2))))
    ((= head ":commit") (ok (ty/opCommit (textAt xs 0) (textAt xs 1) (intAt xs 2))))
    ((= head ":cursor") (ok (ty/opCursor (textAt xs 0) (textAt xs 1))))
    (else (err (str "unknown op " head))))

fn shapeOf head: String -> String
  (cond
    ((= head ":get") "ssi")
    ((= head ":put") "sssii")
    ((= head ":cas") "ssisii")
    ((= head ":del") "ssii")
    ((= head ":scan") "sssii")
    ((= head ":append") "ssi")
    ((= head ":read") "sii")
    ((= head ":commit") "ssi")
    ((= head ":cursor") "ss")
    (else ""))

; (:m :ref VS-CORE :do "(:get C I now) (:put C I V ttl now) (:cas C I rev V ttl now) (:del C I rev now) (:scan C prefix after limit now) (:append S V now) (:read S from limit) (:commit S consumer offset) (:cursor S consumer); a value may be (:rep unit count) so a script can carry a 4 MiB value")
fn opParse x: Sx -> (Result ty/Op String)
  (match x
    ((sxList items)
      (let [(head (leafText (headOr items)))
            (xs (map valueText (tailOr items)))
            (kinds (shapeOf head))]
        (if (stringEmpty? kinds)
          (err (str "unknown op " head))
          (if (and (= (listLength xs) (stringLength kinds)) (shapeOk? kinds xs 0))
            (build head xs)
            (err (str "bad arguments for " head))))))
    (_ (err "op is not a form")))

fn int n: Int64 -> Sx
  (sxAtom (stringFromInt64 n))

fn scanRowSx r: ty/ScanRow -> Sx
  (sxList (list (sxAtom r.id) (int r.rev) (sxStr r.value) (int r.expiresAt)))

fn logRowSx r: ty/LogRow -> Sx
  (sxList (list (int r.offset) (sxStr r.value) (int r.at)))

fn replyShow r: ty/Reply -> Sx
  (match r
    ((ty/rValue rev v exp) (sxList (list (sxAtom ":value") (int rev) (sxStr v) (int exp))))
    ((ty/rAbsent) (sxList (list (sxAtom ":absent"))))
    ((ty/rWritten rev) (sxList (list (sxAtom ":written") (int rev))))
    ((ty/rConflict cur) (sxList (list (sxAtom ":conflict") (int cur))))
    ((ty/rDeleted) (sxList (list (sxAtom ":deleted"))))
    ((ty/rPage rows next) (sxList (list (sxAtom ":page") (sxList (map scanRowSx rows)) (sxStr next))))
    ((ty/rErr code text) (sxList (list (sxAtom ":err") (sxAtom code) (sxStr text))))
    ((ty/rAppended off) (sxList (list (sxAtom ":appended") (int off))))
    ((ty/rRecords rows next) (sxList (list (sxAtom ":records") (sxList (map logRowSx rows)) (int next))))
    ((ty/rCommitted off) (sxList (list (sxAtom ":committed") (int off))))
    ((ty/rOffset n) (sxList (list (sxAtom ":offset") (int n)))))
