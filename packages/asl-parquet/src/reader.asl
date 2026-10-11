(module asl-parquet/reader :x [parquetOpen parquetNumRowGroups parquetNumRows parquetColumnType parquetReadF64 parquetReadI64 parquetReadI8 parquetKvMetadata pqLoadUAt pqLoad64] :i [])

(schema PqCol (:f name String) (:f ptype Int64) (:f maxDef Int64) (:f int8 Bool))

(schema PqChunk (:f ptype Int64) (:f codec Int64) (:f nvals Int64) (:f dictOff Int64) (:f dataOff Int64) (:f compSize Int64) (:f encodings (List Int64)))

(schema PqFile (:f path String) (:f size Int64) (:f rows Int64) (:f cols (List PqCol)) (:f groupRows (List Int64)) (:f chunks (List PqChunk)) (:f kv (List (Pair String String))))

(schema PqPage (:f kind Int64) (:f uncomp Int64) (:f comp Int64) (:f nvals Int64) (:f encoding Int64) (:f defLen Int64) (:f repLen Int64) (:f compressed Bool))

(schema PqTr (:f data Bytes) (:f end Int64) (:f st Bytes))

fn pqPow2 n: Int64 -> Int64
  (cond
    ((= n 0) 1) ((= n 1) 2) ((= n 2) 4) ((= n 3) 8)
    ((= n 4) 16) ((= n 5) 32) ((= n 6) 64) ((= n 7) 128)
    (else
      (let [(h (pqPow2 (/ n 2)))]
        (if (= (mod n 2) 1) (* (* h h) 2) (* h h)))))

fn pqLoadUAt bs: Bytes at: Int64 n: Int64 acc: Int64 -> Int64
  (cond
    ((= n 0) acc)
    ((= n 1) (+ (* acc 256) (bytesGet bs at)))
    ((= n 2)
      (let [(b1 (bytesGet bs at)) (b0 (bytesGet bs (- at 1)))]
        (+ (* acc 65536) (+ (* b1 256) b0))))
    ((= n 3)
      (let [(b2 (bytesGet bs at)) (b1 (bytesGet bs (- at 1))) (b0 (bytesGet bs (- at 2)))]
        (+ (* acc 16777216) (+ (* b2 65536) (+ (* b1 256) b0)))))
    ((= n 4)
      (let [(b3 (bytesGet bs at)) (b2 (bytesGet bs (- at 1))) (b1 (bytesGet bs (- at 2))) (b0 (bytesGet bs (- at 3)))]
        (+ (* acc 4294967296) (+ (* b3 16777216) (+ (* b2 65536) (+ (* b1 256) b0))))))
    ((= n 5)
      (let [(b4 (bytesGet bs at)) (b3 (bytesGet bs (- at 1))) (b2 (bytesGet bs (- at 2))) (b1 (bytesGet bs (- at 3))) (b0 (bytesGet bs (- at 4)))]
        (+ (* acc 1099511627776) (+ (* b4 4294967296) (+ (* b3 16777216) (+ (* b2 65536) (+ (* b1 256) b0)))))))
    ((= n 6)
      (let [(b5 (bytesGet bs at)) (b4 (bytesGet bs (- at 1))) (b3 (bytesGet bs (- at 2))) (b2 (bytesGet bs (- at 3))) (b1 (bytesGet bs (- at 4))) (b0 (bytesGet bs (- at 5)))]
        (+ (* acc 281474976710656) (+ (* b5 1099511627776) (+ (* b4 4294967296) (+ (* b3 16777216) (+ (* b2 65536) (+ (* b1 256) b0))))))))
    ((= n 7)
      (let [(b6 (bytesGet bs at)) (b5 (bytesGet bs (- at 1))) (b4 (bytesGet bs (- at 2))) (b3 (bytesGet bs (- at 3))) (b2 (bytesGet bs (- at 4))) (b1 (bytesGet bs (- at 5))) (b0 (bytesGet bs (- at 6)))]
        (+ (* acc 72057594037927936) (+ (* b6 281474976710656) (+ (* b5 1099511627776) (+ (* b4 4294967296) (+ (* b3 16777216) (+ (* b2 65536) (+ (* b1 256) b0)))))))))
    (else (pqLoadUAt bs (- at 1) (- n 1) (+ (* acc 256) (bytesGet bs at)))))

fn pqLoad64 bs: Bytes i: Int64 -> Int64
  (let [(b0 (bytesGet bs i)) (b1 (bytesGet bs (+ i 1))) (b2 (bytesGet bs (+ i 2))) (b3 (bytesGet bs (+ i 3)))
        (b4 (bytesGet bs (+ i 4))) (b5 (bytesGet bs (+ i 5))) (b6 (bytesGet bs (+ i 6))) (top (bytesGet bs (+ i 7)))
        (low (+ b0 (+ (* b1 256) (+ (* b2 65536) (+ (* b3 16777216) (+ (* b4 4294967296) (+ (* b5 1099511627776) (* b6 281474976710656))))))))]
    (+ low (* (if (>= top 128) (- top 256) top) 72057594037927936)))

fn ! pqStoreU bs: Bytes i: Int64 u: Int64 n: Int64 -> Bool
  (if (= n 0) true
    (do (bytesSet bs i (mod u 256)) (pqStoreU bs (+ i 1) (/ u 256) (- n 1))))

fn ! pqStore64 bs: Bytes i: Int64 v: Int64 -> Bool
  (if (< v 0)
    (do (pqStoreU bs i (+ (+ v 9223372036854775807) 1) 8)
        (bytesSet bs (+ i 7) (+ (bytesGet bs (+ i 7)) 128))
        true)
    (pqStoreU bs i v 8))

fn ! pqCopy src: Bytes si: Int64 dst: Bytes di: Int64 n: Int64 -> Bool
  (if (<= n 0) true
    (do (bytesSet dst di (bytesGet src si)) (pqCopy src (+ si 1) dst (+ di 1) (- n 1))))

fn ! pqCopySlot8 src: Bytes sslot: Int64 dst: Bytes dslot: Int64 -> Bool
  (do (bytesSetFloat64 dst dslot (bytesGetFloat64 src sslot)) true)

fn ! pqFill dst: Bytes di: Int64 b: Int64 n: Int64 -> Bool
  (if (<= n 0) true
    (do (bytesSet dst di b) (pqFill dst (+ di 1) b (- n 1))))

fn ! pqCopyBack dst: Bytes n: Int64 off: Int64 l: Int64 j: Int64 -> Bool
  (if (>= j l) true
    (do (bytesSet dst (+ n j) (bytesGet dst (- (+ n j) off))) (pqCopyBack dst n off l (+ j 1))))

fn ! pqSlice src: Bytes off: Int64 n: Int64 -> Bytes
  (let [(d (bytesAlloc n))]
    (do (pqCopy src off d 0 n) d))

fn ! pqSlots n: Int64 -> Bytes
  (bytesAlloc (* n 8))

fn pqSlotGet s: Bytes i: Int64 -> Int64
  (pqLoad64 s (* i 8))

fn ! pqSlotSet s: Bytes i: Int64 v: Int64 -> Bool
  (pqStore64 s (* i 8) v)

fn pqByteStr b: Int64 -> String
  (let [(tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff")]
    (optionOr (stringSlice tbl b (+ b 1)) ""))

fn pqText bs: Bytes off: Int64 n: Int64 -> String
  (stringJoin (map (fn [(i Int64)] -> String (pqByteStr (bytesGet bs (+ off i)))) (range 0 n)) "")

fn pqZigzag value: Int64 -> Int64
  (if (< value 0)
    (let [(low (+ (+ value 9223372036854775807) 1))
          (half (+ 4611686018427387904 (/ low 2)))]
      (if (= (mod low 2) 0) half (- (- 0 half) 1)))
    (if (= (mod value 2) 0) (/ value 2) (- (- 0 (/ value 2)) 1)))

fn pqWrapAdd a: Int64 b: Int64 -> Int64
  (if (and (and (> a -4611686018427387904) (< a 4611686018427387904)) (and (> b -4611686018427387904) (< b 4611686018427387904)))
    (+ a b)
    (zstdAslAdd64 a b))

fn pqAddPow v: Int64 piece: Int64 shift: Int64 -> Int64
  (if (<= shift 49)
    (+ v (* piece (pqPow2 shift)))
    (zstdAslAdd64 v (zstdAslMul64 piece (zstdAslPow64 shift))))

fn pqToI32 x: Int64 -> Int64
  (let [(m (mod (if (< x 0) (+ (+ x 9223372036854775807) 1) x) 4294967296))]
    (if (>= m 2147483648) (- m 4294967296) m))

fn pqUlebLoop p: Bytes pos: Int64 end: Int64 maxShift: Int64 shift: Int64 v: Int64 -> (Pair Int64 Int64)
  (if (or (or (< pos 0) (>= pos end)) (> shift maxShift)) (pair 0 -1)
    (let [(b (bytesGet p pos))
          (nv (pqAddPow v (mod b 128) shift))]
      (if (< b 128) (pair nv (+ pos 1)) (pqUlebLoop p (+ pos 1) end maxShift (+ shift 7) nv))))

fn pqUleb p: Bytes pos: Int64 end: Int64 maxShift: Int64 -> (Pair Int64 Int64)
  (pqUlebLoop p pos end maxShift 0 0)

fn ! pqTrAt data: Bytes start: Int64 end: Int64 -> PqTr
  (let [(st (bytesAlloc 16))]
    (do (pqSlotSet st 0 start) (PqTr :data data :end end :st st)))

fn pqTrPos tr: PqTr -> Int64
  (pqSlotGet tr.st 0)

fn pqTrErr? tr: PqTr -> Bool
  (= (bytesGet tr.st 8) 1)

fn ! pqTrFail tr: PqTr -> Int64
  (do (bytesSet tr.st 8 1) 0)

fn ! pqTrByte tr: PqTr -> Int64
  (let [(pos (pqTrPos tr))]
    (if (>= pos tr.end) (pqTrFail tr)
      (do (pqSlotSet tr.st 0 (+ pos 1)) (bytesGet tr.data pos))))

fn ! pqTrVarintLoop tr: PqTr shift: Int64 v: Int64 -> Int64
  (if (>= shift 64) (pqTrFail tr)
    (let [(b (pqTrByte tr))
          (nv (pqAddPow v (mod b 128) shift))]
      (if (< b 128) nv (pqTrVarintLoop tr (+ shift 7) nv))))

fn ! pqTrVarint tr: PqTr -> Int64
  (pqTrVarintLoop tr 0 0)

fn ! pqTrField tr: PqTr last: Int64 -> (Option (Pair Int64 Int64))
  (let [(h (pqTrByte tr))]
    (if (or (pqTrErr? tr) (= h 0)) (none)
      (let [(delta (/ h 16))
            (id (if (> delta 0) (+ last delta) (pqZigzag (pqTrVarint tr))))]
        (if (pqTrErr? tr) (none) (some (pair id (mod h 16)))))))

fn ! pqTrInt tr: PqTr ty: Int64 -> Int64
  (cond
    ((= ty 3) (let [(b (pqTrByte tr))] (if (>= b 128) (- b 256) b)))
    ((and (>= ty 4) (<= ty 6)) (pqZigzag (pqTrVarint tr)))
    (else (pqTrFail tr)))

fn ! pqTrBool tr: PqTr ty: Int64 -> Bool
  (cond
    ((= ty 1) true)
    ((= ty 2) false)
    (else (do (pqTrFail tr) false)))

fn ! pqTrBinary tr: PqTr -> (Pair Int64 Int64)
  (let [(n (pqTrVarint tr))
        (pos (pqTrPos tr))]
    (if (or (pqTrErr? tr) (or (< n 0) (> n (- tr.end pos))))
      (do (pqTrFail tr) (pair pos 0))
      (do (pqSlotSet tr.st 0 (+ pos n)) (pair pos n))))

fn ! pqTrList tr: PqTr -> (Pair Int64 Int64)
  (let [(h (pqTrByte tr))
        (n0 (/ h 16))
        (n (if (= n0 15) (pqTrVarint tr) n0))]
    (if (or (< n 0) (> n (- tr.end (pqTrPos tr))))
      (do (pqTrFail tr) (pair 0 (mod h 16)))
      (pair n (mod h 16))))

fn ! pqTrSkipN tr: PqTr n: Int64 -> Bool
  (if (<= n 0) true (do (pqTrByte tr) (pqTrSkipN tr (- n 1))))

fn ! pqTrSkipItems tr: PqTr et: Int64 i: Int64 n: Int64 depth: Int64 -> Bool
  (if (or (>= i n) (pqTrErr? tr)) true
    (do (if (or (= et 1) (= et 2)) (do (pqTrByte tr) true) (pqTrSkip tr et (+ depth 1)))
        (pqTrSkipItems tr et (+ i 1) n depth)))

fn ! pqTrSkipPairs tr: PqTr kv: Int64 i: Int64 n: Int64 depth: Int64 -> Bool
  (if (or (>= i n) (pqTrErr? tr)) true
    (do (pqTrSkip tr (/ kv 16) (+ depth 1)) (pqTrSkip tr (mod kv 16) (+ depth 1))
        (pqTrSkipPairs tr kv (+ i 1) n depth)))

fn ! pqTrSkipStruct tr: PqTr last: Int64 depth: Int64 -> Bool
  (mt (pqTrField tr last)
    ((none) true)
    ((some f) (do (pqTrSkip tr (pairSecond f) (+ depth 1)) (pqTrSkipStruct tr (pairFirst f) depth))))

fn ! pqTrSkip tr: PqTr ty: Int64 depth: Int64 -> Bool
  (if (> depth 32) (do (pqTrFail tr) false)
    (cond
      ((or (= ty 1) (= ty 2)) true)
      ((= ty 3) (do (pqTrByte tr) true))
      ((and (>= ty 4) (<= ty 6)) (do (pqTrVarint tr) true))
      ((= ty 7) (pqTrSkipN tr 8))
      ((= ty 8) (do (pqTrBinary tr) true))
      ((or (= ty 9) (= ty 10)) (let [(l (pqTrList tr))] (pqTrSkipItems tr (pairSecond l) 0 (pairFirst l) depth)))
      ((= ty 11)
        (let [(n (pqTrVarint tr))]
          (if (= n 0) true (let [(kv (pqTrByte tr))] (pqTrSkipPairs tr kv 0 n depth)))))
      ((= ty 12) (pqTrSkipStruct tr 0 depth))
      (else (do (pqTrFail tr) false))))

fn ! pqIntType tr: PqTr s: Bytes last: Int64 bits: Int64 -> Bool
  (mt (pqTrField tr last)
    ((none) (if (= bits 8) (pqSlotSet s 3 1) true))
    ((some f)
      (if (= (pairFirst f) 1)
        (pqIntType tr s 1 (pqTrInt tr (pairSecond f)))
        (do (pqTrSkip tr (pairSecond f) 0) (pqIntType tr s (pairFirst f) bits)))))

fn ! pqLogical tr: PqTr s: Bytes last: Int64 -> Bool
  (mt (pqTrField tr last)
    ((none) true)
    ((some f)
      (do (if (and (= (pairFirst f) 10) (= (pairSecond f) 12)) (pqIntType tr s 0 0) (pqTrSkip tr (pairSecond f) 0))
          (pqLogical tr s (pairFirst f)))))

fn ! pqSchemaElem tr: PqTr s: Bytes last: Int64 name: String -> String
  (mt (pqTrField tr last)
    ((none) name)
    ((some f)
      (let [(id (pairFirst f))
            (ty (pairSecond f))]
        (cond
          ((= id 1) (do (pqSlotSet s 0 (pqTrInt tr ty)) (pqSchemaElem tr s id name)))
          ((= id 3) (do (pqSlotSet s 1 (pqTrInt tr ty)) (pqSchemaElem tr s id name)))
          ((and (= id 4) (= ty 8))
            (let [(b (pqTrBinary tr))]
              (pqSchemaElem tr s id (pqText tr.data (pairFirst b) (min (pairSecond b) 255)))))
          ((= id 5) (do (pqSlotSet s 2 (pqTrInt tr ty)) (pqSchemaElem tr s id name)))
          ((= id 6) (do (if (= (pqTrInt tr ty) 15) (pqSlotSet s 3 1) true) (pqSchemaElem tr s id name)))
          ((and (= id 10) (= ty 12)) (do (pqLogical tr s 0) (pqSchemaElem tr s id name)))
          (else (do (pqTrSkip tr ty 0) (pqSchemaElem tr s id name)))))))

fn ! pqSchema tr: PqTr i: Int64 k: Int64 acc: (List PqCol) -> (Result (List PqCol) String)
  (if (or (>= i k) (pqTrErr? tr)) (ok (listReverse acc))
    (let [(s (pqSlots 4))
          (name (pqSchemaElem tr s 0 ""))
          (children (pqSlotGet s 2))
          (rep (pqSlotGet s 1))]
      (cond
        ((= i 0) (if (!= children (- k 1)) (err "ERR_PARQUET_UNSUPPORTED: nested schema") (pqSchema tr 1 k acc)))
        ((!= children 0) (err (str "ERR_PARQUET_UNSUPPORTED: nested column " name)))
        ((= rep 2) (err (str "ERR_PARQUET_UNSUPPORTED: repeated column " name)))
        (else (pqSchema tr (+ i 1) k (cons (PqCol :name name :ptype (pqSlotGet s 0) :maxDef (if (= rep 1) 1 0) :int8 (= (pqSlotGet s 3) 1)) acc))))))

fn ! pqEncodings tr: PqTr et: Int64 i: Int64 k: Int64 acc: (List Int64) -> (List Int64)
  (if (or (>= i k) (pqTrErr? tr)) acc
    (let [(enc (pqTrInt tr et))]
      (pqEncodings tr et (+ i 1) k (if (< (listLength acc) 16) (listAppend acc (list enc)) acc))))

fn ! pqColumnMeta tr: PqTr s: Bytes last: Int64 encs: (List Int64) -> (List Int64)
  (mt (pqTrField tr last)
    ((none) encs)
    ((some f)
      (let [(id (pairFirst f))
            (ty (pairSecond f))
            (slot (cond ((= id 1) 0) ((= id 4) 1) ((= id 5) 2) ((= id 7) 3) ((= id 9) 4) ((= id 11) 5) (else -1)))]
        (cond
          ((= id 2)
            (if (!= ty 9) (do (pqTrSkip tr ty 0) (pqColumnMeta tr s id encs))
              (let [(l (pqTrList tr))]
                (pqColumnMeta tr s id (pqEncodings tr (pairSecond l) 0 (pairFirst l) encs)))))
          ((>= slot 0) (do (pqSlotSet s slot (pqTrInt tr ty)) (pqColumnMeta tr s id encs)))
          (else (do (pqTrSkip tr ty 0) (pqColumnMeta tr s id encs)))))))

fn ! pqColumnChunk tr: PqTr s: Bytes last: Int64 encs: (List Int64) -> (List Int64)
  (mt (pqTrField tr last)
    ((none) encs)
    ((some f)
      (if (and (= (pairFirst f) 3) (= (pairSecond f) 12))
        (pqColumnChunk tr s 3 (pqColumnMeta tr s 0 encs))
        (do (pqTrSkip tr (pairSecond f) 0) (pqColumnChunk tr s (pairFirst f) encs)))))

fn ! pqChunk tr: PqTr -> PqChunk
  (let [(s (pqSlots 6))
        (encs (pqColumnChunk tr s 0 (list)))]
    (PqChunk :ptype (pqSlotGet s 0) :codec (pqSlotGet s 1) :nvals (pqSlotGet s 2) :dictOff (pqSlotGet s 5) :dataOff (pqSlotGet s 4) :compSize (pqSlotGet s 3) :encodings encs))

fn ! pqChunks tr: PqTr j: Int64 c: Int64 acc: (List PqChunk) -> (List PqChunk)
  (if (or (>= j c) (pqTrErr? tr)) acc
    (pqChunks tr (+ j 1) c (cons (pqChunk tr) acc)))

fn ! pqRowGroup tr: PqTr ncols: Int64 r: Int64 last: Int64 seen: Bool rows: Int64 chunks: (List PqChunk) -> (Result (Pair Int64 (List PqChunk)) String)
  (mt (pqTrField tr last)
    ((none) (if seen (ok (pair rows chunks)) (err (str "ERR_PARQUET: row group " (stringFromInt64 r) " without columns"))))
    ((some f)
      (let [(id (pairFirst f))
            (ty (pairSecond f))]
        (cond
          ((and (= id 1) (= ty 9))
            (let [(c (pairFirst (pqTrList tr)))]
              (if (!= c ncols)
                (err (str "ERR_PARQUET: row group " (stringFromInt64 r) " has " (stringFromInt64 c) " columns, schema " (stringFromInt64 ncols)))
                (pqRowGroup tr ncols r id true rows (pqChunks tr 0 c chunks)))))
          ((= id 3) (pqRowGroup tr ncols r id seen (pqTrInt tr ty) chunks))
          (else (do (pqTrSkip tr ty 0) (pqRowGroup tr ncols r id seen rows chunks)))))))

fn ! pqRowGroups tr: PqTr ncols: Int64 r: Int64 g: Int64 rows: (List Int64) chunks: (List PqChunk) -> (Result (Pair (List Int64) (List PqChunk)) String)
  (if (or (>= r g) (pqTrErr? tr)) (ok (pair (listReverse rows) (listReverse chunks)))
    (mt (pqRowGroup tr ncols r 0 false 0 chunks)
      ((err e) (err e))
      ((ok p) (pqRowGroups tr ncols (+ r 1) g (cons (pairFirst p) rows) (pairSecond p)))))

fn ! pqKv tr: PqTr last: Int64 k: (Option String) v: (Option String) -> (Pair (Option String) (Option String))
  (mt (pqTrField tr last)
    ((none) (pair k v))
    ((some f)
      (let [(id (pairFirst f))
            (ty (pairSecond f))]
        (if (and (or (= id 1) (= id 2)) (= ty 8))
          (let [(b (pqTrBinary tr))
                (t (some (pqText tr.data (pairFirst b) (pairSecond b))))]
            (if (= id 1) (pqKv tr id t v) (pqKv tr id k t)))
          (do (pqTrSkip tr ty 0) (pqKv tr id k v))))))

fn ! pqKvs tr: PqTr i: Int64 n: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (if (or (>= i n) (pqTrErr? tr)) (listReverse acc)
    (let [(kv (pqKv tr 0 (none) (none)))]
      (pqKvs tr (+ i 1) n
        (mt (pairFirst kv)
          ((none) acc)
          ((some k) (cons (pair k (optionOr (pairSecond kv) "")) acc))))))

fn ! pqPageInner tr: PqTr s: Bytes outer: Int64 last: Int64 -> Bool
  (mt (pqTrField tr last)
    ((none) true)
    ((some f)
      (let [(id (pairFirst f))
            (ty (pairSecond f))]
        (do
          (cond
            ((= id 1) (pqSlotSet s 3 (pqTrInt tr ty)))
            ((and (or (= outer 5) (= outer 7)) (= id 2)) (pqSlotSet s 4 (pqTrInt tr ty)))
            ((and (= outer 8) (= id 4)) (pqSlotSet s 4 (pqTrInt tr ty)))
            ((and (= outer 8) (= id 5)) (pqSlotSet s 5 (pqTrInt tr ty)))
            ((and (= outer 8) (= id 6)) (pqSlotSet s 6 (pqTrInt tr ty)))
            ((and (= outer 8) (= id 7)) (pqSlotSet s 7 (if (pqTrBool tr ty) 1 0)))
            (else (pqTrSkip tr ty 0)))
          (pqPageInner tr s outer id)))))

fn ! pqPageFields tr: PqTr s: Bytes last: Int64 -> Bool
  (mt (pqTrField tr last)
    ((none) true)
    ((some f)
      (let [(id (pairFirst f))
            (ty (pairSecond f))]
        (do
          (cond
            ((= id 1) (pqSlotSet s 0 (pqTrInt tr ty)))
            ((= id 2) (pqSlotSet s 1 (pqTrInt tr ty)))
            ((= id 3) (pqSlotSet s 2 (pqTrInt tr ty)))
            ((and (or (= id 5) (or (= id 7) (= id 8))) (= ty 12)) (pqPageInner tr s id 0))
            (else (pqTrSkip tr ty 0)))
          (pqPageFields tr s id)))))

fn ! pqPageHeader tr: PqTr -> (Option PqPage)
  (let [(s (pqSlots 8))]
    (do
      (pqSlotSet s 0 -1)
      (pqSlotSet s 7 1)
      (pqPageFields tr s 0)
      (if (or (pqTrErr? tr) (or (< (pqSlotGet s 0) 0) (or (< (pqSlotGet s 1) 0) (or (< (pqSlotGet s 2) 0) (< (pqSlotGet s 3) 0)))))
        (none)
        (some (PqPage :kind (pqSlotGet s 0) :uncomp (pqSlotGet s 1) :comp (pqSlotGet s 2) :nvals (pqSlotGet s 3) :encoding (pqSlotGet s 4)
                      :defLen (pqSlotGet s 5) :repLen (pqSlotGet s 6) :compressed (!= (pqSlotGet s 7) 0))))))

fn pqColAt q: PqFile col: Int64 -> PqCol
  (mt (listGet q.cols col)
    ((some c) c)
    ((none) (trap "ERR_PARQUET" "column index outside the schema")))

fn pqChunkAt q: PqFile col: Int64 rg: Int64 -> PqChunk
  (mt (listGet q.chunks (+ (* rg (listLength q.cols)) col))
    ((some c) c)
    ((none) (trap "ERR_PARQUET" "column chunk outside the footer")))

fn pqGroupRows q: PqFile rg: Int64 -> Int64
  (optionOr (listGet q.groupRows rg) 0)

fn pqChunkStart c: PqChunk -> Int64
  (if (and (> c.dictOff 0) (< c.dictOff c.dataOff)) c.dictOff c.dataOff)

fn pqEncodingOk? enc: Int64 -> Bool
  (or (or (or (= enc 0) (= enc 1)) (or (= enc 2) (= enc 3))) (or (= enc 5) (or (= enc 8) (= enc 9))))

fn pqPageEncodingOk? enc: Int64 -> Bool
  (or (or (= enc 0) (= enc 2)) (or (= enc 8) (or (= enc 5) (= enc 9))))

fn ! pqScanPages q: PqFile c: PqChunk name: String rg: Int64 start: Int64 pos: Int64 -> (Result Bool String)
  (if (>= pos c.compSize) (ok true)
    (let [(rem (- c.compSize pos))
          (toRead (min rem 128))]
      (mt (fileReadRange q.path (+ start pos) toRead)
        ((err _) (err "ERR_IO: cannot read column chunk"))
        ((ok hb)
          (if (!= (bytesLength hb) toRead) (err "ERR_IO: cannot read column chunk")
            (let [(tr (pqTrAt hb 0 toRead))]
              (mt (pqPageHeader tr)
                ((none) (err (str "ERR_PARQUET: malformed page header in column " name " row group " (stringFromInt64 rg))))
                ((some ph)
                  (let [(hl (pqTrPos tr))]
                    (cond
                      ((> ph.comp (- rem hl)) (err (str "ERR_PARQUET: page beyond the column chunk in column " name " row group " (stringFromInt64 rg))))
                      ((and (or (= ph.kind 0) (= ph.kind 3)) (not (pqPageEncodingOk? ph.encoding)))
                        (err (str "ERR_PARQUET_UNSUPPORTED: column " name " row group " (stringFromInt64 rg) " encoding " (stringFromInt64 ph.encoding))))
                      (else (pqScanPages q c name rg start (+ pos (+ hl ph.comp))))))))))))))

fn pqBadEncoding encs: (List Int64) -> (Option Int64)
  (listHead (filter (fn [(e Int64)] -> Bool (not (pqEncodingOk? e))) encs))

fn ! pqValidate q: PqFile i: Int64 n: Int64 -> (Result Bool String)
  (if (>= i n) (ok true)
    (let [(ncols (listLength q.cols))
          (col (mod i ncols))
          (rg (/ i ncols))
          (c (pqChunkAt q col rg))
          (cd (pqColAt q col))
          (start (pqChunkStart c))]
      (cond
        ((or (< start 4) (or (<= c.compSize 0) (> (+ start c.compSize) (- q.size 8)))) (err "ERR_PARQUET: column chunk outside the file"))
        ((!= c.ptype cd.ptype) (err "ERR_PARQUET: chunk type differs from schema"))
        ((= c.codec 1) (err "snappy unsupported"))
        ((and (!= c.codec 0) (!= c.codec 6))
          (err (str "ERR_PARQUET_UNSUPPORTED: column " cd.name " row group " (stringFromInt64 rg) " codec " (stringFromInt64 c.codec))))
        (else
          (mt (pqBadEncoding c.encodings)
            ((some e) (err (str "ERR_PARQUET_UNSUPPORTED: column " cd.name " row group " (stringFromInt64 rg) " encoding " (stringFromInt64 e))))
            ((none)
              (mt (pqScanPages q c cd.name rg start 0)
                ((err e) (err e))
                ((ok _) (pqValidate q (+ i 1) n)))))))))

fn ! pqFooterDone tr: PqTr q: PqFile -> (Result PqFile String)
  (cond
    ((pqTrErr? tr) (err "ERR_PARQUET: malformed footer"))
    ((listEmpty? q.cols) (err "ERR_PARQUET: footer without a schema"))
    (else
      (mt (pqValidate q 0 (* (listLength q.groupRows) (listLength q.cols)))
        ((err e) (err e))
        ((ok _) (ok q)))))

fn ! pqFooter tr: PqTr q: PqFile last: Int64 -> (Result PqFile String)
  (mt (pqTrField tr last)
    ((none) (pqFooterDone tr q))
    ((some f)
      (let [(id (pairFirst f))
            (ty (pairSecond f))]
        (cond
          ((and (= id 2) (= ty 9))
            (let [(k (pairFirst (pqTrList tr)))]
              (if (or (< k 2) (> k 4096)) (err (str "ERR_PARQUET: schema with " (stringFromInt64 k) " elements"))
                (mt (pqSchema tr 0 k (list))
                  ((err e) (err e))
                  ((ok cs) (pqFooter tr (with q :cols cs) id))))))
          ((= id 3)
            (let [(rows (pqTrInt tr ty))]
              (pqFooter tr (with q :rows rows) id)))
          ((and (= id 4) (= ty 9))
            (if (listEmpty? q.cols) (err "ERR_PARQUET: row groups before schema")
              (let [(g (pairFirst (pqTrList tr)))]
                (if (> g 65536) (err (str "ERR_PARQUET: " (stringFromInt64 g) " row groups"))
                  (mt (pqRowGroups tr (listLength q.cols) 0 g (list) (list))
                    ((err e) (err e))
                    ((ok rg) (pqFooter tr (with q :groupRows (pairFirst rg) :chunks (pairSecond rg)) id)))))))
          ((and (= id 5) (= ty 9))
            (let [(n (pairFirst (pqTrList tr)))]
              (if (> n 4096) (err "ERR_PARQUET: too many metadata keys")
                (let [(kv (pqKvs tr 0 n (list)))]
                  (pqFooter tr (with q :kv kv) id)))))
          (else (do (pqTrSkip tr ty 0) (pqFooter tr q id)))))))

fn ! pqReadExact path: String off: Int64 n: Int64 -> (Option Bytes)
  (mt (fileReadRange path off n)
    ((ok b) (if (= (bytesLength b) n) (some b) (none)))
    ((err _) (none)))

fn pqMagic? b: Bytes at: Int64 -> Bool
  (and (and (= (bytesGet b at) 80) (= (bytesGet b (+ at 1)) 65)) (and (= (bytesGet b (+ at 2)) 82) (= (bytesGet b (+ at 3)) 49)))

fn ! parquetOpen path: String -> (Result PqFile String)
  (mt (fileStat path)
    ((err _) (err (str "ERR_IO: cannot open " path)))
    ((ok st)
      (let [(size st.size)
            (head (if (>= size 12) (pqReadExact path 0 4) (none)))
            (tail (if (>= size 12) (pqReadExact path (- size 8) 8) (none)))]
        (mt head
          ((none) (err (str "ERR_PARQUET: " path " is too short for a parquet file")))
          ((some hb)
            (mt tail
              ((none) (err (str "ERR_PARQUET: " path " is too short for a parquet file")))
              ((some tb)
                (if (or (not (pqMagic? hb 0)) (not (pqMagic? tb 4))) (err (str "ERR_PARQUET: " path " has no PAR1 magic"))
                  (let [(flen (pqLoadUAt tb 3 4 0))]
                    (if (or (> flen (- size 12)) (= flen 0)) (err (str "ERR_PARQUET: footer length " (stringFromInt64 flen) " outside " path))
                      (mt (pqReadExact path (- (- size 8) flen) flen)
                        ((none) (err (str "ERR_IO: cannot read the footer of " path)))
                        ((some fb)
                          (pqFooter (pqTrAt fb 0 flen) (PqFile :path path :size size :rows 0 :cols (list) :groupRows (list) :chunks (list) :kv (list)) 0)))))))))))))

fn parquetNumRowGroups h: PqFile -> Int64
  (listLength h.groupRows)

fn parquetNumRows h: PqFile -> Int64
  h.rows

fn pqColIndexFrom cols: (List PqCol) name: String i: Int64 -> Int64
  (mt (listHead cols)
    ((none) -1)
    ((some c) (if (= c.name name) i (pqColIndexFrom (optionOr (listTail cols) (list)) name (+ i 1)))))

fn pqColIndex q: PqFile name: String who: String -> Int64
  (let [(i (pqColIndexFrom q.cols name 0))]
    (if (< i 0) (trap "ERR_PARQUET" (str who ": no column " name)) i))

fn parquetColumnType h: PqFile name: String -> String
  (let [(c (pqColAt h (pqColIndex h name "parquetColumnType")))]
    (cond
      ((= c.ptype 2) "int64")
      ((= c.ptype 5) "double")
      ((= c.ptype 1) (if c.int8 "int8" "int32"))
      (else "other")))

fn parquetKvMetadata h: PqFile key: String -> (Result String String)
  (mt (listHead (filter (fn [(kv (Pair String String))] -> Bool (= (pairFirst kv) key)) h.kv))
    ((some kv) (ok (pairSecond kv)))
    ((none) (err "key not found")))

fn ! pqPutCell w: Int64 src: Bytes s: Int64 out: Bytes d: Int64 -> Bool
  (if (= w 8) (pqCopy src s out d 8)
    (do (pqCopy src s out d 4) (pqFill out (+ d 4) (if (>= (bytesGet src (+ s 3)) 128) 255 0) 4)))

fn ! pqPlainLoop w: Int64 src: Bytes off: Int64 n: Int64 out: Bytes at: Int64 i: Int64 -> Bool
  (if (>= i n) true
    (do (pqPutCell w src (+ off (* i w)) out (* (+ at i) 8))
        (pqPlainLoop w src off n out at (+ i 1))))

fn ! pqPlain ptype: Int64 src: Bytes off: Int64 len: Int64 n: Int64 out: Bytes at: Int64 -> Bool
  (let [(w (if (= ptype 1) 4 8))]
    (if (> n (/ len w)) false (pqPlainLoop w src off n out at 0)))

fn ! pqBssCell w: Int64 src: Bytes off: Int64 n: Int64 i: Int64 out: Bytes d: Int64 k: Int64 -> Bool
  (if (>= k w)
    (if (= w 4) (pqFill out (+ d 4) (if (>= (bytesGet out (+ d 3)) 128) 255 0) 4) true)
    (do (bytesSet out (+ d k) (bytesGet src (+ off (+ (* k n) i))))
        (pqBssCell w src off n i out d (+ k 1))))

fn ! pqBssLoop w: Int64 src: Bytes off: Int64 n: Int64 out: Bytes at: Int64 i: Int64 -> Bool
  (if (>= i n) true
    (do (pqBssCell w src off n i out (* (+ at i) 8) 0)
        (pqBssLoop w src off n out at (+ i 1))))

fn ! pqBss ptype: Int64 src: Bytes off: Int64 len: Int64 n: Int64 out: Bytes at: Int64 -> Bool
  (let [(w (if (= ptype 1) 4 8))]
    (if (> n (/ len w)) false (pqBssLoop w src off n out at 0)))

fn pqBitsSmall bs: Bytes base: Int64 bit: Int64 bw: Int64 pw: Int64 -> Int64
  (if (= bw 0) 0
    (let [(first (+ base (/ bit 8)))
          (last (+ base (/ (+ bit (- bw 1)) 8)))
          (w (pqLoadUAt bs last (+ (- last first) 1) 0))]
      (mod (/ w (pqPow2 (mod bit 8))) pw)))

fn pqBitsAny bs: Bytes base: Int64 bit: Int64 bw: Int64 pw: Int64 -> Int64
  (if (<= bw 48) (pqBitsSmall bs base bit bw pw)
    (zstdAslPack64 (pqBitsSmall bs base (+ bit 32) (- bw 32) (pqPow2 (- bw 32))) (pqBitsSmall bs base bit 32 4294967296)))

fn ! pqUnpackRun p: Bytes base: Int64 bw: Int64 take: Int64 sink: (fn [Int64 Int64] -> Bool) got: Int64 i: Int64 pw: Int64 -> Bool
  (if (>= i take) true
    (if (sink (+ got i) (pqBitsSmall p base (* i bw) bw pw))
      (pqUnpackRun p base bw take sink got (+ i 1) pw)
      false))

fn ! pqRepeat sink: (fn [Int64 Int64] -> Bool) got: Int64 take: Int64 v: Int64 i: Int64 -> Bool
  (if (>= i take) true
    (if (sink (+ got i) v) (pqRepeat sink got take v (+ i 1)) false))

fn ! pqHybridLoop p: Bytes off: Int64 len: Int64 bw: Int64 vb: Int64 count: Int64 sink: (fn [Int64 Int64] -> Bool) pos: Int64 got: Int64 -> Bool
  (if (>= got count) true
    (let [(hv (pqUleb p (+ off pos) (+ off len) 35))]
      (if (< (pairSecond hv) 0) false
        (let [(h (pairFirst hv))
              (npos (- (pairSecond hv) off))]
          (if (= (mod h 2) 1)
            (let [(groups (/ h 2))
                  (nbytes (* groups bw))]
              (if (> nbytes (- len npos)) false
                (let [(take (min (* groups 8) (- count got)))]
                  (if (pqUnpackRun p (+ off npos) bw take sink got 0 (pqPow2 bw))
                    (pqHybridLoop p off len bw vb count sink (+ npos nbytes) (+ got take))
                    false))))
            (let [(run (/ h 2))]
              (if (> vb (- len npos)) false
                (let [(v (pqLoadUAt p (+ off (+ npos (- vb 1))) vb 0))]
                  (if (= run 0) false
                    (let [(take (min run (- count got)))]
                      (if (pqRepeat sink got take v 0)
                        (pqHybridLoop p off len bw vb count sink (+ npos vb) (+ got take))
                        false)))))))))))

fn ! pqHybrid p: Bytes off: Int64 len: Int64 bw: Int64 count: Int64 sink: (fn [Int64 Int64] -> Bool) -> Bool
  (pqHybridLoop p off len bw (/ (+ bw 7) 8) count sink 0 0)

fn ! pqDeltaValues src: Bytes base: Int64 bw: Int64 ptype: Int64 out: Bytes at: Int64 cur: Int64 minD: Int64 i: Int64 take: Int64 pw: Int64 -> Int64
  (if (>= i take) cur
    (let [(sum (pqWrapAdd cur (pqWrapAdd minD (pqBitsAny src base (* i bw) bw pw))))
          (next (if (= ptype 1) (pqToI32 sum) sum))]
      (do (pqStore64 out (* (+ at i) 8) next)
          (pqDeltaValues src base bw ptype out at next minD (+ i 1) take pw))))

fn ! pqDeltaMinis src: Bytes bwAt: Int64 p: Int64 end: Int64 ptype: Int64 n: Int64 out: Bytes at: Int64 vpm: Int64 nmb: Int64 mb: Int64 got: Int64 cur: Int64 minD: Int64 -> Bool
  (cond
    ((>= got n) true)
    ((>= mb nmb) (pqDeltaBlocks src p end ptype n out at vpm nmb got cur))
    (else
      (let [(bw (bytesGet src (+ bwAt mb)))]
        (if (> bw 64) false
          (let [(mbBytes (/ (+ (* vpm bw) 7) 8))]
            (if (> mbBytes (- end p)) false
              (let [(take (min vpm (- n got)))
                    (last (pqDeltaValues src p bw ptype out (+ at got) cur minD 0 take (if (<= bw 48) (pqPow2 bw) 0)))]
                (pqDeltaMinis src bwAt (+ p mbBytes) end ptype n out at vpm nmb (+ mb 1) (+ got take) last minD))))))))

fn ! pqDeltaBlocks src: Bytes p: Int64 end: Int64 ptype: Int64 n: Int64 out: Bytes at: Int64 vpm: Int64 nmb: Int64 got: Int64 cur: Int64 -> Bool
  (if (>= got n) true
    (let [(md (pqUleb src p end 63))
          (bwAt (pairSecond md))]
      (if (or (< bwAt 0) (> nmb (- end bwAt))) false
        (pqDeltaMinis src bwAt (+ bwAt nmb) end ptype n out at vpm nmb 0 got cur (pqZigzag (pairFirst md))))))

fn ! pqDelta ptype: Int64 src: Bytes off: Int64 len: Int64 n: Int64 out: Bytes at: Int64 -> Bool
  (if (= n 0) true
    (let [(end (+ off len))
          (a (pqUleb src off end 63))
          (b (pqUleb src (pairSecond a) end 63))
          (c (pqUleb src (pairSecond b) end 63))
          (d (pqUleb src (pairSecond c) end 63))
          (bs (pairFirst a))
          (nmb (pairFirst b))
          (tc (pairFirst c))]
      (if (or (or (< (pairSecond d) 0) (or (<= nmb 0) (< bs 0))) (or (!= (mod bs nmb) 0) (or (< tc 0) (< tc n)))) false
        (let [(vpm (/ bs nmb))]
          (if (or (= vpm 0) (> vpm 4294967296)) false
            (let [(cur0 (pqZigzag (pairFirst d)))
                  (cur (if (= ptype 1) (pqToI32 cur0) cur0))]
              (do (pqStore64 out (* at 8) cur)
                  (pqDeltaBlocks src (pairSecond d) end ptype n out at vpm nmb 1 cur))))))))

fn ! pqDecompress codec: Int64 src: Bytes off: Int64 n: Int64 want: Int64 -> (Result (Pair Bytes Int64) String)
  (cond
    ((= codec 0) (if (!= n want) (err "ERR_PARQUET: uncompressed page size mismatch") (ok (pair src off))))
    ((= codec 1) (err "snappy unsupported"))
    ((= codec 6)
      (mt (zstdDecompress (pqSlice src off n))
        ((err e) (err e))
        ((ok d) (if (!= (bytesLength d) want) (err "ERR_PARQUET: zstd page size mismatch") (ok (pair d 0))))))
    (else (err (str "ERR_PARQUET_UNSUPPORTED: codec " (stringFromInt64 codec)))))

fn ! pqDecodeValues cd: PqCol enc: Int64 vals: Bytes off: Int64 vlen: Int64 n: Int64 dict: Bytes ndict: Int64 out: Bytes at: Int64 -> (Result Bool String)
  (let [(ptype cd.ptype)
        (good
          (cond
            ((= enc 0) (some (pqPlain ptype vals off vlen n out at)))
            ((= enc 5) (some (and (or (= ptype 1) (= ptype 2)) (pqDelta ptype vals off vlen n out at))))
            ((= enc 9) (some (pqBss ptype vals off vlen n out at)))
            ((or (= enc 2) (= enc 8))
              (some
                (if (or (< ndict 0) (or (< vlen 1) (> (bytesGet vals off) 32))) false
                  (pqHybrid vals (+ off 1) (- vlen 1) (bytesGet vals off) n
                    (fn [(i Int64) (v Int64)] -> Bool
                      (if (>= v ndict) false (pqCopySlot8 dict v out (+ at i))))))))
            (else (none))))]
    (mt good
      ((none) (err (str "ERR_PARQUET_UNSUPPORTED: encoding " (stringFromInt64 enc))))
      ((some g) (if g (ok true) (err "ERR_PARQUET: corrupt data page")))))

fn ! pqLevels p: Bytes off: Int64 len: Int64 n: Int64 nulls: Bytes -> Bool
  (pqHybrid p off len 1 n (fn [(i Int64) (v Int64)] -> Bool (do (if (!= v 1) (bytesSet nulls 0 1) ()) true)))

fn ! pqDataPage c: PqChunk cd: PqCol buf: Bytes p: Int64 h: PqPage dict: Bytes ndict: Int64 out: Bytes got: Int64 -> (Result Bool String)
  (let [(nulls (bytesAlloc 1))
        (n h.nvals)
        (body
          (if (= h.kind 0)
            (mt (pqDecompress c.codec buf p h.comp h.uncomp)
              ((err e) (err e))
              ((ok d)
                (let [(dv (pairFirst d))
                      (doff (pairSecond d))
                      (vlen h.uncomp)]
                  (if (= cd.maxDef 0) (ok (pair dv (pair doff vlen)))
                    (if (< vlen 4) (err "ERR_PARQUET: definition levels truncated")
                      (let [(dl (pqLoadUAt dv (+ doff 3) 4 0))]
                        (if (or (> dl (- vlen 4)) (not (pqLevels dv (+ doff 4) dl n nulls))) (err "ERR_PARQUET: bad definition levels")
                          (ok (pair dv (pair (+ doff (+ 4 dl)) (- vlen (+ 4 dl))))))))))))
            (let [(lev (+ h.defLen h.repLen))]
              (cond
                ((or (or (< h.defLen 0) (!= h.repLen 0)) (or (> lev h.comp) (> lev h.uncomp))) (err "ERR_PARQUET: bad v2 level lengths"))
                ((and (!= cd.maxDef 0) (not (pqLevels buf p h.defLen n nulls))) (err "ERR_PARQUET: bad definition levels"))
                (else
                  (let [(clen (- h.comp lev))
                        (vlen (if h.compressed (- h.uncomp lev) clen))]
                    (mt (pqDecompress (if h.compressed c.codec 0) buf (+ p lev) clen vlen)
                      ((err e) (err e))
                      ((ok d) (ok (pair (pairFirst d) (pair (pairSecond d) vlen)))))))))))]
    (mt body
      ((err e) (err e))
      ((ok b)
        (if (= (bytesGet nulls 0) 1) (err (str "ERR_PARQUET_NULL: column " cd.name " has null values"))
          (pqDecodeValues cd h.encoding (pairFirst b) (pairFirst (pairSecond b)) (pairSecond (pairSecond b)) n dict ndict out got)))))

fn ! pqPages c: PqChunk cd: PqCol buf: Bytes out: Bytes want: Int64 pos: Int64 got: Int64 dict: Bytes ndict: Int64 -> (Result Int64 String)
  (cond
    ((>= got want) (ok got))
    ((>= pos c.compSize) (err "ERR_PARQUET: malformed page header"))
    (else
      (let [(tr (pqTrAt buf pos c.compSize))]
        (mt (pqPageHeader tr)
          ((none) (err "ERR_PARQUET: malformed page header"))
          ((some h)
            (let [(p (pqTrPos tr))
                  (next (+ p h.comp))]
              (cond
                ((> h.comp (- c.compSize p)) (err "ERR_PARQUET: page beyond the column chunk"))
                ((= h.kind 2)
                  (mt (pqDecompress c.codec buf p h.comp h.uncomp)
                    ((err e) (err e))
                    ((ok d)
                      (let [(w (if (= cd.ptype 1) 4 8))]
                        (if (> h.nvals (/ h.uncomp w)) (err "ERR_PARQUET: dictionary page truncated")
                          (let [(nd (bytesAlloc (* h.nvals 8)))]
                            (if (pqPlain cd.ptype (pairFirst d) (pairSecond d) h.uncomp h.nvals nd 0)
                              (pqPages c cd buf out want next got nd h.nvals)
                              (err "ERR_PARQUET: dictionary page truncated"))))))))
                ((and (!= h.kind 0) (!= h.kind 3)) (pqPages c cd buf out want next got dict ndict))
                ((> h.nvals (- want got)) (err "ERR_PARQUET: page values beyond the row group"))
                (else
                  (mt (pqDataPage c cd buf p h dict ndict out got)
                    ((err e) (err e))
                    ((ok _) (pqPages c cd buf out want next (+ got h.nvals) dict ndict)))))))))))

fn ! pqReadChunk q: PqFile col: Int64 rg: Int64 -> (Result (Pair Bytes Int64) String)
  (let [(c (pqChunkAt q col rg))
        (cd (pqColAt q col))
        (want (pqGroupRows q rg))]
    (if (or (or (< want 0) (> want 2147483648)) (!= c.nvals want))
      (err (str "ERR_PARQUET: chunk value count " (stringFromInt64 c.nvals) " differs from " (stringFromInt64 want) " rows"))
      (mt (pqReadExact q.path (pqChunkStart c) c.compSize)
        ((none) (err "ERR_IO: cannot read column chunk"))
        ((some buf)
          (let [(out (bytesAlloc (* want 8)))]
            (mt (pqPages c cd buf out want 0 0 (bytesAlloc 0) -1)
              ((err e) (err e))
              ((ok got) (ok (pair out got)))))))))

fn ! pqReadAs h: PqFile name: String rg: Int64 kind: Int64 who: String -> (Pair Bytes Int64)
  (let [(col (pqColIndex h name who))
        (groups (listLength h.groupRows))]
    (if (or (< rg 0) (>= rg groups)) (trap "ERR_RANGE" (str who ": row group outside 0.." (stringFromInt64 (- groups 1))))
      (let [(cd (pqColAt h col))
            (pt cd.ptype)]
        (if (or (and (= kind 5) (!= pt 5)) (or (and (= kind 2) (!= pt 2)) (and (= kind 1) (not (and (= pt 1) cd.int8)))))
          (trap "ERR_TYPE" (str who ": column " cd.name " is not of that type"))
          (mt (pqReadChunk h col rg)
            ((err e) (trap "ERR_PARQUET" (str who ": " e)))
            ((ok r) r))))))

fn ! parquetReadF64 h: PqFile name: String rg: Int64 -> F64Array
  (let [(r (pqReadAs h name rg 5 "parquetReadF64"))
        (cells (pairFirst r))]
    (f64ArrayGenerate (pairSecond r) (fn [(i Int64)] -> Float64 (bytesGetFloat64 cells i))))

fn ! parquetReadI64 h: PqFile name: String rg: Int64 -> I64Array
  (let [(r (pqReadAs h name rg 2 "parquetReadI64"))
        (cells (pairFirst r))]
    (i64ArrayGenerate (pairSecond r) (fn [(i Int64)] -> Int64 (pqLoad64 cells (* i 8)))))

fn pqFirstBadI8 cells: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n) -1
    (let [(v (pqLoad64 cells (* i 8)))]
      (if (or (< v -128) (> v 127)) i (pqFirstBadI8 cells (+ i 1) n))))

fn ! parquetReadI8 h: PqFile name: String rg: Int64 -> I8Array
  (let [(r (pqReadAs h name rg 1 "parquetReadI8"))
        (cells (pairFirst r))
        (n (pairSecond r))]
    (let [(bad (pqFirstBadI8 cells 0 n))]
      (if (>= bad 0) (trap "ERR_RANGE" (str "parquetReadI8: " (stringFromInt64 (pqLoad64 cells (* bad 8))) " outside Int(8)"))
        (i8ArrayGenerate n (fn [(i Int64)] -> Int64 (pqLoad64 cells (* i 8)))))))
