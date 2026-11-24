(module asl-text/percent
  :x [percentEncode percentDecode formEncode]
  :i [(asl-syntax/core/bytesText :a bt)])

fn unreservedIndex b: Int64 -> Int64
  (cond
    ((and (>= b 48) (<= b 57)) (- b 48))
    ((and (>= b 65) (<= b 90)) (+ 10 (- b 65)))
    ((and (>= b 97) (<= b 122)) (+ 36 (- b 97)))
    ((= b 45) 62)
    ((= b 46) 63)
    ((= b 95) 64)
    (else 65))

fn unreservedChar b: Int64 -> String
  (let [(i (unreservedIndex b))]
    (optionOr (stringSlice "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._~" i (+ i 1)) ""))

fn isUnreserved b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
      (and (>= b 97) (<= b 122))
      (and (>= b 48) (<= b 57))
      (= b 45)
      (= b 46)
      (= b 95)
      (= b 126))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789ABCDEF" n (+ n 1)) "")

fn percentByte b: Int64 -> String
  (str "%" (hexDigit (/ b 16)) (hexDigit (mod b 16)))

fn encodeLoop bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))]
      (if (isUnreserved b)
        (encodeLoop bs n (+ i 1) (cons (unreservedChar b) acc))
        (encodeLoop bs n (+ i 1) (cons (percentByte b) acc)))))

fn percentEncode s: String -> String
  (let [(bs (stringToBytes s))]
    (encodeLoop bs (bytesLength bs) 0 (list)))

fn hexVal c: String -> (Option Int64)
  (let [(n (charCode c))]
    (cond
      ((and (>= n 48) (<= n 57)) (some (- n 48)))
      ((and (>= n 65) (<= n 70)) (some (- n 55)))
      ((and (>= n 97) (<= n 102)) (some (- n 87)))
      (else (none))))

fn hexPair h1: String h2: String -> (Result Int64 String)
  (match (hexVal h1)
    ((none) (err (str "bad percent escape: %" h1 h2)))
    ((some v1) (hexPair2 h1 h2 v1)))

fn hexPair2 h1: String h2: String v1: Int64 -> (Result Int64 String)
  (match (hexVal h2)
    ((none) (err (str "bad percent escape: %" h1 h2)))
    ((some v2) (ok (+ (* v1 16) v2))))

fn appendBytes bs: Bytes n: Int64 i: Int64 acc: (List Int64) -> (List Int64)
  (if (>= i n)
    acc
    (appendBytes bs n (+ i 1) (cons (bytesGet bs i) acc)))

fn decodeLoop cs: (List String) acc: (List Int64) -> (Result (List Int64) String)
  (match (listHead cs)
    ((none) (ok (listReverse acc)))
    ((some c) (decodeStep cs c acc)))

fn decodeStep cs: (List String) c: String acc: (List Int64) -> (Result (List Int64) String)
  (if (= c "%")
    (decodeEscape cs acc)
    (let [(bs (stringToBytes c))]
      (decodeLoop (listDrop cs 1) (appendBytes bs (bytesLength bs) 0 acc))))

fn decodeEscape cs: (List String) acc: (List Int64) -> (Result (List Int64) String)
  (match (listGet cs 1)
    ((none) (err "truncated percent escape"))
    ((some h1) (decodeEscape2 cs h1 acc)))

fn decodeEscape2 cs: (List String) h1: String acc: (List Int64) -> (Result (List Int64) String)
  (match (listGet cs 2)
    ((none) (err "truncated percent escape"))
    ((some h2) (decodeEscape3 cs h1 h2 acc)))

fn decodeEscape3 cs: (List String) h1: String h2: String acc: (List Int64) -> (Result (List Int64) String)
  (match (hexPair h1 h2)
    ((err e) (err e))
    ((ok b) (decodeLoop (listDrop cs 3) (cons b acc))))

fn bytesFromList xs: (List Int64) -> Bytes
  (let [(n (listLength xs))
        (bs (bytesAlloc n))]
    (do (fold (fn [i b] (do (bytesSet bs i b) (+ i 1))) 0 xs)
        bs))

fn contByte? b: Int64 -> Bool
  (and (>= b 128) (<= b 191))

fn utf8Loop bs: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n)
    true
    (utf8Step bs n i (bytesGet bs i)))

fn utf8Step bs: Bytes n: Int64 i: Int64 b: Int64 -> Bool
  (cond
    ((< b 128) (utf8Loop bs n (+ i 1)))
    ((and (>= b 194) (<= b 223)) (utf8Two bs n i))
    ((= b 224) (utf8Three bs n i 160 191))
    ((= b 237) (utf8Three bs n i 128 159))
    ((and (>= b 225) (<= b 239)) (utf8Three bs n i 128 191))
    ((= b 240) (utf8Four bs n i 144 191))
    ((and (>= b 241) (<= b 243)) (utf8Four bs n i 128 191))
    ((= b 244) (utf8Four bs n i 128 143))
    (else false))

fn utf8Two bs: Bytes n: Int64 i: Int64 -> Bool
  (if (and (< (+ i 1) n) (contByte? (bytesGet bs (+ i 1))))
    (utf8Loop bs n (+ i 2))
    false)

fn utf8Three bs: Bytes n: Int64 i: Int64 lo: Int64 hi: Int64 -> Bool
  (if (and (< (+ i 2) n)
           (and (and (>= (bytesGet bs (+ i 1)) lo) (<= (bytesGet bs (+ i 1)) hi))
                (contByte? (bytesGet bs (+ i 2)))))
    (utf8Loop bs n (+ i 3))
    false)

fn utf8Four bs: Bytes n: Int64 i: Int64 lo: Int64 hi: Int64 -> Bool
  (if (and (< (+ i 3) n)
           (and (and (>= (bytesGet bs (+ i 1)) lo) (<= (bytesGet bs (+ i 1)) hi))
                (and (contByte? (bytesGet bs (+ i 2))) (contByte? (bytesGet bs (+ i 3))))))
    (utf8Loop bs n (+ i 4))
    false)

fn decodeUtf8 xs: (List Int64) -> (Result String String)
  (let [(bs (bytesFromList xs))]
    (if (utf8Loop bs (bytesLength bs) 0)
      (ok (bt/bytesToString bs))
      (err "invalid UTF-8")))

fn percentDecode s: String -> (Result String String)
  (match (decodeLoop (stringChars s) (list))
    ((err e) (err e))
    ((ok xs) (decodeUtf8 xs)))

fn formPair p: (Pair String String) -> String
  (str (percentEncode (pairFirst p)) "=" (percentEncode (pairSecond p)))

fn formEncode pairs: (List (Pair String String)) -> String
  (stringJoin (map (fn [p] (formPair p)) pairs) "&")
