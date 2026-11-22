(module asl-store/types
  :x [Key ScanRow LogRow Op Reply maxValueBytes maxScanLimit nameOk? keyOk? checkOp capLimit errReply opGet opPut opCas opDel opScan opAppend opRead opCommit opCursor rValue rAbsent rWritten rConflict rDeleted rPage rErr rAppended rRecords rCommitted rOffset]
  :i [])

; (:m :ref VS-CORE :do "collection and id are the keys of one row; the wire, the memory adapter and every effectful adapter take the same Op rows and return the same Reply rows")
(schema Key (:f collection String) (:f id String))

(schema ScanRow (:f id String) (:f rev Int64) (:f value String) (:f expiresAt Int64))

(schema LogRow (:f offset Int64) (:f value String) (:f at Int64))

(enum Op
  (:c opGet [(key Key) (now Int64)])
  (:c opPut [(key Key) (value String) (ttlMs Int64) (now Int64)])
  (:c opCas [(key Key) (expectRev Int64) (value String) (ttlMs Int64) (now Int64)])
  (:c opDel [(key Key) (expectRev Int64) (now Int64)])
  (:c opScan [(collection String) (prefix String) (after String) (limit Int64) (now Int64)])
  (:c opAppend [(stream String) (value String) (now Int64)])
  (:c opRead [(stream String) (fromOffset Int64) (limit Int64)])
  (:c opCommit [(stream String) (consumer String) (offset Int64)])
  (:c opCursor [(stream String) (consumer String)]))

(enum Reply
  (:c rValue [(rev Int64) (value String) (expiresAt Int64)])
  (:c rAbsent [])
  (:c rWritten [(rev Int64)])
  (:c rConflict [(currentRev Int64)])
  (:c rDeleted [])
  (:c rPage [(rows (List ScanRow)) (next String)])
  (:c rErr [(code String) (text String)])
  (:c rAppended [(offset Int64)])
  (:c rRecords [(rows (List LogRow)) (next Int64)])
  (:c rCommitted [(offset Int64)])
  (:c rOffset [(n Int64)]))

fn maxValueBytes -> Int64
  4194304

fn maxScanLimit -> Int64
  1000

fn errReply code: String text: String -> Reply
  (rErr code text)

fn byteNameOk? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57))
      (or (and (>= b 65) (<= b 90))
          (or (and (>= b 97) (<= b 122)) (or (= b 46) (or (= b 95) (= b 45))))))

fn bytesNameOk? bs: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true (and (byteNameOk? (bytesGet bs i)) (bytesNameOk? bs (+ i 1) n)))

; (:m :ref VS-CORE :do "a name is one segment of [A-Za-z0-9._-], 1 to 128 bytes, and never starts with a dot, so . and .. cannot climb out of a collection and .lock or .tmp files cannot be keys")
fn nameOk? s: String -> Bool
  (let [(n (stringLength s))]
    (and (>= n 1) (and (<= n 128) (and (not (stringStartsWith? s ".")) (bytesNameOk? (stringToBytes s) 0 n)))))

; (:m :ref VS-CORE :do "an id is one or more / separated names none of which ends in .row (a row file is <id>.row, so such a segment would collide with a directory), so rows can nest under a prefix")
fn keyOk? k: Key -> Bool
  (and (nameOk? k.collection) (listAll? (fn [(s String)] -> Bool (and (nameOk? s) (not (stringEndsWith? s ".row")))) (stringSplit k.id "/")))

fn capLimit l: Int64 -> Int64
  (if (or (<= l 0) (> l (maxScanLimit))) (maxScanLimit) l)

fn keyBad k: Key -> (Option Reply)
  (if (keyOk? k) (none) (some (rErr "keyInvalid" (str "key " k.collection "/" k.id))))

fn valueBad v: String -> (Option Reply)
  (if (> (stringLength v) (maxValueBytes)) (some (rErr "tooLarge" "value over 4 MiB")) (none))

fn nameBad what: String s: String -> (Option Reply)
  (if (nameOk? s) (none) (some (rErr "keyInvalid" (str what " " s))))

fn negBad what: String n: Int64 -> (Option Reply)
  (if (< n 0) (some (rErr "argInvalid" (str what " is negative"))) (none))

fn firstBad rs: (List (Option Reply)) -> (Option Reply)
  (match (listFind (fn [(r (Option Reply))] -> Bool (some? r)) rs)
    ((some r) r)
    ((none) (none)))

; (:m :ref VS-CORE :do "the checks every adapter runs before touching storage: keyInvalid, tooLarge and argInvalid are decided here once, so a mutant adapter cannot disagree about them")
fn checkOp op: Op -> (Option Reply)
  (match op
    ((opGet k _) (keyBad k))
    ((opPut k v ttl _) (firstBad (list (keyBad k) (valueBad v) (negBad "ttlMs" ttl))))
    ((opCas k e v ttl _) (firstBad (list (keyBad k) (valueBad v) (negBad "ttlMs" ttl) (negBad "expectRev" e))))
    ((opDel k e _) (firstBad (list (keyBad k) (negBad "expectRev" e))))
    ((opScan c _ _ l _) (firstBad (list (nameBad "collection" c) (negBad "limit" l))))
    ((opAppend s v _) (firstBad (list (nameBad "stream" s) (valueBad v))))
    ((opRead s f l) (firstBad (list (nameBad "stream" s) (negBad "fromOffset" f) (negBad "limit" l))))
    ((opCommit s c o) (firstBad (list (nameBad "stream" s) (nameBad "consumer" c) (negBad "offset" o))))
    ((opCursor s c) (firstBad (list (nameBad "stream" s) (nameBad "consumer" c)))))
