(module aslHarness/sanitizerTest :x [testPhaticDetection testTokenSavingsCalculation testSanitizedSud testCompileRawPromptToIntent testAsrAcousticRepair testAcousticHesitationDetection testGluedVoicePunctuationRepair runTests] :i [(sanitizer :a san)])

fn testPhaticDetection -> Bool
  (do (assert (san/isPhaticWord "привет")) (assert (san/isPhaticWord "пожалуйста")) (assert (san/isPhaticWord "спасибо")) (assert (san/isPhaticWord "кажется")) (assert (san/isPhaticWord "слушай")) (assert (san/isPhaticWord "hello")) (assert (san/isPhaticWord "please")) (assert (san/isPhaticWord "thanks")) (assert (san/isPhaticWord "maybe")) (assert (not (san/isPhaticWord "calculate_discount"))) (assert (not (san/isPhaticWord "ZeroDivisionError"))) (assert (not (san/isPhaticWord "pricing.py"))) true)

fn testTokenSavingsCalculation -> Bool
  (let [(savings (san/calculateTokenSavings 118 42))] (do (assert (> savings 64.0)) (assert (< savings 65.0)) true))

fn testSanitizedSud -> Bool
  (let [(sud (san/calculateSanitizedSud 34 42))] (do (assert (> sud 0.80)) (assert (< sud 0.82)) true))

fn testCompileRawPromptToIntent -> Bool
  (let [(intent (san/compileRawPromptToIntent "i1" "billing" "fixAnomaly" (list "billing/pricing.py:calculate_discount") (list "ZeroDivisionError" "AssertionError" "InvalidDiscountException") 118 42 34))] (do (assert (= intent.id "i1")) (assert (= intent.domain "billing")) (assert (= intent.action "fixAnomaly")) (assert (= (listLength intent.targets) 1)) (assert (= (optionOr (listGet intent.targets 0) "") "billing/pricing.py:calculate_discount")) (assert (= (listLength intent.exceptions) 3)) (assert (= intent.rawTokenCount 118)) (assert (= intent.compiledTokenCount 42)) (assert (> intent.tokenSavingsPct 64.0)) (assert (> intent.sudScore 0.80)) true))

fn testAsrAcousticRepair -> Bool
  (do (assert (= (san/repairAsrAcousticToken "ВОГ") "ASN")) (assert (= (san/repairAsrAcousticToken "vog") "ASN")) (assert (= (san/repairAsrAcousticToken "асн") "ASN")) (assert (= (san/repairAsrAcousticToken "асел") "ASL")) (assert (= (san/repairAsrAcousticToken "edgends") "agents")) (assert (= (san/repairAsrAcousticToken "тоу зловины") "tools")) (assert (= (san/repairAsrAcousticToken "клотку") "claude")) (assert (= (san/repairAsrAcousticToken "села и") "cli")) (assert (= (san/repairAsrAcousticToken "search-пати") "thirdparty")) (assert (= (san/repairAsrAcousticToken "ханес") "harness")) (assert (= (san/repairAsrAcousticToken "мультиленс") "multilens")) true)

fn testAcousticHesitationDetection -> Bool
  (do (assert (san/isAcousticHesitation "бо что")) (assert (san/isAcousticHesitation "ну и")) (assert (san/isAcousticHesitation "вот это вот все")) (assert (san/isAcousticHesitation "как бы")) (assert (san/isAcousticHesitation "короче")) (assert (not (san/isAcousticHesitation "calculate_discount"))) (assert (not (san/isAcousticHesitation "pricing.py"))) true)

fn testGluedVoicePunctuationRepair -> Bool
  (do (assert (= (san/repairGluedVoicePunctuation "в.edgendс папке") "в .agents папке")) (assert (= (san/repairGluedVoicePunctuation "в edgends md файле") "в AGENTS.md файле")) (assert (= (san/repairGluedVoicePunctuation "конвертировании промпт в ВОГ") "конвертировании промпт в ASN")) (assert (san/fuzzyMatchSymbol "pricing.py" "billing/pricing.py")) (assert (san/fuzzyMatchSymbol "calculate_discount" "calculate_discount")) true)

fn runTests -> Bool
  (do (assert (testPhaticDetection)) (assert (testTokenSavingsCalculation)) (assert (testSanitizedSud)) (assert (testCompileRawPromptToIntent)) (assert (testAsrAcousticRepair)) (assert (testAcousticHesitationDetection)) (assert (testGluedVoicePunctuationRepair)) true)
