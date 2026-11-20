(module aslPack/pkgIndex
  :x [Artefact Dep Version Pkg Index normVersion caretPrefixEq mapResult kvFind strField listField atomText unquote validName? validVersion? validSha? validTriple? validSpec? versionParts versionCompare versionSatisfies? findPkg findVersion highestMatching artefactFor parseIndex parseRequest]
  :i [(asl-parser/reader :a rd)])

(schema Artefact (:f triple String) (:f url String) (:f sha256 String))
(schema Dep (:f name String) (:f spec String))
(schema Version (:f v String) (:f artefacts (List Artefact)) (:f source (List Artefact)) (:f deps (List Dep)))
(schema Pkg (:f name String) (:f versions (List Version)))
(schema Index (:f pkgs (List Pkg)) (:f diags (List String)))

fn mapResult f: (fn [A] -> (Result B String)) xs: (List A) -> (Result (List B) String)
  (match (listHead xs)
    ((none) (ok (list)))
    ((some h)
     (match (f h)
       ((err e) (err e))
       ((ok y)
        (match (mapResult f (optionOr (listTail xs) (list)))
          ((err e) (err e))
          ((ok ys) (ok (cons y ys))))))))

fn unquote s: String -> String
  (if (and (>= (stringLength s) 2) (and (stringStartsWith? s "\"") (stringEndsWith? s "\"")))
    (optionOr (stringSlice s 1 (- (stringLength s) 1)) "")
    s)

fn rawAtom e: rd/SExpr -> String
  (match e
    ((rd/sexprAtom v) v)
    ((rd/sexprList _) "")
    ((rd/sexprVect _) ""))

fn atomText e: rd/SExpr -> String
  (unquote (rawAtom e))

fn kvFind items: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead items)
    ((none) (none))
    ((some h)
     (let [(t (optionOr (listTail items) (list)))]
       (if (= (rawAtom h) key) (listHead t) (kvFind t key)))))

fn strField items: (List rd/SExpr) key: String -> String
  (match (kvFind items key)
    ((some e) (atomText e))
    ((none) ""))

fn listField items: (List rd/SExpr) key: String -> (List rd/SExpr)
  (match (kvFind items key)
    ((some e) (rd/sexprToList e))
    ((none) (list)))

fn nameChar? c: String -> Bool
  (let [(n (charCode c))]
    (or (and (>= n 97) (<= n 122)) (or (and (>= n 48) (<= n 57)) (= n 45))))

fn digitChar? c: String -> Bool
  (let [(n (charCode c))]
    (and (>= n 48) (<= n 57)))

fn hexChar? c: String -> Bool
  (let [(n (charCode c))]
    (or (and (>= n 48) (<= n 57)) (and (>= n 97) (<= n 102))))

fn tripleChar? c: String -> Bool
  (let [(n (charCode c))]
    (or (nameChar? c) (or (= n 95) (= n 46))))

fn validName? s: String -> Bool
  (and (and (not (stringEmpty? s)) (<= (stringLength s) 64))
       (and (listAll? nameChar? (stringChars s)) (not (stringStartsWith? s "-"))))

fn validVersionPart? s: String -> Bool
  (and (and (not (stringEmpty? s)) (<= (stringLength s) 9)) (listAll? digitChar? (stringChars s)))

fn validVersion? s: String -> Bool
  (let [(parts (stringSplit s "."))]
    (and (and (>= (listLength parts) 1) (<= (listLength parts) 4)) (listAll? validVersionPart? parts)))

fn validSha? s: String -> Bool
  (and (= (stringLength s) 64) (listAll? hexChar? (stringChars s)))

fn validTriple? s: String -> Bool
  (and (and (not (stringEmpty? s)) (<= (stringLength s) 40)) (listAll? tripleChar? (stringChars s)))

fn specBody spec: String -> String
  (cond
    ((stringStartsWith? spec ">=") (optionOr (stringSlice spec 2 (stringLength spec)) ""))
    ((stringStartsWith? spec "^") (optionOr (stringSlice spec 1 (stringLength spec)) ""))
    (else spec))

fn validSpec? spec: String -> Bool
  (or (= spec "*") (validVersion? (specBody spec)))

fn versionParts v: String -> (List Int64)
  (map (fn [(p String)] -> Int64 (optionOr (stringToInt64 p) 0)) (stringSplit v "."))

fn versionCompare a: (List Int64) b: (List Int64) -> Int64
  (if (and (listEmpty? a) (listEmpty? b)) 0
    (let [(x (optionOr (listHead a) 0)) (y (optionOr (listHead b) 0))]
      (cond
        ((< x y) -1)
        ((> x y) 1)
        (else (versionCompare (optionOr (listTail a) (list)) (optionOr (listTail b) (list)))))))

fn padTo parts: (List Int64) k: Int64 -> (List Int64)
  (if (>= (listLength parts) k) parts (padTo (listAppend parts (list 0)) k))

fn firstNonZero parts: (List Int64) i: Int64 -> Int64
  (cond
    ((listEmpty? parts) 0)
    ((!= (optionOr (listHead parts) 0) 0) i)
    ((= (listLength parts) 1) i)
    (else (firstNonZero (optionOr (listTail parts) (list)) (+ i 1))))

; (:m :ref PKG-CLIENT :do "caret is semver: ^1.2 keeps the major, ^0.2.3 keeps 0.2, ^0.0.3 is exactly 0.0.3 (the first non-zero component and everything before it must match)")
fn caretPrefixEq vp: (List Int64) bp: (List Int64) -> Bool
  (let [(n (+ (firstNonZero bp 0) 1))]
    (= (listTake (padTo vp n) n) (listTake (padTo bp n) n)))

fn normVersion v: String -> String
  (let [(ps (map (fn [(p String)] -> String (stringFromInt64 (optionOr (stringToInt64 p) 0))) (stringSplit v ".")))]
    (stringJoin (padStrings ps 3) "."))

fn padStrings ps: (List String) k: Int64 -> (List String)
  (if (>= (listLength ps) k) ps (padStrings (listAppend ps (list "0")) k))

fn versionSatisfies? spec: String v: String -> Bool
  (let [(vp (versionParts v)) (bp (versionParts (specBody spec)))]
    (cond
      ((= spec "*") true)
      ((stringStartsWith? spec ">=") (>= (versionCompare vp bp) 0))
      ((stringStartsWith? spec "^") (and (>= (versionCompare vp bp) 0) (caretPrefixEq vp bp)))
      (else (= (versionCompare vp bp) 0))))

fn findPkg idx: Index name: String -> (Option Pkg)
  (listFind (fn [(p Pkg)] -> Bool (= p.name name)) idx.pkgs)

fn findVersion p: Pkg v: String -> (Option Version)
  (listFind (fn [(x Version)] -> Bool (= (versionCompare (versionParts x.v) (versionParts v)) 0)) p.versions)

fn highestMatching p: Pkg spec: String -> (Option Version)
  (fold (fn [(best (Option Version)) (x Version)] -> (Option Version)
          (if (not (versionSatisfies? spec x.v)) best
            (match best
              ((none) (some x))
              ((some b) (if (> (versionCompare (versionParts x.v) (versionParts b.v)) 0) (some x) best)))))
        (none) p.versions)

fn artefactFor v: Version triple: String -> (Option Artefact)
  (listFind (fn [(a Artefact)] -> Bool (= a.triple triple)) v.artefacts)

fn parseArtefact triple: String e: rd/SExpr -> (Result Artefact String)
  (let [(items (rd/sexprToList e))
        (t (if (stringEmpty? triple) (strField items ":triple") triple))
        (u (strField items ":url"))
        (h (strField items ":sha256"))]
    (cond
      ((not (validTriple? t)) (err (str "ERR_PKG_INDEX: bad artefact triple '" t "'")))
      ((stringEmpty? u) (err "ERR_PKG_INDEX: artefact without :url"))
      ((not (validSha? h)) (err (str "ERR_PKG_INDEX: artefact " u " has no valid lowercase hex :sha256")))
      (else (ok (Artefact :triple t :url u :sha256 h)))))

fn parseDep e: rd/SExpr -> (Result Dep String)
  (let [(items (rd/sexprToList e))
        (n (atomText (optionOr (listGet items 0) (rd/sexprAtom ""))))
        (s (atomText (optionOr (listGet items 1) (rd/sexprAtom "*"))))]
    (cond
      ((not (validName? n)) (err (str "ERR_PKG_INDEX: bad dependency name '" n "'")))
      ((not (validSpec? s)) (err (str "ERR_PKG_INDEX: bad dependency spec '" s "' for " n)))
      (else (ok (Dep :name n :spec s)))))

fn parseVersion e: rd/SExpr -> (Result Version String)
  (let [(items (rd/sexprToList e))
        (v (strField items ":v"))
        (srcItems (listField items ":source"))]
    (if (not (validVersion? v)) (err (str "ERR_PKG_INDEX: bad version '" v "'"))
      (match (mapResult (fn [(a rd/SExpr)] -> (Result Artefact String) (parseArtefact "" a)) (listField items ":artefacts"))
        ((err m) (err m))
        ((ok arts)
         (match (if (listEmpty? srcItems) (ok (list)) (resultMap (parseArtefact "source" (rd/makeList srcItems)) (fn [(a Artefact)] -> (List Artefact) (list a))))
           ((err m) (err m))
           ((ok src)
            (match (mapResult parseDep (listField items ":deps"))
              ((err m) (err m))
              ((ok deps) (ok (Version :v (normVersion v) :artefacts arts :source src :deps deps))))))))))

; (:m :ref PKG-CLIENT :do "a bad version row or package row is skipped with a diagnostic instead of failing the whole index; only a wrong top form or index version is fatal")
fn parseVersions es: (List rd/SExpr) seen: (List String) acc: (List Version) diags: (List String) -> (Pair (List Version) (List String))
  (match (listHead es)
    ((none) (pair (listReverse acc) (listReverse diags)))
    ((some e)
     (let [(rest (optionOr (listTail es) (list)))]
       (match (parseVersion e)
         ((err m) (parseVersions rest seen acc (cons m diags)))
         ((ok v)
          (if (listContains? seen v.v)
            (parseVersions rest seen acc (cons (str "ERR_PKG_INDEX: duplicate version " v.v) diags))
            (parseVersions rest (cons v.v seen) (cons v acc) diags)))))))

fn parsePkg e: rd/SExpr -> (Result (Pair Pkg (List String)) String)
  (let [(items (rd/sexprToList e))
        (n (strField items ":name"))]
    (if (not (validName? n)) (err (str "ERR_PKG_INDEX: bad package name '" n "'"))
      (let [(r (parseVersions (listField items ":versions") (list) (list) (list)))]
        (ok (pair (Pkg :name n :versions (pairFirst r)) (map (fn [(d String)] -> String (str n ": " d)) (pairSecond r)))))))

fn parsePkgs es: (List rd/SExpr) acc: (List Pkg) diags: (List String) -> (Pair (List Pkg) (List String))
  (match (listHead es)
    ((none) (pair (listReverse acc) (listReverse diags)))
    ((some e)
     (let [(rest (optionOr (listTail es) (list)))]
       (match (parsePkg e)
         ((err m) (parsePkgs rest acc (cons m diags)))
         ((ok p) (parsePkgs rest (cons (pairFirst p) acc) (listAppend (listReverse (pairSecond p)) diags)))))))

fn dupName? pkgs: (List Pkg) -> Bool
  (let [(names (map (fn [(p Pkg)] -> String p.name) pkgs))]
    (!= (listLength names) (listLength (listSort names))))

fn parseIndex text: String -> (Result Index String)
  (let [(top (rd/parseSexpr text))
        (items (rd/sexprToList top))]
    (cond
      ((not (= (rd/sexprHead top) ":index")) (err "ERR_PKG_INDEX: not an (:index ...) form"))
      ((not (= (strField items ":v") "1")) (err (str "ERR_PKG_INDEX: unsupported index version '" (strField items ":v") "'")))
      (else
       (let [(r (parsePkgs (filter (fn [(e rd/SExpr)] -> Bool (= (rd/sexprHead e) ":pkg")) items) (list) (list)))]
         (if (dupName? (pairFirst r)) (err "ERR_PKG_INDEX: duplicate package name")
           (ok (Index :pkgs (pairFirst r) :diags (pairSecond r))))))))

fn parseRequest s: String -> (Result (Pair String String) String)
  (let [(parts (stringSplit s "@"))
        (n (optionOr (listHead parts) ""))
        (v (if (= (listLength parts) 2) (optionOr (listGet parts 1) "") "*"))]
    (cond
      ((> (listLength parts) 2) (err (str "ERR_PKG_REQUEST: '" s "' has more than one @")))
      ((not (validName? n)) (err (str "ERR_PKG_NAME: '" n "' is not [a-z0-9-]")))
      ((not (validSpec? v)) (err (str "ERR_PKG_REQUEST: bad version spec '" v "'")))
      (else (ok (pair n v)))))
