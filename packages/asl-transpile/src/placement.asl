(module asl-transpile/placement :x [PlacementKind placementAos placementColumnar placementTable placementRows LayoutMetrics PlacementResult analyzeRecords recommendPlacement aosToColumnar columnarToAos aosToTable tableToAos optimizePlacementString measurePlacementSavings getRecordFieldVal placementEq?] :i [(asn :a a)])

(enum PlacementKind (:c placementAos [] "Array-of-Structs representation: [(:k v ...) ...]") (:c placementColumnar [] "Columnar ASN representation: (:k [v ...] ...)") (:c placementTable [] "Table ASN representation: ([:cols ...] [[rows ...]])") (:c placementRows [] "Schema-grouped rows representation: (Schema [row ...] ...)"))

(schema LayoutMetrics (:f rowCount I64) (:f columnCount I64) (:f homogeneous Bool) (:f aosTokens I64) (:f columnarTokens I64) (:f tableTokens I64) (:f recommended PlacementKind) (:f savingsPercent F64))

(schema PlacementResult (:f output Str) (:f layout PlacementKind) (:f originalTokens I64) (:f optimizedTokens I64) (:f savingsPercent F64) (:f success Bool))

fn getRecordFields rec: a/AsnValue -> (List a/AsnField)
  (mt rec ((asnRec fs) fs) ((asnCtor _ fs) fs) ((a/asnRec fs) fs) ((a/asnCtor _ fs) fs) (_ (list)))

fn getRecordFieldVal rec: a/AsnValue targetKey: Str -> (Option a/AsnValue)
  (let [(fields (getRecordFields rec))] (fold (fn [(acc (Option a/AsnValue)) (f a/AsnField)] -> (Option a/AsnValue) (mt acc ((some _) acc) ((none) (if (= f.key targetKey) (some f.val) (none))))) (none) fields))

fn recordKeys rec: a/AsnValue -> (List Str)
  (map (fn [(f a/AsnField)] -> Str f.key) (getRecordFields rec))

fn getVecItems v: a/AsnValue -> (List a/AsnValue)
  (mt v ((asnVec items) items) ((a/asnVec items) items) (_ (list)))

fn asnKwToStr v: a/AsnValue -> Str
  (mt v ((asnKw k) k) ((a/asnKw k) k) ((asnSym s) s) ((a/asnSym s) s) ((asnStr s) s) ((a/asnStr s) s) (_ ""))

fn placementKindToString k: PlacementKind -> Str
  (mt k ((placementAos) "aos") ((placementColumnar) "columnar") ((placementTable) "table") ((placementRows) "rows") (_ "aos"))

fn placementEq? k1: PlacementKind k2: PlacementKind -> Bool
  (= (placementKindToString k1) (placementKindToString k2))

fn listsEqualStrings? l1: (List Str) l2: (List Str) -> Bool
  (if (!= (listLength l1) (listLength l2)) false (let [(n (listLength l1)) (indices (range 0 n))] (fold (fn [(matched Bool) (idx I64)] -> Bool (and matched (= (optionOr (listGet l1 idx) "") (optionOr (listGet l2 idx) "")))) true indices)))

fn measurePlacementSavings origTokens: I64 optTokens: I64 -> F64
  (if (or (<= origTokens 0) (>= optTokens origTokens)) 0.0 (* 100.0 (/ (int64ToFloat64 (- origTokens optTokens)) (int64ToFloat64 origTokens))))

fn recommendPlacement metrics: LayoutMetrics -> PlacementKind
  (if (or (not metrics.homogeneous) (< metrics.rowCount 3)) (placementAos) (if (and (>= metrics.rowCount 3) (>= metrics.columnCount 2)) (if (<= metrics.columnarTokens metrics.tableTokens) (placementColumnar) (placementTable)) (placementAos)))

fn analyzeRecords records: (List a/AsnValue) -> LayoutMetrics
  (let [(rowCount (listLength records))] (if (= rowCount 0) (LayoutMetrics :rowCount 0 :columnCount 0 :homogeneous true :aosTokens 0 :columnarTokens 0 :tableTokens 0 :recommended (placementAos) :savingsPercent 0.0) (let [(firstRec (optionOr (listHead records) (a/asnRec (list)))) (firstKeys (recordKeys firstRec)) (colCount (listLength firstKeys)) (homogeneous (if (= colCount 0) false (fold (fn [(isHomo Bool) (r a/AsnValue)] -> Bool (and isHomo (listsEqualStrings? firstKeys (recordKeys r)))) true records))) (aosTokens (+ 2 (* rowCount (+ 2 (* 2 colCount))))) (columnarTokens (+ 2 (* colCount (+ 3 rowCount)))) (tableTokens (+ (+ 6 colCount) (* rowCount (+ 2 colCount)))) (tempMetrics (LayoutMetrics :rowCount rowCount :columnCount colCount :homogeneous homogeneous :aosTokens aosTokens :columnarTokens columnarTokens :tableTokens tableTokens :recommended (placementAos) :savingsPercent 0.0)) (rec (recommendPlacement tempMetrics)) (optTokens (mt rec ((placementColumnar) columnarTokens) ((placementTable) tableTokens) ((placementRows) tableTokens) ((placementAos) aosTokens))) (savings (measurePlacementSavings aosTokens optTokens))] (LayoutMetrics :rowCount rowCount :columnCount colCount :homogeneous homogeneous :aosTokens aosTokens :columnarTokens columnarTokens :tableTokens tableTokens :recommended rec :savingsPercent savings))))

fn aosToColumnar records: (List a/AsnValue) -> a/AsnValue
  (if (listEmpty? records) (a/asnRec (list)) (let [(firstRec (optionOr (listHead records) (a/asnRec (list)))) (fields (getRecordFields firstRec)) (keys (map (fn [(f a/AsnField)] -> Str f.key) fields)) (colFields (map (fn [(k Str)] -> a/AsnField (let [(colVals (map (fn [(r a/AsnValue)] -> a/AsnValue (optionOr (getRecordFieldVal r k) (a/asnNil))) records))] (a/AsnField :key k :val (a/asnVec colVals)))) keys))] (a/asnRec colFields)))

fn columnarToAos colRec: a/AsnValue -> (List a/AsnValue)
  (let [(colFields (getRecordFields colRec))] (if (listEmpty? colFields) (list) (let [(firstCol (optionOr (listHead colFields) (a/AsnField :key "" :val (a/asnVec (list))))) (firstVals (getVecItems firstCol.val)) (numRows (listLength firstVals)) (rowIndices (range 0 numRows))] (map (fn [(rowIdx I64)] -> a/AsnValue (let [(rowFields (map (fn [(col a/AsnField)] -> a/AsnField (let [(vals (getVecItems col.val)) (val (optionOr (listGet vals rowIdx) (a/asnNil)))] (a/AsnField :key col.key :val val))) colFields))] (a/asnRec rowFields))) rowIndices))))

fn aosToTable records: (List a/AsnValue) -> a/AsnValue
  (if (listEmpty? records) (a/asnTable (list) (list)) (let [(firstRec (optionOr (listHead records) (a/asnRec (list)))) (fields (getRecordFields firstRec)) (keys (map (fn [(f a/AsnField)] -> Str f.key) fields)) (colNodes (map (fn [(k Str)] -> a/AsnValue (a/asnKw k)) keys)) (rowNodes (map (fn [(r a/AsnValue)] -> a/AsnValue (let [(rowVals (map (fn [(k Str)] -> a/AsnValue (optionOr (getRecordFieldVal r k) (a/asnNil))) keys))] (a/asnVec rowVals))) records))] (a/asnTable colNodes rowNodes)))

fn tableToAos table: a/AsnValue -> (List a/AsnValue)
  (mt table ((asnTable cols rows) (let [(keys (map (fn [(c a/AsnValue)] -> Str (asnKwToStr c)) cols))] (map (fn [(row a/AsnValue)] -> a/AsnValue (let [(vals (getVecItems row)) (numKeys (listLength keys)) (indices (range 0 numKeys)) (rowFields (map (fn [(idx I64)] -> a/AsnField (let [(k (optionOr (listGet keys idx) "")) (v (optionOr (listGet vals idx) (a/asnNil)))] (a/AsnField :key k :val v))) indices))] (a/asnRec rowFields))) rows))) ((a/asnTable cols rows) (let [(keys (map (fn [(c a/AsnValue)] -> Str (asnKwToStr c)) cols))] (map (fn [(row a/AsnValue)] -> a/AsnValue (let [(vals (getVecItems row)) (numKeys (listLength keys)) (indices (range 0 numKeys)) (rowFields (map (fn [(idx I64)] -> a/AsnField (let [(k (optionOr (listGet keys idx) "")) (v (optionOr (listGet vals idx) (a/asnNil)))] (a/AsnField :key k :val v))) indices))] (a/asnRec rowFields))) rows))) (_ (list)))

fn optimizePlacementString sourceAsn: Str -> PlacementResult
  (let [(readRes (a/asnRead sourceAsn))] (mt readRes ((err _) (PlacementResult :output sourceAsn :layout (placementAos) :originalTokens 0 :optimizedTokens 0 :savingsPercent 0.0 :success false)) ((ok root) (let [(records (getVecItems root))] (if (listEmpty? records) (PlacementResult :output sourceAsn :layout (placementAos) :originalTokens 0 :optimizedTokens 0 :savingsPercent 0.0 :success true) (let [(metrics (analyzeRecords records)) (rec metrics.recommended)] (cond ((or (placementEq? rec (placementColumnar)) (placementEq? rec (placementRows))) (let [(optNode (aosToColumnar records)) (out (a/asnWrite optNode))] (PlacementResult :output out :layout rec :originalTokens metrics.aosTokens :optimizedTokens metrics.columnarTokens :savingsPercent metrics.savingsPercent :success true))) ((placementEq? rec (placementTable)) (let [(optNode (aosToTable records)) (out (a/asnWrite optNode))] (PlacementResult :output out :layout rec :originalTokens metrics.aosTokens :optimizedTokens metrics.tableTokens :savingsPercent metrics.savingsPercent :success true))) (else (PlacementResult :output sourceAsn :layout (placementAos) :originalTokens metrics.aosTokens :optimizedTokens metrics.aosTokens :savingsPercent 0.0 :success true)))))))))
