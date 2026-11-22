(module asl-store/mem
  :x [MemState memEmpty memStep]
  :i [(asl-store/types :a ty) (asl-store/kv :a kv)])

(schema MemState (:f rows (Map String kv/Entry)) (:f logs (Map String (List ty/LogRow))) (:f cursors (Map String Int64)))

fn memEmpty -> MemState
  (MemState :rows (mapEmpty) :logs (mapEmpty) :cursors (mapEmpty))

fn rowKey k: ty/Key -> String
  (str k.collection "/" k.id)

fn applyKv st: MemState op: ty/Op -> (Pair MemState ty/Reply)
  (let [(ks (rowKey (kv/keyOfOp op)))
        (out (kv/decide (mapGet st.rows ks) op))
        (rows (match out.write
                ((some e) (mapSet st.rows ks e))
                ((none) (if out.remove (mapRemove st.rows ks) st.rows))))]
    (pair (with st :rows rows) out.reply))

fn liveRows st: MemState collection: String now: Int64 -> (List ty/ScanRow)
  (let [(pre (str collection "/"))]
    (fold (fn [(acc (List ty/ScanRow)) (k String)] -> (List ty/ScanRow)
            (if (stringStartsWith? k pre)
              (match (mapGet st.rows k)
                ((some e) (if (kv/liveAt? e now)
                            (cons (ty/ScanRow :id (optionOr (stringSlice k (stringLength pre) (stringLength k)) "") :rev e.rev :value e.value :expiresAt e.expiresAt) acc)
                            acc))
                ((none) acc))
              acc))
          (list) (mapKeys st.rows)))

fn logOf st: MemState stream: String -> (List ty/LogRow)
  (optionOr (mapGet st.logs stream) (list))

fn curKey stream: String consumer: String -> String
  (str stream "\n" consumer)

fn applyOp st: MemState op: ty/Op -> (Pair MemState ty/Reply)
  (match op
    ((ty/opScan c prefix after limit now) (pair st (kv/scanPage (liveRows st c now) prefix after limit)))
    ((ty/opAppend s v now)
      (let [(rows (logOf st s)) (off (listLength rows))]
        (pair (with st :logs (mapSet st.logs s (listAppend rows (list (ty/LogRow :offset off :value v :at now))))) (ty/rAppended off))))
    ((ty/opRead s from limit) (pair st (kv/readPage (logOf st s) from limit)))
    ((ty/opCommit s c o)
      (let [(cur (optionOr (mapGet st.cursors (curKey s c)) 0))]
        (match (kv/commitCheck (listLength (logOf st s)) cur o)
          ((some bad) (pair st bad))
          ((none) (pair (with st :cursors (mapSet st.cursors (curKey s c) o)) (ty/rCommitted o))))))
    ((ty/opCursor s c) (pair st (ty/rOffset (optionOr (mapGet st.cursors (curKey s c)) 0))))
    (_ (applyKv st op)))

; (:m :ref VS-CORE :do "the pure reference adapter: fn step state op -> (Pair state reply); the effectful adapters must be indistinguishable from it on every conformance script")
fn memStep st: MemState op: ty/Op -> (Pair MemState ty/Reply)
  (match (ty/checkOp op)
    ((some bad) (pair st bad))
    ((none) (applyOp st op)))
