(module aslHarness/humanResonanceParadigmTest :x [testReflexiveTomLevels testJtbdJobDimensions testAppFormatTaxonomy testSemanticRegisters runTests] :i [])

fn testReflexiveTomLevels -> Bool
  (let [(levels (list "r0-empirical-world" "r1-user-mental-model" "r2-counter-perception"))] (assert (= (listLength levels) 3) "Theory of mind must specify exactly 3 recursive levels") (assert (not (= (listHead levels) (listHead (listDrop levels 1)))) "Levels must be distinct") true)

fn testJtbdJobDimensions -> Bool
  (let [(jobs (list "functional" "emotional" "social"))] (assert (= (listLength jobs) 3) "JTBD must cover exactly 3 human dimensions") true)

fn testAppFormatTaxonomy -> Bool
  (let [(formats (list "agentic-micro-saas" "headless-agent-service" "dynamic-vdom-canvas" "outcome-based-escrow" "agent-to-agent-marketplace"))] (assert (= (listLength formats) 5) "Taxonomy must define exactly 5 modern application formats") (assert (not (listEmpty? formats)) "Formats list must be non-empty") true)

fn testSemanticRegisters -> Bool
  (let [(registers (list "executive" "engineering" "collaborative-user"))] (assert (= (listLength registers) 3) "Must define exactly 3 audience registers") true)

fn runTests -> Bool
  (and (testReflexiveTomLevels) (and (testJtbdJobDimensions) (and (testAppFormatTaxonomy) (testSemanticRegisters))))
