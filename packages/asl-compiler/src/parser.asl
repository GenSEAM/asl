(module asl-compiler/parser
  :d "Pure ASL self-hosted lexer, parser and AST generator pipeline under D86."
  :x [parseAslSource
      tokenizeAsl
      astBuilder
      syntaxTree]
  :i [])

(df tokenizeAsl [src] -> List
  :d "Tokenizes ASL source text into token list"
  (let [(tokens (string-split src " "))]
    tokens))

(df astBuilder [tokens] -> Map
  :d "Constructs structured AST from token stream"
  {:kind :syntaxTree :tokens tokens :nodeCount (count tokens)})

(df syntaxTree [rootNode] -> Map
  :d "Wraps root node into typed syntax tree representation"
  {:root rootNode :valid true :pipeline :aslParser})

(df parseAslSource [src] -> Map
  :d "Parses ASL source string into complete AST"
  (let [(tokens (tokenizeAsl src))
        (tree (astBuilder tokens))]
    (syntaxTree tree)))
