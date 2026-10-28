(module aslGateway/secrets
  :x [SecretStore secretsDefaultPath secretsParse secretsLoad! secretsGet secretsIds secretsEnvFor secretsRedact secretsEqual? secretsMissingReceipt octalOf secretEnvName]
  :i [])

; (:m :ref GW-SECRETS-FILE-20261027 :do "one local file per machine holds rows (:secret :id ID :value V), one per line; the loader refuses a symlink or a file readable by group or other, errors name ids and paths and never a value, and a child CLI gets exactly the env it lists, built from an empty base")

(schema SecretStore
  (:f path String)
  (:f ids (List String))
  (:f values (Map String String)))

fn secretsDefaultPath -> String
  (str (optionOr (envGet "HOME") "") "/.asl/secrets.asn")

fn secretEnvName id: String -> String
  (str "ASLSECRET_" id)

fn octalOf n: Int64 -> String
  (if (< n 8) (stringFromInt64 n) (str (octalOf (/ n 8)) (stringFromInt64 (mod n 8))))

fn quotedFrom cs: (List String) i: Int64 acc: (List String) -> (Option (Pair String Int64))
  (match (listGet cs i)
    ((none) (none))
    ((some c)
      (cond
        ((= c "\"") (some (pair (stringJoin (listReverse acc) "") (+ i 1))))
        ((= c "\\")
          (match (listGet cs (+ i 1))
            ((none) (none))
            ((some e) (quotedFrom cs (+ i 2) (cons (cond ((= e "n") "\n") ((= e "t") "\t") (else e)) acc)))))
        (else (quotedFrom cs (+ i 1) (cons c acc))))))

fn parseRow line: String -> (Option (Pair String String))
  (let [(t (stringTrim line))
        (pre "(:secret :id ")
        (mid " :value \"")]
    (if (not (and (stringStartsWith? t pre) (stringEndsWith? t "\")"))) (none)
      (let [(rest (optionOr (stringSlice t (stringLength pre) (stringLength t)) ""))]
        (match (stringIndexOf rest mid)
          ((none) (none))
          ((some at)
            (let [(id (optionOr (stringSlice rest 0 at) ""))
                  (tail (optionOr (stringSlice rest (+ at (stringLength mid)) (stringLength rest)) ""))
                  (cs (stringChars tail))]
              (if (or (stringEmpty? id) (stringContains? id " ")) (none)
                (match (quotedFrom cs 0 (list))
                  ((none) (none))
                  ((some r) (if (= (pairSecond r) (- (listLength cs) 1)) (some (pair id (pairFirst r))) (none)))))))))))

fn rowIssue idx: Int64 line: String -> (Option String)
  (let [(t (stringTrim line))]
    (if (or (stringEmpty? t) (stringStartsWith? t ";")) (none)
      (match (parseRow t)
        ((some _) (none))
        ((none) (some (str "(:err :code ERR_SECRET_ROW :line " (stringFromInt64 (+ idx 1)) ")"))))))

fn secretsParse path: String text: String -> (Result SecretStore String)
  (let [(lines (stringSplit text "\n"))
        (bad (listFind (fn [(o (Option String))] -> Bool (some? o)) (map (fn [(p (Pair Int64 String))] -> (Option String) (rowIssue (pairFirst p) (pairSecond p))) (enumerate lines))))]
    (match bad
      ((some issue) (err (optionOr issue "")))
      ((none)
        (let [(rows (listFlatMap (fn [(l String)] -> (List (Pair String String)) (match (parseRow l) ((some r) (list r)) ((none) (list)))) lines))
              (ids (map pairFirst rows))
              (dup (listFind (fn [(i String)] -> Bool (> (listCount (fn [(j String)] -> Bool (= i j)) ids) 1)) ids))]
          (match dup
            ((some d) (err (str "(:err :code ERR_SECRET_DUPLICATE :id " d ")")))
            ((none) (ok (SecretStore :path path :ids ids :values (mapFromPairs rows)))))))))

fn sameFile? a: LinkStat after: (Result LinkStat String) -> Bool
  (match after
    ((err _) false)
    ((ok b) (and (not b.isSymlink) (and (= a.size b.size) (and (= a.mtimeNs b.mtimeNs) (= a.mode b.mode))))))

fn ! secretsLoad! path: String -> (Result SecretStore String)
  (match (fileLstat path)
    ((err _) (err (str "(:err :code ERR_SECRETS_FILE :path \"" path "\" :why missing)")))
    ((ok st)
      (cond
        (st.isSymlink (err (str "(:err :code ERR_SECRETS_SYMLINK :path \"" path "\")")))
        ((not (= (& st.mode 63) 0)) (err (str "(:err :code ERR_SECRETS_PERMS :path \"" path "\" :mode 0" (octalOf (& st.mode 511)) " :want 0600)")))
        (else
          (match (fileReadString path)
            ((err _) (err (str "(:err :code ERR_SECRETS_FILE :path \"" path "\" :why unreadable)")))
            ((ok text) (if (sameFile? st (fileLstat path)) (secretsParse path text) (err (str "(:err :code ERR_SECRETS_CHANGED :path \"" path "\" :why changedWhileReading)")))))))))

fn secretsMissingReceipt id: String -> String
  (str "(:err :code ERR_SECRET_MISSING :id " id ")")

fn secretsGet store: SecretStore id: String -> (Result String String)
  (match (mapGet store.values id)
    ((some v) (ok v))
    ((none) (err (secretsMissingReceipt id))))

fn secretsIds store: SecretStore -> (List String)
  store.ids

fn secretsEnvFor store: SecretStore base: (Map String String) rows: (List (Pair String String)) -> (Result (Map String String) String)
  (fold (fn [(acc (Result (Map String String) String)) (r (Pair String String))] -> (Result (Map String String) String)
          (match acc
            ((err e) (err e))
            ((ok m) (match (secretsGet store (pairSecond r))
                      ((err e) (err e))
                      ((ok v) (ok (mapSet m (pairFirst r) v)))))))
        (ok base)
        rows)

fn jsonEscaped v: String -> String
  (stringReplace (stringReplace (stringReplace v "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

; (:m :ref AUDIT11-A4 :do "a secret is also hidden in the forms an echoing service or a JSON log would write it: percent-encoded in upper and lower hex, and \\uXXXX-escaped either for non-ASCII only (ensure_ascii) or for every character, upper and lower hex")
fn hexDigit n: Int64 upper: Bool -> String
  (let [(digits (if upper "0123456789ABCDEF" "0123456789abcdef"))]
    (optionOr (stringSlice digits n (+ n 1)) "0"))

fn hexPad n: Int64 width: Int64 upper: Bool -> String
  (if (<= width 0) ""
    (str (hexPad (/ n 16) (- width 1) upper) (hexDigit (mod n 16) upper)))

fn unreservedByte? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (or (= b 45) (or (= b 46) (or (= b 95) (= b 126)))))))

fn bytesOf v: String -> (List Int64)
  (let [(bs (stringToBytes v))]
    (map (fn [(i Int64)] -> Int64 (bytesGet bs i)) (range 0 (bytesLength bs))))

fn percentForm v: String upper: Bool -> String
  (stringJoin (map (fn [(b Int64)] -> String (if (unreservedByte? b) (asciiChar b) (str "%" (hexPad b 2 upper)))) (bytesOf v)) "")

fn asciiChar b: Int64 -> String
  (optionOr (stringSlice " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" (- b 32) (- b 31)) "")

fn codepointOf c: String -> Int64
  (let [(bs (bytesOf c))
        (b0 (optionOr (listGet bs 0) 0))
        (cont (fn [(i Int64)] -> Int64 (& (optionOr (listGet bs i) 0) 63)))]
    (cond
      ((< b0 128) b0)
      ((< b0 224) (+ (* (& b0 31) 64) (cont 1)))
      ((< b0 240) (+ (* (& b0 15) 4096) (+ (* (cont 1) 64) (cont 2))))
      (else (+ (* (& b0 7) 262144) (+ (* (cont 1) 4096) (+ (* (cont 2) 64) (cont 3)))))))

fn uEscape cp: Int64 upper: Bool -> String
  (if (< cp 65536)
    (str "\\u" (hexPad cp 4 upper))
    (let [(v (- cp 65536))]
      (str "\\u" (hexPad (+ 55296 (/ v 1024)) 4 upper) "\\u" (hexPad (+ 56320 (mod v 1024)) 4 upper))))

; (:m :ref GW-JSON-ESCAPE-REDACT-CHECK :do "every string encoder in reach: asl-json emitString (quote, backslash, b t n f r, other controls as lower \\u00xx, everything else raw), wire.asl emitPythonJsonString (the same plus ensure_ascii: DEL and non-ASCII as lower \\uXXXX with surrogate pairs), the optional escaped slash of JavaScript and PHP encoders, upper-hex \\uXXXX of some encoders, a string encoded twice (a secret inside an embedded JSON string), wire.asnEscape and core.serString (the n r t subset of the JSON escapes), and chat.escapeAsnStr (quote and backslash escaped, n r t turned into spaces). jsonFull builds the first group from the options ascii, slash and upper hex")
fn jsonFull v: String ascii: Bool slash: Bool upper: Bool -> String
  (stringJoin (map (fn [(c String)] -> String
                     (let [(cp (codepointOf c))]
                       (cond
                         ((= cp 34) "\\\"")
                         ((= cp 92) "\\\\")
                         ((and slash (= cp 47)) "\\/")
                         ((= cp 8) "\\b")
                         ((= cp 9) "\\t")
                         ((= cp 10) "\\n")
                         ((= cp 12) "\\f")
                         ((= cp 13) "\\r")
                         ((< cp 32) (uEscape cp upper))
                         ((and ascii (>= cp 127)) (uEscape cp upper))
                         (else c))))
                   (stringChars v)) "")

fn uForm v: String all: Bool upper: Bool -> String
  (stringJoin (map (fn [(c String)] -> String (uEscape (codepointOf c) upper)) (stringChars v)) "")

fn spaceForm v: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace v "\\" "\\\\") "\"" "\\\"") "\n" " ") "\r" " ") "\t" " ")

fn redactForms v: String -> (List String)
  (listReverse (listSortBy (fn [(f String)] -> Int64 (stringLength f))
    (list v (jsonEscaped v) (percentForm v true) (percentForm v false)
          (jsonFull v false false false) (jsonFull v false true false)
          (jsonFull v true false false) (jsonFull v true true false)
          (jsonFull v true false true) (jsonFull v true true true)
          (jsonFull (jsonFull v false false false) false false false)
          (uForm v true false) (uForm v true true)
          (spaceForm v))))

; (:m :ref AUDIT11-A6 :do "equality of two secret strings without an early exit: the lengths and every byte up to the longer length are folded, so the time depends on the longer length only")
fn secretsEqual? a: String b: String -> Bool
  (let [(ba (stringToBytes a))
        (bb (stringToBytes b))
        (la (bytesLength ba))
        (lb (bytesLength bb))
        (n (max la lb))
        (at (fn [(bs Bytes) (len Int64) (i Int64)] -> Int64 (if (< i len) (bytesGet bs i) 0)))
        (diff (fold (fn [(acc Int64) (i Int64)] -> Int64 (+ acc (^ (at ba la i) (at bb lb i)))) (if (= la lb) 0 1) (range 0 n)))]
    (= diff 0))

fn secretsRedact store: SecretStore text: String -> String
  (fold (fn [(acc String) (id String)] -> String
          (let [(v (optionOr (mapGet store.values id) ""))]
            (if (stringEmpty? v) acc
              (fold (fn [(t String) (form String)] -> String (if (stringEmpty? form) t (stringReplace t form (str "<secret:" id ">"))))
                    acc (redactForms v)))))
        text
        (listReverse (listSortBy (fn [(id String)] -> Int64 (stringLength (optionOr (mapGet store.values id) ""))) store.ids)))
