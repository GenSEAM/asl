(module asl-parser/indentLexerTest :x [runTests] :i [(indentLexer :a lx)])

fn testBasicIndentation -> Bool
  (let [(src (str "fn area s: Shape -> Float\n" "  match s\n" "    Circle r -> mul pi (mul r r)\n")) (res (lx/tokenizeIndented src)) (toks (pairFirst res)) (diags (pairSecond res))] (assert (listEmpty? diags) "Basic well-formed indentation should have zero diagnostics") (assert (> (listLength toks) 10) "Tokens length must exceed 10") (let [(typeNames (map (fn [(t lx/IndentToken)] -> String (lx/tokenTypeName t.kind)) toks))] (let [(joined (stringJoin typeNames " "))] (assert (stringContains? joined "SYMBOL(fn)") "Must tokenize fn symbol") (assert (stringContains? joined "SYMBOL(area)") "Must tokenize area symbol") (assert (stringContains? joined "COLON") "Must tokenize type annotation colon") (assert (stringContains? joined "ARROW") "Must tokenize arrow operator") (assert (stringContains? joined "INDENT(1)") "Must emit INDENT(1) for match block") (assert (stringContains? joined "INDENT(2)") "Must emit INDENT(2) for Circle arm") (assert (stringContains? joined "DEDENT(0)") "Must flush DEDENT at EOF") (assert (stringContains? joined "EOF") "Must emit EOF sentinel") true)))

fn testW001TabConversion -> Bool
  (let [(src (str "fn main\n" "\tprint 42\n")) (res (lx/tokenizeIndented src)) (diags (pairSecond res))] (assert (> (listLength diags) 0) "Must record diagnostic for tab") (let [(codes (map (fn [(d lx/LexerDiagnostic)] -> String d.code) diags))] (assert (stringContains? (stringJoin codes " ") "W001") "Diagnostics must contain W001") true))

fn testW002OddIndentation -> Bool
  (let [(src (str "fn main\n" "   print 42\n")) (res (lx/tokenizeIndented src)) (toks (pairFirst res)) (diags (pairSecond res))] (let [(codes (map (fn [(d lx/LexerDiagnostic)] -> String d.code) diags))] (assert (stringContains? (stringJoin codes " ") "W002") "Diagnostics must contain W002") (let [(typeNames (map (fn [(t lx/IndentToken)] -> String (lx/tokenTypeName t.kind)) toks))] (assert (stringContains? (stringJoin typeNames " ") "INDENT(1)") "3 spaces must round down to 1 indent level") true)))

fn testInterpolatedString -> Bool
  (let [(src "print \"Hello {name}!\"\n") (res (lx/tokenizeIndented src)) (toks (pairFirst res)) (vals (map (fn [(t lx/IndentToken)] -> String (mt t.kind ((lx/tokString v) (str "STRING:" v)) (_ (lx/tokenTypeName t.kind)))) toks))] (do (assert (listContains? vals "STRING:Hello {name}!") (str "a {name} hole is literal text of a plain string token, as the host reads it: " (stringJoin vals " "))) (assert (listEmpty? (pairSecond res)) "a brace in a string literal raises no diagnostic") true))

fn testCompoundDotIdentifiers -> Bool
  (let [(src "val = person.address.city\n") (res (lx/tokenizeIndented src)) (toks (pairFirst res))] (let [(raws (map (fn [(t lx/IndentToken)] -> String t.rawText) toks))] (assert (stringContains? (stringJoin raws " ") "person.address.city") "Must preserve compound dot identifier person.address.city") true))

fn testCommentsSkipped -> Bool
  (let [(src (str "# leading comment\n" "fn work\n" "  ; inline comment line\n" "  step 1\n")) (res (lx/tokenizeIndented src)) (toks (pairFirst res))] (let [(raws (map (fn [(t lx/IndentToken)] -> String t.rawText) toks))] (let [(allRaw (stringJoin raws " "))] (assert (not (stringContains? allRaw "leading")) "Comment text must not be emitted") (assert (not (stringContains? allRaw "inline")) "Comment text must not be emitted") (assert (stringContains? allRaw "work") "Code symbol work must be emitted") (assert (stringContains? allRaw "step") "Code symbol step must be emitted") true)))

fn testMultiLineStringLiteral -> Bool
  (let [(src (str "val = \"line one\n" "line two\"\n")) (res (lx/tokenizeIndented src)) (toks (pairFirst res)) (diags (pairSecond res)) (vals (map (fn [(t lx/IndentToken)] -> String (mt t.kind ((lx/tokString v) (str "STRING:" v)) (_ (lx/tokenTypeName t.kind)))) toks))] (do (assert (listContains? vals (str "STRING:line one\n" "line two")) (str "a string literal spanning two physical lines keeps the embedded newline as literal text, as the host reads it: " (stringJoin vals " "))) (assert (listEmpty? diags) (str "a closed multi-line string raises no diagnostic, got " (stringJoin (map (fn [(d lx/LexerDiagnostic)] -> String d.code) diags) " "))) true))

fn testEscapedAndRealNewlineInString -> Bool
  (let [(src (str "val = \"a\\nb\n" "c\"\n")) (res (lx/tokenizeIndented src)) (toks (pairFirst res)) (vals (map (fn [(t lx/IndentToken)] -> String (mt t.kind ((lx/tokString v) (str "STRING:" v)) (_ (lx/tokenTypeName t.kind)))) toks))] (do (assert (listContains? vals (str "STRING:a\n" "b\n" "c")) (str "an escaped \\n and a real embedded newline both decode to a newline byte, as the host reads it: " (stringJoin vals " "))) true))

fn testUnterminatedStringAtEof -> Bool
  (let [(src (str "val = \"abc\n" "def\n")) (res (lx/tokenizeIndented src)) (diags (pairSecond res)) (codes (map (fn [(d lx/LexerDiagnostic)] -> String d.code) diags))] (do (assert (stringContains? (stringJoin codes " ") "E010") (str "a string literal never closed by end of file is still an error, got " (stringJoin codes " "))) (assert (listContains? (map (fn [(d lx/LexerDiagnostic)] -> Int64 d.line) diags) 1) "the E010 diagnostic points at the line where the string opened") true))

fn stringsOf src: String -> (List String)
  (filter (fn [(v String)] -> Bool (stringStartsWith? v "STRING:")) (map (fn [(t lx/IndentToken)] -> String (mt t.kind ((lx/tokString v) (str "STRING:" v)) (_ ""))) (pairFirst (lx/tokenizeIndented src))))

fn escapeCodes src: String -> (List String)
  (filter (fn [(c String)] -> Bool (= c "E019")) (map (fn [(d lx/LexerDiagnostic)] -> String d.code) (pairSecond (lx/tokenizeIndented src))))

fn testStrictEscapes -> Bool
  (do (assert (= (stringsOf "val = \"\\u{62}\\u{1F600}\\u00e9\\x41\"\n") (list (str "STRING:" "\u{62}\u{1F600}\u00e9\x41"))) "braced, 4-digit and byte escapes decode as the host reader does")
      (assert (listEmpty? (escapeCodes "val = \"\\u{10FFFF}\\n\\t\\r\\\\\\\"\"\n")) "the accepted set gives no E019")
      (map (fn [(body String)] -> Bool
             (do (assert (= (escapeCodes (str "val = \"" body "\"\n")) (list "E019")) (str body " gives one E019 ERR_BAD_ESCAPE"))
                 true))
           (list "\\u{1g}" "\\u{110000}" "\\u{}" "\\u{D800}" "\\xZZ" "\\x-1" "\\a" "\\q" "\\0" "\\e" "\\{" "\\u +1a" "\\uD800"))
      true)

fn testManyEscapesLinear -> Bool
  (let [(n 8000)
        (body (stringJoin (map (fn [(i Int64)] -> String "ab\\\"") (range 0 n)) ""))
        (lens (map (fn [(v String)] -> Int64 (- (stringLength v) 7)) (stringsOf (str "val = \"" body "\"\n"))))]
    (do (assert (= lens (list (* 3 n))) "8000 escaped quotes decode in one pass to 24000 bytes") true))

fn runTests -> Bool
  (do (assert (testStrictEscapes) "testStrictEscapes passed") (assert (testManyEscapesLinear) "testManyEscapesLinear passed") (assert (testBasicIndentation) "testBasicIndentation passed") (assert (testW001TabConversion) "testW001TabConversion passed") (assert (testW002OddIndentation) "testW002OddIndentation passed") (assert (testInterpolatedString) "testInterpolatedString passed") (assert (testCompoundDotIdentifiers) "testCompoundDotIdentifiers passed") (assert (testCommentsSkipped) "testCommentsSkipped passed") (assert (testMultiLineStringLiteral) "testMultiLineStringLiteral passed") (assert (testEscapedAndRealNewlineInString) "testEscapedAndRealNewlineInString passed") (assert (testUnterminatedStringAtEof) "testUnterminatedStringAtEof passed") true)
