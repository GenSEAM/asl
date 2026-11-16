(module asl-parquet/merge
  :x [parquetMergeDecodes MergeRow parquetMergeOpen parquetMergeNext parquetMergeTake parquetMergeSourceCount parquetMergeWindowRows]
  :i [(asl-parquet/reader :a r)])

; (:m :ref PQ-MERGE :do "k-way merge of parquet files by an Int64 timestamp column; every source is a window of chunkRows rows per column read with parquetReadRange*, so memory is k * chunkRows * (1 + columns) * 8 bytes plus one decoded page per refill, never a file; ties on ts go to the lower source index (position in paths), then to file order; a source whose ts decreases is an error, not a silent misorder")
(schema MergeRow (:f source Int64) (:f ts Int64) (:f row Int64) (:f ints (List Int64)) (:f floats (List Float64)))

(schema MergeSrc (:f file Any) (:f group Int64) (:f loaded Int64) (:f ts I64Array) (:f ints (List I64Array)) (:f floats (List F64Array)) (:f pos Int64) (:f base Int64) (:f last Int64) (:f hasLast Bool) (:f tsCur Any) (:f intCurs (List Any)) (:f floatCurs (List Any)) (:f isOpen Bool) (:f decoded Int64))

(schema Merge (:f srcs (List MergeSrc)) (:f tsName String) (:f intNames (List String)) (:f floatNames (List String)) (:f chunkRows Int64))

fn mgSorted? ts: I64Array i: Int64 prev: Int64 -> Bool
  (if (>= i (i64ArrayLen ts)) true
    (let [(v (i64ArrayGet ts i))]
      (if (< v prev) false (mgSorted? ts (+ i 1) v))))

fn ! mgOpenCurs file: Any names: (List String) rg: Int64 -> (Result (List Any) String)
  (match (listHead names)
    ((none) (ok (list)))
    ((some n)
      (match (if (= (r/parquetColumnType file n) "double") (r/parquetCursorF64 file n rg) (if (= (r/parquetColumnType file n) "int8") (r/parquetCursorI8 file n rg) (r/parquetCursorI64 file n rg)))
        ((err e) (err e))
        ((ok c)
          (match (mgOpenCurs file (optionOr (listTail names) (list)) rg)
            ((err e) (err e))
            ((ok rest) (ok (cons c rest))))))))

fn ! mgReadInts file: Any names: (List String) curs: (List Any) start: Int64 count: Int64 -> (Result (Pair (List I64Array) (List Any)) String)
  (match (listHead names)
    ((none) (ok (pair (list) (list))))
    ((some n)
      (let [(cur (listHead curs))
            (got (match cur
                   ((none) (err "ERR_MERGE: cursor missing"))
                   ((some cu)
                     (if (= (r/parquetColumnType file n) "int8")
                       (match (r/parquetCursorReadI8 cu start count)
                         ((err e) (err e))
                         ((ok p) (ok (pair (i64ArrayGenerate count (fn [(i Int64)] -> Int64 (i8ArrayGet (pairFirst p) i))) (pairSecond p)))))
                       (r/parquetCursorReadI64 cu start count)))))]
        (match got
          ((err e) (err e))
          ((ok p)
            (match (mgReadInts file (optionOr (listTail names) (list)) (optionOr (listTail curs) (list)) start count)
              ((err e) (err e))
              ((ok rest) (ok (pair (cons (pairFirst p) (pairFirst rest)) (cons (pairSecond p) (pairSecond rest)))))))))))

fn ! mgReadFloats names: (List String) curs: (List Any) start: Int64 count: Int64 -> (Result (Pair (List F64Array) (List Any)) String)
  (match (listHead names)
    ((none) (ok (pair (list) (list))))
    ((some n)
      (match (match (listHead curs)
               ((none) (err "ERR_MERGE: cursor missing"))
               ((some cu) (r/parquetCursorReadF64 cu start count)))
        ((err e) (err e))
        ((ok p)
          (match (mgReadFloats (optionOr (listTail names) (list)) (optionOr (listTail curs) (list)) start count)
            ((err e) (err e))
            ((ok rest) (ok (pair (cons (pairFirst p) (pairFirst rest)) (cons (pairSecond p) (pairSecond rest))))))))))

fn mgCurDecodes curs: (List Any) -> Int64
  (listSum (map (fn [(c Any)] -> Int64 (r/parquetCursorDecodes c)) curs))

fn mgDecodes src: MergeSrc -> Int64
  (if (not src.isOpen) src.decoded
    (+ src.decoded (+ (r/parquetCursorDecodes src.tsCur) (+ (mgCurDecodes src.intCurs) (mgCurDecodes src.floatCurs)))))

; (:m :ref PQ-MERGE :do "cursors are opened once per row group and keep the decoded page, so a group is decoded once however small chunkRows is; the largest thing held per source is one decoded page per column (one group when the file has a page per group)")
fn ! mgFill src: MergeSrc m: Merge -> (Result MergeSrc String)
  (if (< src.pos (i64ArrayLen src.ts)) (ok src)
    (let [(base (+ src.base (i64ArrayLen src.ts)))
          (groups (r/parquetNumRowGroups src.file))
          (empty (i64ArrayGenerate 0 (fn [(i Int64)] -> Int64 0)))]
      (cond
        ((>= src.group groups) (ok (with src :ts empty :ints (list) :floats (list) :pos 0 :base base)))
        ((not src.isOpen)
          (match (r/parquetCursorI64 src.file m.tsName src.group)
            ((err e) (err e))
            ((ok tc)
              (match (mgOpenCurs src.file m.intNames src.group)
                ((err e) (err e))
                ((ok ic)
                  (match (mgOpenCurs src.file m.floatNames src.group)
                    ((err e) (err e))
                    ((ok fc) (mgFill (with src :tsCur tc :intCurs ic :floatCurs fc :isOpen true :loaded 0 :ts empty :pos 0 :base base) m))))))))
        ((>= src.loaded (r/parquetGroupRows src.file src.group))
          (mgFill (with src :group (+ src.group 1) :decoded (mgDecodes src) :isOpen false :loaded 0 :ts empty :pos 0 :base base) m))
        (else
          (let [(n (min m.chunkRows (- (r/parquetGroupRows src.file src.group) src.loaded)))]
            (match (r/parquetCursorReadI64 src.tsCur src.loaded n)
              ((err e) (err e))
              ((ok tp)
                (let [(ts (pairFirst tp))]
                  (if (not (mgSorted? ts 0 (if src.hasLast src.last (i64ArrayGet ts 0))))
                    (err (str "ERR_MERGE_ORDER: " m.tsName " decreases in row group " (stringFromInt64 src.group) " after row " (stringFromInt64 base)))
                    (match (mgReadInts src.file m.intNames src.intCurs src.loaded n)
                      ((err e) (err e))
                      ((ok ip)
                        (match (mgReadFloats m.floatNames src.floatCurs src.loaded n)
                          ((err e) (err e))
                          ((ok fp)
                            (ok (with src :loaded (+ src.loaded n) :ts ts :ints (pairFirst ip) :floats (pairFirst fp) :tsCur (pairSecond tp) :intCurs (pairSecond ip) :floatCurs (pairSecond fp) :pos 0 :base base)))))))))))))))

fn ! mgTypesOk? file: Any m: Merge -> (Result Bool String)
  (cond
    ((not (r/parquetHasColumn file m.tsName)) (err (str "ERR_MERGE_COLUMN: no column " m.tsName)))
    ((!= (r/parquetColumnType file m.tsName) "int64") (err (str "ERR_MERGE_COLUMN: " m.tsName " is not int64")))
    ((not (listAll? (fn [(n String)] -> Bool (and (r/parquetHasColumn file n) (or (= (r/parquetColumnType file n) "int64") (= (r/parquetColumnType file n) "int8")))) m.intNames))
      (err "ERR_MERGE_COLUMN: an int column is missing or not int64/int8"))
    ((not (listAll? (fn [(n String)] -> Bool (and (r/parquetHasColumn file n) (= (r/parquetColumnType file n) "double"))) m.floatNames))
      (err "ERR_MERGE_COLUMN: a float column is missing or not double"))
    (else (ok true)))

fn ! mgOpenAll paths: (List String) m: Merge acc: (List MergeSrc) -> (Result (List MergeSrc) String)
  (match (listHead paths)
    ((none) (ok (listReverse acc)))
    ((some path)
      (match (r/parquetOpen path)
        ((err e) (err e))
        ((ok file)
          (match (mgTypesOk? file m)
            ((err e) (err (str path ": " e)))
            ((ok _)
              (match (mgFill (MergeSrc :file file :group 0 :loaded 0 :ts (i64ArrayGenerate 0 (fn [(i Int64)] -> Int64 0)) :ints (list) :floats (list) :pos 0 :base 0 :last 0 :hasLast false :tsCur () :intCurs (list) :floatCurs (list) :isOpen false :decoded 0) m)
                ((err e) (err (str path ": " e)))
                ((ok src) (mgOpenAll (optionOr (listTail paths) (list)) m (cons src acc))))))))))

; (:m :ref PQ-MERGE :do "intNames name int64 or int8 columns, floatNames double columns; their values come back in MergeRow ints and floats in that order")
fn ! parquetMergeOpen paths: (List String) tsName: String intNames: (List String) floatNames: (List String) chunkRows: Int64 -> (Result Merge String)
  (if (<= chunkRows 0) (err "chunkRows must be positive")
    (let [(m (Merge :srcs (list) :tsName tsName :intNames intNames :floatNames floatNames :chunkRows chunkRows))]
      (match (mgOpenAll paths m (list))
        ((err e) (err e))
        ((ok srcs) (ok (with m :srcs srcs))))))

fn parquetMergeSourceCount m: Merge -> Int64
  (listLength m.srcs)

fn mgBest srcs: (List MergeSrc) i: Int64 best: Int64 bestTs: Int64 -> Int64
  (match (listGet srcs i)
    ((none) best)
    ((some s)
      (if (>= s.pos (i64ArrayLen s.ts)) (mgBest srcs (+ i 1) best bestTs)
        (let [(t (i64ArrayGet s.ts s.pos))]
          (if (or (< best 0) (< t bestTs)) (mgBest srcs (+ i 1) i t) (mgBest srcs (+ i 1) best bestTs))))))

; (:m :ref PQ-MERGE :do "none when every source is exhausted; otherwise the row and the merge advanced past it; the merge value is immutable, so keeping an old one replays from there")
fn ! parquetMergeNext m: Merge -> (Result (Option (Pair MergeRow Merge)) String)
  (let [(i (mgBest m.srcs 0 -1 0))]
    (if (< i 0) (ok (none))
      (match (listGet m.srcs i)
        ((none) (err "ERR_MERGE: source index"))
        ((some s0)
          (let [(s MergeSrc s0)
                (ts (i64ArrayGet s.ts s.pos))
                (row (MergeRow :source i :ts ts :row (+ s.base s.pos)
                       :ints (map (fn [(a I64Array)] -> Int64 (i64ArrayGet a s.pos)) s.ints)
                       :floats (map (fn [(a F64Array)] -> Float64 (f64ArrayGet a s.pos)) s.floats)))]
            (match (mgFill (with s :pos (+ s.pos 1) :last ts :hasLast true) m)
              ((err e) (err e))
              ((ok moved)
                (ok (some (pair row (with m :srcs (listAppend (listTake m.srcs i) (cons moved (listDrop m.srcs (+ i 1)))))))))))))))

fn ! mgTake m: Merge n: Int64 acc: (List MergeRow) -> (Result (Pair (List MergeRow) Merge) String)
  (if (<= n 0) (ok (pair (listReverse acc) m))
    (match (parquetMergeNext m)
      ((err e) (err e))
      ((ok next)
        (match next
          ((none) (ok (pair (listReverse acc) m)))
          ((some p) (mgTake (pairSecond p) (- n 1) (cons (pairFirst p) acc)))))))

fn ! parquetMergeTake m: Merge n: Int64 -> (Result (Pair (List MergeRow) Merge) String)
  (mgTake m n (list))

; (:m :ref PQ-MERGE :do "the largest window any source holds right now, in rows; it never exceeds chunkRows, which is the memory bound by construction")
fn parquetMergeWindowRows m: Merge -> Int64
  (fold (fn [(acc Int64) (s MergeSrc)] -> Int64 (max acc (i64ArrayLen s.ts))) 0 m.srcs)

; (:m :ref PQ-MERGE :do "total page decodes so far across all sources and columns; a group costs one decode per page and column however small chunkRows is")
fn parquetMergeDecodes m: Merge -> Int64
  (fold (fn [(acc Int64) (s MergeSrc)] -> Int64 (+ acc (mgDecodes s))) 0 m.srcs)
