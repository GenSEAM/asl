(module asl-codec/placement
  :d "Automated data layout analysis, layout recommendation, and compaction transforms for ASN data structures."
  :x [PlacementKind
      placement-aos placement-columnar placement-table placement-rows
      LayoutMetrics PlacementResult
      analyze-records recommend-placement
      aos-to-columnar columnar-to-aos
      aos-to-table table-to-aos
      optimize-placement-string measure-placement-savings]
  :i [(asn :a a)])

(dfe PlacementKind
  (:c placement-aos      [] "Array-of-Structs representation: [(:k v ...) ...]")
  (:c placement-columnar [] "Columnar ASN representation: (:k [v ...] ...)")
  (:c placement-table    [] "Table ASN representation: ([:cols ...] [[rows ...]])")
  (:c placement-rows     [] "Schema-grouped rows representation: (Schema [row ...] ...)"))

(dfs LayoutMetrics
  (:f row-count I64 "Number of records in layout")
  (:f column-count I64 "Number of distinct field columns")
  (:f homogeneous Bool "True if all records possess the exact same keys")
  (:f aos-tokens I64 "Estimated token footprint in AoS format")
  (:f columnar-tokens I64 "Estimated token footprint in Columnar format")
  (:f table-tokens I64 "Estimated token footprint in Table format")
  (:f recommended PlacementKind "Optimal layout recommended by optimizer")
  (:f savings-percent F64 "Token compaction percentage relative to AoS"))

(dfs PlacementResult
  (:f output Str "Serialized S-expression in optimized placement format")
  (:f layout PlacementKind "Applied layout kind")
  (:f original-tokens I64 "Initial token count before optimization")
  (:f optimized-tokens I64 "Resulting token count after optimization")
  (:f savings-percent F64 "Measured token savings percentage")
  (:f success Bool "True if optimization and transform succeeded"))

(df get-record-fields [(rec a/AsnValue)] -> (List a/AsnField)
  :d "Extracts field list from an asn-rec or asn-ctor."
  (mt rec
    ((asn-rec fs) fs)
    ((asn-ctor _ fs) fs)
    ((a/asn-rec fs) fs)
    ((a/asn-ctor _ fs) fs)
    (_ (list))))

(df get-record-field-val [(rec a/AsnValue) (target-key Str)] -> (Option a/AsnValue)
  :d "Gets the value of target keyword in record."
  (let [(fields (get-record-fields rec))]
    (fold (fn [(acc (Option a/AsnValue)) (f a/AsnField)] -> (Option a/AsnValue)
            (mt acc
              ((some _) acc)
              ((none) (if (= (.-key f) target-key) (some (.-val f)) (none)))))
          (none)
          fields)))

(df record-keys [(rec a/AsnValue)] -> (List Str)
  :d "Extracts ordered list of field keys from a record."
  (map (fn [(f a/AsnField)] -> Str (.-key f)) (get-record-fields rec)))

(df get-vec-items [(v a/AsnValue)] -> (List a/AsnValue)
  :d "Extracts item list from asn-vec."
  (mt v
    ((asn-vec items) items)
    ((a/asn-vec items) items)
    (_ (list))))

(df asn-kw-to-str [(v a/AsnValue)] -> Str
  :d "Extracts string name from an asn-kw value."
  (mt v
    ((asn-kw k) k)
    ((a/asn-kw k) k)
    ((asn-sym s) s)
    ((a/asn-sym s) s)
    ((asn-str s) s)
    ((a/asn-str s) s)
    (_ "")))

(df placement-kind-to-string [(k PlacementKind)] -> Str
  :d "Converts PlacementKind enum variant to string."
  (mt k
    ((placement-aos) "aos")
    ((p/placement-aos) "aos")
    ((placement-columnar) "columnar")
    ((p/placement-columnar) "columnar")
    ((placement-table) "table")
    ((p/placement-table) "table")
    ((placement-rows) "rows")
    ((p/placement-rows) "rows")
    (_ "aos")))

(df placement-eq? [(k1 PlacementKind) (k2 PlacementKind)] -> Bool
  :d "Compares two PlacementKind enum variants."
  (= (placement-kind-to-string k1) (placement-kind-to-string k2)))

(df lists-equal-strings? [(l1 (List Str)) (l2 (List Str))] -> Bool
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

(df measure-placement-savings [(orig-tokens I64) (opt-tokens I64)] -> F64
  :d "Calculates token savings percentage from layout optimization."
  (if (or (<= orig-tokens 0) (>= opt-tokens orig-tokens))
      0.0
      (* 100.0 (/ (int64-to-float64 (- orig-tokens opt-tokens)) (int64-to-float64 orig-tokens)))))

(df recommend-placement [(metrics LayoutMetrics)] -> PlacementKind
  :d "Determines optimal placement layout based on cardinality, homogeneity, and token footprint."
  (if (or (not (.-homogeneous metrics)) (< (.-row-count metrics) 3))
      (placement-aos)
      (if (and (>= (.-row-count metrics) 3) (>= (.-column-count metrics) 2))
          (if (<= (.-columnar-tokens metrics) (.-table-tokens metrics))
              (placement-columnar)
              (placement-table))
          (placement-aos))))

(df analyze-records [(records (List a/AsnValue))] -> LayoutMetrics
  :d "Analyzes records layout, homogeneity, and token footprints across candidate representations."
  (let [(row-count (list-length records))]
    (if (= row-count 0)
        (LayoutMetrics
          :row-count 0
          :column-count 0
          :homogeneous true
          :aos-tokens 0
          :columnar-tokens 0
          :table-tokens 0
          :recommended (placement-aos)
          :savings-percent 0.0)
        (let [(first-rec (option-or (list-head records) (a/asn-rec (list))))
              (first-keys (record-keys first-rec))
              (col-count (list-length first-keys))
              (homogeneous (if (= col-count 0)
                               false
                               (fold (fn [(is-homo Bool) (r a/AsnValue)] -> Bool
                                       (and is-homo (lists-equal-strings? first-keys (record-keys r))))
                                     true
                                     records)))
              (aos-tokens (+ 2 (* row-count (+ 2 (* 2 col-count)))))
              (columnar-tokens (+ 2 (* col-count (+ 3 row-count))))
              (table-tokens (+ (+ 6 col-count) (* row-count (+ 2 col-count))))
              (temp-metrics (LayoutMetrics
                              :row-count row-count
                              :column-count col-count
                              :homogeneous homogeneous
                              :aos-tokens aos-tokens
                              :columnar-tokens columnar-tokens
                              :table-tokens table-tokens
                              :recommended (placement-aos)
                              :savings-percent 0.0))
              (rec (recommend-placement temp-metrics))
              (opt-tokens (mt rec
                            ((placement-columnar) columnar-tokens)
                            ((placement-table) table-tokens)
                            ((placement-rows) table-tokens)
                            ((placement-aos) aos-tokens)))
              (savings (measure-placement-savings aos-tokens opt-tokens))]
          (LayoutMetrics
            :row-count row-count
            :column-count col-count
            :homogeneous homogeneous
            :aos-tokens aos-tokens
            :columnar-tokens columnar-tokens
            :table-tokens table-tokens
            :recommended rec
            :savings-percent savings)))))

(df aos-to-columnar [(records (List a/AsnValue))] -> a/AsnValue
  :d "Transforms Array-of-Structs records to Columnar ASN representation."
  (if (list-empty? records)
      (a/asn-rec (list))
      (let [(first-rec (option-or (list-head records) (a/asn-rec (list))))
            (fields (get-record-fields first-rec))
            (keys (map (fn [(f a/AsnField)] -> Str (.-key f)) fields))
            (col-fields (map (fn [(k Str)] -> a/AsnField
                               (let [(col-vals (map (fn [(r a/AsnValue)] -> a/AsnValue
                                                      (option-or (get-record-field-val r k) (a/asn-nil)))
                                                    records))]
                                 (a/AsnField :key k :val (a/asn-vec col-vals))))
                             keys))]
        (a/asn-rec col-fields))))

(df columnar-to-aos [(col-rec a/AsnValue)] -> (List a/AsnValue)
  :d "Transforms Columnar ASN representation back to Array-of-Structs records."
  (let [(col-fields (get-record-fields col-rec))]
    (if (list-empty? col-fields)
        (list)
        (let [(first-col (option-or (list-head col-fields) (a/AsnField :key "" :val (a/asn-vec (list)))))
              (first-vals (get-vec-items (.-val first-col)))
              (num-rows (list-length first-vals))
              (row-indices (range 0 num-rows))]
          (map (fn [(row-idx I64)] -> a/AsnValue
                 (let [(row-fields (map (fn [(col a/AsnField)] -> a/AsnField
                                          (let [(vals (get-vec-items (.-val col)))
                                                (val (option-or (list-get vals row-idx) (a/asn-nil)))]
                                            (a/AsnField :key (.-key col) :val val)))
                                        col-fields))]
                   (a/asn-rec row-fields)))
               row-indices)))))

(df aos-to-table [(records (List a/AsnValue))] -> a/AsnValue
  :d "Transforms Array-of-Structs records to Table ASN representation."
  (if (list-empty? records)
      (a/asn-table (list) (list))
      (let [(first-rec (option-or (list-head records) (a/asn-rec (list))))
            (fields (get-record-fields first-rec))
            (keys (map (fn [(f a/AsnField)] -> Str (.-key f)) fields))
            (col-nodes (map (fn [(k Str)] -> a/AsnValue (a/asn-kw k)) keys))
            (row-nodes (map (fn [(r a/AsnValue)] -> a/AsnValue
                              (let [(row-vals (map (fn [(k Str)] -> a/AsnValue
                                                     (option-or (get-record-field-val r k) (a/asn-nil)))
                                                   keys))]
                                (a/asn-vec row-vals)))
                            records))]
        (a/asn-table col-nodes row-nodes))))

(df table-to-aos [(table a/AsnValue)] -> (List a/AsnValue)
  :d "Transforms Table ASN representation back to Array-of-Structs records."
  (mt table
    ((asn-table cols rows)
     (let [(keys (map (fn [(c a/AsnValue)] -> Str (asn-kw-to-str c)) cols))]
       (map (fn [(row a/AsnValue)] -> a/AsnValue
              (let [(vals (get-vec-items row))
                    (num-keys (list-length keys))
                    (indices (range 0 num-keys))
                    (row-fields (map (fn [(idx I64)] -> a/AsnField
                                       (let [(k (option-or (list-get keys idx) ""))
                                             (v (option-or (list-get vals idx) (a/asn-nil)))]
                                         (a/AsnField :key k :val v)))
                                     indices))]
                (a/asn-rec row-fields)))
            rows)))
    ((a/asn-table cols rows)
     (let [(keys (map (fn [(c a/AsnValue)] -> Str (asn-kw-to-str c)) cols))]
       (map (fn [(row a/AsnValue)] -> a/AsnValue
              (let [(vals (get-vec-items row))
                    (num-keys (list-length keys))
                    (indices (range 0 num-keys))
                    (row-fields (map (fn [(idx I64)] -> a/AsnField
                                       (let [(k (option-or (list-get keys idx) ""))
                                             (v (option-or (list-get vals idx) (a/asn-nil)))]
                                         (a/AsnField :key k :val v)))
                                     indices))]
                (a/asn-rec row-fields)))
            rows)))
    (_ (list))))

(df optimize-placement-string [(source-asn Str)] -> PlacementResult
  :d "Parses ASN S-expression, evaluates placement layout, and emits token-compacted output."
  (let [(read-res (a/asn-read source-asn))]
    (mt read-res
      ((err _)
       (PlacementResult
         :output source-asn
         :layout (placement-aos)
         :original-tokens 0
         :optimized-tokens 0
         :savings-percent 0.0
         :success false))
      ((ok root)
       (let [(records (get-vec-items root))]
         (if (list-empty? records)
             (PlacementResult
               :output source-asn
               :layout (placement-aos)
               :original-tokens 0
               :optimized-tokens 0
               :savings-percent 0.0
               :success true)
             (let [(metrics (analyze-records records))
                   (rec (.-recommended metrics))]
               (cond
                 ((or (placement-eq? rec (placement-columnar))
                      (placement-eq? rec (placement-rows)))
                  (let [(opt-node (aos-to-columnar records))
                        (out (a/asn-write opt-node))]
                    (PlacementResult
                      :output out
                      :layout rec
                      :original-tokens (.-aos-tokens metrics)
                      :optimized-tokens (.-columnar-tokens metrics)
                      :savings-percent (.-savings-percent metrics)
                      :success true)))
                 ((placement-eq? rec (placement-table))
                  (let [(opt-node (aos-to-table records))
                        (out (a/asn-write opt-node))]
                    (PlacementResult
                      :output out
                      :layout rec
                      :original-tokens (.-aos-tokens metrics)
                      :optimized-tokens (.-table-tokens metrics)
                      :savings-percent (.-savings-percent metrics)
                      :success true)))
                 (:else
                  (PlacementResult
                    :output source-asn
                    :layout (placement-aos)
                    :original-tokens (.-aos-tokens metrics)
                    :optimized-tokens (.-aos-tokens metrics)
                    :savings-percent 0.0
                    :success true))))))))))
