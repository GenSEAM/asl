(module asl-parser/indentReaderIntegrationTest
  :d "Baseline integration tests for Language v0.4 pure ASL indented reader."
  :x [runTests]
  :i [(indentParser :a ip) (reader :a rd)])

(df runTests [] -> Bool
  :d "Executes integration assertions verifying v0.4 indented syntax lowers to canonical SExpr AST."
  (let [(sampleSource (str "fn area s: Shape -> Float\n"
                           "  match s\n"
                           "    Circle r -> mul pi (mul r r)\n"))
        (parseRes (ip/parseIndented sampleSource))]
    (mt parseRes
      ((ok sexpr)
       (let [(rendered (rd/renderSexpr sexpr))]
         (assert (string-contains? rendered "area") "Parsed SExpr must contain function name area")
         (assert (string-contains? rendered "Shape") "Parsed SExpr must contain Shape parameter type")
         (assert (string-contains? rendered "match") "Parsed SExpr must preserve match construct")
         true))
      ((err msg)
       (assert false (str "Failed to parse v0.4 indented syntax: " msg))
       false))))
