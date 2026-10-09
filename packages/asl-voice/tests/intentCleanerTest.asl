(module aslVoice/testIntentCleaner :x [testStripDisfluencies testDeduplicateStutters testRepairAsrSlips testStripConversationalPreamble testCleanVoiceIntentEndToEnd runAllIntentCleanerTests runTests] :i [(voice/intentCleaner :a ic)])

fn testStripDisfluencies -> Bool
  (let [(r1 (ic/stripDisfluencies "ну эээ типа запусти тесты")) (r2 (ic/stripDisfluencies "um uh like run the build"))] (assert (= r1 "запусти тесты") "russian disfluencies stripped") (assert (= r2 "run the build") "english disfluencies stripped") true)

fn testDeduplicateStutters -> Bool
  (let [(r1 (ic/deduplicateConsecutiveTokens "мы мы хотим запустить")) (r2 (ic/deduplicateConsecutiveTokens "run run the test test suite"))] (assert (= r1 "мы хотим запустить") "consecutive russian word stutters deduplicated") (assert (= r2 "run the test suite") "consecutive english word stutters deduplicated") true)

fn testRepairAsrSlips -> Bool
  (let [(r1 (ic/repairAsrSlips "запусти шроуди и датахаб")) (r2 (ic/repairAsrSlips "сделай гет пуш и коммит"))] (assert (stringContains? r1 "shrody") "шроуди repaired to shrody") (assert (stringContains? r1 "datahub") "датахаб repaired to datahub") (assert (stringContains? r2 "git") "гет repaired to git") (assert (stringContains? r2 "push") "пуш repaired to push") (assert (stringContains? r2 "commit") "коммит repaired to commit") true)

fn testStripConversationalPreamble -> Bool
  (let [(r1 (ic/stripConversationalPreamble "можешь пожалуйста запустить проверку")) (r2 (ic/stripConversationalPreamble "could you please run the verification"))] (assert (= r1 "запустить проверку") "russian preamble stripped") (assert (= r2 "run the verification") "english preamble stripped") true)

fn testCleanVoiceIntentEndToEnd -> Bool
  (let [(res (ic/cleanVoiceIntent "ну эээ можешь пожалуйста запустить запустить тесты в шроуди"))] (assert res.hadRepetitions "repetitions detected in raw transcript") (assert (= res.cleanedIntent "запустить tests в shrody") "end-to-end cleaned intent matches expectation") true)

fn runAllIntentCleanerTests -> Bool
  (do (testStripDisfluencies) (testDeduplicateStutters) (testRepairAsrSlips) (testStripConversationalPreamble) (testCleanVoiceIntentEndToEnd) true)

fn runTests -> Bool
  (runAllIntentCleanerTests)
