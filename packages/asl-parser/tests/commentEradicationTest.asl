(module asl-parser/commentEradicationTest
  :x [runTests]
  :i [(asl-parser/indentLexer :a lx) (asl-parser/lexer :a rl)])

fn testPureCodePasses -> Bool
  (let [(code "fn add a: Int64 b: Int64 -> Int64\n  (+ a b)\n")
        (res (lx/tokenizeIndented code))
        (toks (pairFirst res))
        (diags (pairSecond res))]
    (assert (> (listLength toks) 0) "tokens must be produced")
    (assert (listEmpty? diags) "clean code must produce zero diagnostics")
    true)

fn testStringWithSemicolonAllowed -> Bool
  (let [(code "fn getSemi -> String\n  \"hello; world\"\n")
        (res (lx/tokenizeIndented code))
        (toks (pairFirst res))
        (diags (pairSecond res))]
    (assert (listEmpty? diags) "semicolon inside string literal must not trigger diagnostic")
    (let [(strFound (fold (fn [(found Bool) (t lx/IndentToken)] -> Bool
                            (if (stringContains? t.rawText "hello; world") true found))
                          false toks))]
      (assert strFound "string token must preserve semicolon")
      true))

fn rawTexts toks: (List lx/IndentToken) -> (List String)
  (map (fn [(t lx/IndentToken)] -> String (lx/tokenTypeName t.kind)) toks)

fn testCommentDroppedAsHostDoes -> Bool
  (let [(plain (lx/tokenizeIndented "fn work -> Int64\n  42\n"))
        (commented (lx/tokenizeIndented "; leading\nfn work -> Int64\n  ; own line\n  42 ; trailing\n"))]
    (assert (listEmpty? (pairSecond commented)) "a ';' comment is not a diagnostic: asl-host reads it as a comment")
    (assert (= (rawTexts (pairFirst commented)) (rawTexts (pairFirst plain))) "a ';' comment leaves no tokens")
    true)

fn testParenReaderDropsComment -> Bool
  (let [(plain (rl/tokenize "(f 1)\n(g 2)"))
        (commented (rl/tokenize "; head\n(f 1) ; tail\n(g 2) ;"))]
    (assert (= (map (fn [(t rl/Token)] -> String t.rawText) commented) (map (fn [(t rl/Token)] -> String t.rawText) plain)) "the paren lexer drops ';' comments")
    true)

fn testHashIsSymbolChar -> Bool
  (let [(res (lx/tokenizeIndented "fn f -> String\n  a#b\n"))]
    (assert (listEmpty? (pairSecond res)) "'#' is a symbol character in asl-host")
    (assert (listContains? (rawTexts (pairFirst res)) "SYMBOL(a#b)") "a#b is one symbol")
    true)

fn runTests -> Bool
  (and (testPureCodePasses)
       (and (testStringWithSemicolonAllowed)
            (and (testCommentDroppedAsHostDoes)
                 (and (testParenReaderDropsComment) (testHashIsSymbolChar)))))
