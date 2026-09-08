(module asl-parser/tests/balance-test
  :d "Unit tests for pure AgentScript delimiter balance and structural verification engine."
  :x [run-tests]
  :i [(balance :a bal)])

(df test-balanced-forms [] -> Bool
  :d "Verifies properly balanced parentheses, brackets, and braces."
  (let [(code-sexpr "(defn foo [x y] (+ x (* y 2)))")
        (code-mixed "let arr = [{ id: 1, val: (x + y) }];")
        (res-sexpr (bal/check-delimiter-balance code-sexpr))
        (res-mixed (bal/check-delimiter-balance code-mixed))]
    (assert (.-balanced res-sexpr) "S-expression code must be balanced")
    (assert (= (.-open-parens res-sexpr) 0) "Open parens must be zero")
    (assert (= (.-open-brackets res-sexpr) 0) "Open brackets must be zero")
    (assert (.-balanced res-mixed) "Mixed syntax code must be balanced")
    true))

(df test-unbalanced-forms [] -> Bool
  :d "Verifies detection of unclosed or inverted delimiters."
  (let [(unclosed "(defn bar [x] (+ x 1)")
        (inverted "][")
        (inverted-parens ")(")
        (res-unclosed (bal/check-delimiter-balance unclosed))
        (res-inverted (bal/check-delimiter-balance inverted))
        (res-inverted-p (bal/check-delimiter-balance inverted-parens))]
    (assert (not (.-balanced res-unclosed)) "Unclosed parens must be flagged unbalanced")
    (assert (= (.-open-parens res-unclosed) 1) "Unclosed parens count must be 1")
    (assert (not (.-balanced res-inverted)) "Inverted brackets must be flagged unbalanced")
    (assert (not (.-balanced res-inverted-p)) "Inverted parens must be flagged unbalanced")
    (assert (not (bal/is-delimiter-balanced? unclosed)) "is-delimiter-balanced? must return false for unclosed")
    (assert (not (bal/is-delimiter-balanced? inverted)) "is-delimiter-balanced? must return false for inverted")
    true))

(df test-delimiters-in-strings [] -> Bool
  :d "Verifies that delimiters inside string literals do not affect balance."
  (let [(code-str "(println \")\")")
        (code-escaped "(println \"(\\\"foo\\\")\")")
        (res-str (bal/check-delimiter-balance code-str))
        (res-escaped (bal/check-delimiter-balance code-escaped))]
    (assert (.-balanced res-str) "Parens inside string literals must be ignored")
    (assert (.-balanced res-escaped) "Escaped quotes inside strings must be handled correctly")
    true))

(df test-count-unclosed-parens [] -> Bool
  :d "Verifies count-unclosed-parens returns exact count of unclosed open parentheses."
  (let [(code-two "((+ 1 2) (+ 3 4")
        (code-one "(println \"(\") (+ 1 2")
        (code-bal "(defn foo [] (+ 1 2))")]
    (assert (= (bal/count-unclosed-parens code-two) 2) "Open parens count must be 2")
    (assert (= (bal/count-unclosed-parens code-one) 1) "Open parens count must be 1")
    (assert (= (bal/count-unclosed-parens code-bal) 0) "Balanced code unclosed count must be 0")
    true))

(df run-tests [] -> Bool
  :d "Executes all delimiter balance unit tests."
  (and (test-balanced-forms)
       (and (test-unbalanced-forms)
            (and (test-delimiters-in-strings)
                 (test-count-unclosed-parens)))))
