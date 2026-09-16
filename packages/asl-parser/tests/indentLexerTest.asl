(module asl-parser/indentLexerTest
  :d "Unit tests for pure ASL v0.4 Indentation-Aware Lexer (Item 1.1, Task T11_LEXER_V04)."
  :x [runTests]
  :i [(indentLexer :a lx)])

(df testBasicIndentation [] -> Bool
  :d "Verifies indentation stack, dedent flushing, and symbol classification."
  (let [(src (str "fn area s: Shape -> Float\n"
                  "  match s\n"
                  "    Circle r -> mul pi (mul r r)\n"))
        (res (lx/tokenizeIndented src))
        (toks (.-first res))
        (diags (.-second res))]
    (assert (list-empty? diags) "Basic well-formed indentation should have zero diagnostics")
    (assert (> (list-length toks) 10) "Tokens length must exceed 10")
    (let [(typeNames (map (fn [(t lx/IndentToken)] -> String (lx/tokenTypeName (.-kind t))) toks))]
      (let [(joined (string-join typeNames " "))]
        (assert (string-contains? joined "SYMBOL(fn)") "Must tokenize fn symbol")
        (assert (string-contains? joined "SYMBOL(area)") "Must tokenize area symbol")
        (assert (string-contains? joined "COLON") "Must tokenize type annotation colon")
        (assert (string-contains? joined "ARROW") "Must tokenize arrow operator")
        (assert (string-contains? joined "INDENT(1)") "Must emit INDENT(1) for match block")
        (assert (string-contains? joined "INDENT(2)") "Must emit INDENT(2) for Circle arm")
        (assert (string-contains? joined "DEDENT(0)") "Must flush DEDENT at EOF")
        (assert (string-contains? joined "EOF") "Must emit EOF sentinel")
        true))))

(df testW001TabConversion [] -> Bool
  :d "Verifies diagnostic W001 when tab appears in indentation."
  (let [(src (str "fn main\n"
                  "\tprint 42\n"))
        (res (lx/tokenizeIndented src))
        (diags (.-second res))]
    (assert (> (list-length diags) 0) "Must record diagnostic for tab")
    (let [(codes (map (fn [(d lx/LexerDiagnostic)] -> String (.-code d)) diags))]
      (assert (string-contains? (string-join codes " ") "W001") "Diagnostics must contain W001")
      true)))

(df testW002OddIndentation [] -> Bool
  :d "Verifies diagnostic W002 when odd number of spaces is used."
  (let [(src (str "fn main\n"
                  "   print 42\n"))
        (res (lx/tokenizeIndented src))
        (toks (.-first res))
        (diags (.-second res))]
    (let [(codes (map (fn [(d lx/LexerDiagnostic)] -> String (.-code d)) diags))]
      (assert (string-contains? (string-join codes " ") "W002") "Diagnostics must contain W002")
      (let [(typeNames (map (fn [(t lx/IndentToken)] -> String (lx/tokenTypeName (.-kind t))) toks))]
        (assert (string-contains? (string-join typeNames " ") "INDENT(1)") "3 spaces must round down to 1 indent level")
        true))))

(df testInterpolatedString [] -> Bool
  :d "Verifies {expr} string interpolation tokenization."
  (let [(src "print \"Hello {name}!\"\n")
        (res (lx/tokenizeIndented src))
        (toks (.-first res))]
    (let [(interpToks (map (fn [(t lx/IndentToken)] -> Bool (lx/isInterpolatedString? t)) toks))]
      (assert (fold (fn [(acc Bool) (b Bool)] -> Bool (or acc b)) false interpToks) "Must produce an interpolated string token")
      true)))

(df testCompoundDotIdentifiers [] -> Bool
  :d "Verifies atomic compound dot identifiers x.f.g."
  (let [(src "val = person.address.city\n")
        (res (lx/tokenizeIndented src))
        (toks (.-first res))]
    (let [(raws (map (fn [(t lx/IndentToken)] -> String (.-rawText t)) toks))]
      (assert (string-contains? (string-join raws " ") "person.address.city") "Must preserve compound dot identifier person.address.city")
      true)))

(df testCommentsSkipped [] -> Bool
  :d "Verifies line comments starting with # and ; are skipped cleanly."
  (let [(src (str "# leading comment\n"
                  "fn work\n"
                  "  ; inline comment line\n"
                  "  step 1\n"))
        (res (lx/tokenizeIndented src))
        (toks (.-first res))]
    (let [(raws (map (fn [(t lx/IndentToken)] -> String (.-rawText t)) toks))]
      (let [(allRaw (string-join raws " "))]
        (assert (not (string-contains? allRaw "leading")) "Comment text must not be emitted")
        (assert (not (string-contains? allRaw "inline")) "Comment text must not be emitted")
        (assert (string-contains? allRaw "work") "Code symbol work must be emitted")
        (assert (string-contains? allRaw "step") "Code symbol step must be emitted")
        true))))

(df runTests [] -> Bool
  :d "Runs all pure ASL v0.4 indent lexer unit tests."
  (assert (testBasicIndentation) "testBasicIndentation passed")
  (assert (testW001TabConversion) "testW001TabConversion passed")
  (assert (testW002OddIndentation) "testW002OddIndentation passed")
  (assert (testInterpolatedString) "testInterpolatedString passed")
  (assert (testCompoundDotIdentifiers) "testCompoundDotIdentifiers passed")
  (assert (testCommentsSkipped) "testCommentsSkipped passed")
  true)
