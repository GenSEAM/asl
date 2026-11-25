(module asl-parquet/tests/streamWriterTest
  :x [runTests]
  :i [(asl-parquet/reader :a r) (asl-parquet/writer :a pq)])

; (:m :ref D157 :do "read-back uses only the pure ASL reader; no python, pyarrow or other foreign reader")
fn dirPath -> String
  (str "/tmp/aslParquetStream-" (stringFromInt64 (procSelf)))

fn ! sweep! -> Bool
  (match (dirList (dirPath))
    ((err _) true)
    ((ok names)
      (do (map (fn [n] (pathRemove (str (dirPath) "/" n))) names)
          (pathRemove (dirPath))
          true)))

fn ! ck good: Bool -> Bool
  (if good true (do (sweep!) false))

fn ! tempDir! -> String
  (do
    (sweep!)
    (assert (ok? (dirCreate (dirPath))) "temp dir created")
    (dirPath))

fn tsAt i: Int64 -> Int64
  (+ 1000 (* i 3))

fn pxAt i: Int64 -> Float64
  (+ 0.25 (* (int64ToFloat64 i) 0.5))

fn ! groupColumns! base: Int64 n: Int64 -> (List pq/ParquetColumn)
  (list (pq/i64Column "ts" (i64ArrayGenerate n (fn [i] (tsAt (+ base i)))) "DELTA_BINARY_PACKED")
        (pq/f64Column "price" (f64ArrayGenerate n (fn [i] (pxAt (+ base i)))) "BYTE_STREAM_SPLIT"))

fn ! badNameColumns -> (List pq/ParquetColumn)
  (list (pq/i64Column "tsx" (i64ArrayGenerate 2 (fn [i] i)) "PLAIN")
        (pq/f64Column "price" (f64ArrayGenerate 2 (fn [i] (int64ToFloat64 i))) "PLAIN"))

fn ! badKindColumns -> (List pq/ParquetColumn)
  (list (pq/f64Column "ts" (f64ArrayGenerate 2 (fn [i] (int64ToFloat64 i))) "PLAIN")
        (pq/f64Column "price" (f64ArrayGenerate 2 (fn [i] (int64ToFloat64 i))) "PLAIN"))

fn indicesFrom i: Int64 n: Int64 -> (List Int64)
  (if (>= i n) (list) (cons i (indicesFrom (+ i 1) n)))

fn ! checkGroupAt! path: String rg: Int64 base: Int64 count: Int64 -> Bool
  (match (r/parquetOpen path)
    ((err e) (do (assert (ck false) e) true))
    ((ok h)
      (let [(ts (r/parquetReadI64 h "ts" rg))
            (px (r/parquetReadF64 h "price" rg))
            (okAll (fold (fn [acc i]
                     (if (and acc (and (= (i64ArrayGet ts i) (tsAt (+ base i)))
                                       (= (f64ArrayGet px i) (pxAt (+ base i)))))
                       true false))
                   true (indicesFrom 0 count)))]
        (do
          (assert (ck (= (i64ArrayLen ts) count)) "group ts length")
          (assert (ck (= (f64ArrayLen px) count)) "group price length")
          (assert (ck okAll) "group values match exactly")
          true))))

fn ! checkFileAt! path: String -> Bool
  (match (r/parquetOpen path)
    ((err e) (do (assert (ck false) e) true))
    ((ok h)
      (do
        (assert (ck (= (r/parquetNumRowGroups h) 3)) "3 row groups")
        (assert (ck (= (r/parquetNumRows h) 12)) "12 rows total")
        (assert (ck (= (r/parquetGroupRows h 0) 5)) "group 0 has 5 rows")
        (assert (ck (= (r/parquetGroupRows h 1) 4)) "group 1 has 4 rows")
        (assert (ck (= (r/parquetGroupRows h 2) 3)) "group 2 has 3 rows")
        (assert (ck (= (resultOr (r/parquetKvMetadata h "a") "") "1")) "kv a round-trips")
        (assert (ck (= (resultOr (r/parquetKvMetadata h "b") "") "2")) "kv b round-trips")
        true)))

fn ! closeAndCheck! w: pq/PqWriter path: String -> Bool
  (do
    (assert (ck (ok? (pq/parquetWriterClose! w))) "close writes the footer")
    (assert (ck (err? (pq/parquetWriterClose! w))) "closing twice is an error")
    (assert (ck (err? (pq/parquetWriterAppend! w (groupColumns! 12 1)))) "append after close is an error")
    (checkFileAt! path)
    (checkGroupAt! path 0 0 5)
    (checkGroupAt! path 1 5 4)
    (checkGroupAt! path 2 9 3))

fn ! appendThree! w2: pq/PqWriter path: String -> Bool
  (let [(a3 (pq/parquetWriterAppend! w2 (groupColumns! 9 3)))]
    (do
      (assert (ck (ok? a3)) "group 2 appends")
      (closeAndCheck! (resultOr a3 w2) path)))

fn ! appendTwo! w1: pq/PqWriter path: String -> Bool
  (let [(a2 (pq/parquetWriterAppend! w1 (groupColumns! 5 4)))]
    (do
      (assert (ck (ok? a2)) "group 1 appends after rejected appends")
      (appendThree! (resultOr a2 w1) path)))

fn ! appendRest! w1: pq/PqWriter path: String -> Bool
  (let [(badName (pq/parquetWriterAppend! w1 (badNameColumns)))
        (badKind (pq/parquetWriterAppend! w1 (badKindColumns)))]
    (do
      (assert (ck (err? badName)) "wrong column name is an error")
      (assert (ck (err? badKind)) "wrong column kind is an error")
      (appendTwo! w1 path)))

fn ! appendGroups! w0: pq/PqWriter path: String -> Bool
  (let [(a1 (pq/parquetWriterAppend! w0 (groupColumns! 0 5)))]
    (do
      (assert (ck (ok? a1)) "group 0 appends")
      (appendRest! (resultOr a1 w0) path)))

fn streamOptions compression: String -> (List (List String))
  (list (list "compression" compression) (list "pageRows" "2"))

fn ! testStream! dir: String compression: String -> Bool
  (let [(path (str dir "/stream-" compression ".parquet"))
        (opened (pq/parquetWriterOpen! path (list "ts" "price") (list "I64" "F64") (streamOptions compression) (list (list "a" "1") (list "b" "2"))))]
    (do
      (assert (ck (ok? opened)) "open succeeds")
      (match opened
        ((err e) (do (assert (ck false) e) true))
        ((ok w0) (appendGroups! w0 path)))))

fn ! runTests -> Bool
  (let [(dir (tempDir!))]
    (do
      (testStream! dir "none")
      (testStream! dir "zstd")
      (sweep!)
      (assert (not (fileExists? (dirPath))) "temp dir removed")
      true))
