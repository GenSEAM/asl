(module aslHarness/promptCalibrationTest :x [testMicroAffirmativePass testAntiPatternContamination testFullCalibrationMatrix testBrowserCalibrationMatrix testFormatCalibrationAsn testTranslatorCalibrationSweep runCalibrationTests runTests] :i [(promptCalibration :a pc)])

fn testMicroAffirmativePass -> Bool
  (let [(score (pc/evaluateStrategy (pc/scaleMicro) (pc/stratAffirmative)))] (assert (>= score.schemaPassRate 90.0) "schema pass rate >= 90") (assert (<= score.contaminationRate 5.0) "contamination rate <= 5") (assert score.recommended "is recommended") true)

fn testAntiPatternContamination -> Bool
  (let [(score (pc/evaluateStrategy (pc/scaleMicro) (pc/stratContrastive)))] (assert (> score.contaminationRate 30.0) "contamination rate > 30") (assert (not score.recommended) "not recommended") true)

fn testFullCalibrationMatrix -> Bool
  (let [(m (pc/runFullCalibration))] (assert (= (listLength m.scores) 12) "scores length is 12") (assert (= m.optimalStrategyMicro "Pure Affirmative Schema") "optimal strategy matches") true)

fn testBrowserCalibrationMatrix -> Bool
  (let [(scoreNano (pc/evaluateStrategy (pc/scaleNano) (pc/stratAffirmative))) (m (pc/runBrowserModelCalibration))] (assert (>= scoreNano.schemaPassRate 85.0) "Nano schema pass rate >= 85%") (assert scoreNano.recommended "Nano affirmative strategy recommended") (assert (= (listLength m.scores) 9) "Browser calibration has 9 scores (3 models * 3 strategies)") (assert (stringContains? m.title "Browser-Targeted") "Title references browser targets") true)

fn testFormatCalibrationAsn -> Bool
  (let [(m (pc/runFullCalibration)) (asnOut (pc/formatCalibrationAsn m))] (assert (stringStartsWith? asnOut "(:prompt-calibration") "starts with :prompt-calibration") (assert (stringContains? asnOut ":optimal-micro") "contains :optimal-micro") true)

fn testTranslatorCalibrationSweep -> Bool
  (let [(m (pc/runTranslatorCalibrationSweep)) (scores m.scores) (scoreNano (optionOr (listHead scores) (pc/makeScore "" "" 0 0.0 0.0 0 false))) (scoreMicro (pc/evaluateStrategyWithTranslator (pc/scaleMicro) (pc/stratAffirmative) true))] (do (assert (= (listLength scores) 5) "Translator sweep tests 5 scales") (assert (stringContains? m.title "ASN Prompt Translator") "Title references prompt translator") (assert scoreNano.recommended "Nano model with safe fallback must be recommended") (assert (= scoreMicro.promptTokens 78) "Micro model with ASN translation must reduce prompt tokens to 78") (assert (>= scoreMicro.schemaPassRate 95.0) "Micro schema pass rate must be >= 95%") (assert (<= scoreMicro.contaminationRate 2.0) "Micro contamination rate must be <= 2%") true))

fn runCalibrationTests -> Bool
  (do (testMicroAffirmativePass) (testAntiPatternContamination) (testFullCalibrationMatrix) (testBrowserCalibrationMatrix) (testFormatCalibrationAsn) (testTranslatorCalibrationSweep) true)

fn runTests -> Bool
  (runCalibrationTests)
