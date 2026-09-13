(module asl-parser/tests/balanceTest
  :d "Unit tests for pure AgentScript delimiter balance and structural verification engine."
  :x [runTests]
  :i [(balance :a bal)])

(df testBalancedForms [] -> Bool
  :d "Verifies properly balanced parentheses, brackets, and braces."
  (let [(codeSexpr "(defn foo [x y] (+ x (* y 2)))")
        (codeMixed "let arr = [{ id: 1, val: (x + y) }];")
        (resSexpr (bal/checkDelimiterBalance codeSexpr))
        (resMixed (bal/checkDelimiterBalance codeMixed))]
    (assert (.-balanced resSexpr) "S-expression code must be balanced")
    (assert (= (.-openParens resSexpr) 0) "Open parens must be zero")
    (assert (= (.-openBrackets resSexpr) 0) "Open brackets must be zero")
    (assert (.-balanced resMixed) "Mixed syntax code must be balanced")
    true))

(df testUnbalancedForms [] -> Bool
  :d "Verifies detection of unclosed or inverted delimiters."
  (let [(unclosed "(defn bar [x] (+ x 1)")
        (inverted "][")
        (invertedParens ")(")
        (resUnclosed (bal/checkDelimiterBalance unclosed))
        (resInverted (bal/checkDelimiterBalance inverted))
        (resInvertedP (bal/checkDelimiterBalance invertedParens))]
    (assert (not (.-balanced resUnclosed)) "Unclosed parens must be flagged unbalanced")
    (assert (= (.-openParens resUnclosed) 1) "Unclosed parens count must be 1")
    (assert (not (.-balanced resInverted)) "Inverted brackets must be flagged unbalanced")
    (assert (not (.-balanced resInvertedP)) "Inverted parens must be flagged unbalanced")
    (assert (not (bal/isDelimiterBalanced? unclosed)) "is-delimiter-balanced? must return false for unclosed")
    (assert (not (bal/isDelimiterBalanced? inverted)) "is-delimiter-balanced? must return false for inverted")
    true))

(df testDelimitersInStrings [] -> Bool
  :d "Verifies that delimiters inside string literals do not affect balance."
  (let [(codeStr "(println \")\")")
        (codeEscaped "(println \"(\\\"foo\\\")\")")
        (resStr (bal/checkDelimiterBalance codeStr))
        (resEscaped (bal/checkDelimiterBalance codeEscaped))]
    (assert (.-balanced resStr) "Parens inside string literals must be ignored")
    (assert (.-balanced resEscaped) "Escaped quotes inside strings must be handled correctly")
    true))

(df testCountUnclosedParens [] -> Bool
  :d "Verifies count-unclosed-parens returns exact count of unclosed open parentheses."
  (let [(codeTwo "((+ 1 2) (+ 3 4")
        (codeOne "(println \"(\") (+ 1 2")
        (codeBal "(defn foo [] (+ 1 2))")]
    (assert (= (bal/countUnclosedParens codeTwo) 2) "Open parens count must be 2")
    (assert (= (bal/countUnclosedParens codeOne) 1) "Open parens count must be 1")
    (assert (= (bal/countUnclosedParens codeBal) 0) "Balanced code unclosed count must be 0")
    true))

(df testBalanceDelimiters [] -> Bool
  :d "Verifies balance-delimiters appends closing parentheses to unclosed S-expressions."
  (let [(unclosed "(defn foo [x] (+ x 1")
        (balanced (bal/balanceDelimiters unclosed))
        (alreadyBal "(defn bar [] 42)")
        (unchanged (bal/balanceDelimiters alreadyBal))]
    (assert (= balanced "(defn foo [x] (+ x 1))") "Must append 1 closing paren")
    (assert (= unchanged alreadyBal) "Must leave balanced code unchanged")
    true))

(df testInterleavedDelimiters [] -> Bool
  :d "Verifies that interleaved delimiters like ([)] and {[(])} are correctly flagged as unbalanced."
  (let [(r1 (bal/checkDelimiterBalance "([)]"))
        (r2 (bal/checkDelimiterBalance "[(])"))
        (r3 (bal/checkDelimiterBalance "{(})"))
        (r4 (bal/checkDelimiterBalance "{[(])}"))]
    (assert (not (.-balanced r1)) "([)] must be unbalanced")
    (assert (not (.-balanced r2)) "[(]) must be unbalanced")
    (assert (not (.-balanced r3)) "{(}) must be unbalanced")
    (assert (not (.-balanced r4)) "{[(])} must be unbalanced")
    (assert (not (bal/isDelimiterBalanced? "([)]")) "is-delimiter-balanced? must reject ([)]")
    true))

(df runTests [] -> Bool
  :d "Executes all delimiter balance unit tests."
  (and (testBalancedForms)
       (and (testUnbalancedForms)
            (and (testDelimitersInStrings)
                 (and (testCountUnclosedParens)
                      (and (testBalanceDelimiters)
                           (testInterleavedDelimiters)))))))

