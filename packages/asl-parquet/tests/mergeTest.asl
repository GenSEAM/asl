(module asl-parquet/tests/mergeTest
  :x [runTests]
  :i [(asl-parquet/merge :a mg) (asl-parquet/writer :a pq)])

; (:m :ref PQ-MERGE :do "expected order is computed by sorting (ts, source, row) keys, independent of the merge; fixtures are written into a temp dir this test creates and removes")
fn dirPath -> String
  (str "/tmp/aslParquetMerge-" (stringFromInt64 (procSelf)))

; (:m :ref PQ-TEST-CLEAN :do "a failing check sweeps the fixture dir before its assert aborts the run, so a red test leaves nothing in /tmp")
fn ! sweep! -> Bool
  (match (dirList (dirPath))
    ((err _) true)
    ((ok names)
      (do (map (fn [n] (pathRemove (str (dirPath) "/" n))) names)
          (pathRemove (dirPath))
          true)))

fn ! ck ok: Bool -> Bool
  (if ok true (do (sweep!) false))

fn ! tempDir! -> String
  (do (sweep!)
      (assert (ok? (dirCreate (dirPath))) "temp dir created")
      (dirPath))

fn ! writeSourceP! path: String stamps: (List Int64) source: Int64 pageRows: String -> Bool
  (let [(n (listLength stamps))
        (at (fn [(i Int64)] -> Int64 (optionOr (listGet stamps i) 0)))
        (cols (list (pq/i64Column "ts" (i64ArrayGenerate n at) "DELTA_BINARY_PACKED")
                    (pq/i64Column "id" (i64ArrayGenerate n (fn [(i Int64)] -> Int64 (+ (* i 10) source))) "PLAIN")
                    (pq/f64Column "px" (f64ArrayGenerate n (fn [(i Int64)] -> Float64 (* 0.5 (int64ToFloat64 (at i))))) "BYTE_STREAM_SPLIT")
                    (pq/i8Column "side" (i8ArrayGenerate n (fn [(i Int64)] -> Int64 (- (mod i 3) 1))) "PLAIN")))
        (w (pq/parquetWrite path cols (list (list "compression" "none") (list "rowGroupRows" "3") (list "pageRows" pageRows)) (list)))]
    (do (assert (ck (ok? w)) (str "source " (stringFromInt64 source) " writes")) true))

fn ! writeSource! path: String stamps: (List Int64) source: Int64 -> Bool
  (writeSourceP! path stamps source "2")

fn keyOf ts: Int64 source: Int64 row: Int64 -> Int64
  (+ (* ts 10000) (+ (* source 100) row))

fn keysFor stamps: (List Int64) source: Int64 -> (List Int64)
  (map (fn [(q (Pair Int64 Int64))] -> Int64 (keyOf (pairSecond q) source (pairFirst q))) (zipIndex stamps 0))

fn expectedAll sources: (List (List Int64)) source: Int64 -> (List Int64)
  (match (listHead sources)
    ((none) (list))
    ((some stamps) (listAppend (keysFor stamps source) (expectedAll (optionOr (listTail sources) (list)) (+ source 1)))))

fn expectedKeys sources: (List (List Int64)) -> (List Int64)
  (listSort (expectedAll sources 0))

fn zipIndex xs: (List Int64) i: Int64 -> (List (Pair Int64 Int64))
  (match (listHead xs)
    ((none) (list))
    ((some x) (cons (pair i x) (zipIndex (optionOr (listTail xs) (list)) (+ i 1)))))

fn ! drain! m: Any acc: (List Int64) bound: Int64 maxWindow: Int64 -> (Result (List Int64) String)
  (match (mg/parquetMergeNext m)
    ((err e) (err e))
    ((ok next)
      (match next
        ((none) (ok (listReverse acc)))
        ((some p)
          (let [(row (pairFirst p))
                (id (optionOr (listHead row.ints) -1))
                (px (optionOr (listHead row.floats) -1.0))]
            (do
              (assert (ck (<= (mg/parquetMergeWindowRows (pairSecond p)) bound)) "window never exceeds chunkRows")
              (assert (ck (= px (* 0.5 (int64ToFloat64 row.ts)))) "float column follows the row")
              (assert (ck (= id (+ (* row.row 10) row.source))) "int column follows the row")
              (assert (ck (= (listLength row.ints) 2)) "two int columns")
              (drain! (pairSecond p) (cons (keyOf row.ts row.source row.row) acc) bound maxWindow)))))))

fn ! testMerge! dir: String chunk: Int64 -> Bool
  (let [(a (list 1 4 4 7 10 13 16))
        (b (list 2 4 7 7 11))
        (c (list))
        (pa (str dir "/a.parquet")) (pb (str dir "/b.parquet")) (pc (str dir "/c.parquet"))]
    (do
      (writeSource! pa a 0)
      (writeSource! pb b 1)
      (writeSource! pc c 2)
      (match (mg/parquetMergeOpen (list pa pb pc) "ts" (list "id" "side") (list "px") chunk)
        ((err e) (do (assert (ck false) (str "merge opens: " e)) true))
        ((ok m)
          (do
            (assert (ck (= (mg/parquetMergeSourceCount m) 3)) "three sources")
            (assert (ck (<= (mg/parquetMergeWindowRows m) chunk)) "initial windows are bounded")
            (match (drain! m (list) chunk 0)
              ((err e) (do (assert (ck false) e) true))
              ((ok keys)
                (do
                  (assert (ck (= (listLength keys) 12)) "all 12 rows come out")
                  (assert (ck (= keys (expectedKeys (list a b c)))) "order is (ts, source, row) with equal timestamps lower source first")
                  true))))))))

fn ! testTake! dir: String -> Bool
  (match (mg/parquetMergeOpen (list (str dir "/a.parquet") (str dir "/b.parquet")) "ts" (list) (list) 2)
    ((err e) (do (assert (ck false) e) true))
    ((ok m)
      (match (mg/parquetMergeTake m 5)
        ((err e) (do (assert (ck false) e) true))
        ((ok t)
          (do
            (assert (ck (= (listLength (pairFirst t)) 5)) "take 5")
            (match (mg/parquetMergeTake (pairSecond t) 100)
              ((err e) (do (assert (ck false) e) true))
              ((ok rest) (do (assert (ck (= (listLength (pairFirst rest)) 7)) "the rest is 7 rows") true))))))))

fn ! testErrors! dir: String -> Bool
  (let [(bad (str dir "/bad.parquet"))
        (cut (str dir "/cut.parquet"))]
    (do
      (writeSource! bad (list 5 3 9 9 9 9 9) 0)
      (assert (ck (err? (mg/parquetMergeOpen (list bad) "ts" (list) (list) 2)))
        "a decreasing timestamp in the first window is an error at open")
      (writeSource! bad (list 1 2 3 4 5 6 7 8 0) 0)
      (match (mg/parquetMergeOpen (list bad) "ts" (list) (list) 2)
        ((err e) (do (assert (ck false) e) true))
        ((ok m)
          (do (assert (ck (err? (mg/parquetMergeTake m 100))) "a decreasing timestamp in a later window is an error while merging") true)))
      (assert (ck (err? (mg/parquetMergeOpen (list (str dir "/a.parquet")) "nope" (list) (list) 2))) "unknown ts column is an error")
      (assert (ck (err? (mg/parquetMergeOpen (list (str dir "/a.parquet")) "ts" (list) (list "id") 2))) "an int column asked as float is an error")
      (assert (ck (err? (mg/parquetMergeOpen (list (str dir "/a.parquet")) "ts" (list) (list) 0))) "chunkRows 0 is an error")
      (assert (ck (err? (mg/parquetMergeOpen (list (str dir "/missing.parquet")) "ts" (list) (list) 2))) "a missing file is an error")
      (match (fileReadRange (str dir "/a.parquet") 0 40)
        ((err e) (do (assert (ck false) e) true))
        ((ok head)
          (do (assert (ck (ok? (fileWrite cut head))) "truncated copy written")
              (assert (ck (err? (mg/parquetMergeOpen (list (str dir "/a.parquet") cut) "ts" (list) (list) 2))) "a truncated source is an error")
              true)))))

; (:m :ref PQ-MERGE-DECODES :do "files with one page per group (as other writers produce): 7 and 5 rows in groups of 3 are 3 + 2 groups, 4 columns each, chunkRows 2 would re-decode a group 2 to 3 times without the cursor; the count is exactly one decode per group and column")
fn ! testDecodes! dir: String -> Bool
  (let [(pa (str dir "/sa.parquet")) (pb (str dir "/sb.parquet"))]
    (do
      (writeSourceP! pa (list 1 4 4 7 10 13 16) 0 "0")
      (writeSourceP! pb (list 2 4 7 7 11) 1 "0")
      (match (mg/parquetMergeOpen (list pa pb) "ts" (list "id" "side") (list "px") 2)
        ((err e) (do (assert (ck false) e) true))
        ((ok m)
          (match (mg/parquetMergeTake m 100)
            ((err e) (do (assert (ck false) e) true))
            ((ok t)
              (do
                (assert (ck (= (listLength (pairFirst t)) 12)) "all rows merged")
                (assert (ck (= (mg/parquetMergeDecodes (pairSecond t)) 20)) "5 groups x 4 columns = 20 decodes, not one per refill")
                true)))))))

fn ! runTests -> Bool
  (let [(dir (tempDir!))]
    (do
      (testMerge! dir 2)
      (testMerge! dir 1000)
      (testTake! dir)
      (testErrors! dir)
      (testDecodes! dir)
      (sweep!)
      (assert (not (fileExists? (dirPath))) "temp dir removed")
      true))
