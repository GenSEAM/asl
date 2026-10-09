(module asl-cli/tests/bootstrapTest
  :x [runTests]
  :i [(asl/packages/asl-gates/src/dyck :a dyck)])

fn verifyDelimiterBalance src: String -> Bool
  (none? (dyck/checkString src false))

fn testBalancedForms -> Bool
  (do
    (assert (verifyDelimiterBalance "(:ok (1 2 [3 4]))") "basic balanced parens and brackets")
    (assert (verifyDelimiterBalance "()") "empty parens")
    (assert (verifyDelimiterBalance "[]") "empty brackets")
    (assert (verifyDelimiterBalance "{}") "empty braces")
    (assert (verifyDelimiterBalance "") "empty string is balanced")
    (assert (verifyDelimiterBalance "   ") "whitespace string is balanced")
    (assert (verifyDelimiterBalance "(foo [bar {baz 1}])") "nested mixed delimiters")
    (assert (verifyDelimiterBalance "\"hello world\"") "simple string literal")
    true)

fn testStringLiteralAwareness -> Bool
  (do
    (assert (verifyDelimiterBalance "\"(\"") "open paren inside string must be ignored")
    (assert (verifyDelimiterBalance "\")\"") "close paren inside string must be ignored")
    (assert (verifyDelimiterBalance "\"[\"") "open bracket inside string must be ignored")
    (assert (verifyDelimiterBalance "\"]\"") "close bracket inside string must be ignored")
    (assert (verifyDelimiterBalance "\"(foo [bar])\"") "nested delimiters inside string must be ignored")
    (assert (verifyDelimiterBalance "(:tag \"hello (world [test]\" 42)") "string containing parens inside balanced form")
    (assert (verifyDelimiterBalance "(:tag \"escaped \\\" ( quote\" 1)") "escaped quote with paren inside string")
    (assert (verifyDelimiterBalance "(:tag \"escaped \\\\\" 2)") "escaped backslash followed by closing quote")
    true)

fn testUnderflowAndInversion -> Bool
  (do
    (refute (verifyDelimiterBalance ")(") "inverted parens must fail")
    (refute (verifyDelimiterBalance "][") "inverted brackets must fail")
    (refute (verifyDelimiterBalance "}{") "inverted braces must fail")
    (refute (verifyDelimiterBalance "())") "excess close paren must fail")
    (refute (verifyDelimiterBalance "[]]") "excess close bracket must fail")
    (refute (verifyDelimiterBalance "{}}") "excess close brace must fail")
    (refute (verifyDelimiterBalance "(()") "excess open paren must fail")
    (refute (verifyDelimiterBalance "[[]") "excess open bracket must fail")
    (refute (verifyDelimiterBalance "{{}") "excess open brace must fail")
    (refute (verifyDelimiterBalance "(module foo (fn bar [x] (+ x 1))) )") "trailing close delimiter must fail")
    true)

fn testUnclosedStrings -> Bool
  (do
    (refute (verifyDelimiterBalance "\"(unclosed string") "unclosed string literal must fail")
    (refute (verifyDelimiterBalance "(:msg \"hello)") "unclosed string before close paren must fail")
    (refute (verifyDelimiterBalance "\"escaped \\\" quote unclosed") "escaped quote followed by unclosed text must fail")
    true)

fn runTests -> Bool
  (and (testBalancedForms)
       (and (testStringLiteralAwareness)
            (and (testUnderflowAndInversion)
                 (testUnclosedStrings))))
