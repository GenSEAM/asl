(module asl-codec/placementTest
  :d "Unit verification test suite for ASN Data Placement Optimizer and layout transforms."
  :x [testHomogeneityAnalysis
      testRecommendationThresholds
      testLosslessRoundtripColumnar
      testLosslessRoundtripTable
      testTokenSavingsThreshold
      testOptimizePlacementString
      runTests]
  :i [(asl-codec/placement :a p)
      (asl-codec/asn :a a)])

(df makeTestRecord [(id Str) (name Str) (role Str)] -> a/AsnValue
  :d "Constructs a test record with 3 keys."
  (a/asnRec
    (list (a/AsnField :key ":id" :val (a/asnStr (str "\"" id "\"")))
          (a/AsnField :key ":name" :val (a/asnStr (str "\"" name "\"")))
          (a/AsnField :key ":role" :val (a/asnStr (str "\"" role "\""))))))

(df make5Records [] -> (List a/AsnValue)
  :d "Constructs a homogeneous collection of 5 records across 3 keys."
  (list (makeTestRecord "1" "alice" "admin")
        (makeTestRecord "2" "bob" "dev")
        (makeTestRecord "3" "charlie" "qa")
        (makeTestRecord "4" "dave" "sre")
        (makeTestRecord "5" "eve" "sec")))

(df testHomogeneityAnalysis [] -> Bool
  :d "Verifies layout metrics and homogeneity detection on uniform vs non-uniform record collections."
  (let [(uniform (make5Records))
        (nonUniform (list (makeTestRecord "1" "alice" "admin")
                           (a/asnRec (list (a/AsnField :key ":id" :val (a/asnStr "\"2\""))
                                            (a/AsnField :key ":title" :val (a/asnStr "\"dev\""))))))
        (mUniform (p/analyzeRecords uniform))
        (mDiff (p/analyzeRecords nonUniform))]
    (assert (.-homogeneous mUniform) "uniform records detected as homogeneous")
    (assert (= (.-rowCount mUniform) 5) "uniform row count is 5")
    (assert (= (.-columnCount mUniform) 3) "uniform column count is 3")
    (assert (not (.-homogeneous mDiff)) "non-uniform records not homogeneous")
    (assert (= (.-rowCount mDiff) 2) "non-uniform row count is 2")
    true))

(df testRecommendationThresholds [] -> Bool
  :d "Verifies placement recommendation rules: N < 3 -> AoS, N >= 3 with K >= 2 -> Columnar or Table."
  (let [(twoRecords (list (makeTestRecord "1" "alice" "admin")
                           (makeTestRecord "2" "bob" "dev")))
        (fiveRecords (make5Records))
        (mTwo (p/analyzeRecords twoRecords))
        (mFive (p/analyzeRecords fiveRecords))
        (recTwo (p/recommendPlacement mTwo))
        (recFive (p/recommendPlacement mFive))]
    (assert (p/placementEq? recTwo (p/placementAos)) "two records recommend AoS")
    (assert (or (p/placementEq? recFive (p/placementColumnar))
                (p/placementEq? recFive (p/placementTable))) "five records recommend Columnar or Table")
    (assert (not (p/placementEq? recTwo (p/placementColumnar))) "two records do not recommend Columnar")
    true))

(df testLosslessRoundtripColumnar [] -> Bool
  :d "Verifies lossless bidirectional roundtrip between AoS and Columnar representations."
  (let [(orig (make5Records))
        (col (p/aosToColumnar orig))
        (restored (p/columnarToAos col))]
    (assert (= (list-length restored) 5) "restored length is 5")
    (let [(f0 (option-unwrap (list-head restored)))
          (valId (p/getRecordFieldVal f0 ":id"))
          (valRole (p/getRecordFieldVal f0 ":role"))
          (valMissing (p/getRecordFieldVal f0 ":missing"))]
      (assert (optionIsSome? valId) "id is present")
      (assert (optionIsSome? valRole) "role is present")
      (assert (not (optionIsSome? valMissing)) "missing field is not present")
      true)))

(df testLosslessRoundtripTable [] -> Bool
  :d "Verifies lossless bidirectional roundtrip between AoS and Table representations."
  (let [(orig (make5Records))
        (tbl (p/aosToTable orig))
        (restored (p/tableToAos tbl))]
    (assert (= (list-length restored) 5) "restored table length is 5")
    (let [(f0 (option-unwrap (list-head restored)))
          (valName (p/getRecordFieldVal f0 ":name"))
          (valMissing (p/getRecordFieldVal f0 ":missing"))]
      (assert (optionIsSome? valName) "name is present")
      (assert (not (optionIsSome? valMissing)) "missing field is not present")
      true)))

(df testTokenSavingsThreshold [] -> Bool
  :d "Verifies that optimizing 5+ homogeneous records with 3 keys yields at least 25% token savings."
  (let [(records (make5Records))
        (metrics (p/analyzeRecords records))]
    (assert (>= (.-savingsPercent metrics) 25.0) "savings >= 25%")
    (assert (> (.-aosTokens metrics) (.-columnarTokens metrics)) "columnar uses fewer tokens than aos")
    (assert (not (<= (.-savingsPercent metrics) 0.0)) "savings is positive")
    true))

(df testOptimizePlacementString [] -> Bool
  :d "Verifies end-to-end string optimization emits valid layout with >= 25% savings."
  (let [(source "[ (:id \"1\" :name \"alice\" :role \"admin\") (:id \"2\" :name \"bob\" :role \"dev\") (:id \"3\" :name \"charlie\" :role \"qa\") (:id \"4\" :name \"dave\" :role \"sre\") (:id \"5\" :name \"eve\" :role \"sec\") ]")
        (res (p/optimizePlacementString source))
        (resBad (p/optimizePlacementString "invalid-payload-syntax-unbalanced"))]
    (assert (.-success res) "optimization succeeded")
    (assert (>= (.-savingsPercent res) 25.0) "savings >= 25%")
    (assert (string-contains? (.-output res) ":id") "output contains id")
    (assert (not (.-success resBad)) "reject invalid payload syntax")
    true))

(df runTests [] -> Bool
  :d "Executes all placement unit assertions."
  (do
    (assert (testHomogeneityAnalysis) "homogeneity analysis")
    (assert (testRecommendationThresholds) "recommendation thresholds")
    (assert (testLosslessRoundtripColumnar) "lossless roundtrip columnar")
    (assert (testLosslessRoundtripTable) "lossless roundtrip table")
    (assert (testTokenSavingsThreshold) "token savings threshold")
    (assert (testOptimizePlacementString) "optimize placement string")
    true))
