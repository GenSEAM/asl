(module asl-parser/token :doc "AgentScript pure token predicates, taxonomy, and classification utilities." :export [isParenToken? isBracketToken? isDelimiterToken? isLiteralToken? isIdentToken? tokenCategory])

fn isParenToken? k: String -> Bool
  or (== k "LPAREN") (== k "RPAREN")

fn isBracketToken? k: String -> Bool
  or (== k "LBRACKET") (== k "RBRACKET")

fn isDelimiterToken? k: String -> Bool
  or (isParenToken? k) (isBracketToken? k)

fn isLiteralToken? k: String -> Bool
  or (== k "STRING") (or (== k "INT") (== k "FLOAT"))

fn isIdentToken? k: String -> Bool
  or (== k "SYMBOL") (== k "KEYWORD")

fn tokenCategory k: String -> String
  if (isParenToken? k) "paren" (if (isBracketToken? k) "bracket" (if (isLiteralToken? k) "literal" (if (isIdentToken? k) "ident" "other")))
