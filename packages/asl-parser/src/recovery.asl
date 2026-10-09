(module asl-parser/recovery :x [DiagnosticSeverity DiagnosticRecord formatLlmDiagnostic lookupRecovery lookupSeverity diagnoseAndRecover renderLlmStream] :i [(indentLexer :a lx)])

(enum DiagnosticSeverity (:c sevWarning [] "Non-fatal warning, auto-recovered") (:c sevError [] "Syntax or structural error with deterministic fallback"))

(schema DiagnosticRecord (:f code String) (:f line Int64) (:f col Int64) (:f severity DiagnosticSeverity) (:f msg String) (:f recovery String))

fn severityName s: DiagnosticSeverity -> String
  (mt s ((sevWarning) "WARNING") ((sevError) "ERROR"))

fn lookupSeverity code: String -> DiagnosticSeverity
  (if (stringStartsWith? code "W") (sevWarning) (sevError))

fn lookupRecovery code: String -> String
  (cond ((= code "W001") "replace tab with 2 spaces") ((= code "W002") "round down to 2-space boundary") ((= code "E010") "auto-close delimiter at EOL") ((= code "E011") "treat as line continuation") ((= code "E012") "round down to nearest active indentation level") ((= code "E013") "strip trailing delimiter") ((= code "E014") "infer parameter type or default to Any") ((= code "E015") "default return type to Unit") ((= code "E016") "replace all tabs with 2 spaces") ((= code "E017") "auto-close bracket at EOL") ((= code "E018") "auto-close brace at quote boundary") ((= code "E020") "align to enclosing block level") ((= code "E030") "parse as fallback arm") ((= code "W040") "shift line indentation by 1 level") (else "log and continue parse"))

fn formatLlmDiagnostic diag: DiagnosticRecord -> String
  (str diag.code ":" (stringFromInt64 diag.line) ":" (stringFromInt64 diag.col) ":" (severityName diag.severity) ":" diag.msg ":" diag.recovery)

fn diagnoseAndRecover diags: (List lx/LexerDiagnostic) -> (List DiagnosticRecord)
  (map (fn [(d lx/LexerDiagnostic)] -> DiagnosticRecord (let [(c d.code)] (DiagnosticRecord :code c :line d.line :col d.col :severity (lookupSeverity c) :msg d.msg :recovery (lookupRecovery c)))) diags)

fn renderLlmStream diags: (List lx/LexerDiagnostic) -> String
  (let [(records (diagnoseAndRecover diags))] (stringJoin (map (fn [(r DiagnosticRecord)] -> String (formatLlmDiagnostic r)) records) "\n"))
