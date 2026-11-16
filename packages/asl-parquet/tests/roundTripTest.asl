(module asl-parquet/tests/roundTripTest
  :x [runTests]
  :i [(asl-parquet/reader :a r) (asl-parquet/writer :a pq)])

; (:m :ref PQ-ROUNDTRIP :do "fixtures live in a directory this test creates and removes; no foreign reader is needed, pyarrow read-back is a manual check")
fn dirPath -> String
  (str "/tmp/aslParquetRt-" (stringFromInt64 (procSelf)))

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

fn tsAt i: Int64 -> Int64
  (+ 1000 (* i 3))

fn pxAt i: Int64 -> Float64
  (+ 0.25 (* (int64ToFloat64 i) 0.5))

fn sideAt i: Int64 -> Int64
  (- (mod i 3) 1)

fn ! columns! n: Int64 -> (List ParquetColumn)
  (list (pq/i64Column "ts" (i64ArrayGenerate n (fn [i] (tsAt i))) "DELTA_BINARY_PACKED")
        (pq/f64Column "px" (f64ArrayGenerate n (fn [i] (pxAt i))) "BYTE_STREAM_SPLIT")
        (pq/i8Column "side" (i8ArrayGenerate n (fn [i] (sideAt i))) "PLAIN"))

fn opts compression: String groupRows: Int64 pageRows: Int64 -> (List (List String))
  (list (list "compression" compression) (list "rowGroupRows" (stringFromInt64 groupRows)) (list "pageRows" (stringFromInt64 pageRows)))

fn ! checkRange! h: Any rg: Int64 base: Int64 start: Int64 count: Int64 -> Bool
  (let [(ts (r/parquetReadRangeI64 h "ts" rg start count))
        (px (r/parquetReadRangeF64 h "px" rg start count))
        (sd (r/parquetReadRangeI8 h "side" rg start count))]
    (match ts
      ((err e) (do (assert (ck false) (str "ts range failed: " e)) true))
      ((ok t)
        (match px
          ((err e) (do (assert (ck false) (str "px range failed: " e)) true))
          ((ok p)
            (match sd
              ((err e) (do (assert (ck false) (str "side range failed: " e)) true))
              ((ok s)
                (do
                  (assert (ck (and (= (i64ArrayLen t) count) (and (= (f64ArrayLen p) count) (= (i8ArrayLen s) count)))) "range lengths")
                  (assert (ck (= 1 (i64ArrayFold (fn [acc i] (if (and (= acc 1) (and (= (i64ArrayGet t i) (tsAt (+ base (+ start i)))) (and (= (f64ArrayGet p i) (pxAt (+ base (+ start i)))) (= (i8ArrayGet s i) (sideAt (+ base (+ start i))))))) 1 0)) 1 (i64ArrayGenerate count (fn [i] i)))))
                    (str "range " (stringFromInt64 start) "+" (stringFromInt64 count) " of group " (stringFromInt64 rg) " matches")))
                true)))))))

fn ! testEmpty! dir: String -> Bool
  (let [(path (str dir "/empty.parquet"))
        (w (pq/parquetWrite path (columns! 0) (opts "none" 10 0) (list (list "k" "v"))))]
    (do
      (assert (ck (ok? w)) "empty file writes")
      (match (r/parquetOpen path)
        ((err e) (do (assert (ck false) (str "empty file opens: " e)) true))
        ((ok h)
          (do
            (assert (ck (= (r/parquetNumRows h) 0)) "empty file has 0 rows")
            (assert (ck (= (r/parquetNumRowGroups h) 0)) "empty file has 0 groups")
            (assert (ck (= (r/parquetColumnType h "px") "double")) "empty file keeps the schema")
            (assert (ck (= (resultOr (r/parquetKvMetadata h "k") "") "v")) "empty file keeps metadata")
            true)))))

fn ! testOneRow! dir: String -> Bool
  (let [(path (str dir "/one.parquet"))
        (w (pq/parquetWrite path (columns! 1) (opts "none" 10 0) (list)))]
    (do
      (assert (ck (ok? w)) "one-row file writes")
      (match (r/parquetOpen path)
        ((err e) (do (assert (ck false) e) true))
        ((ok h)
          (do
            (assert (ck (= (r/parquetNumRows h) 1)) "one row")
            (assert (ck (= (r/parquetGroupRows h 0) 1)) "one row in group 0")
            (assert (ck (= (r/parquetGroupRows h 1) -1)) "no group 1")
            (checkRange! h 0 0 0 1))))))

fn ! testGroups! dir: String compression: String -> Bool
  (let [(path (str dir "/groups-" compression ".parquet"))
        (w (pq/parquetWrite path (columns! 25) (opts compression 10 4) (list (list "a" "1") (list "b" "2"))))]
    (do
      (assert (ck (ok? w)) (str "multi-group file writes " compression))
      (match (r/parquetOpen path)
        ((err e) (do (assert (ck false) e) true))
        ((ok h)
          (do
            (assert (ck (= (r/parquetNumRows h) 25)) "25 rows")
            (assert (ck (= (r/parquetNumRowGroups h) 3)) "3 groups of 10, 10, 5")
            (assert (ck (= (r/parquetGroupRows h 2) 5)) "last group has 5 rows")
            (assert (ck (= (resultOr (r/parquetKvMetadata h "b") "") "2")) "metadata b")
            (assert (ck (= (i64ArraySum (r/parquetReadI64 h "ts" 1)) (+ (* 10 1000) (* 3 (+ 100 (* 45 1)))))) "whole-group read of group 1 sums")
            (assert (ck (checkRange! h 0 0 0 10)) "whole group 0")
            (assert (ck (checkRange! h 1 10 0 4)) "first page of group 1")
            (assert (ck (checkRange! h 1 10 4 4)) "second page of group 1")
            (assert (ck (checkRange! h 1 10 3 2)) "range across a page boundary")
            (assert (ck (checkRange! h 1 10 8 2)) "last page of group 1")
            (assert (ck (checkRange! h 1 10 9 1)) "last row of group 1")
            (assert (ck (checkRange! h 2 20 4 1)) "last row of the file")
            (assert (ck (checkRange! h 2 20 5 0)) "empty range at the group end")
            (assert (ck (checkRange! h 0 0 2 7)) "range across two page boundaries")
            (assert (ck (err? (r/parquetReadRangeI64 h "ts" 0 5 6))) "range beyond the group is an error")
            (assert (ck (err? (r/parquetReadRangeI64 h "ts" 3 0 1))) "group outside the file is an error")
            (assert (ck (err? (r/parquetReadRangeI64 h "ts" 0 -1 1))) "negative start is an error")
            (assert (ck (err? (r/parquetReadRangeI64 h "px" 0 0 1))) "wrong type is an error")
            (assert (ck (err? (r/parquetReadRangeI64 h "nope" 0 0 1))) "unknown column is an error")
            true)))))

fn ! testSinglePage! dir: String -> Bool
  (let [(path (str dir "/single.parquet"))
        (w (pq/parquetWrite path (columns! 12) (opts "none" 12 0) (list)))]
    (match (r/parquetOpen path)
      ((err e) (do (assert (ck false) e) true))
      ((ok h) (do (assert (ck (ok? w)) "single-page file writes") (checkRange! h 0 0 5 4)))))

fn ! prefix! path: String n: Int64 target: String -> Bool
  (match (fileReadRange path 0 n)
    ((err e) (do (assert (ck false) e) true))
    ((ok b) (ok? (fileWrite target b))))

fn ! testTruncated! dir: String -> Bool
  (let [(path (str dir "/groups-none.parquet"))
        (size (resultOr (fileSize path) 0))
        (cut (str dir "/cut.parquet"))]
    (do
      (assert (ck (> size 100)) "source file exists")
      (assert (ck (and (prefix! path (- size 3) cut) (err? (r/parquetOpen cut)))) "tail cut by 3 bytes is an error")
      (assert (ck (and (prefix! path (/ size 2) cut) (err? (r/parquetOpen cut)))) "half a file is an error")
      (assert (ck (and (prefix! path 7 cut) (err? (r/parquetOpen cut)))) "7 bytes is an error")
      (assert (ck (and (prefix! path 0 cut) (err? (r/parquetOpen cut)))) "0 bytes is an error")
      (match (fileReadBytes path)
        ((err e) (do (assert (ck false) e) true))
        ((ok b)
          (do
            (bytesSet b 4 255)
            (assert (ck (and (ok? (fileWrite cut b)) (err? (r/parquetOpen cut)))) "corrupt first page header is an error")
            true)))))

; (:m :ref PQ-OVERFLOW :do "n=300, ts 0 except rows 120..149; blocks of 128 cut from the column start pass the old whole-column check, blocks cut at the page or group boundary do not, so the check runs on exactly the page the encoder emits")
fn ! testDeltaOverflow! dir: String -> Bool
  (let [(big 6917529027641081856)
        (ts (i64ArrayGenerate 300 (fn [(i Int64)] -> Int64 (if (and (>= i 120) (< i 150)) big 0))))
        (cols (list (pq/i64Column "ts" ts "DELTA_BINARY_PACKED")))
        (byPage (pq/parquetWrite (str dir "/ovPage.parquet") cols (opts "none" 1000 100) (list)))
        (byGroup (pq/parquetWrite (str dir "/ovGroup.parquet") cols (opts "none" 100 0) (list)))
        (plain (pq/parquetWrite (str dir "/ovPlain.parquet") (list (pq/i64Column "ts" ts "PLAIN")) (opts "none" 100 100) (list)))]
    (do
      (assert (ck (err? byPage)) "overflow inside a page is an error, not a trap (pageRows 100)")
      (assert (ck (err? byGroup)) "overflow inside a row group is an error, not a trap (rowGroupRows 100, one page)")
      (assert (ck (ok? plain)) "the same values as PLAIN write")
      (assert (ck (not (fileExists? (str dir "/ovPage.parquet")))) "a failed write leaves no file")
      true))

; (:m :ref PQ-HEADER :do "page 1 header of a 1 column PLAIN none file starts at byte 4: 15 00 15 20 15 20 2c 15 04, so byte 12 is num_values zigzag (4 = 2 values); 2 turns it into 1")
fn ! testUnderstatedHeader! dir: String -> Bool
  (let [(path (str dir "/under.parquet"))
        (w (pq/parquetWrite path (list (pq/i64Column "ts" (i64ArrayGenerate 4 (fn [(i Int64)] -> Int64 (+ 100 i))) "PLAIN")) (opts "none" 4 2) (list)))]
    (do
      (assert (ck (ok? w)) "fixture writes")
      (match (fileReadBytes path)
        ((err e) (do (assert (ck false) e) true))
        ((ok b)
          (do
            (assert (ck (= (bytesGet b 12) 4)) "page 1 num_values byte is where the fixture expects it")
            (match (r/parquetOpen path)
              ((err e) (do (assert (ck false) e) true))
              ((ok good)
                (do
                  (assert (ck (ok? (r/parquetReadRangeI64 good "ts" 0 1 1))) "intact file: range 1+1 reads")
                  (bytesSet b 12 2)
                  (assert (ck (ok? (fileWrite path b))) "header patched")
                  (match (r/parquetOpen path)
                    ((err _) (do (assert (ck true) "open may already refuse it") true))
                    ((ok bad)
                      (do
                        (assert (ck (err? (r/parquetReadRangeI64 bad "ts" 0 1 1))) "understated num_values is an error for a range read")
                        (assert (ck (err? (r/parquetCursorI64 bad "ts" 0))) "and for a cursor")
                        true)))))))))))

; (:m :ref PQ-CURSOR :do "decodes counts pages and dictionaries decoded; a group with one page costs one decode for any number of small reads, a group of 3 pages costs 3")
fn ! testCursor! dir: String -> Bool
  (let [(one (pq/parquetWrite (str dir "/curOne.parquet") (columns! 12) (opts "none" 12 0) (list)))
        (three (pq/parquetWrite (str dir "/curThree.parquet") (columns! 12) (opts "none" 12 4) (list)))]
    (do
      (assert (ck (and (ok? one) (ok? three))) "cursor fixtures write")
      (match (r/parquetOpen (str dir "/curOne.parquet"))
        ((err e) (do (assert (ck false) e) true))
        ((ok h1)
          (match (r/parquetOpen (str dir "/curThree.parquet"))
            ((err e) (do (assert (ck false) e) true))
            ((ok h3)
              (match (r/parquetCursorI64 h1 "ts" 0)
                ((err e) (do (assert (ck false) e) true))
                ((ok c0)
                  (match (r/parquetCursorReadI64 c0 0 2)
                    ((err e) (do (assert (ck false) e) true))
                    ((ok p1)
                      (match (r/parquetCursorReadI64 (pairSecond p1) 2 2)
                        ((err e) (do (assert (ck false) e) true))
                        ((ok p2)
                          (match (r/parquetCursorReadI64 (pairSecond p2) 10 2)
                            ((err e) (do (assert (ck false) e) true))
                            ((ok p3)
                              (do
                                (assert (ck (= (i64ArrayGet (pairFirst p3) 1) (tsAt 11))) "cursor reads the right rows")
                                (assert (ck (= (r/parquetCursorDecodes (pairSecond p3)) 1)) "single-page group: 3 reads, 1 decode")
                                (assert (ck (= (i64ArrayGet (pairFirst (optionOr (resultToOption (r/parquetCursorReadI64 (pairSecond p3) 0 1)) (pair (i64ArrayGenerate 1 (fn [(i Int64)] -> Int64 -1)) (pairSecond p3)))) 0) (tsAt 0))) "inside the cached page an earlier row is still served")
                                (assert (ck (err? (r/parquetCursorReadI64 (pairSecond p3) 11 2))) "a cursor read past the group is an error")
                                (match (r/parquetCursorI64 h3 "ts" 0)
                                  ((err e) (do (assert (ck false) e) true))
                                  ((ok d0)
                                    (match (r/parquetCursorReadI64 d0 0 2)
                                      ((err e) (do (assert (ck false) e) true))
                                      ((ok q1)
                                        (match (r/parquetCursorReadI64 (pairSecond q1) 2 2)
                                          ((err e) (do (assert (ck false) e) true))
                                          ((ok q2)
                                            (match (r/parquetCursorReadI64 (pairSecond q2) 4 8)
                                              ((err e) (do (assert (ck false) e) true))
                                              ((ok q3)
                                                (do
                                                  (assert (ck (err? (r/parquetCursorReadI64 (pairSecond q3) 0 1))) "a cursor does not read backwards past its page")
                                                  (assert (ck (= (r/parquetCursorDecodes (pairSecond q3)) 3)) "three pages: 3 decodes for rows 0..11, none repeated")
                                                  true))))))))))))))))))))))))

fn ! runTests -> Bool
  (let [(dir (tempDir!))]
    (do
      (testEmpty! dir)
      (testOneRow! dir)
      (testGroups! dir "none")
      (testGroups! dir "zstd")
      (testSinglePage! dir)
      (testTruncated! dir)
      (testDeltaOverflow! dir)
      (testUnderstatedHeader! dir)
      (testCursor! dir)
      (sweep!)
      (assert (not (fileExists? (dirPath))) "temp dir removed")
      true))
