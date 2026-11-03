(module asl-parquet/tests/windowTest
  :x [runTests]
  :i [(asl-parquet/reader :a rd)])

; (:m :ref PQ-WINDOW-SCAN :do "expected group ranges come from pyarrow row_group(g).column(0).statistics on the fixture: group 0 1782864090013919..1783010805663592, group 1 1783010940814814..1783212467982568, group 2 1783212947923969..1783315035412213; the row counts of a window are compared with reading every group and filtering, so pruning is checked against the answer it must not change")
fn fixture -> String
  "tests/acceptance/r1Host/fixtures/parquet/seiSpotDeals10k-zstdPageV2.parquet"

fn inWindow values: I64Array index: Int64 lo: Int64 hi: Int64 -> Int64
  (if (>= index (i64ArrayLen values)) 0
    (+ (if (and (>= (i64ArrayGet values index) lo) (< (i64ArrayGet values index) hi)) 1 0) (inWindow values (+ index 1) lo hi)))

fn ! countFull h: Any group: Int64 lo: Int64 hi: Int64 -> Int64
  (if (>= group (rd/parquetNumRowGroups h)) 0
    (+ (inWindow (rd/parquetReadI64 h "tsUs" group) 0 lo hi) (countFull h (+ group 1) lo hi)))

fn ! countPruned h: Any groups: (List Int64) lo: Int64 hi: Int64 -> Int64
  (fold (fn [(acc Int64) (group Int64)] -> Int64
          (let [(values (rd/parquetReadI64 h "tsUs" group))]
            (+ acc (- (rd/parquetLowerBound values hi) (rd/parquetLowerBound values lo)))))
        0 groups)

fn ! checkWindow! h: Any lo: Int64 hi: Int64 groups: (List Int64) rows: Int64 -> Bool
  (let [(found (rd/parquetWindowGroups h "tsUs" lo hi))]
    (do
      (assert (= found groups) (str "window " (stringFromInt64 lo) ".." (stringFromInt64 hi) " keeps groups " (stringJoin (map stringFromInt64 found) ",")))
      (assert (= (countFull h 0 lo hi) rows) (str "full read counts " (stringFromInt64 rows) " rows in the window"))
      (assert (= (countPruned h found lo hi) rows) "pruned read counts the same rows as the full read")
      true))

fn ! runTests -> Bool
  (match (rd/parquetOpen (fixture))
    ((err e) (assert false e))
    ((ok h)
      (do
        (assert (= (rd/parquetColumnRange h "tsUs" 1) (some (pair 1783010940814814 1783212467982568))) "group 1 range comes from the footer")
        (assert (= (rd/parquetColumnRange h "price" 0) (none)) "a double column has no Int64 range")
        (assert (= (rd/parquetColumnRange h "side" 0) (none)) "an int32 column has no Int64 range")
        (assert (= (rd/parquetWindowGroups h "price" 0 1) (list 0 1 2)) "a column without a range prunes nothing")
        (checkWindow! h 1783100000000000 1783200000000000 (list 1) 1301)
        (checkWindow! h 1783000000000000 1783020000000000 (list 0 1) 786)
        (checkWindow! h 1783212500000000 1783212900000000 (list) 0)
        (checkWindow! h 1783315035412214 1790000000000000 (list) 0)
        (checkWindow! h 0 1782864090013919 (list) 0)
        (checkWindow! h 0 9000000000000000 (list 0 1 2) 10000)
        (checkWindow! h 1783010805663592 1783010940814814 (list 0) 1)
        (checkWindow! h 1783010805663593 1783010940814814 (list) 0)
        (assert (= (rd/parquetLowerBound (i64ArrayGenerate 5 (fn [i] (* i 10))) 25) 3) "lower bound between values")
        (assert (= (rd/parquetLowerBound (i64ArrayGenerate 5 (fn [i] (* i 10))) 20) 2) "lower bound on a value")
        (assert (= (rd/parquetLowerBound (i64ArrayGenerate 5 (fn [i] (* i 10))) -1) 0) "lower bound before all")
        (assert (= (rd/parquetLowerBound (i64ArrayGenerate 5 (fn [i] (* i 10))) 99) 5) "lower bound after all")
        true)))
