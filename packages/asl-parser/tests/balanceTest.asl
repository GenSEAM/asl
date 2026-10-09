(module asl-parser/tests/balanceTest :x [runTests] :i [(balance :a bal)])

fn testBalancedForms -> Bool
  (let [(codeSexpr "(defn foo [x y] (+ x (* y 2)))") (codeMixed "let arr = [{ id: 1, val: (x + y) }];") (resSexpr (bal/checkDelimiterBalance codeSexpr)) (resMixed (bal/checkDelimiterBalance codeMixed))] (assert resSexpr.balanced "S-expression code must be balanced") (assert (= resSexpr.openParens 0) "Open parens must be zero") (assert (= resSexpr.openBrackets 0) "Open brackets must be zero") (assert resMixed.balanced "Mixed syntax code must be balanced") true)

fn testUnbalancedForms -> Bool
  (let [(unclosed "(defn bar [x] (+ x 1)") (inverted "][") (invertedParens ")(") (resUnclosed (bal/checkDelimiterBalance unclosed)) (resInverted (bal/checkDelimiterBalance inverted)) (resInvertedP (bal/checkDelimiterBalance invertedParens))] (assert (not resUnclosed.balanced) "Unclosed parens must be flagged unbalanced") (assert (= resUnclosed.openParens 1) "Unclosed parens count must be 1") (assert (not resInverted.balanced) "Inverted brackets must be flagged unbalanced") (assert (not resInvertedP.balanced) "Inverted parens must be flagged unbalanced") (assert (not (bal/isDelimiterBalanced? unclosed)) "is-delimiter-balanced? must return false for unclosed") (assert (not (bal/isDelimiterBalanced? inverted)) "is-delimiter-balanced? must return false for inverted") true)

fn testDelimitersInComments -> Bool
  (let [(code1 "(a ; )\n)")
        (code2 "(defn foo [x] ; [unclosed bracket\n(+ x 1))")
        (code3 "; comment with (\n(defn bar [] 42)")
        (code4 "(defn bad []\n; )\n")
        (codeStrComment "(println \"; not a comment )\")")
        (res1 (bal/checkDelimiterBalance code1))
        (res2 (bal/checkDelimiterBalance code2))
        (res3 (bal/checkDelimiterBalance code3))
        (res4 (bal/checkDelimiterBalance code4))
        (resStr (bal/checkDelimiterBalance codeStrComment))]
    (assert res1.balanced "Paren inside comment must be ignored; code1 is balanced")
    (assert (bal/isDelimiterBalanced? code1) "isDelimiterBalanced? must return true for code1")
    (assert (bal/isDyck1Balanced? code1) "isDyck1Balanced? must return true for code1")
    (assert res2.balanced "Bracket inside comment must be ignored")
    (assert res3.balanced "Leading comment with open paren must be ignored")
    (assert (not res4.balanced) "Close paren inside comment must not close outer paren; code4 is unbalanced")
    (assert (not (bal/isDelimiterBalanced? code4)) "isDelimiterBalanced? must return false for code4")
    (assert (= res4.openParens 1) "Open parens count must be 1 for code4")
    (assert resStr.balanced "Semicolon inside string is not a comment")
    true)

fn testDelimitersInStrings -> Bool
  (let [(codeStr "(println \")\")") (codeEscaped "(println \"(\\\"foo\\\")\")") (resStr (bal/checkDelimiterBalance codeStr)) (resEscaped (bal/checkDelimiterBalance codeEscaped))] (assert resStr.balanced "Parens inside string literals must be ignored") (assert resEscaped.balanced "Escaped quotes inside strings must be handled correctly") true)

fn testCountUnclosedParens -> Bool
  (let [(codeTwo "((+ 1 2) (+ 3 4") (codeOne "(println \"(\") (+ 1 2") (codeBal "(defn foo [] (+ 1 2))")] (assert (= (bal/countUnclosedParens codeTwo) 2) "Open parens count must be 2") (assert (= (bal/countUnclosedParens codeOne) 1) "Open parens count must be 1") (assert (= (bal/countUnclosedParens codeBal) 0) "Balanced code unclosed count must be 0") true)

fn testBalanceDelimiters -> Bool
  (let [(unclosed "(defn foo [x] (+ x 1") (balanced (bal/balanceDelimiters unclosed)) (alreadyBal "(defn bar [] 42)") (unchanged (bal/balanceDelimiters alreadyBal))] (assert (= balanced "(defn foo [x] (+ x 1))") "Must append 1 closing paren") (assert (= unchanged alreadyBal) "Must leave balanced code unchanged") true)

fn testInterleavedDelimiters -> Bool
  (let [(r1 (bal/checkDelimiterBalance "([)]")) (r2 (bal/checkDelimiterBalance "[(])")) (r3 (bal/checkDelimiterBalance "{(})")) (r4 (bal/checkDelimiterBalance "{[(])}"))] (assert (not r1.balanced) "([)] must be unbalanced") (assert (not r2.balanced) "[(]) must be unbalanced") (assert (not r3.balanced) "{(}) must be unbalanced") (assert (not r4.balanced) "{[(])} must be unbalanced") (assert (not (bal/isDelimiterBalanced? "([)]")) "is-delimiter-balanced? must reject ([)]") true)

fn runTests -> Bool
  (and (testBalancedForms) (and (testUnbalancedForms) (and (testDelimitersInComments) (and (testDelimitersInStrings) (and (testCountUnclosedParens) (and (testBalanceDelimiters) (testInterleavedDelimiters)))))))
