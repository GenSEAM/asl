(module asl-parser/recoveryTableTest
  :d "Falsifiable gate for pure ASL recovery engine W001-W040 and --llm diagnostic formatting."
  :x [runTests]
  :i [(recovery :a rec) (indentLexer :a lx)])

(df testLookupTable [] -> Bool
  :d "Verifies all Table §6 recovery actions."
  (assert (string-contains? (rec/lookupRecovery "W001") "tab") "W001 recovery")
  (assert (string-contains? (rec/lookupRecovery "W002") "round down") "W002 recovery")
  (assert (string-contains? (rec/lookupRecovery "E010") "auto-close") "E010 recovery")
  (assert (string-contains? (rec/lookupRecovery "E011") "continuation") "E011 recovery")
  (assert (string-contains? (rec/lookupRecovery "E012") "round down") "E012 recovery")
  (assert (string-contains? (rec/lookupRecovery "E013") "strip") "E013 recovery")
  (assert (string-contains? (rec/lookupRecovery "E014") "infer") "E014 recovery")
  (assert (string-contains? (rec/lookupRecovery "E015") "default") "E015 recovery")
  (assert (string-contains? (rec/lookupRecovery "E016") "replace") "E016 recovery")
  (assert (string-contains? (rec/lookupRecovery "E017") "auto-close") "E017 recovery")
  (assert (string-contains? (rec/lookupRecovery "E018") "auto-close") "E018 recovery")
  (assert (string-contains? (rec/lookupRecovery "E020") "align") "E020 recovery")
  (assert (string-contains? (rec/lookupRecovery "E030") "fallback") "E030 recovery")
  (assert (string-contains? (rec/lookupRecovery "W040") "shift") "W040 recovery")
  true)

(df testFlatLlmFormatting [] -> Bool
  :d "Verifies CODE:LINE:COL:LEVEL:MESSAGE:RECOVERY flat stream formatting."
  (let [(d1 (rec/DiagnosticRecord :code "W001" :line 2 :col 1
                                  :severity (rec/sevWarning)
                                  :msg "tab in indentation"
                                  :recovery "replace tab with 2 spaces"))
        (d2 (rec/DiagnosticRecord :code "E017" :line 5 :col 12
                                  :severity (rec/sevError)
                                  :msg "unclosed inline bracket"
                                  :recovery "auto-close bracket at EOL"))]
    (assert (= (rec/formatLlmDiagnostic d1) "W001:2:1:WARNING:tab in indentation:replace tab with 2 spaces")
            "Formatted W001 must match flat contract")
    (assert (= (rec/formatLlmDiagnostic d2) "E017:5:12:ERROR:unclosed inline bracket:auto-close bracket at EOL")
            "Formatted E017 must match flat contract")
    true))

(df testDiagnoseAndRecoverPipeline [] -> Bool
  :d "Verifies transformation of raw lexer diagnostics into formatted LLM stream."
  (let [(rawDiags (list (lx/makeDiagnostic "W001" "tab used" 3 1)
                        (lx/makeDiagnostic "E018" "unclosed interpolation" 7 15)))
        (stream (rec/renderLlmStream rawDiags))]
    (assert (string-contains? stream "W001:3:1:WARNING:tab used:replace tab with 2 spaces") "Stream must include W001 record")
    (assert (string-contains? stream "E018:7:15:ERROR:unclosed interpolation:auto-close brace at quote boundary") "Stream must include E018 record")
    true))

(df runTests [] -> Bool
  :d "Runs all recovery engine tests."
  (assert (testLookupTable) "testLookupTable passed")
  (assert (testFlatLlmFormatting) "testFlatLlmFormatting passed")
  (assert (testDiagnoseAndRecoverPipeline) "testDiagnoseAndRecoverPipeline passed")
  true)
