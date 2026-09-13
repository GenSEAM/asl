(module asl-codec/placement
  :d "Automated data layout analysis, layout recommendation, and compaction transforms for ASN data structures."
  :x [PlacementKind
      placementAos placementColumnar placementTable placementRows
      LayoutMetrics PlacementResult
      analyzeRecords recommendPlacement
      aosToColumnar columnarToAos
      aosToTable tableToAos
      optimizePlacementString measurePlacementSavings]
  :i [(asn :a a)])

(dfe PlacementKind
  (:c placementAos      [] "Array-of-Structs representation: [(:k v ...) ...]")
  (:c placementColumnar [] "Columnar ASN representation: (:k [v ...] ...)")
  (:c placementTable    [] "Table ASN representation: ([:cols ...] [[rows ...]])")
  (:c placementRows     [] "Schema-grouped rows representation: (Schema [row ...] ...)"))

(dfs LayoutMetrics
  (:f rowCount I64 "Number of records in layout")
  (:f columnCount I64 "Number of distinct field columns")
  (:f homogeneous Bool "True if all records possess the exact same keys")
  (:f aosTokens I64 "Estimated token footprint in AoS format")
  (:f columnarTokens I64 "Estimated token footprint in Columnar format")
  (:f tableTokens I64 "Estimated token footprint in Table format")
  (:f recommended PlacementKind "Optimal layout recommended by optimizer")
  (:f savingsPercent F64 "Token compaction percentage relative to AoS"))

(dfs PlacementResult
  (:f output Str "Serialized S-expression in optimized placement format")
  (:f layout PlacementKind "Applied layout kind")
  (:f originalTokens I64 "Initial token count before optimization")
  (:f optimizedTokens I64 "Resulting token count after optimization")
  (:f savingsPercent F64 "Measured token savings percentage")
  (:f success Bool "True if optimization and transform succeeded"))

(df getRecordFields [(rec a/AsnValue)] -> (List a/AsnField)
  :d "Extracts field list from an asn-rec or asn-ctor."
  (mt rec
    ((asnRec fs) fs)
    ((asnCtor _ fs) fs)
    ((a/asnRec fs) fs)
    ((a/asnCtor _ fs) fs)
    (_ (list))))

(df getRecordFieldVal [(rec a/AsnValue) (targetKey Str)] -> (Option a/AsnValue)
  :d "Gets the value of target keyword in record."
  (let [(fields (getRecordFields rec))]
    (fold (fn [(acc (Option a/AsnValue)) (f a/AsnField)] -> (Option a/AsnValue)
            (mt acc
              ((some _) acc)
              ((none) (if (= (.-key f) targetKey) (some (.-val f)) (none)))))
          (none)
          fields)))

(df recordKeys [(rec a/AsnValue)] -> (List Str)
  :d "Extracts ordered list of field keys from a record."
  (map (fn [(f a/AsnField)] -> Str (.-key f)) (getRecordFields rec)))

(df getVecItems [(v a/AsnValue)] -> (List a/AsnValue)
  :d "Extracts item list from asn-vec."
  (mt v
    ((asnVec items) items)
    ((a/asnVec items) items)
    (_ (list))))

(df asnKwToStr [(v a/AsnValue)] -> Str
  :d "Extracts string name from an asn-kw value."
  (mt v
    ((asnKw k) k)
    ((a/asnKw k) k)
    ((asnSym s) s)
    ((a/asnSym s) s)
    ((asnStr s) s)
    ((a/asnStr s) s)
    (_ "")))

(df placementKindToString [(k PlacementKind)] -> Str
  :d "Converts PlacementKind enum variant to string."
  (mt k
    ((placementAos) "aos")
    ((p/placementAos) "aos")
    ((placementColumnar) "columnar")
    ((p/placementColumnar) "columnar")
    ((placementTable) "table")
    ((p/placementTable) "table")
    ((placementRows) "rows")
    ((p/placementRows) "rows")
    (_ "aos")))

(df placementEq? [(k1 PlacementKind) (k2 PlacementKind)] -> Bool
  :d "Compares two PlacementKind enum variants."
  (= (placementKindToString k1) (placementKindToString k2)))

(df listsEqualStrings? [(l1 (List Str)) (l2 (List Str))] -> Bool
  :d "Checks whether two string lists are identical in elements and order."
  (if (!= (list-length l1) (list-length l2))
      false
      (let [(n (list-length l1))
            (indices (range 0 n))]
        (fold (fn [(matched Bool) (idx I64)] -> Bool
                (and matched
                     (= (option-or (list-get l1 idx) "")
                        (option-or (list-get l2 idx) ""))))
              true
              indices))))

(df measurePlacementSavings [(origTokens I64) (optTokens I64)] -> F64
  :d "Calculates token savings percentage from layout optimization."
  (if (or (<= origTokens 0) (>= optTokens origTokens))
      0.0
      (* 100.0 (/ (int64-to-float64 (- origTokens optTokens)) (int64-to-float64 origTokens)))))

(df recommendPlacement [(metrics LayoutMetrics)] -> PlacementKind
  :d "Determines optimal placement layout based on cardinality, homogeneity, and token footprint."
  (if (or (not (.-homogeneous metrics)) (< (.-rowCount metrics) 3))
      (placementAos)
      (if (and (>= (.-rowCount metrics) 3) (>= (.-columnCount metrics) 2))
          (if (<= (.-columnarTokens metrics) (.-tableTokens metrics))
              (placementColumnar)
              (placementTable))
          (placementAos))))

(df analyzeRecords [(records (List a/AsnValue))] -> LayoutMetrics
  :d "Analyzes records layout, homogeneity, and token footprints across candidate representations."
  (let [(rowCount (list-length records))]
    (if (= rowCount 0)
        (LayoutMetrics
          :rowCount 0
          :columnCount 0
          :homogeneous true
          :aosTokens 0
          :columnarTokens 0
          :tableTokens 0
          :recommended (placementAos)
          :savingsPercent 0.0)
        (let [(firstRec (option-or (list-head records) (a/asnRec (list))))
              (firstKeys (recordKeys firstRec))
              (colCount (list-length firstKeys))
              (homogeneous (if (= colCount 0)
                               false
                               (fold (fn [(isHomo Bool) (r a/AsnValue)] -> Bool
                                       (and isHomo (listsEqualStrings? firstKeys (recordKeys r))))
                                     true
                                     records)))
              (aosTokens (+ 2 (* rowCount (+ 2 (* 2 colCount)))))
              (columnarTokens (+ 2 (* colCount (+ 3 rowCount))))
              (tableTokens (+ (+ 6 colCount) (* rowCount (+ 2 colCount))))
              (tempMetrics (LayoutMetrics
                              :rowCount rowCount
                              :columnCount colCount
                              :homogeneous homogeneous
                              :aosTokens aosTokens
                              :columnarTokens columnarTokens
                              :tableTokens tableTokens
                              :recommended (placementAos)
                              :savingsPercent 0.0))
              (rec (recommendPlacement tempMetrics))
              (optTokens (mt rec
                            ((placementColumnar) columnarTokens)
                            ((placementTable) tableTokens)
                            ((placementRows) tableTokens)
                            ((placementAos) aosTokens)))
              (savings (measurePlacementSavings aosTokens optTokens))]
          (LayoutMetrics
            :rowCount rowCount
            :columnCount colCount
            :homogeneous homogeneous
            :aosTokens aosTokens
            :columnarTokens columnarTokens
            :tableTokens tableTokens
            :recommended rec
            :savingsPercent savings)))))

(df aosToColumnar [(records (List a/AsnValue))] -> a/AsnValue
  :d "Transforms Array-of-Structs records to Columnar ASN representation."
  (if (list-empty? records)
      (a/asnRec (list))
      (let [(firstRec (option-or (list-head records) (a/asnRec (list))))
            (fields (getRecordFields firstRec))
            (keys (map (fn [(f a/AsnField)] -> Str (.-key f)) fields))
            (colFields (map (fn [(k Str)] -> a/AsnField
                               (let [(colVals (map (fn [(r a/AsnValue)] -> a/AsnValue
                                                      (option-or (getRecordFieldVal r k) (a/asnNil)))
                                                    records))]
                                 (a/AsnField :key k :val (a/asnVec colVals))))
                             keys))]
        (a/asnRec colFields))))

(df columnarToAos [(colRec a/AsnValue)] -> (List a/AsnValue)
  :d "Transforms Columnar ASN representation back to Array-of-Structs records."
  (let [(colFields (getRecordFields colRec))]
    (if (list-empty? colFields)
        (list)
        (let [(firstCol (option-or (list-head colFields) (a/AsnField :key "" :val (a/asnVec (list)))))
              (firstVals (getVecItems (.-val firstCol)))
              (numRows (list-length firstVals))
              (rowIndices (range 0 numRows))]
          (map (fn [(rowIdx I64)] -> a/AsnValue
                 (let [(rowFields (map (fn [(col a/AsnField)] -> a/AsnField
                                          (let [(vals (getVecItems (.-val col)))
                                                (val (option-or (list-get vals rowIdx) (a/asnNil)))]
                                            (a/AsnField :key (.-key col) :val val)))
                                        colFields))]
                   (a/asnRec rowFields)))
               rowIndices)))))

(df aosToTable [(records (List a/AsnValue))] -> a/AsnValue
  :d "Transforms Array-of-Structs records to Table ASN representation."
  (if (list-empty? records)
      (a/asnTable (list) (list))
      (let [(firstRec (option-or (list-head records) (a/asnRec (list))))
            (fields (getRecordFields firstRec))
            (keys (map (fn [(f a/AsnField)] -> Str (.-key f)) fields))
            (colNodes (map (fn [(k Str)] -> a/AsnValue (a/asnKw k)) keys))
            (rowNodes (map (fn [(r a/AsnValue)] -> a/AsnValue
                              (let [(rowVals (map (fn [(k Str)] -> a/AsnValue
                                                     (option-or (getRecordFieldVal r k) (a/asnNil)))
                                                   keys))]
                                (a/asnVec rowVals)))
                            records))]
        (a/asnTable colNodes rowNodes))))

(df tableToAos [(table a/AsnValue)] -> (List a/AsnValue)
  :d "Transforms Table ASN representation back to Array-of-Structs records."
  (mt table
    ((asnTable cols rows)
     (let [(keys (map (fn [(c a/AsnValue)] -> Str (asnKwToStr c)) cols))]
       (map (fn [(row a/AsnValue)] -> a/AsnValue
              (let [(vals (getVecItems row))
                    (numKeys (list-length keys))
                    (indices (range 0 numKeys))
                    (rowFields (map (fn [(idx I64)] -> a/AsnField
                                       (let [(k (option-or (list-get keys idx) ""))
                                             (v (option-or (list-get vals idx) (a/asnNil)))]
                                         (a/AsnField :key k :val v)))
                                     indices))]
                (a/asnRec rowFields)))
            rows)))
    ((a/asnTable cols rows)
     (let [(keys (map (fn [(c a/AsnValue)] -> Str (asnKwToStr c)) cols))]
       (map (fn [(row a/AsnValue)] -> a/AsnValue
              (let [(vals (getVecItems row))
                    (numKeys (list-length keys))
                    (indices (range 0 numKeys))
                    (rowFields (map (fn [(idx I64)] -> a/AsnField
                                       (let [(k (option-or (list-get keys idx) ""))
                                             (v (option-or (list-get vals idx) (a/asnNil)))]
                                         (a/AsnField :key k :val v)))
                                     indices))]
                (a/asnRec rowFields)))
            rows)))
    (_ (list))))

(df optimizePlacementString [(sourceAsn Str)] -> PlacementResult
  :d "Parses ASN S-expression, evaluates placement layout, and emits token-compacted output."
  (let [(readRes (a/asnRead sourceAsn))]
    (mt readRes
      ((err _)
       (PlacementResult
         :output sourceAsn
         :layout (placementAos)
         :originalTokens 0
         :optimizedTokens 0
         :savingsPercent 0.0
         :success false))
      ((ok root)
       (let [(records (getVecItems root))]
         (if (list-empty? records)
             (PlacementResult
               :output sourceAsn
               :layout (placementAos)
               :originalTokens 0
               :optimizedTokens 0
               :savingsPercent 0.0
               :success true)
             (let [(metrics (analyzeRecords records))
                   (rec (.-recommended metrics))]
               (cond
                 ((or (placementEq? rec (placementColumnar))
                      (placementEq? rec (placementRows)))
                  (let [(optNode (aosToColumnar records))
                        (out (a/asnWrite optNode))]
                    (PlacementResult
                      :output out
                      :layout rec
                      :originalTokens (.-aosTokens metrics)
                      :optimizedTokens (.-columnarTokens metrics)
                      :savingsPercent (.-savingsPercent metrics)
                      :success true)))
                 ((placementEq? rec (placementTable))
                  (let [(optNode (aosToTable records))
                        (out (a/asnWrite optNode))]
                    (PlacementResult
                      :output out
                      :layout rec
                      :originalTokens (.-aosTokens metrics)
                      :optimizedTokens (.-tableTokens metrics)
                      :savingsPercent (.-savingsPercent metrics)
                      :success true)))
                 (:else
                  (PlacementResult
                    :output sourceAsn
                    :layout (placementAos)
                    :originalTokens (.-aosTokens metrics)
                    :optimizedTokens (.-aosTokens metrics)
                    :savingsPercent 0.0
                    :success true))))))))))
