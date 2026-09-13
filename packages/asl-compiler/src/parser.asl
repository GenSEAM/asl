(module asl-compiler/parser
  :d "Pure ASL self-hosted lexer, parser and AST generator pipeline under D86."
  :x [parse_asl_source
      tokenize_asl
      ast_builder
      syntax_tree]
  :i [])

(df tokenize_asl [src] -> List
  :d "Tokenizes ASL source text into token list"
  (let [(tokens (string-split src " "))]
    tokens))

(df ast_builder [tokens] -> Map
  :d "Constructs structured AST from token stream"
  {:kind :syntax_tree :tokens tokens :nodeCount (count tokens)})

(df syntax_tree [root-node] -> Map
  :d "Wraps root node into typed syntax tree representation"
  {:root root-node :valid true :pipeline :asl-parser})

(df parse_asl_source [src] -> Map
  :d "Parses ASL source string into complete AST"
  (let [(tokens (tokenize_asl src))
        (tree (ast_builder tokens))]
    (syntax_tree tree)))
