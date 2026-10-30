(module asl-parquet/footer
  :x [parquetColumnEncodings parquetColumnCompression parquetColumnHasDictionary parquetKvMetadata parquetColumnStatsInt64 parquetColumnStatsFloat64]
  :i [(asl-syntax/core/bytesText :a bt) (asl-parquet/reader :a rd)])

; (:m :ref V0021-PQ-STATS :do "min and max are the footer's own bytes, never a data page: a missing statistics struct is an error, not a guess")
(schema Int64Stats (:f min Int64) (:f max Int64) (:f nulls Int64))

(schema Float64Stats (:f min Float64) (:f max Float64) (:f nulls Int64))

enum ThriftValue
  (thInt number: Int64)
  (thBinary raw: Bytes)
  (thList values: (List ThriftValue))
  (thStruct fields: (List (Pair Int64 ThriftValue)))
  (thBool boolean: Bool)
  (thOther)

enum FooterRead
  (footerEnd next: Int64)
  (footerField id: Int64 ty: Int64 at: Int64)

fn readVar bs: Bytes pos: Int64 limit: Int64 acc: Int64 scale: Int64 -> (Pair Int64 Int64)
  (if (or (>= pos limit) (> scale 72057594037927936))
    (pair acc pos)
    (let [(b (bytesGet bs pos))
          (nextAcc (+ acc (* (mod b 128) scale)))
          (next (+ pos 1))]
      (if (< b 128)
        (pair nextAcc next)
        (if (= scale 72057594037927936)
          (if (>= next limit) (pair nextAcc next)
            (let [(top (bytesGet bs next))
                  (low (mod top 128))]
              (pair (if (= low 1) (+ nextAcc (- 0 9223372036854775807) -1) nextAcc) (+ next 1))))
          (readVar bs next limit nextAcc (* scale 128))))))

fn zigzagValue value: Int64 -> Int64
  (if (< value 0)
    (let [(low (+ value 9223372036854775807 1))
          (half (+ 4611686018427387904 (/ low 2)))]
      (if (= (mod low 2) 0) half (- (- 0 half) 1)))
    (if (= (mod value 2) 0) (/ value 2) (- (- 0 (/ value 2)) 1)))

fn readField bs: Bytes pos: Int64 limit: Int64 lastId: Int64 -> FooterRead
  (if (>= pos limit)
    (footerEnd pos)
    (let [(header (bytesGet bs pos))
          (ty (mod header 16))
          (delta (/ header 16))
          (next (+ pos 1))]
      (if (= ty 0)
        (footerEnd next)
        (if (> delta 0)
          (footerField (+ lastId delta) ty next)
          (let [(raw (readVar bs next limit 0 1))
                (n (pairFirst raw))]
            (footerField (zigzagValue n) ty (pairSecond raw)))))))

fn ! readValue bs: Bytes pos: Int64 limit: Int64 ty: Int64 -> (Result (Pair ThriftValue Int64) String)
  (cond
    ((or (= ty 1) (= ty 2)) (ok (pair (thBool (= ty 1)) pos)))
    ((= ty 3)
     (if (>= pos limit)
       (err "ERR_PARQUET: compact byte truncated")
       (let [(raw (bytesGet bs pos))]
         (ok (pair (thInt (if (>= raw 128) (- raw 256) raw)) (+ pos 1))))))
    ((or (= ty 4) (or (= ty 5) (= ty 6)))
     (let [(n (readVar bs pos limit 0 1))]
       (ok (pair (thInt (zigzagValue (pairFirst n))) (pairSecond n)))))
    ((= ty 7) (ok (pair (thOther) (min limit (+ pos 8)))))
    ((= ty 8)
     (let [(n (readVar bs pos limit 0 1))
           (count (pairFirst n))
           (start (pairSecond n))]
       (if (or (< count 0) (> (+ start count) limit))
         (err "ERR_PARQUET: invalid compact binary length")
         (let [(raw (bytesAlloc count))]
           (copyFooterBytes bs raw start 0 count)
           (ok (pair (thBinary raw) (+ start count)))))))
    ((or (= ty 9) (= ty 10))
     (let [(h (readListHead bs pos limit))]
       (if (or (< (pairFirst h) 0) (> (pairFirst h) 1000000))
         (err "ERR_PARQUET: invalid compact list length")
         (readList bs (pairSecond (pairSecond h)) limit (pairFirst h) (pairFirst (pairSecond h)) (list)))))
    ((= ty 11) (err "ERR_PARQUET: compact maps are unsupported in footer metadata"))
    ((= ty 12)
     (readStruct bs pos limit 0 (list)))
    (else (err "ERR_PARQUET: invalid compact type")))

fn ! copyFooterBytes source: Bytes dest: Bytes sourceAt: Int64 destAt: Int64 count: Int64 -> Unit
  (if (<= count 0) ()
    (do
      (bytesSet dest destAt (bytesGet source sourceAt))
      (copyFooterBytes source dest (+ sourceAt 1) (+ destAt 1) (- count 1))))

fn readListHead bs: Bytes pos: Int64 limit: Int64 -> (Pair Int64 (Pair Int64 Int64))
  (if (>= pos limit) (pair 0 (pair 0 0))
    (let [(head (bytesGet bs pos))
          (small (/ head 16))
          (elementTy (mod head 16))]
      (if (< small 15)
        (pair small (pair elementTy (+ pos 1)))
        (let [(count (readVar bs (+ pos 1) limit 0 1))]
          (pair (pairFirst count) (pair elementTy (pairSecond count)))))))

fn ! readList bs: Bytes pos: Int64 limit: Int64 left: Int64 ty: Int64 acc: (List ThriftValue) -> (Result (Pair ThriftValue Int64) String)
  (if (<= left 0)
    (ok (pair (thList (listReverse acc)) pos))
    (match (readValue bs pos limit ty)
      ((err e) (err e))
      ((ok entry)
       (if (<= (pairSecond entry) pos)
         (err "ERR_PARQUET: compact list did not advance")
         (readList bs (pairSecond entry) limit (- left 1) ty (cons (pairFirst entry) acc))))))

fn ! readStruct bs: Bytes pos: Int64 limit: Int64 lastId: Int64 acc: (List (Pair Int64 ThriftValue)) -> (Result (Pair ThriftValue Int64) String)
  (let [(field (readField bs pos limit lastId))]
    (match field
      ((footerEnd next) (ok (pair (thStruct (listReverse acc)) next)))
      ((footerField id ty at)
       (match (readValue bs at limit ty)
         ((err e) (err e))
         ((ok value)
          (if (<= (pairSecond value) pos)
            (err "ERR_PARQUET: compact struct did not advance")
            (readStruct bs (pairSecond value) limit id (cons (pair id (pairFirst value)) acc))))))))

fn ! footerTree path: String -> (Result (List (Pair Int64 ThriftValue)) String)
  (match (fileReadBytes path)
    ((err e) (err e))
    ((ok bs)
     (let [(size (bytesLength bs))]
       (if (< size 12)
         (err "ERR_PARQUET: file too short")
         (let [(magic (bytesAlloc 4))]
           (copyFooterBytes bs magic 0 0 4)
           (if (or (not (= (bt/bytesToString magic) "PAR1")) (not (parMagicAt? bs (- size 4))))
             (err "ERR_PARQUET: missing PAR1 magic")
             (let [(length (+ (bytesGet bs (- size 8))
                              (+ (* 256 (bytesGet bs (- size 7)))
                                 (+ (* 65536 (bytesGet bs (- size 6))) (* 16777216 (bytesGet bs (- size 5)))))))
                   (start (- size (+ 8 length)))
                   (end (- size 8))]
               (if (or (<= length 0) (< start 4))
                 (err "ERR_PARQUET: invalid footer length")
                 (match (readStruct bs start end 0 (list))
                   ((err e) (err e))
                   ((ok parsed) (ok (matchStructFields (pairFirst parsed)))))))))))))

fn parMagicAt? bs: Bytes at: Int64 -> Bool
  (and (and (= (bytesGet bs at) 80) (= (bytesGet bs (+ at 1)) 65)) (and (= (bytesGet bs (+ at 2)) 82) (= (bytesGet bs (+ at 3)) 49)))

fn matchStructFields value: ThriftValue -> (List (Pair Int64 ThriftValue))
  (match value ((thStruct fields) fields) (_ (list)))

fn fieldAt fields: (List (Pair Int64 ThriftValue)) id: Int64 -> (Option ThriftValue)
  (match (listHead fields)
    ((none) (none))
    ((some entry)
     (if (= (pairFirst entry) id) (some (pairSecond entry))
       (fieldAt (optionOr (listTail fields) (list)) id))))

fn asList value: ThriftValue -> (List ThriftValue)
  (match value ((thList xs) xs) (_ (list)))

fn asFields value: ThriftValue -> (List (Pair Int64 ThriftValue))
  (matchStructFields value)

fn asInt value: ThriftValue -> Int64
  (match value ((thInt n) n) (_ 0))

fn asText value: ThriftValue -> String
  (match value ((thBinary raw) (bt/bytesToString raw)) (_ ""))

fn asBinary value: ThriftValue -> (Option Bytes)
  (match value ((thBinary raw) (some raw)) (_ (none)))

fn getField fields: (List (Pair Int64 ThriftValue)) id: Int64 -> ThriftValue
  (optionOr (fieldAt fields id) (thOther))

fn columnIndex schema: (List ThriftValue) name: String at: Int64 -> Int64
  (match (listHead schema)
    ((none) -1)
    ((some item)
     (if (= (asText (getField (asFields item) 4)) name)
       at
       (columnIndex (optionOr (listTail schema) (list)) name (+ at 1)))))

fn findColumnChunk groups: (List ThriftValue) groupIndex: Int64 columnIndexValue: Int64 -> ThriftValue
  (match (listGet groups groupIndex)
    ((none) (thOther))
    ((some group)
     (let [(chunks (asList (getField (asFields group) 1)))]
       (optionOr (listGet chunks columnIndexValue) (thOther)))))

fn findGroup groups: (List ThriftValue) index: Int64 -> ThriftValue
  (optionOr (listGet groups index) (thOther))

fn ! footerChunk path: String columnName: String rowGroup: Int64 -> (Result (List (Pair Int64 ThriftValue)) String)
  (match (footerTree path)
    ((err e) (err e))
    ((ok root)
     (let [(schema (asList (getField root 2)))
           (groups (asList (getField root 4)))
           (col (columnIndex (optionOr (listTail schema) (list)) columnName 0))]
       (if (or (< col 0) (or (< rowGroup 0) (>= rowGroup (listLength groups))))
         (err "ERR_PARQUET: column or row group not found")
         (let [(chunk (findColumnChunk groups rowGroup col))
               (meta (getField (asFields chunk) 3))]
           (if (not (some? (fieldAt (asFields chunk) 3)))
             (err "ERR_PARQUET: missing column metadata")
             (ok (asFields meta))))))))

fn encodingName n: Int64 -> String
  (cond ((= n 0) "PLAIN") ((= n 2) "PLAIN_DICTIONARY") ((= n 3) "RLE")
        ((= n 4) "BIT_PACKED") ((= n 5) "DELTA_BINARY_PACKED")
        ((= n 6) "DELTA_LENGTH_BYTE_ARRAY") ((= n 7) "DELTA_BYTE_ARRAY")
        ((= n 8) "RLE_DICTIONARY") ((= n 9) "BYTE_STREAM_SPLIT")
        (else (str "UNKNOWN_" (stringFromInt64 n))))

fn encodingsFor xs: (List ThriftValue) -> (List String)
  (map (fn [(v ThriftValue)] -> String (encodingName (asInt v))) xs)

fn ! parquetColumnEncodings path: String columnName: String rowGroup: Int64 -> (Result (List String) String)
  (match (footerChunk path columnName rowGroup)
    ((err e) (err e))
    ((ok meta) (ok (encodingsFor (asList (getField meta 2))))))

fn ! parquetColumnCompression path: String columnName: String rowGroup: Int64 -> (Result String String)
  (match (footerChunk path columnName rowGroup)
    ((err e) (err e))
    ((ok meta)
     (let [(codec (asInt (getField meta 4)))]
       (cond ((not (some? (fieldAt meta 4))) (err "ERR_PARQUET: missing codec"))
             ((not (match (getField meta 4) ((thInt _) true) (_ false))) (err "ERR_PARQUET: codec is not an integer"))
             ((= codec 0) (ok "UNCOMPRESSED"))
             ((= codec 1) (ok "SNAPPY"))
             ((= codec 6) (ok "ZSTD"))
             (else (err (str "ERR_PARQUET: unknown codec " (stringFromInt64 codec))))))))

fn ! parquetColumnHasDictionary path: String columnName: String rowGroup: Int64 -> (Result Bool String)
  (match (footerChunk path columnName rowGroup)
    ((err e) (err e))
    ((ok meta)
     (let [(encs (asList (getField meta 2)))]
       (ok (or (some? (fieldAt meta 11))
               (or (listContains encs (thInt 2))
                   (listContains encs (thInt 8))))))))

fn listContains xs: (List ThriftValue) value: ThriftValue -> Bool
  (match (listHead xs)
    ((none) false)
    ((some x)
     (or (= x value) (listContains (optionOr (listTail xs) (list)) value))))

fn ! parquetKvMetadata path: String key: String -> (Result String String)
  (match (footerTree path)
    ((err e) (err e))
    ((ok root) (findKv (asList (getField root 5)) key)))

fn findKv xs: (List ThriftValue) key: String -> (Result String String)
  (match (listHead xs)
    ((none) (err (str "ERR_PARQUET: key-value metadata not found: " key)))
    ((some item)
     (let [(fields (asFields item))
           (k (asText (getField fields 1)))]
       (if (= k key)
         (ok (asText (getField fields 2)))
         (findKv (optionOr (listTail xs) (list)) key)))))

fn statBinary stats: (List (Pair Int64 ThriftValue)) preferred: Int64 legacy: Int64 -> (Option Bytes)
  (match (asBinary (getField stats preferred))
    ((some raw) (some raw))
    ((none) (asBinary (getField stats legacy))))

fn ! footerStats path: String columnName: String rowGroup: Int64 physical: Int64 -> (Result (Pair (Pair Bytes Bytes) Int64) String)
  (match (footerChunk path columnName rowGroup)
    ((err e) (err e))
    ((ok meta)
     (let [(stats (asFields (getField meta 12)))
           (low (statBinary stats 6 2))
           (high (statBinary stats 5 1))]
       (cond
         ((!= (asInt (getField meta 1)) physical) (err (str "ERR_PARQUET: column " columnName " is not the requested physical type")))
         ((not (some? (fieldAt meta 12))) (err (str "ERR_PARQUET: no statistics for column " columnName)))
         ((or (none? low) (none? high)) (err (str "ERR_PARQUET: no min or max statistics for column " columnName)))
         ((or (!= (bytesLength (optionOr low (bytesAlloc 0))) 8) (!= (bytesLength (optionOr high (bytesAlloc 0))) 8)) (err (str "ERR_PARQUET: statistics of column " columnName " are not 8 bytes")))
         (else (ok (pair (pair (optionOr low (bytesAlloc 0)) (optionOr high (bytesAlloc 0)))
                         (if (some? (fieldAt stats 3)) (asInt (getField stats 3)) -1))))))))

fn ! parquetColumnStatsInt64 path: String columnName: String rowGroup: Int64 -> (Result Int64Stats String)
  (match (footerStats path columnName rowGroup 2)
    ((err e) (err e))
    ((ok found)
     (ok (Int64Stats :min (rd/pqLoad64 (pairFirst (pairFirst found)) 0) :max (rd/pqLoad64 (pairSecond (pairFirst found)) 0) :nulls (pairSecond found)))))

fn ! parquetColumnStatsFloat64 path: String columnName: String rowGroup: Int64 -> (Result Float64Stats String)
  (match (footerStats path columnName rowGroup 5)
    ((err e) (err e))
    ((ok found)
     (ok (Float64Stats :min (bytesGetFloat64 (pairFirst (pairFirst found)) 0) :max (bytesGetFloat64 (pairSecond (pairFirst found)) 0) :nulls (pairSecond found)))))
