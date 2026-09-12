(module asl-codec/placement-test
  :d "Unit verification test suite for ASN Data Placement Optimizer and layout transforms."
  :x [test-homogeneity-analysis
      test-recommendation-thresholds
      test-lossless-roundtrip-columnar
      test-lossless-roundtrip-table
      test-token-savings-threshold
      test-optimize-placement-string
      run-tests]
  :i [(asl-codec/placement :a p)
      (asl-codec/asn :a a)])

(df make-test-record [(id Str) (name Str) (role Str)] -> a/AsnValue
  :d "Constructs a test record with 3 keys."
  (a/asn-rec
    (list (a/AsnField :key ":id" :val (a/asn-str (str "\"" id "\"")))
          (a/AsnField :key ":name" :val (a/asn-str (str "\"" name "\"")))
          (a/AsnField :key ":role" :val (a/asn-str (str "\"" role "\""))))))

(df make-5-records [] -> (List a/AsnValue)
  :d "Constructs a homogeneous collection of 5 records across 3 keys."
  (list (make-test-record "1" "alice" "admin")
        (make-test-record "2" "bob" "dev")
        (make-test-record "3" "charlie" "qa")
        (make-test-record "4" "dave" "sre")
        (make-test-record "5" "eve" "sec")))

(df test-homogeneity-analysis [] -> Bool
  :d "Verifies layout metrics and homogeneity detection on uniform vs non-uniform record collections."
  (let [(uniform (make-5-records))
        (non-uniform (list (make-test-record "1" "alice" "admin")
                           (a/asn-rec (list (a/AsnField :key ":id" :val (a/asn-str "\"2\""))
                                            (a/AsnField :key ":title" :val (a/asn-str "\"dev\""))))))
        (m-uniform (p/analyze-records uniform))
        (m-diff (p/analyze-records non-uniform))]
    (assert (.-homogeneous m-uniform) "uniform records detected as homogeneous")
    (assert (= (.-row-count m-uniform) 5) "uniform row count is 5")
    (assert (= (.-column-count m-uniform) 3) "uniform column count is 3")
    (assert (not (.-homogeneous m-diff)) "non-uniform records not homogeneous")
    (assert (= (.-row-count m-diff) 2) "non-uniform row count is 2")
    true))

(df test-recommendation-thresholds [] -> Bool
  :d "Verifies placement recommendation rules: N < 3 -> AoS, N >= 3 with K >= 2 -> Columnar or Table."
  (let [(two-records (list (make-test-record "1" "alice" "admin")
                           (make-test-record "2" "bob" "dev")))
        (five-records (make-5-records))
        (m-two (p/analyze-records two-records))
        (m-five (p/analyze-records five-records))
        (rec-two (p/recommend-placement m-two))
        (rec-five (p/recommend-placement m-five))]
    (assert (p/placement-eq? rec-two (p/placement-aos)) "two records recommend AoS")
    (assert (or (p/placement-eq? rec-five (p/placement-columnar))
                (p/placement-eq? rec-five (p/placement-table))) "five records recommend Columnar or Table")
    (assert (not (p/placement-eq? rec-two (p/placement-columnar))) "two records do not recommend Columnar")
    true))

(df test-lossless-roundtrip-columnar [] -> Bool
  :d "Verifies lossless bidirectional roundtrip between AoS and Columnar representations."
  (let [(orig (make-5-records))
        (col (p/aos-to-columnar orig))
        (restored (p/columnar-to-aos col))]
    (assert (= (list-length restored) 5) "restored length is 5")
    (let [(f0 (option-unwrap (list-head restored)))
          (val-id (p/get-record-field-val f0 ":id"))
          (val-role (p/get-record-field-val f0 ":role"))
          (val-missing (p/get-record-field-val f0 ":missing"))]
      (assert (option-is-some? val-id) "id is present")
      (assert (option-is-some? val-role) "role is present")
      (assert (not (option-is-some? val-missing)) "missing field is not present")
      true)))

(df test-lossless-roundtrip-table [] -> Bool
  :d "Verifies lossless bidirectional roundtrip between AoS and Table representations."
  (let [(orig (make-5-records))
        (tbl (p/aos-to-table orig))
        (restored (p/table-to-aos tbl))]
    (assert (= (list-length restored) 5) "restored table length is 5")
    (let [(f0 (option-unwrap (list-head restored)))
          (val-name (p/get-record-field-val f0 ":name"))
          (val-missing (p/get-record-field-val f0 ":missing"))]
      (assert (option-is-some? val-name) "name is present")
      (assert (not (option-is-some? val-missing)) "missing field is not present")
      true)))

(df test-token-savings-threshold [] -> Bool
  :d "Verifies that optimizing 5+ homogeneous records with 3 keys yields at least 25% token savings."
  (let [(records (make-5-records))
        (metrics (p/analyze-records records))]
    (assert (>= (.-savings-percent metrics) 25.0) "savings >= 25%")
    (assert (> (.-aos-tokens metrics) (.-columnar-tokens metrics)) "columnar uses fewer tokens than aos")
    (assert (not (<= (.-savings-percent metrics) 0.0)) "savings is positive")
    true))

(df test-optimize-placement-string [] -> Bool
  :d "Verifies end-to-end string optimization emits valid layout with >= 25% savings."
  (let [(source "[ (:id \"1\" :name \"alice\" :role \"admin\") (:id \"2\" :name \"bob\" :role \"dev\") (:id \"3\" :name \"charlie\" :role \"qa\") (:id \"4\" :name \"dave\" :role \"sre\") (:id \"5\" :name \"eve\" :role \"sec\") ]")
        (res (p/optimize-placement-string source))
        (res-bad (p/optimize-placement-string "invalid-payload-syntax-unbalanced"))]
    (assert (.-success res) "optimization succeeded")
    (assert (>= (.-savings-percent res) 25.0) "savings >= 25%")
    (assert (string-contains? (.-output res) ":id") "output contains id")
    (assert (not (.-success res-bad)) "reject invalid payload syntax")
    true))

(df run-tests [] -> Bool
  :d "Executes all placement unit assertions."
  (do
    (assert (test-homogeneity-analysis) "homogeneity analysis")
    (assert (test-recommendation-thresholds) "recommendation thresholds")
    (assert (test-lossless-roundtrip-columnar) "lossless roundtrip columnar")
    (assert (test-lossless-roundtrip-table) "lossless roundtrip table")
    (assert (test-token-savings-threshold) "token savings threshold")
    (assert (test-optimize-placement-string) "optimize placement string")
    true))
