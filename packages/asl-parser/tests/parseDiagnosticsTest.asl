(module asl-parser/parseDiagnosticsTest :x [runTests] :i [(ast :a a) (indentParser :a ip) (reader :a rd)])

fn showTop r: (Result (List a/TopForm) a/ParseError) -> String
  (mt r ((ok fs) (str "ok " (stringJoin (map (fn [(t a/TopForm)] -> String (a/renderNode t)) fs) " | "))) ((err e) (str "err " (stringFromInt64 e.line) ":" (stringFromInt64 e.col) " " e.msg)))

fn showIndent r: (Result (List rd/SExpr) String) -> String
  (mt r ((ok fs) (str "ok " (stringJoin (map (fn [(s rd/SExpr)] -> String (rd/renderSexpr s)) fs) " | "))) ((err e) (str "err " e)))

fn testUnclosedIndentBody -> Bool
  (let [(got (showIndent (ip/parseIndentedForms "fn bad [] -> Int64\n  (foo 1\n")))] (do (assert (= got "err 2:3: unclosed '(' at end of file") (str "an unclosed paren in an indented body is an error at its opener, got " got)) true))

fn testUnclosedIndentTopLevel -> Bool
  (let [(got (showIndent (ip/parseIndentedForms "foo (bar 1\n")))] (do (assert (= got "err 1:5: unclosed '(' at end of file") (str "an unclosed top-level call is an error at its opener, got " got)) true))

fn testUnclosedKeepsPosition -> Bool
  (let [(got (showTop (a/parse "fn f x: Int64 -> Int64\n  (g x\n\nfn g x: Int64 -> Int64\n  x\n")))] (do (assert (= got "err 2:3 unclosed '(' at end of file") (str "parse reports an unclosed paren at its opener and keeps no form, got " got)) true))

fn testReaderErrorNotMasked -> Bool
  (let [(got (showTop (a/parse "(module m :x [] :i [])\n\n(fn f [(x Int64)] -> Int64\n  x)\n (g ]\n")))] (do (assert (= got "err 5:5 mismatched closing delimiter ']'") (str "a paren-source reader error is reported at the stray closer, got " got)) true))

fn testRecordLiteralParses -> Bool
  (let [(got (showTop (a/parse "(module m :x [] :i [])
(fn f [] -> Int64 (g {:a 1}))
")))] (do (refute (stringStartsWith? got "err") (str "a record literal the host accepts parses, got " got)) true))

fn testPascalFnName -> Bool
  (let [(got (showTop (a/parse "fn RunTests -> Bool\n  true\n")))] (do (assert (= got "ok (fn RunTests [] -> Bool true)") (str "a PascalCase fn name parses as the host reader accepts it, got " got)) true))

fn testFnNameErrorSurfaced -> Bool
  (let [(got (showTop (a/parse "fn :k -> Int64\n  1\n")))] (do (assert (= got "err 1:1 fn name must be a symbol: ':k'") (str "a bad fn name reports the name error, not the fallback's, got " got)) true))

fn testUnterminatedStringIndent -> Bool
  (let [(got (showTop (a/parse "fn f [] -> String\n  \"unterminated")))] (do (assert (= got "err 2:3 unterminated string literal") (str "unterminated string in indent body, got " got)) true))

fn testUnterminatedStringParenTop -> Bool
  (let [(got (showTop (a/parse "(module m :x [] :i [])\n\"unterminated")))] (do (assert (= got "err 2:1 unterminated string literal") (str "unterminated string at top-level in paren dialect, got " got)) true))

fn testUnterminatedStringIndentCall -> Bool
  (let [(got (showTop (a/parse "fn f [] -> String\n  (g \"unterminated)")))] (do (assert (= got "err 2:6 unterminated string literal") (str "unterminated string in indented call, got " got)) true))

fn testMismatchedBracketBracketParen -> Bool
  (let [(got (showTop (a/parse "(module m :x [] :i [])\n[ )")))] (do (assert (= got "err 2:3 mismatched closing delimiter ')'") (str "bracket-paren mismatch in paren dialect, got " got)) true))

fn testMismatchedBracketParenBracketIndent -> Bool
  (let [(got (showTop (a/parse "fn f [] -> Int64\n  ( ]")))] (do (assert (= got "err 2:5 ']' closes '(' opened at 2:3") (str "paren-bracket mismatch in indented dialect, got " got)) true))

fn testStrayCloseBraceIndent -> Bool
  (let [(got (showTop (a/parse "fn f [] -> Int64\n  }")))] (do (assert (= got "err 2:3 unmatched '}'") (str "stray close brace in indented dialect, got " got)) true))

fn runTests -> Bool
  (do (assert (testUnclosedIndentBody) "unclosed paren in an indented body")
      (assert (testUnclosedIndentTopLevel) "unclosed top-level call")
      (assert (testUnclosedKeepsPosition) "unclosed paren position through parse")
      (assert (testReaderErrorNotMasked) "reader error not masked by the indent fallback")
      (assert (testRecordLiteralParses) "record literal parses")
      (assert (testPascalFnName) "PascalCase fn name")
      (assert (testFnNameErrorSurfaced) "fn name error surfaced")
      (assert (testUnterminatedStringIndent) "unterminated string in indent body")
      (assert (testUnterminatedStringParenTop) "unterminated string at top-level in paren dialect")
      (assert (testUnterminatedStringIndentCall) "unterminated string in indented call")
      (assert (testMismatchedBracketBracketParen) "bracket-paren mismatch in paren dialect")
      (assert (testMismatchedBracketParenBracketIndent) "paren-bracket mismatch in indented dialect")
      (assert (testStrayCloseBraceIndent) "stray close brace in indented dialect")
      true)
