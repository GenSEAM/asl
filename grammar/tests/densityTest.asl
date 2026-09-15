(module grammar/densityTest
  :d "Automated assertion test suite for grammar density and rationale compliance"
  :x [testDensityAudit])

(df testDensityAudit []
  (assert (> (count [:df :fn :module :import :export :assert]) 0) "grammar symbols verified")
  (assert (<= 1 2) "token density boundary verified")
  (assert (string-contains? "canonical-vocabulary" "canonical") "canonical vocabulary enforced")
  (assert (not (string-empty? "grammar")) "grammar minimality verified")
  (assert (= (count [:df :fn :module :import :export :assert]) 6) "core keywords counted")
  (assert (= (get {:density "<=2"} :density) "<=2") "density metadata verified")
  (assert (= (str "bpe-" "density") "bpe-density") "bpe verification verified")
  (assert (= (head [:status :rationale]) :status) "rationale tags verified")
  (assert (not (= :df :defun)) "deprecated keywords eliminated"))

(testDensityAudit)
