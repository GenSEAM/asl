(module asl-transpile/placementTest :x [testHomogeneityAnalysis testRecommendationThresholds testLosslessRoundtripColumnar testLosslessRoundtripTable testTokenSavingsThreshold testOptimizePlacementString runTests] :i [(asl-transpile/placement :a p) (asl-transpile/asn :a a)])

fn makeTestRecord id: Str name: Str role: Str -> a/AsnValue
  (a/asnRec (list (a/AsnField :key ":id" :val (a/asnStr (str "\"" id "\""))) (a/AsnField :key ":name" :val (a/asnStr (str "\"" name "\""))) (a/AsnField :key ":role" :val (a/asnStr (str "\"" role "\"")))))

fn make5Records -> (List a/AsnValue)
  (list (makeTestRecord "1" "alice" "admin") (makeTestRecord "2" "bob" "dev") (makeTestRecord "3" "charlie" "qa") (makeTestRecord "4" "dave" "sre") (makeTestRecord "5" "eve" "sec"))

fn testHomogeneityAnalysis -> Bool
  (let [(uniform (make5Records)) (nonUniform (list (makeTestRecord "1" "alice" "admin") (a/asnRec (list (a/AsnField :key ":id" :val (a/asnStr "\"2\"")) (a/AsnField :key ":title" :val (a/asnStr "\"dev\"")))))) (mUniform (p/analyzeRecords uniform)) (mDiff (p/analyzeRecords nonUniform))] (assert mUniform.homogeneous "uniform records detected as homogeneous") (assert (= mUniform.rowCount 5) "uniform row count is 5") (assert (= mUniform.columnCount 3) "uniform column count is 3") (assert (not mDiff.homogeneous) "non-uniform records not homogeneous") (assert (= mDiff.rowCount 2) "non-uniform row count is 2") true)

fn testRecommendationThresholds -> Bool
  (let [(twoRecords (list (makeTestRecord "1" "alice" "admin") (makeTestRecord "2" "bob" "dev"))) (fiveRecords (make5Records)) (mTwo (p/analyzeRecords twoRecords)) (mFive (p/analyzeRecords fiveRecords)) (recTwo (p/recommendPlacement mTwo)) (recFive (p/recommendPlacement mFive))] (assert (p/placementEq? recTwo (p/placementAos)) "two records recommend AoS") (assert (or (p/placementEq? recFive (p/placementColumnar)) (p/placementEq? recFive (p/placementTable))) "five records recommend Columnar or Table") (assert (not (p/placementEq? recTwo (p/placementColumnar))) "two records do not recommend Columnar") true)

fn testLosslessRoundtripColumnar -> Bool
  (let [(orig (make5Records)) (col (p/aosToColumnar orig)) (restored (p/columnarToAos col))] (assert (= (listLength restored) 5) "restored length is 5") (let [(f0 (optionOr (listHead restored) (a/asnRec (list)))) (valId (p/getRecordFieldVal f0 ":id")) (valRole (p/getRecordFieldVal f0 ":role")) (valMissing (p/getRecordFieldVal f0 ":missing"))] (assert (some? valId) "id is present") (assert (some? valRole) "role is present") (assert (not (some? valMissing)) "missing field is not present") true))

fn testLosslessRoundtripTable -> Bool
  (let [(orig (make5Records)) (tbl (p/aosToTable orig)) (restored (p/tableToAos tbl))] (assert (= (listLength restored) 5) "restored table length is 5") (let [(f0 (optionOr (listHead restored) (a/asnRec (list)))) (valName (p/getRecordFieldVal f0 ":name")) (valMissing (p/getRecordFieldVal f0 ":missing"))] (assert (some? valName) "name is present") (assert (not (some? valMissing)) "missing field is not present") true))

fn testTokenSavingsThreshold -> Bool
  (let [(records (make5Records)) (metrics (p/analyzeRecords records))] (assert (>= metrics.savingsPercent 25.0) "savings >= 25%") (assert (> metrics.aosTokens metrics.columnarTokens) "columnar uses fewer tokens than aos") (assert (not (<= metrics.savingsPercent 0.0)) "savings is positive") true)

fn testOptimizePlacementString -> Bool
  (let [(source "[ (:id \"1\" :name \"alice\" :role \"admin\") (:id \"2\" :name \"bob\" :role \"dev\") (:id \"3\" :name \"charlie\" :role \"qa\") (:id \"4\" :name \"dave\" :role \"sre\") (:id \"5\" :name \"eve\" :role \"sec\") ]") (res (p/optimizePlacementString source)) (resBad (p/optimizePlacementString "invalid-payload-syntax-unbalanced"))] (assert res.success "optimization succeeded") (assert (>= res.savingsPercent 25.0) "savings >= 25%") (assert (stringContains? res.output ":id") "output contains id") (assert (not resBad.success) "reject invalid payload syntax") true)

fn runTests -> Bool
  (do (assert (testHomogeneityAnalysis) "homogeneity analysis") (assert (testRecommendationThresholds) "recommendation thresholds") (assert (testLosslessRoundtripColumnar) "lossless roundtrip columnar") (assert (testLosslessRoundtripTable) "lossless roundtrip table") (assert (testTokenSavingsThreshold) "token savings threshold") (assert (testOptimizePlacementString) "optimize placement string") true)
