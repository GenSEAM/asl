(module asl-parser/lexerTest :x [runTokenize runTests] :i [(lexer :a lex)])

fn renderToken t: lex/Token -> String
  (str (lex/tokenTypeName t.kind) "|" t.rawText "|" (stringFromInt64 t.line) "|" (stringFromInt64 t.col))

fn runTokenize -> (List String)
  (map (fn [(t lex/Token)] -> String (renderToken t)) (lex/tokenize "(a 12\n:b \"xy\")"))

fn testSigilRejection -> Bool
  (let [(tokens (lex/tokenize "@bad"))] (assert (> (listLength tokens) 0) "tokens must not be empty") (let [(t0 (optionOr (listHead tokens) (lex/makeToken (lex/tokEof) "" 0 0)))] (assert (= (lex/tokenTypeName t0.kind) "ERROR") "sigil @ must produce ERROR token") (assert (= t0.rawText "@") "raw-text of rejected sigil must be @") (let [(msg (mt t0.kind ((lex/tokError m) m) (_ "")))] (assert (stringContains? msg "invalid character '@'") "error message contains invalid character notice")) true))

fn expectedTokens -> (List String)
  (list "LPAREN|(|1|1" "SYMBOL|a|1|2" "INT|12|1|4" "KEYWORD|:b|2|1" "STRING|\"xy\"|2|4" "RPAREN|)|2|8" "EOF||2|9")

fn oneTokenKind s: String -> String
  (mt (listHead (lex/tokenize s)) ((some t) (lex/tokenTypeName t.kind)) ((none) "EMPTY"))

fn oneTokenFloat s: String -> Float64
  (mt (listHead (lex/tokenize s)) ((some t) (mt t.kind ((lex/tokFloat f) f) (_ 0.0))) ((none) 0.0))

fn testExponentFloats -> Bool
  (do
    (assert (= (oneTokenKind "1e22") "FLOAT") "1e22 lexes as a single FLOAT token")
    (assert (= (oneTokenKind "1.5e-3") "FLOAT") "1.5e-3 lexes as a single FLOAT token")
    (assert (= (oneTokenKind "-2E+5") "FLOAT") "-2E+5 lexes as a single FLOAT token")
    (assert (= (oneTokenFloat "1e22") 1e22) "1e22 parses to the Float64 value 1e22")
    (assert (= (oneTokenFloat "1.5e-3") 0.0015) "1.5e-3 parses to the Float64 value 0.0015")
    (assert (= (oneTokenFloat "-2E+5") -200000.0) "-2E+5 parses to the Float64 value -200000.0")
    (assert (= (oneTokenKind "1e") "ERROR") "1e alone (no exponent digit) is one ERROR token")
    (assert (= (oneTokenKind "1e+") "ERROR") "1e+ alone (sign, no exponent digit) is one ERROR token")
    true)

fn runTests -> Bool
  (let [(tokens (runTokenize))] (do (assert (= tokens (expectedTokens)) (str "tokenize yields every token of the sample with its position, got " (stringJoin tokens " "))) (assert (testSigilRejection) "sigil @ rejection verified") (assert (testExponentFloats) "exponent float literals verified") true))
