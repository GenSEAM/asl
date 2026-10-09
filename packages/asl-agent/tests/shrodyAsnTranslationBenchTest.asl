(module aslAgent/testShrodyAsnTranslationBench :x [testShrodyReleaseCases testShrodyAdminCases testShrodyDevCases testMultilingualCodeswitchCases testIntelAndMetaQueries testAsnSexpRenderingBalance testMultilingualDetectionMatrix runAllBenchTests runTests] :i [(asnTranslator :a tr) (aslVoice/multilingualMatrix :a mm)])

fn testShrodyReleaseCases -> Bool
  (let [(f1 (tr/translatePromptToAsn "го")) (f2 (tr/translatePromptToAsn "давай")) (f3 (tr/translatePromptToAsn "send it")) (f4 (tr/translatePromptToAsn "that's it"))] (assert (= f1.disposition "release") "го yields release disposition") (assert (= f2.disposition "release") "давай yields release disposition") (assert (= f3.disposition "release") "send it yields release disposition") (assert (= f4.disposition "release") "that's it yields release disposition") (assert (= f1.kind "fast-path") "release is fast-path") true)

fn testShrodyAdminCases -> Bool
  (let [(f1 (tr/translatePromptToAsn "unregister vtbot")) (f2 (tr/translatePromptToAsn "переключись на проект vtbot"))] (assert (= f1.disposition "admin") "unregister yields admin disposition") (assert (= f2.disposition "admin") "переключись yields admin disposition") (assert (= f1.projectTarget "vtbot") "target is vtbot") (assert (= f2.projectTarget "vtbot") "target is vtbot") true)

fn testShrodyDevCases -> Bool
  (let [(fEn (tr/translatePromptToAsn "fix the flaky login test in agentube")) (fRu (tr/translatePromptToAsn "добавь ретрай в datahub-core"))] (assert (= fEn.kind "dev") "english dev command classified as dev") (assert (= fEn.projectTarget "agentube") "target project is agentube") (assert fEn.requiresWorktree "agentube dev task requires worktree") (assert fEn.requiresGate "agentube dev task requires verification gate") (assert (= fRu.kind "dev") "russian dev command classified as dev") (assert (= fRu.projectTarget "datahub-core") "target project is datahub-core") true)

fn testMultilingualCodeswitchCases -> Bool
  (let [(fMix (tr/translatePromptToAsn "ну эээ сделай git commit и push в vtbot"))] (assert (= fMix.kind "dev") "mixed codeswitch classified as dev") (assert (= fMix.projectTarget "vtbot") "project target extracted as vtbot") (assert (not (stringContains? fMix.goal "ну")) "fillers stripped from goal") (assert (stringContains? fMix.goal "commit") "commit token preserved") true)

fn testIntelAndMetaQueries -> Bool
  (let [(fIntel (tr/translatePromptToAsn "где находится символ VadConfig в asex")) (fMetaRu (tr/translatePromptToAsn "что сейчас выполняется")) (fMetaEn (tr/translatePromptToAsn "what is running"))] (assert (= fIntel.kind "intel") "intel query classified") (assert (= fIntel.projectTarget "asex") "asex project target extracted") (assert (= fIntel.disposition "query") "query disposition") (assert (= fMetaRu.kind "meta") "russian meta query classified") (assert (= fMetaEn.kind "meta") "english meta query classified") true)

fn testAsnSexpRenderingBalance -> Bool
  (let [(frame (tr/makeAsnIntentFrame "intent-01" "dev" "vtbot" "new" "add poller retry" true true)) (sexp (tr/renderAsnIntentSexp frame))] (assert (stringStartsWith? sexp "(:intent") "rendered sexp starts with (:intent") (assert (stringEndsWith? sexp ")") "rendered sexp ends with balanced paren") (assert (stringContains? sexp ":project \"vtbot\"") "rendered sexp contains project") (assert (stringContains? sexp ":requires-worktree true") "rendered sexp contains worktree flag") true)

fn testMultilingualDetectionMatrix -> Bool
  (let [(dEn (mm/detectLanguageDialect "run the verification gate")) (dRu (mm/detectLanguageDialect "запусти проверку гейтов")) (dMix (mm/detectLanguageDialect "запусти build и tests в asex")) (cfgMix (mm/makeMultilingualConfig (mm/localeMixedCodeswitch))) (engine (mm/resolveSpeechEngine cfgMix dMix))] (assert (= dEn.detectedDialect (mm/localeEnPrimary)) "detected english dialect") (assert (= dRu.detectedDialect (mm/localeRuNative)) "detected russian dialect") (assert (= dMix.detectedDialect (mm/localeMixedCodeswitch)) "detected mixed codeswitch dialect") (assert (= engine "silero-ru") "mixed dialect with cyrillic routes to silero-ru") true)

fn runAllBenchTests -> Bool
  (do (testShrodyReleaseCases) (testShrodyAdminCases) (testShrodyDevCases) (testMultilingualCodeswitchCases) (testIntelAndMetaQueries) (testAsnSexpRenderingBalance) (testMultilingualDetectionMatrix) true)

fn runTests -> Bool
  (runAllBenchTests)
