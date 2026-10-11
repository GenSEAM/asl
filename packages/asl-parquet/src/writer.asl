(module asl-parquet/writer
  :x [ParquetColumn i64Column f64Column i8Column parquetWrite]
  :i [(asl-proc/process :a proc)])

(enum ParquetColumn (:c i64Column [(name String) (values I64Array) (encoding String)] "I64 column") (:c f64Column [(name String) (values F64Array) (encoding String)] "F64 column") (:c i8Column [(name String) (values I8Array) (encoding String)] "I8 column"))

(schema ChunkMeta (:f name String) (:f physical Int64) (:f encoding String) (:f values Int64) (:f offset Int64) (:f compressed Int64) (:f uncompressed Int64))

(schema GroupMeta (:f chunks (List ChunkMeta)) (:f rows Int64))


fn bytePut! bytes: Bytes at: Int64 value: Int64 -> Int64
  (do (bytesSet bytes at value) (+ at 1))

fn littlePut! bytes: Bytes at: Int64 value: Int64 width: Int64 -> Int64
  (if (= width 0) at
    (littlePut! bytes
      (bytePut! bytes at (mod value 256))
      (/ value 256) (- width 1)))

fn unsignedVarint! bytes: Bytes at: Int64 value: Int64 -> Int64
  (if (< value 128)
    (bytePut! bytes at value)
    (unsignedVarint! bytes
      (bytePut! bytes at (+ 128 (mod value 128)))
      (/ value 128)))

fn ! zigzagVarint! bytes: Bytes at: Int64 value: Int64 -> Int64
  (if (>= value 0)
    (let [(low (* (mod value 64) 2))
          (rest (/ value 64))]
      (if (= rest 0) (bytePut! bytes at low)
        (unsignedVarint! bytes (bytePut! bytes at (+ low 128)) rest)))
    (let [(remainder (mod value 64))
          (magnitudeHigh (if (= remainder 0) (- (/ value 64)) (- (- (/ value 64)) 1)))
          (magnitudeLow (if (= remainder 0) 0 (- 64 remainder)))
          (low (if (= magnitudeLow 0) 127 (- (* magnitudeLow 2) 1)))
          (rest (if (= magnitudeLow 0) (- magnitudeHigh 1) magnitudeHigh))]
      (if (= rest 0) (bytePut! bytes at low)
        (unsignedVarint! bytes (bytePut! bytes at (+ low 128)) rest))))

fn ! signedVarint! bytes: Bytes at: Int64 value: Int64 -> Int64
  (zigzagVarint! bytes at value)

fn copyBytes! source: Bytes sourceAt: Int64 target: Bytes targetAt: Int64 count: Int64 -> Int64
  (if (= count 0) targetAt
    (copyBytes! source (+ sourceAt 1) target
      (bytePut! target targetAt (bytesGet source sourceAt)) (- count 1)))

fn exactBytes! source: Bytes used: Int64 -> Bytes
  (let [(target (bytesAlloc used))]
    (do (copyBytes! source 0 target 0 used) target))

fn ! compactField! out: Bytes at: Int64 last: Int64 field: Int64 kind: Int64 -> Int64
  (let [(delta (- field last))]
    (if (and (> delta 0) (< delta 16))
      (bytePut! out at (+ (* delta 16) kind))
      (zigzagVarint! out (bytePut! out at kind) field)))

fn ! compactIntField! out: Bytes at: Int64 last: Int64 field: Int64 value: Int64 -> Int64
  (signedVarint! out (compactField! out at last field 5) value)

fn ! compactLongField! out: Bytes at: Int64 last: Int64 field: Int64 value: Int64 -> Int64
  (signedVarint! out (compactField! out at last field 6) value)

fn ! compactBinary! out: Bytes at: Int64 value: String -> Int64
  (let [(raw (stringToBytes value))
        (size (bytesLength raw))
        (next (unsignedVarint! out at size))]
    (copyBytes! raw 0 out next size))

fn ! compactList! out: Bytes at: Int64 count: Int64 elementType: Int64 -> Int64
  (if (< count 15)
    (bytePut! out at (+ (* count 16) elementType))
    (unsignedVarint! out (bytePut! out at (+ 240 elementType)) count))

fn arrayCount column: ParquetColumn -> Int64
  (mt column
    ((i64Column _ values _) (i64ArrayLen values))
    ((f64Column _ values _) (f64ArrayLen values))
    ((i8Column _ values _) (i8ArrayLen values)))

fn columnName column: ParquetColumn -> String
  (mt column
    ((i64Column name _ _) name)
    ((f64Column name _ _) name)
    ((i8Column name _ _) name))

fn columnEncoding column: ParquetColumn -> String
  (mt column
    ((i64Column _ _ encoding) encoding)
    ((f64Column _ _ encoding) encoding)
    ((i8Column _ _ encoding) encoding))

fn physicalType column: ParquetColumn -> Int64
  (mt column
    ((i64Column _ _ _) 2)
    ((f64Column _ _ _) 5)
    ((i8Column _ _ _) 1))

fn typeEncodingValid? column: ParquetColumn -> Bool
  (mt column
    ((i64Column _ _ enc) (or (= enc "PLAIN") (= enc "DELTA_BINARY_PACKED") (= enc "BYTE_STREAM_SPLIT")))
    ((f64Column _ _ enc) (or (= enc "PLAIN") (= enc "BYTE_STREAM_SPLIT")))
    ((i8Column _ _ enc) (= enc "PLAIN")))

fn validName? name: String -> Bool
  (and (not (stringEmpty? name)) (not (stringContains? name "/")))

fn optionValue options: (List (List String)) key: String fallback: String -> String
  (cond
    ((listEmpty? options) fallback)
    (else
      (mt (listHead options)
        ((none) fallback)
        ((some head)
          (mt (listGet head 0)
            ((none) (optionValue (listDrop options 1) key fallback))
            ((some k)
              (if (= k key)
                (optionOr (listGet head 1) fallback)
                (optionValue (listDrop options 1) key fallback))))))))

fn pairValid? pair: (List String) -> Bool
  (= (listLength pair) 2)

fn metadataPairsValid? kv: (List (List String)) -> Bool
  (listAll? (fn [item] (pairValid? item)) kv)

fn metadataHasKey? kv: (List (List String)) key: String -> Bool
  (if (listEmpty? kv) false
    (mt (listHead kv)
      ((none) false)
      ((some item)
        (or (= (optionOr (listGet item 0) "") key)
          (metadataHasKey? (listDrop kv 1) key)))))

fn columnsValid? columns: (List ParquetColumn) -> Bool
  (and (not (listEmpty? columns))
    (listAll? (fn [column]
      (and (validName? (columnName column))
        (typeEncodingValid? column)
        (> (arrayCount column) 0))) columns))

fn firstColumnCount columns: (List ParquetColumn) -> Int64
  (mt (listHead columns)
    ((none) 0)
    ((some column) (arrayCount column)))

fn sameColumnLengths? columns: (List ParquetColumn) count: Int64 -> Bool
  (listAll? (fn [column] (= (arrayCount column) count)) columns)

fn ! removeCompressionFile! path: String -> (Result Unit String)
  (if (not (fileExists? path)) (ok ())
    (mt (pathRemove path)
      ((err e) (err e))
      ((ok _) (ok ()))))

fn ! removeCompressionFiles! rawPath: String compressedPath: String -> (Result Unit String)
  (mt (removeCompressionFile! rawPath)
    ((err e) (err e))
    ((ok _) (removeCompressionFile! compressedPath)))

fn ! zstdCompress! input: Bytes level: Int64 -> (Result Bytes String)
  (let [(stem (str "/tmp/aslParquetZstd-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))) )
        (rawPath (str stem ".raw"))
        (compressedPath (str stem ".zst"))
        (written (fileWrite rawPath input))]
    (mt written
      ((err e) (err (str e)))
      ((ok _)
        (mt (proc/exec! (proc/withTimeout
              (proc/cmd "zstd" (listAppend (if (> level 19) (list "--ultra") (list))
                (listAppend (list "-q" "-f" (str "-" (stringFromInt64 level)) "-o" compressedPath rawPath) (list))))
              300000))
          ((err e)
            (mt (removeCompressionFiles! rawPath compressedPath)
              ((err cleanup) (err (str "zstd failed: " e "; cleanup failed: " cleanup)))
              ((ok _) (err (str "zstd failed: " e)))))
          ((ok run)
            (if (!= run.exitCode 0)
              (mt (removeCompressionFiles! rawPath compressedPath)
                ((err cleanup) (err (str "zstd failed: " run.stderr "; cleanup failed: " cleanup)))
                ((ok _) (err (str "zstd failed: " run.stderr))))
              (mt (fileReadBytes compressedPath)
              ((err e)
                (mt (removeCompressionFiles! rawPath compressedPath)
                  ((err cleanup) (err (str e "; cleanup failed: " cleanup)))
                  ((ok _) (err (str e)))))
              ((ok compressed)
                (mt (removeCompressionFiles! rawPath compressedPath)
                  ((err cleanup) (err (str "zstd output cleanup failed: " cleanup)))
                  ((ok _) (ok compressed)))))))))))

fn ! fillI64Plain! values: I64Array index: Int64 out: Bytes -> Int64
  (if (= index (i64ArrayLen values)) (* index 8)
    (do
      (littlePut! out (* index 8) (i64ArrayGet values index) 8)
      (fillI64Plain! values (+ index 1) out)))

fn ! fillI8Plain! values: I8Array index: Int64 out: Bytes -> Int64
  (if (= index (i8ArrayLen values)) index
    (do
      (littlePut! out (* index 4) (i8ArrayGet values index) 4)
      (fillI8Plain! values (+ index 1) out)))

fn ! fillF64Plain! values: F64Array index: Int64 out: Bytes -> Int64
  (if (= index (f64ArrayLen values)) (* index 8)
    (do
      (bytesSetFloat64 out index (f64ArrayGet values index))
      (fillF64Plain! values (+ index 1) out)))

fn ! fillPlanes! raw: Bytes count: Int64 byteIndex: Int64 valueIndex: Int64 out: Bytes -> Int64
  (if (= byteIndex 8) (* count 8)
    (if (= valueIndex count)
      (fillPlanes! raw count (+ byteIndex 1) 0 out)
      (do
        (bytesSet out (+ (* byteIndex count) valueIndex)
          (bytesGet raw (+ (* valueIndex 8) byteIndex)))
        (fillPlanes! raw count byteIndex (+ valueIndex 1) out))))

fn ! plainData! column: ParquetColumn -> Bytes
  (mt column
    ((i64Column _ values _) (let [(out (bytesAlloc (* (i64ArrayLen values) 8)))] (do (fillI64Plain! values 0 out) out)))
    ((f64Column _ values _) (let [(out (bytesAlloc (* (f64ArrayLen values) 8)))] (do (fillF64Plain! values 0 out) out)))
    ((i8Column _ values _) (let [(out (bytesAlloc (* (i8ArrayLen values) 4)))] (do (fillI8Plain! values 0 out) out))))

fn ! splitData! column: ParquetColumn -> (Result Bytes String)
  (mt column
    ((i64Column _ values _) (let [(count (i64ArrayLen values))
                                  (raw (plainData! column))
                                  (out (bytesAlloc (* count 8)))]
                              (do (fillPlanes! raw count 0 0 out) (ok out))))
    ((f64Column _ values _) (let [(count (f64ArrayLen values))
                                  (raw (plainData! column))
                                  (out (bytesAlloc (* count 8)))]
                              (do (fillPlanes! raw count 0 0 out) (ok out))))
    ((i8Column _ _ _) (err "BYTE_STREAM_SPLIT is supported only for INT64 and DOUBLE columns")))

fn deltaSubtractionSafe? current: Int64 previous: Int64 -> Bool
  (if (< previous 0)
    (if (>= current 0) (<= current (+ 9223372036854775807 previous)) true)
    (if (< current 0) (>= current (+ previous (- 0 9223372036854775807) -1)) true))

fn deltaBlockValid? values: I64Array index: Int64 last: Int64 minimum: Int64 maximum: Int64 -> Bool
  (if (> index last) (deltaSubtractionSafe? maximum minimum)
    (let [(current (i64ArrayGet values index))
          (previous (i64ArrayGet values (- index 1)))]
      (if (not (deltaSubtractionSafe? current previous)) false
        (let [(delta (- current previous))]
          (deltaBlockValid? values (+ index 1) last (min minimum delta) (max maximum delta))))))

fn deltaBlocksValid? values: I64Array start: Int64 -> Bool
  (if (>= start (i64ArrayLen values)) true
    (let [(last (min (+ start 127) (- (i64ArrayLen values) 1)))]
      (and (deltaBlockValid? values start last 0 0)
        (deltaBlocksValid? values (+ last 1)))))

fn columnDeltasValid? column: ParquetColumn -> Bool
  (mt column
    ((i64Column _ values encoding) (if (= encoding "DELTA_BINARY_PACKED") (deltaBlocksValid? values 1) true))
    ((f64Column _ _ _) true)
    ((i8Column _ _ _) true))

fn columnsDeltasValid? columns: (List ParquetColumn) -> Bool
  (listAll? (fn [column] (columnDeltasValid? column)) columns)

fn deltaAt values: I64Array index: Int64 -> Int64
  (if (= index 0) 0 (- (i64ArrayGet values index) (i64ArrayGet values (- index 1))))

fn deltaMinimum values: I64Array index: Int64 last: Int64 current: Int64 -> Int64
  (if (> index last) current
    (let [(delta (deltaAt values index))]
      (deltaMinimum values (+ index 1) last (if (< delta current) delta current))))

fn integerBits value: Int64 -> Int64
  (if (= value 0) 0
    (if (< value 2) 1 (+ 1 (integerBits (/ value 2)))))

fn power2 value: Int64 -> Int64
  (if (= value 0) 1 (* 2 (power2 (- value 1))))

fn ! putBits! out: Bytes start: Int64 bitIndex: Int64 value: Int64 width: Int64 -> Int64
  (if (= width 0) bitIndex
    (let [(bit (mod value 2))
          (byteAt (+ start (/ bitIndex 8)))
          (mask (power2 (mod bitIndex 8)))]
      (do
        (bytesSet out byteAt (| (bytesGet out byteAt) (* bit mask)))
        (putBits! out start (+ bitIndex 1) (/ value 2) (- width 1)))))

fn residualMax values: I64Array index: Int64 last: Int64 minimum: Int64 current: Int64 -> Int64
  (if (> index last) current
    (let [(residual (- (deltaAt values index) minimum))]
      (residualMax values (+ index 1) last minimum (if (> residual current) residual current))))

fn ! putDeltaValues! values: I64Array index: Int64 last: Int64 minimum: Int64 out: Bytes start: Int64 bitIndex: Int64 width: Int64 -> Int64
  (if (> index last)
    (if (< bitIndex (* 32 width))
      (putDeltaValues! values (+ index 1) last minimum out start
        (putBits! out start bitIndex 0 width) width)
      bitIndex)
    (let [(residual (if (> index last) 0 (- (deltaAt values index) minimum)))]
      (putDeltaValues! values (+ index 1) last minimum out start
        (putBits! out start bitIndex residual width) width)))

fn ! deltaMiniWidths! values: I64Array blockStart: Int64 blockCount: Int64 minimum: Int64 mini: Int64 out: Bytes at: Int64 -> Int64
  (if (= mini 4) (+ at 4)
    (let [(first (+ blockStart (* mini 32)))
          (last (min (+ first 31) (+ blockStart blockCount -1)))
          (maxResidual (if (> first last) 0 (residualMax values first last minimum 0)))
          (width (integerBits maxResidual))]
      (do
        (bytePut! out (+ at mini) width)
        (deltaMiniWidths! values blockStart blockCount minimum (+ mini 1) out at))))

fn ! deltaMiniValues! values: I64Array blockStart: Int64 blockCount: Int64 minimum: Int64 mini: Int64 out: Bytes at: Int64 -> Int64
  (if (= mini 4) at
    (let [(first (+ blockStart (* mini 32)))
          (last (min (+ first 31) (+ blockStart blockCount -1)))
          (maxResidual (if (> first last) 0 (residualMax values first last minimum 0)))
          (width (integerBits maxResidual))
          (used (putDeltaValues! values first last minimum out at 0 width))]
      (deltaMiniValues! values blockStart blockCount minimum (+ mini 1) out (+ at (* width 4)))))

fn ! deltaMiniblocks! values: I64Array blockStart: Int64 blockCount: Int64 minimum: Int64 mini: Int64 out: Bytes at: Int64 -> Int64
  (if (= mini 4) at
    (let [(dataAt (deltaMiniWidths! values blockStart blockCount minimum 0 out at))]
      (deltaMiniValues! values blockStart blockCount minimum 0 out dataAt)))

fn ! deltaBlocks! values: I64Array index: Int64 out: Bytes at: Int64 -> Int64
  (if (>= index (i64ArrayLen values)) at
    (let [(count (min 128 (- (i64ArrayLen values) index)))
          (last (+ index count -1))
          (minimum (deltaMinimum values index last (deltaAt values index)))
          (afterMin (signedVarint! out at minimum))
          (afterMini (deltaMiniblocks! values index count minimum 0 out afterMin))]
      (deltaBlocks! values (+ last 1) out afterMini)))

fn ! deltaData! values: I64Array -> Bytes
  (let [(count (i64ArrayLen values))
        (capacity (+ 64 (* (/ (+ count 127) 128) 1040)))
        (out (bytesAlloc capacity))
        (p1 (unsignedVarint! out 0 128))
        (p2 (unsignedVarint! out p1 4))
        (p3 (unsignedVarint! out p2 count))
        (p4 (signedVarint! out p3 (i64ArrayGet values 0)))
        (p5 (deltaBlocks! values 1 out p4))]
    (exactBytes! out p5))

fn ! pageHeader! values: Int64 encoding: String uncompressed: Int64 compressed: Int64 -> Bytes
  (let [(out (bytesAlloc 128))
        (p1 (compactIntField! out 0 0 1 0))
        (p2 (compactIntField! out p1 1 2 uncompressed))
        (p3 (compactIntField! out p2 2 3 compressed))
        (p4 (compactField! out p3 3 5 12))
        (p5 (compactIntField! out p4 0 1 values))
        (enc (cond ((= encoding "PLAIN") 0) ((= encoding "DELTA_BINARY_PACKED") 5) (else 9)))
        (p6 (compactIntField! out p5 1 2 enc))
        (p7 (compactIntField! out p6 2 3 3))
        (p8 (compactIntField! out p7 3 4 3))
        (p9 (bytePut! out p8 0))
        (p10 (bytePut! out p9 0))]
    (exactBytes! out p10))

fn ! schemaRoot! out: Bytes at: Int64 columns: (List ParquetColumn) -> Int64
  (let [(p1 (compactField! out at 0 4 8))
        (p2 (compactBinary! out p1 "schema"))
        (p3 (compactIntField! out p2 4 5 (listLength columns)))
        (p4 (bytePut! out p3 0))]
    p4)

fn ! schemaLeaf! out: Bytes at: Int64 column: ParquetColumn -> Int64
  (let [(p1 (compactIntField! out at 0 1 (physicalType column)))
        (p2 (compactIntField! out p1 1 3 0))
        (p3 (compactField! out p2 3 4 8))
        (p4 (compactBinary! out p3 (columnName column)))
        (p5 (if (match column ((i8Column _ _ _) true) (_ false))
              (compactIntField! out p4 4 6 15)
              p4))]
    (bytePut! out p5 0))

fn ! schemaItems! out: Bytes at: Int64 columns: (List ParquetColumn) -> Int64
  (if (listEmpty? columns) at
    (mt (listHead columns)
      ((none) at)
      ((some column) (schemaItems! out (schemaLeaf! out at column) (listDrop columns 1)))))

fn ! schemaList! out: Bytes at: Int64 columns: (List ParquetColumn) -> Int64
  (let [(p1 (compactField! out at 1 2 9))
        (p2 (compactList! out p1 (+ 1 (listLength columns)) 12))
        (p3 (schemaRoot! out p2 columns))]
    (schemaItems! out p3 columns))

fn ! kvItem! out: Bytes at: Int64 item: (List String) -> Int64
  (let [(key (optionOr (listGet item 0) ""))
        (value (optionOr (listGet item 1) ""))
        (p1 (compactField! out at 0 1 8))
        (p2 (compactBinary! out p1 key))
        (p3 (compactField! out p2 1 2 8))
        (p4 (compactBinary! out p3 value))]
    (bytePut! out p4 0))

fn ! kvItems! out: Bytes at: Int64 kv: (List (List String)) -> Int64
  (if (listEmpty? kv) at
    (mt (listHead kv)
      ((none) at)
      ((some item) (kvItems! out (kvItem! out at item) (listDrop kv 1)))))

fn ! kvList! out: Bytes at: Int64 kv: (List (List String)) -> Int64
  (let [(p1 (compactField! out at 4 5 9))
        (p2 (compactList! out p1 (listLength kv) 12))]
    (kvItems! out p2 kv))

fn kvByteCount kv: (List (List String)) -> Int64
  (if (listEmpty? kv) 0
    (mt (listHead kv)
      ((none) 0)
      ((some item)
        (+ (stringLength (optionOr (listGet item 0) ""))
           (stringLength (optionOr (listGet item 1) ""))
           16 (kvByteCount (listDrop kv 1))))))

fn columnNameByteCount columns: (List ParquetColumn) -> Int64
  (if (listEmpty? columns) 0
    (mt (listHead columns)
      ((none) 0)
      ((some column)
        (+ (bytesLength (stringToBytes (columnName column)))
           (columnNameByteCount (listDrop columns 1))))))

fn chunkCompressedSum chunks: (List ChunkMeta) -> Int64
  (if (listEmpty? chunks) 0
    (mt (listHead chunks)
      ((none) 0)
      ((some chunk) (+ chunk.compressed (chunkCompressedSum (listDrop chunks 1))))))

fn chunkUncompressedSum chunks: (List ChunkMeta) -> Int64
  (if (listEmpty? chunks) 0
    (mt (listHead chunks)
      ((none) 0)
      ((some chunk) (+ chunk.uncompressed (chunkUncompressedSum (listDrop chunks 1))))))

fn ! columnChunk! out: Bytes at: Int64 chunk: ChunkMeta compression: String -> Int64
  (let [(p1 (compactLongField! out at 0 2 chunk.offset))
        (p2 (compactField! out p1 2 3 12))
        (p3 (compactIntField! out p2 0 1 chunk.physical))
        (p4 (compactField! out p3 1 2 9))
        (p5 (compactList! out p4 2 5))
        (p6 (signedVarint! out p5 0))
        (p7 (signedVarint! out p6 (if (= chunk.encoding "PLAIN") 0 (if (= chunk.encoding "DELTA_BINARY_PACKED") 5 9))))
        (p8 (compactField! out p7 2 3 9))
        (p9 (compactList! out p8 1 8))
        (p10 (compactBinary! out p9 chunk.name))
        (p11 (compactIntField! out p10 3 4 (if (= compression "zstd") 6 0)))
        (p12 (compactLongField! out p11 4 5 chunk.values))
        (p13 (compactLongField! out p12 5 6 chunk.uncompressed))
        (p14 (compactLongField! out p13 6 7 chunk.compressed))
        (p15 (compactLongField! out p14 7 9 chunk.offset))
        (p16 (bytePut! out p15 0))]
    (bytePut! out p16 0))

fn ! columnChunks! out: Bytes at: Int64 chunks: (List ChunkMeta) compression: String -> Int64
  (if (listEmpty? chunks) at
    (mt (listHead chunks)
      ((none) at)
      ((some chunk) (columnChunks! out (columnChunk! out at chunk compression) (listDrop chunks 1) compression))))

fn ! rowGroup! out: Bytes at: Int64 group: GroupMeta compression: String -> Int64
  (let [(chunks group.chunks)
        (rows group.rows)
        (p1 (compactField! out at 0 1 9))
        (p2 (compactList! out p1 (listLength chunks) 12))
        (p3 (columnChunks! out p2 chunks compression))
        (p4 (compactLongField! out p3 1 2 (chunkUncompressedSum chunks)))
        (p5 (compactLongField! out p4 2 3 rows))
        (p6 (compactLongField! out p5 3 6 (chunkCompressedSum chunks)))
        (p7 (bytePut! out p6 0))]
    p7)

fn ! rowGroups! out: Bytes at: Int64 groups: (List GroupMeta) compression: String -> Int64
  (if (listEmpty? groups) at
    (mt (listHead groups)
      ((none) at)
      ((some group) (rowGroups! out (rowGroup! out at group compression) (listDrop groups 1) compression))))

fn ! parquetFooter! columns: (List ParquetColumn) groups: (List GroupMeta) rows: Int64 compression: String kv: (List (List String)) -> Bytes
  (let [(ncols (listLength columns))
        (ngroups (listLength groups))
        (kvBytes (kvByteCount kv))
        (nameBytes (columnNameByteCount columns))
        (out (bytesAlloc (+ 4096 (* ncols 256) (* ngroups ncols 192) (* (+ ngroups 1) nameBytes) kvBytes)))
        (p1 (compactIntField! out 0 0 1 1))
        (p2 (schemaList! out p1 columns))
        (p3 (compactLongField! out p2 2 3 rows))
        (p4 (compactField! out p3 3 4 9))
        (p5 (compactList! out p4 ngroups 12))
        (p6 (rowGroups! out p5 groups compression))
        (p7 (kvList! out p6 kv))
        (p8 (bytePut! out p7 0))]
    (exactBytes! out p8))

fn ! columnSlice! column: ParquetColumn start: Int64 end: Int64 -> ParquetColumn
  (mt column
    ((i64Column name values encoding) (i64Column name (i64ArraySlice values start end) encoding))
    ((f64Column name values encoding) (f64Column name (f64ArraySlice values start end) encoding))
    ((i8Column name values encoding) (i8Column name (i8ArraySlice values start end) encoding)))

fn ! columnData! column: ParquetColumn -> (Result Bytes String)
  (let [(encoding (columnEncoding column))]
    (cond
      ((= encoding "PLAIN") (ok (plainData! column)))
      ((= encoding "BYTE_STREAM_SPLIT") (splitData! column))
      (else (mt column
        ((i64Column _ values _) (ok (deltaData! values)))
        ((f64Column _ _ _) (err "DELTA_BINARY_PACKED is supported only for INT64 columns"))
        ((i8Column _ _ _) (err "DELTA_BINARY_PACKED is supported only for INT64 columns"))))))

fn ! writeColumns! temp: String columns: (List ParquetColumn) start: Int64 count: Int64 compression: String level: Int64 offset: Int64 -> (Result (List ChunkMeta) String)
  (if (listEmpty? columns) (ok (list))
    (mt (listHead columns)
      ((none) (ok (list)))
      ((some wholeColumn)
        (let [(column (columnSlice! wholeColumn start (+ start count)))
              (rawResult (columnData! column))]
          (mt rawResult
            ((err e) (err e))
            ((ok raw)
              (mt (if (= compression "zstd") (zstdCompress! raw level) (ok raw))
                ((err e) (err e))
                ((ok compressedBytes)
                  (let [(header (pageHeader! count (columnEncoding column) (bytesLength raw) (bytesLength compressedBytes)))
                        (compressed (+ (bytesLength header) (bytesLength compressedBytes)))
                        (uncompressed (+ (bytesLength header) (bytesLength raw)))]
                    (mt (fileAppend temp header)
                      ((err e) (err (str e)))
                      ((ok _)
                        (mt (fileAppend temp compressedBytes)
                          ((err e) (err (str e)))
                          ((ok _)
                            (mt (writeColumns! temp (listDrop columns 1) start count compression level (+ offset compressed))
                              ((err e) (err e))
                              ((ok rest)
                                (ok (listAppend
                                  (list (ChunkMeta :name (columnName column) :physical (physicalType column)
                                         :encoding (columnEncoding column) :values count :offset offset
                                         :compressed compressed :uncompressed uncompressed)) rest)))))))))))))))))

fn ! writeGroups! temp: String columns: (List ParquetColumn) start: Int64 total: Int64 groupSize: Int64 compression: String level: Int64 offset: Int64 groups: (List GroupMeta) -> (Result (List GroupMeta) String)
  (if (>= start total) (ok groups)
    (let [(count (min groupSize (- total start)))]
      (mt (writeColumns! temp columns start count compression level offset)
        ((err e) (err e))
        ((ok chunks)
          (writeGroups! temp columns (+ start count) total groupSize compression level
            (+ offset (chunkCompressedSum chunks))
            (listAppend groups (list (GroupMeta :chunks chunks :rows count))))))))

fn ! removeWriteTemp! temp: String cause: String -> (Result Unit String)
  (mt (pathRemove temp)
    ((err cleanup) (err (str cause "; temporary cleanup failed: " cleanup)))
    ((ok _) (err cause)))

fn ! writeFile! path: String columns: (List ParquetColumn) kv: (List (List String)) groupSize: Int64 compression: String level: Int64 total: Int64 -> (Result Unit String)
  (let [(temp (str path ".asl-parquet-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs)) ".tmp"))]
    (mt (fileWrite temp "PAR1")
      ((err e) (err e))
      ((ok _)
        (mt (writeGroups! temp columns 0 total groupSize compression level 4 (list))
          ((err e) (removeWriteTemp! temp e))
          ((ok groups)
            (let [(effectiveKv (if (= compression "zstd") (listAppend kv (list (list "asl.parquet.zstd.level" (stringFromInt64 level)))) kv))
                  (footer (parquetFooter! columns groups total compression effectiveKv))
                  (footerLength (bytesLength footer))
                  (lengthBytes (bytesAlloc 4))]
              (do
                (littlePut! lengthBytes 0 footerLength 4)
                (mt (fileAppend temp footer)
                  ((err e) (removeWriteTemp! temp (str e)))
                  ((ok _)
                    (mt (fileAppend temp lengthBytes)
                      ((err e) (removeWriteTemp! temp (str e)))
                      ((ok _)
                        (mt (fileAppend temp "PAR1")
                          ((err e) (removeWriteTemp! temp (str e)))
                          ((ok _)
                            (mt (pathRename temp path)
                              ((ok _) (ok ()))
                              ((err e) (removeWriteTemp! temp (str e)))))))))))))))))

fn ! parquetWrite path: String columns: (List ParquetColumn) options: (List (List String)) kv: (List (List String)) -> (Result Unit String)
  (let [(compression (optionValue options "compression" "zstd"))
        (levelText (optionValue options "level" "3"))
        (dictionary (optionValue options "dictionary" "false"))
        (groupText (optionValue options "rowGroupRows" "1000000"))
        (level (optionToResult (stringToInt64 levelText) "compression level must be an integer"))
        (groupRows (optionToResult (stringToInt64 groupText) "rowGroupRows must be an integer"))]
    (cond
      ((stringEmpty? path) (err "path must not be empty"))
      ((not (columnsValid? columns)) (err "invalid Parquet column: names, types, encoding and nonempty arrays are required"))
      ((not (metadataPairsValid? kv)) (err "key-value metadata entries must be string pairs"))
      ((metadataHasKey? kv "asl.parquet.zstd.level") (err "key-value metadata uses reserved key asl.parquet.zstd.level"))
      ((not (or (= compression "zstd") (= compression "none"))) (err "compression must be zstd or none"))
      ((not (or (= dictionary "false") (= dictionary "true"))) (err "dictionary must be true or false"))
      (else
        (mt level
          ((err e) (err e))
          ((ok levelValue)
            (mt groupRows
              ((err e) (err e))
              ((ok groupValue)
                (if (or (< levelValue 1) (> levelValue 22))
                  (err "compression level must be in 1..22")
                  (if (<= groupValue 0)
                    (err "rowGroupRows must be positive")
                    (if (not (= dictionary "false"))
                      (err "dictionary encoding is not supported")
                      (if (not (sameColumnLengths? columns (firstColumnCount columns)))
                        (err "Parquet columns must have the same number of rows")
                        (if (not (columnsDeltasValid? columns))
                          (err "DELTA_BINARY_PACKED values contain an overflowing INT64 delta")
                          (writeFile! path columns kv groupValue compression levelValue
                            (firstColumnCount columns))))))))))))))
