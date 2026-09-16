(module asl-parser/recovery
  :d "Diagnostic Recovery Engine (W001-W040) & Flat --llm Diagnostic Stream."
  :x [DiagnosticSeverity DiagnosticRecord formatLlmDiagnostic lookupRecovery
      lookupSeverity diagnoseAndRecover renderLlmStream]
  :i [(indentLexer :a lx)])

(dfe DiagnosticSeverity
  (:c sevWarning [] "Non-fatal warning, auto-recovered")
  (:c sevError   [] "Syntax or structural error with deterministic fallback"))

(dfs DiagnosticRecord
  (:f code String "Diagnostic code (W001-W040)")
  (:f line Int64 "1-based source line")
  (:f col Int64 "1-based source column")
  (:f severity DiagnosticSeverity "Warning or Error")
  (:f msg String "Human-readable description")
  (:f recovery String "Applied recovery description"))

(df severityName [(s DiagnosticSeverity)] -> String
  :d "Renders canonical severity label."
  (mt s
    ((sevWarning) "WARNING")
    ((sevError)   "ERROR")))

(df lookupSeverity [(code String)] -> DiagnosticSeverity
  :d "Assigns severity category based on W- or E- prefix."
  (if (string-starts-with? code "W")
    (sevWarning)
    (sevError)))

(df lookupRecovery [(code String)] -> String
  :d "Looks up canonical recovery description for W001-W040 code from Table §6."
  (cond
    ((= code "W001") "replace tab with 2 spaces")
    ((= code "W002") "round down to 2-space boundary")
    ((= code "E010") "auto-close delimiter at EOL")
    ((= code "E011") "treat as line continuation")
    ((= code "E012") "round down to nearest active indentation level")
    ((= code "E013") "strip trailing delimiter")
    ((= code "E014") "infer parameter type or default to Any")
    ((= code "E015") "default return type to Unit")
    ((= code "E016") "replace all tabs with 2 spaces")
    ((= code "E017") "auto-close bracket at EOL")
    ((= code "E018") "auto-close brace at quote boundary")
    ((= code "E020") "align to enclosing block level")
    ((= code "E030") "parse as fallback arm")
    ((= code "W040") "shift line indentation by 1 level")
    (:else           "log and continue parse")))

(df formatLlmDiagnostic [(diag DiagnosticRecord)] -> String
  :d "Formats diagnostic as flat stream entry CODE:LINE:COL:LEVEL:MESSAGE:RECOVERY."
  (str (.-code diag) ":"
       (string-from-int64 (.-line diag)) ":"
       (string-from-int64 (.-col diag)) ":"
       (severityName (.-severity diag)) ":"
       (.-msg diag) ":"
       (.-recovery diag)))

(df diagnoseAndRecover [(diags (List lx/LexerDiagnostic))] -> (List DiagnosticRecord)
  :d "Converts raw lexer/parser diagnostics into classified DiagnosticRecords with recovery actions."
  (map (fn [(d lx/LexerDiagnostic)] -> DiagnosticRecord
         (let [(c (.-code d))]
           (DiagnosticRecord :code c
                             :line (.-line d)
                             :col (.-col d)
                             :severity (lookupSeverity c)
                             :msg (.-msg d)
                             :recovery (lookupRecovery c))))
       diags))

(df renderLlmStream [(diags (List lx/LexerDiagnostic))] -> String
  :d "Renders complete flat --llm diagnostic stream separated by newlines."
  (let [(records (diagnoseAndRecover diags))]
    (string-join (map (fn [(r DiagnosticRecord)] -> String (formatLlmDiagnostic r)) records) "\n")))
