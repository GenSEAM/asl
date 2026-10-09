(module asl-parser/stage1FrontEndTest :x [runTests] :i [(asl-parser/ast :a ast) (indentLexer :a lx) (indentParser :a ip) (reader :a rd)])

fn caseFieldNames forms: (List ast/TopForm) -> (List Str)
  (fold (fn [(acc (List Str)) (f ast/TopForm)] -> (List Str) (mt f ((ast/topEnum e) (listAppend acc (map (fn [(c ast/EnumCase)] -> Str (str c.name "(" (stringJoin (map (fn [(p ast/Param)] -> Str (str p.name ":" p.type)) c.fields) " ") ")")) e.cases))) (_ acc))) (list) forms)

fn enumCases src: Str -> (List Str)
  (mt (ast/parse src) ((ok forms) (caseFieldNames forms)) ((err pe) (list (str "parse error: " pe.msg))))

fn rendered src: Str -> Str
  (mt (ip/parseIndented src) ((ok s) (rd/renderSexpr s)) ((err msg) (str "parse error: " msg)))

fn testParenthesizedEnumCases -> Bool
  (let [(src "(module m :x [] :i [])\n\nenum Pair\n  (pair first: A second: B)\n\nenum IoError\n  (notFound)\n  (other)\n\nenum PreludeMap\n  (preludeMapOf entries: (List (Pair K V)))\n\nfn f -> Int64\n  1\n")
        (got (enumCases src))]
    (do
      (assert (= got (list "pair(first:A second:B)" "notFound()" "other()" "preludeMapOf(entries:(List (Pair K V)))")) (str "enum cases: " (str got)))
      true))

fn testNamesEndingInQuestion -> Bool
  (let [(call (rendered "fn f x: Bool -> Bool\n  (rd/isAtom? x)\n"))
        (bound (rendered "fn g x: Bool -> Bool\n  (let [(hasEmptyName? (h x))] hasEmptyName?)\n"))
        (tried (rendered "fn h id: Int64 -> Result\n  raw = (queryDb id)?\n  ok raw\n"))]
    (do
      (assert (stringContains? call "(rd/isAtom? x)") (str "a call to a name ending in ? stays a call: " call))
      (refute (stringContains? call "__v") (str "a name ending in ? is not the try operator: " call))
      (assert (stringContains? bound "hasEmptyName?)") (str "a let-bound name ending in ? stays a name: " bound))
      (refute (stringContains? bound "__v") (str "a let-bound name ending in ? is not the try operator: " bound))
      (assert (stringContains? tried "(mt (queryDb id) ((ok __v) __v) ((err __e) (err __e)))") (str "? after a closing paren is the try operator: " tried))
      true))

fn testFunctionTypedParameters -> Bool
  (let [(r (rendered "fn listAny? pred: (fn [T] -> Bool) xs: (List T) -> Bool\n  true\n"))]
    (do
      (assert (stringContains? r "[(pred (fn (list T) -> Bool)) (xs (List T))]") (str "two parameters, the first function-typed: " r))
      (assert (stringContains? r "] -> Bool") (str "the return type follows the parameters: " r))
      true))

fn testBracesInStringLiterals -> Bool
  (let [(r (rendered "fn f -> Str\n  \"declare {i64, i1} @llvm.sadd\"\n"))
        (hole (rendered "fn g x: Str -> Str\n  \"a {x} b\"\n"))]
    (do
      (assert (stringContains? r "\"declare {i64, i1} @llvm.sadd\"") (str "braces around a non-name are literal text: " r))
      (refute (stringContains? r "(str") (str "no interpolation for a non-name hole: " r))
      (assert (stringContains? hole "\"a {x} b\"") (str "a {name} in a string literal is literal text, as the host reads it: " hole))
      (refute (stringContains? hole "(str") (str "a string literal never lowers to str: " hole))
      true))

fn stringValue src: Str -> Str
  (mt (listHead (filter (fn [(t lx/IndentToken)] -> Bool (mt t.kind ((tokString _) true) (_ false))) (lx/tokenize src)))
    ((some t) (mt t.kind ((tokString v) v) (_ "")))
    ((none) "no string token"))

fn badEscapeDiags src: Str -> (List Str)
  (map (fn [(d lx/LexerDiagnostic)] -> Str (str d.code " " d.msg)) (filter (fn [(d lx/LexerDiagnostic)] -> Bool (= d.code "E019")) (pairSecond (lx/tokenizeIndented src))))

fn testNoArrowFnRendersWithoutSentinel -> Bool
  (let [(src "(module m :x [] :i [])\n\nfn f x: Int64\n  (+ x 1)\n")
        (parsed (ast/parse src))
        (got (mt parsed ((ok forms) (stringJoin (map ast/renderNode forms) "\n")) ((err pe) (str "parse error: " pe.msg))))]
    (do
      (assert (not (stringContains? got ":inferredUnit")) (str "renderDefun must not leak :inferredUnit: " got))
      (assert (stringContains? got "(fn f [(x Int64)] (+ x 1))") (str "no-arrow fn header renders with no arrow at all: " got))
      true))

fn testHostStringEscapes -> Bool
  (let [(hex (stringValue "x = \"a\\x5cb\\x00c\\x41\"\n"))
        (uni (stringValue "x = \"\\u00e9\\u{62}\\u{1F600}\\u{10FFFF}\"\n"))
        (r (rendered "fn f -> Str\n  \"a\\x5cb\\x00c\\x1b\"\n"))
        (bad (rendered "fn f -> Str\n  \"a\\qb\"\n"))]
    (do
      (assert (= hex "a\x5cb\x00cA") (str "\\xHH decodes to the byte: " hex))
      (assert (= uni "\u00e9\u{62}\u{1F600}\u{10FFFF}") (str "\\uXXXX and \\u{1-6 hex} decode to UTF-8 as the host does: " uni))
      (map (fn [(body Str)] -> Bool
             (let [(diags (badEscapeDiags (str "x = \"" body "\"\n")))]
               (do (assert (and (= (listLength diags) 1) (stringContains? (optionOr (listHead diags) "") "ERR_BAD_ESCAPE")) (str body " is one E019 ERR_BAD_ESCAPE, as the host rejects it: " (stringJoin diags "; ")))
                   true)))
           (list "\\e" "\\q" "\\xZ1" "\\u12" "\\u{110000}" "\\uD800"))
      (assert (stringContains? bad "ERR_BAD_ESCAPE") (str "a bad escape fails the parse: " bad))
      (assert (stringContains? r (str "\"a" "\\\\" "b" "\\x00" "c" "\\x1b" "\"")) (str "the atom re-escapes backslash and control bytes: " r))
      true))

fn ! runTests -> Bool
  (do (assert (testParenthesizedEnumCases) "testParenthesizedEnumCases")
      (assert (testNamesEndingInQuestion) "testNamesEndingInQuestion")
      (assert (testFunctionTypedParameters) "testFunctionTypedParameters")
      (assert (testBracesInStringLiterals) "testBracesInStringLiterals")
      (assert (testHostStringEscapes) "testHostStringEscapes")
      (assert (testNoArrowFnRendersWithoutSentinel) "testNoArrowFnRendersWithoutSentinel")
      true)
