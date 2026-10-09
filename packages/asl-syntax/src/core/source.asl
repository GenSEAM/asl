(module asl-syntax/core/source
  :x [Source
      SourcePos
      makeSource
      sourceFromBytes
      sourceFromString
      sourcePath
      sourceBytes
      sourceLineStarts
      sourceHasBom
      sourceLength
      sourceLineCount
      sourceLineStart
      sourceLineEnd
      sourcePosAt
      sourceLineAt
      sourceByteColAt
      sourceCharColAt
      sourceOffsetAt
      sourceCharOffsetAt
      binaryKind
      binaryKindBytes
      sourceBinaryKind
      binaryKindFile!
      isBinary
      sourceIsBinary]
  :i [])

(schema SourcePos (:f line Int64) (:f byteCol Int64) (:f charCol Int64))

(schema Source (:f path String) (:f bytes Bytes) (:f lineStarts I64Array) (:f hasBom Bool))

fn makeSource path: String bytes: Bytes lineStarts: I64Array hasBom: Bool -> Source
  (Source :path path :bytes bytes :lineStarts lineStarts :hasBom hasBom)

fn sourcePath s: Source -> String
  s.path

fn sourceBytes s: Source -> Bytes
  s.bytes

fn sourceLineStarts s: Source -> I64Array
  s.lineStarts

fn sourceHasBom s: Source -> Bool
  s.hasBom

fn sourceLength s: Source -> Int64
  (bytesLength s.bytes)

fn sourceLineCount s: Source -> Int64
  (i64ArrayLen s.lineStarts)

fn checkBom bs: Bytes len: Int64 -> Bool
  (and (>= len 3)
       (= (bytesGet bs 0) 239)
       (= (bytesGet bs 1) 187)
       (= (bytesGet bs 2) 191))

fn listToI64Chunk xs: (List Int64) len: Int64 -> I64Array
  (i64ArrayGenerate len (fn [(i Int64)] -> Int64 (optionOr (listGet xs i) 0)))

fn scanLineStarts bs: Bytes len: Int64 idx: Int64 cur: (List Int64) curCount: Int64 chunks: (List I64Array) -> I64Array
  (if (>= idx len)
    (let [(finalChunks (if (> curCount 0)
                         (cons (listToI64Chunk (listReverse cur) curCount) chunks)
                         chunks))]
      (i64ArrayConcat (listReverse finalChunks)))
    (let [(b (bytesGet bs idx))]
      (cond
        ((= b 10)
         (let [(nextOff (+ idx 1))]
           (if (>= curCount 127)
             (let [(chunk (listToI64Chunk (listReverse (cons nextOff cur)) (+ curCount 1)))]
               (scanLineStarts bs len (+ idx 1) (list) 0 (cons chunk chunks)))
             (scanLineStarts bs len (+ idx 1) (cons nextOff cur) (+ curCount 1) chunks))))
        ((= b 13)
         (let [(isCrlf (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 10)))
               (nextOff (if isCrlf (+ idx 2) (+ idx 1)))
               (nextIdx (if isCrlf (+ idx 2) (+ idx 1)))]
           (if (>= curCount 127)
             (let [(chunk (listToI64Chunk (listReverse (cons nextOff cur)) (+ curCount 1)))]
               (scanLineStarts bs len nextIdx (list) 0 (cons chunk chunks)))
             (scanLineStarts bs len nextIdx (cons nextOff cur) (+ curCount 1) chunks))))
        (else
         (scanLineStarts bs len (+ idx 1) cur curCount chunks)))))

fn sourceFromBytes path: String bs: Bytes -> Source
  (let [(len (bytesLength bs))
        (bom (checkBom bs len))
        (ls (scanLineStarts bs len 0 (list 0) 1 (list)))]
    (Source :path path :bytes bs :lineStarts ls :hasBom bom))

fn sourceFromString path: String text: String -> Source
  (sourceFromBytes path (stringToBytes text))

fn sourceLineStart s: Source line: Int64 -> (Option Int64)
  (let [(ls s.lineStarts)
        (n (i64ArrayLen ls))]
    (if (or (< line 1) (> line n))
      (none)
      (some (i64ArrayGet ls (- line 1)))))

fn sourceLineEnd s: Source line: Int64 -> Int64
  (let [(ls s.lineStarts)
        (n (i64ArrayLen ls))
        (len (sourceLength s))]
    (if (< line n)
      (let [(nextStart (i64ArrayGet ls line))
            (bs s.bytes)]
        (if (and (>= nextStart 2)
                 (= (bytesGet bs (- nextStart 2)) 13)
                 (= (bytesGet bs (- nextStart 1)) 10))
          (- nextStart 2)
          (if (and (>= nextStart 1)
                   (let [(b (bytesGet bs (- nextStart 1)))]
                     (or (= b 10) (= b 13))))
            (- nextStart 1)
            nextStart)))
      len))

fn binarySearchLine ls: I64Array off: Int64 low: Int64 high: Int64 -> Int64
  (if (>= low high)
    low
    (let [(mid (+ low (/ (- high low) 2)))
          (start (i64ArrayGet ls mid))]
      (if (<= start off)
        (if (or (= (+ mid 1) (i64ArrayLen ls)) (> (i64ArrayGet ls (+ mid 1)) off))
          mid
          (binarySearchLine ls off (+ mid 1) high))
        (binarySearchLine ls off low (- mid 1)))))

fn utf8CharLen bs: Bytes len: Int64 pos: Int64 -> Int64
  (if (>= pos len)
    1
    (let [(b0 (bytesGet bs pos))]
      (cond
        ((< b0 128) 1)
        ((and (>= b0 194) (<= b0 223))
         (if (and (< (+ pos 1) len)
                  (let [(b1 (bytesGet bs (+ pos 1)))]
                    (and (>= b1 128) (<= b1 191))))
           2
           1))
        ((and (>= b0 224) (<= b0 239))
         (if (and (< (+ pos 2) len)
                  (let [(b1 (bytesGet bs (+ pos 1)))
                        (b2 (bytesGet bs (+ pos 2)))]
                    (and (>= b2 128)
                         (<= b2 191)
                         (cond
                           ((= b0 224) (and (>= b1 160) (<= b1 191)))
                           ((= b0 237) (and (>= b1 128) (<= b1 159)))
                           (else (and (>= b1 128) (<= b1 191)))))))
           3
           1))
        ((and (>= b0 240) (<= b0 244))
         (if (and (< (+ pos 3) len)
                  (let [(b1 (bytesGet bs (+ pos 1)))
                        (b2 (bytesGet bs (+ pos 2)))
                        (b3 (bytesGet bs (+ pos 3)))]
                    (and (>= b2 128)
                         (<= b2 191)
                         (>= b3 128)
                         (<= b3 191)
                         (cond
                           ((= b0 240) (and (>= b1 144) (<= b1 191)))
                           ((= b0 244) (and (>= b1 128) (<= b1 143)))
                           (else (and (>= b1 128) (<= b1 191)))))))
           4
           1))
        (else 1))))

fn countCharCols bs: Bytes len: Int64 pos: Int64 target: Int64 curCol: Int64 -> Int64
  (if (>= pos target)
    curCol
    (let [(k (utf8CharLen bs len pos))]
      (if (> (+ pos k) target)
        curCol
        (countCharCols bs len (+ pos k) target (+ curCol 1)))))

fn sourcePosAt s: Source offset: Int64 -> (Option SourcePos)
  (let [(len (sourceLength s))]
    (if (or (< offset 0) (> offset len))
      (none)
      (let [(ls s.lineStarts)
            (mid (binarySearchLine ls offset 0 (- (i64ArrayLen ls) 1)))
            (line (+ mid 1))
            (lineStart (i64ArrayGet ls mid))
            (byteCol (+ (- offset lineStart) 1))
            (charCol (countCharCols s.bytes len lineStart offset 1))]
        (some (SourcePos :line line :byteCol byteCol :charCol charCol)))))

fn sourceLineAt s: Source offset: Int64 -> (Option Int64)
  (mt (sourcePosAt s offset)
    ((some p) (some p.line))
    ((none) (none)))

fn sourceByteColAt s: Source offset: Int64 -> (Option Int64)
  (mt (sourcePosAt s offset)
    ((some p) (some p.byteCol))
    ((none) (none)))

fn sourceCharColAt s: Source offset: Int64 -> (Option Int64)
  (mt (sourcePosAt s offset)
    ((some p) (some p.charCol))
    ((none) (none)))

fn sourceOffsetAt s: Source line: Int64 byteCol: Int64 -> (Option Int64)
  (let [(ls s.lineStarts)
        (n (i64ArrayLen ls))]
    (if (or (< line 1) (> line n) (< byteCol 1))
      (none)
      (let [(lineStart (i64ArrayGet ls (- line 1)))
            (lineEnd (sourceLineEnd s line))
            (maxCol (+ (- lineEnd lineStart) 1))]
        (if (> byteCol maxCol)
          (none)
          (some (+ lineStart (- byteCol 1)))))))

fn stepCharOffset bs: Bytes len: Int64 lineEnd: Int64 pos: Int64 curCol: Int64 targetCol: Int64 -> (Option Int64)
  (if (= curCol targetCol)
    (some pos)
    (if (>= pos lineEnd)
      (none)
      (let [(k (utf8CharLen bs len pos))]
        (stepCharOffset bs len lineEnd (+ pos k) (+ curCol 1) targetCol))))

fn sourceCharOffsetAt s: Source line: Int64 charCol: Int64 -> (Option Int64)
  (let [(ls s.lineStarts)
        (n (i64ArrayLen ls))]
    (if (or (< line 1) (> line n) (< charCol 1))
      (none)
      (let [(lineStart (i64ArrayGet ls (- line 1)))
            (lineEnd (sourceLineEnd s line))]
        (stepCharOffset s.bytes (sourceLength s) lineEnd lineStart 1 charCol))))

fn checkNul bs: Bytes limit: Int64 idx: Int64 -> Bool
  (if (>= idx limit)
    false
    (if (= (bytesGet bs idx) 0)
      true
      (checkNul bs limit (+ idx 1))))

fn binaryKind bs: Bytes -> String
  (let [(len (bytesLength bs))]
    (cond
      ((and (>= len 4)
            (= (bytesGet bs 0) 207)
            (= (bytesGet bs 1) 250)
            (= (bytesGet bs 2) 237)
            (= (bytesGet bs 3) 254))
       "machO")
      ((and (>= len 4)
            (= (bytesGet bs 0) 206)
            (= (bytesGet bs 1) 250)
            (= (bytesGet bs 2) 237)
            (= (bytesGet bs 3) 254))
       "machO")
      ((and (>= len 4)
            (= (bytesGet bs 0) 254)
            (= (bytesGet bs 1) 237)
            (= (bytesGet bs 2) 250)
            (= (bytesGet bs 3) 207))
       "machO")
      ((and (>= len 4)
            (= (bytesGet bs 0) 254)
            (= (bytesGet bs 1) 237)
            (= (bytesGet bs 2) 250)
            (= (bytesGet bs 3) 206))
       "machO")
      ((and (>= len 4)
            (= (bytesGet bs 0) 202)
            (= (bytesGet bs 1) 254)
            (= (bytesGet bs 2) 186)
            (= (bytesGet bs 3) 190))
       "machOFat")
      ((and (>= len 4)
            (= (bytesGet bs 0) 127)
            (= (bytesGet bs 1) 69)
            (= (bytesGet bs 2) 76)
            (= (bytesGet bs 3) 70))
       "elf")
      ((and (>= len 4)
            (= (bytesGet bs 0) 0)
            (= (bytesGet bs 1) 97)
            (= (bytesGet bs 2) 115)
            (= (bytesGet bs 3) 109))
       "wasm")
      ((and (>= len 2)
            (= (bytesGet bs 0) 31)
            (= (bytesGet bs 1) 139))
       "gzip")
      ((and (>= len 4)
            (= (bytesGet bs 0) 80)
            (= (bytesGet bs 1) 75)
            (= (bytesGet bs 2) 3)
            (= (bytesGet bs 3) 4))
       "zip")
      ((and (>= len 8)
            (= (bytesGet bs 0) 137)
            (= (bytesGet bs 1) 80)
            (= (bytesGet bs 2) 78)
            (= (bytesGet bs 3) 71)
            (= (bytesGet bs 4) 13)
            (= (bytesGet bs 5) 10)
            (= (bytesGet bs 6) 26)
            (= (bytesGet bs 7) 10))
       "png")
      ((and (>= len 3)
            (= (bytesGet bs 0) 255)
            (= (bytesGet bs 1) 216)
            (= (bytesGet bs 2) 255))
       "jpeg")
      ((checkNul bs (if (< len 8192) len 8192) 0)
       (if (and (>= len 2)
                (= (bytesGet bs 0) 77)
                (= (bytesGet bs 1) 90))
         "pe"
         "binary"))
      (else "")))

fn binaryKindBytes bs: Bytes -> String
  (binaryKind bs)

fn sourceBinaryKind s: Source -> String
  (binaryKind s.bytes)

fn binaryKindFile! path: String -> (Result String String)
  (mt (fileReadBytes path)
    ((ok bs) (ok (binaryKind bs)))
    ((err e) (err e)))

fn isBinary bs: Bytes -> Bool
  (!= (binaryKind bs) "")

fn sourceIsBinary s: Source -> Bool
  (!= (sourceBinaryKind s) "")
