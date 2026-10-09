(module aslHarness/tests/antiHallucinationTest :x [runTests] :i [(antiHallucination :a ah) (asl-parser/balance :a bal)])

fn testExtractThinking -> Bool
  (let [(raw "<think>Analyzing bounds and coordinates</think>(:svg :w 320 :h 320)") (res (ah/extractThinking raw))] (assert (= res.thinking "Analyzing bounds and coordinates") "Thinking block must match") (assert (= res.code "(:svg :w 320 :h 320)") "Code block must match") true)

fn testStripFences -> Bool
  (let [(raw "```asn\n(:svg :w 320 :h 320)\n```") (res (ah/stripMarkdownFences raw))] (assert (= res "(:svg :w 320 :h 320)") "ASN fences must be stripped") (assert (not (stringContains? res "```")) "ASN fences must not contain markdown ticks") true)

fn testStripJsFences -> Bool
  (let [(raw "```javascript\nconst x = 1;\n```") (res (ah/stripMarkdownFences raw))] (assert (= res "const x = 1;") "JS fences must be stripped") (assert (not (stringContains? res "```")) "JS fences must not contain markdown ticks") true)

fn testToolcallKind -> Bool
  (let [(rep (ah/repairAndNormalize "(:call :tool \"write\" :path \"index.html\" :content \"<h1>test</h1>\")"))] (assert (= rep.toolKind "html") "Kind must be html") (assert (not (= rep.toolKind "svg")) "Kind must not be svg") true)

fn testBalanceDelimiters -> Bool
  (let [(raw "(:svg :w 320 (:rc :x 0 :y 0") (res (bal/balanceDelimiters raw)) (withParensInStr "(print \"hello ) world\"") (resParensInStr (bal/balanceDelimiters withParensInStr))] (assert (= res "(:svg :w 320 (:rc :x 0 :y 0))") "Unclosed parens must be balanced") (assert (= resParensInStr "(print \"hello ) world\")") "Parens in strings must not be double closed") true)

fn testRepairAndNormalize -> Bool
  (let [(raw "```asn\n<think>Drafting diamond</think>(:svg :w 320 (:rc :x 0\n```") (rep (ah/repairAndNormalize raw))] (assert rep.repaired "Must be marked repaired") (assert (= rep.toolKind "svg") "Kind must be svg") (assert (= rep.thinking "Drafting diamond") "Thinking block must match") true)

fn runTests -> Bool
  (and (testExtractThinking) (and (testStripFences) (and (testStripJsFences) (and (testToolcallKind) (and (testBalanceDelimiters) (testRepairAndNormalize))))))
