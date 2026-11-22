(module asl-vault/codec
  :x [andThen mapResult formItems fieldMap checkShape fs fi fl fstrs fpairs strList pairList validId? uniqueStrings? dedupStrings firstFailure check intSx strSx atomSx]
  :i [(asl-store/wire :a w)])

fn andThen r: (Result A String) f: (fn [A] -> (Result B String)) -> (Result B String)
  (match r
    ((err e) (err e))
    ((ok v) (f v)))

fn mapResult f: (fn [A] -> (Result B String)) xs: (List A) -> (Result (List B) String)
  (match (listHead xs)
    ((none) (ok (list)))
    ((some h)
      (andThen (f h)
        (fn [(b B)] -> (Result (List B) String)
          (andThen (mapResult f (optionOr (listTail xs) (list)))
            (fn [(rest (List B))] -> (Result (List B) String) (ok (cons b rest))))))))

; (:m :ref VS-VAULT :do "the items of one top-level form whose head atom is head; anything else is a parse error, so a row of another kind is never read as this one")
fn formItems head: String x: w/Sx -> (Result (List w/Sx) String)
  (match x
    ((w/sxList items)
      (if (= (w/leafText (w/headOr items)) head) (ok (w/tailOr items)) (err (str "not a " head " row"))))
    (_ (err (str "not a " head " row"))))

fn fieldAcc items: (List w/Sx) m: (Map String w/Sx) -> (Map String w/Sx)
  (if (< (listLength items) 2)
    m
    (fieldAcc (w/tailOr (w/tailOr items)) (mapSet m (w/leafText (w/headOr items)) (w/headOr (w/tailOr items)))))

; (:m :ref VS-VAULT :do "the keyword and value pairs of a row as a map; a row is :head :key value :key value ...")
fn fieldMap items: (List w/Sx) -> (Map String w/Sx)
  (fieldAcc items (mapEmpty))

fn kindOk? kind: String x: w/Sx -> Bool
  (match x
    ((w/sxStr _) (= kind "s"))
    ((w/sxAtom a) (and (= kind "i") (some? (stringToInt64 a))))
    ((w/sxList xs) (or (= kind "l") (and (= kind "S") (listAll? (fn [(y w/Sx)] -> Bool (match y ((w/sxStr _) true) (_ false))) xs)))))

fn shapeOne m: (Map String w/Sx) spec: (Pair String String) -> (Option String)
  (match (mapGet m (pairFirst spec))
    ((none) (some (str "missing " (pairFirst spec))))
    ((some x) (if (kindOk? (pairSecond spec) x) (none) (some (str (pairFirst spec) " has the wrong shape")))))

; (:m :ref VS-VAULT :do "every spec key must be present with its kind: s string, i integer, l list, S list of strings; the first miss is the error, so the total accessors below are only called on checked rows")
fn checkShape m: (Map String w/Sx) specs: (List (Pair String String)) -> (Result Bool String)
  (match (optionOr (listFind (fn [(o (Option String))] -> Bool (some? o)) (map (fn [(s (Pair String String))] -> (Option String) (shapeOne m s)) specs)) (none))
    ((some why) (err why))
    ((none) (ok true)))

fn fs m: (Map String w/Sx) k: String -> String
  (w/leafText (optionOr (mapGet m k) (w/sxStr "")))

fn fi m: (Map String w/Sx) k: String -> Int64
  (optionOr (stringToInt64 (fs m k)) 0)

fn fl m: (Map String w/Sx) k: String -> (List w/Sx)
  (match (mapGet m k)
    ((some (w/sxList xs)) xs)
    (_ (list)))

fn fstrs m: (Map String w/Sx) k: String -> (List String)
  (map w/leafText (fl m k))

fn pairOf x: w/Sx -> (Pair String String)
  (match x
    ((w/sxList xs) (pair (w/leafText (w/headOr xs)) (w/leafText (w/headOr (w/tailOr xs)))))
    (_ (pair "" "")))

fn fpairs m: (Map String w/Sx) k: String -> (List (Pair String String))
  (map pairOf (fl m k))

fn strSx s: String -> w/Sx
  (w/sxStr s)

fn atomSx s: String -> w/Sx
  (w/sxAtom s)

fn intSx n: Int64 -> w/Sx
  (w/sxAtom (stringFromInt64 n))

fn strList xs: (List String) -> w/Sx
  (w/sxList (map (fn [(s String)] -> w/Sx (w/sxStr s)) xs))

fn pairList ps: (List (Pair String String)) -> w/Sx
  (w/sxList (map (fn [(p (Pair String String))] -> w/Sx (w/sxList (list (w/sxStr (pairFirst p)) (w/sxStr (pairSecond p))))) ps))

fn idByte? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (or (= b 45) (= b 95)))))

fn idBytes? bs: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (and (idByte? (bytesGet bs i)) (idBytes? bs (+ i 1) n)))

; (:m :ref VS-VAULT :do "an entry, resolution or kind id is 1 to 120 bytes of [A-Za-z0-9_-]; it is one store key segment, so it can never carry a / or a leading dot into a key")
fn validId? s: String -> Bool
  (let [(n (stringLength s))]
    (and (>= n 1) (and (<= n 120) (idBytes? (stringToBytes s) 0 n))))

fn uniqueStrings? xs: (List String) -> Bool
  (= (listLength xs) (mapSize (fold (fn [(m (Map String Bool)) (x String)] -> (Map String Bool) (mapSet m x true)) (mapEmpty) xs)))

fn check ok: Bool why: String -> (Option String)
  (if ok (none) (some why))

fn firstFailure checks: (List (Option String)) -> (Option String)
  (optionOr (listFind (fn [(c (Option String))] -> Bool (some? c)) checks) (none))

fn dedupAcc xs: (List String) seen: (Map String Bool) acc: (List String) -> (List String)
  (match (listHead xs)
    ((none) (listReverse acc))
    ((some x)
      (if (or (stringEmpty? (stringTrim x)) (mapHas? seen x))
        (dedupAcc (optionOr (listTail xs) (list)) seen acc)
        (dedupAcc (optionOr (listTail xs) (list)) (mapSet seen x true) (cons x acc)))))

; (:m :ref VS-VAULT :do "the strings in first-seen order, blanks dropped, each once")
fn dedupStrings xs: (List String) -> (List String)
  (dedupAcc xs (mapEmpty) (list))
