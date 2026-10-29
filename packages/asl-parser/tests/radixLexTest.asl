(module asl-parser/tests/radixLexTest :x [runTests] :i [(asl-parser/lexer :a lx)])

; (:m :ref LL-NUMLIT :do "the paren-form lexer keeps a radix or underscore integer literal as one token, as the indent path does; plain decimals and floats keep their token kinds")
fn kindsAndText src: String -> String
  (stringJoin (map (fn [(t lx/Token)] -> String (str (lx/tokenTypeName t.kind) ":" t.rawText))
                   (filter (fn [(t lx/Token)] -> Bool (!= (lx/tokenTypeName t.kind) "EOF")) (lx/tokenize src))) " ")

fn same? src: String want: String -> Bool
  (let [(got (kindsAndText src))]
    (do (assert (= got want) (str src " lexes to " want "; got " got)) true))

fn ! runTests -> Bool
  (do
    (same? "(fn f [] 0xFF)" "LPAREN:( SYMBOL:fn SYMBOL:f LBRACKET:[ RBRACKET:] SYMBOL:0xFF RPAREN:)")
    (same? "(f 0b1010 0o17)" "LPAREN:( SYMBOL:f SYMBOL:0b1010 SYMBOL:0o17 RPAREN:)")
    (same? "(f 1_000 0xFFFF_FFFF)" "LPAREN:( SYMBOL:f SYMBOL:1_000 SYMBOL:0xFFFF_FFFF RPAREN:)")
    (same? "(f -0x10)" "LPAREN:( SYMBOL:f SYMBOL:-0x10 RPAREN:)")
    (same? "(f 0x1e5)" "LPAREN:( SYMBOL:f SYMBOL:0x1e5 RPAREN:)")
    (same? "(f 42 -7 1.5 1e3)" "LPAREN:( SYMBOL:f INT:42 INT:-7 FLOAT:1.5 FLOAT:1e3 RPAREN:)")
    true)
