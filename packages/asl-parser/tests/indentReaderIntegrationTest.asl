(module asl-parser/indentReaderIntegrationTest :x [runTests] :i [(indentParser :a ip) (reader :a rd)])

fn runTests -> Bool
  (let [(sampleSource (str "fn area s: Shape -> Float\n" "  match s\n" "    Circle r -> mul pi (mul r r)\n")) (parseRes (ip/parseIndented sampleSource))] (mt parseRes ((ok sexpr) (let [(rendered (rd/renderSexpr sexpr))] (assert (stringContains? rendered "area") "Parsed SExpr must contain function name area") (assert (stringContains? rendered "Shape") "Parsed SExpr must contain Shape parameter type") (assert (stringContains? rendered "match") "Parsed SExpr must preserve match construct") true)) ((err msg) (assert false (str "Failed to parse v0.4 indented syntax: " msg)) false)))
