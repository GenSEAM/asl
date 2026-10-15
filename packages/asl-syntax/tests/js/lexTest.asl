(module asl-syntax/tests/js/lexTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)])

fn checkSingleToken input: String expectedKind: String -> Bool
  (let [(tokens (lx/tokenize input))
        (len (stringLength input))
        (tree (lx/tokenizeToTree input))]
    (do
      (assert (= (listLength tokens) 1) (str "single token count for: " input))
      (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))]
        (assert (= (tr/tokenKind tok) expectedKind) (str "expected token kind " expectedKind " for: " input)))
      (assert (ok? (tr/checkTokensTiling tokens len)) (str "tokens tile for: " input))
      (assert (ok? (tr/checkTilingRoot tree)) (str "tree tiles for: " input))
      (assert (= (pr/print input tree) input) (str "round-trip for: " input))
      true))

fn checkRoundTrip input: String -> Bool
  (let [(tokens (lx/tokenize input))
        (len (stringLength input))
        (tree (lx/tokenizeToTree input))]
    (do
      (assert (> (listLength tokens) 0) (str "tokens produced for: " input))
      (assert (ok? (tr/checkTokensTiling tokens len)) (str "tokens tile for: " input))
      (assert (ok? (tr/checkTilingRoot tree)) (str "tree tiles for: " input))
      (assert (= (pr/print input tree) input) (str "round-trip for: " input))
      true))

fn checkIdentToken input: String -> Bool
  (let [(tokens (lx/tokenize input))
        (len (stringLength input))]
    (do
      (assert (= (listLength tokens) 1) (str "single token for ident: " input))
      (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))]
        (do
          (assert (= (tr/tokenKind tok) "ident") (str "token kind ident for: " input))
          (assert (= (tr/tokenStart tok) 0) (str "token start 0 for: " input))
          (assert (= (tr/tokenEnd tok) len) (str "token end len for: " input))))
      (assert (checkSingleToken input "ident") (str "round-trip and tiling for: " input))
      true))

fn testDelimitersAndTrivia -> Bool
  (let [(s "   \t\x0b\x0c \n\r\n// line comment\n/* block \n comment */\n")
        (toks (lx/tokenize s))
        (tree (lx/tokenizeToTree s))]
    (do
      (assert (ok? (tr/checkTokensTiling toks (stringLength s))) "trivia tiles")
      (assert (ok? (tr/checkTilingRoot tree)) "trivia tree tiles")
      (assert (= (pr/print s tree) s) "trivia round-trips")
      (assert (checkSingleToken "  \t  " "whitespace") "whitespace token")
      (assert (checkSingleToken "\n" "newline") "newline token")
      (assert (checkSingleToken "\r\n" "newline") "crlf token")
      (assert (checkSingleToken "// a comment" "comment") "line comment")
      (assert (checkSingleToken "/* block */" "comment") "block comment")
      (assert (checkSingleToken "#!/usr/bin/env node" "comment") "hashbang comment")
      true))

fn testKeywordsAndIdentifiers -> Bool
  (do
    (assert (checkSingleToken "const" "keyword") "const keyword")
    (assert (checkSingleToken "let" "keyword") "let keyword")
    (assert (checkSingleToken "function" "keyword") "function keyword")
    (assert (checkSingleToken "return" "keyword") "return keyword")
    (assert (checkSingleToken "class" "keyword") "class keyword")
    (assert (checkSingleToken "import" "keyword") "import keyword")
    (assert (checkSingleToken "export" "keyword") "export keyword")
    (assert (checkSingleToken "await" "keyword") "await keyword")
    (assert (checkSingleToken "async" "keyword") "async keyword")
    (assert (checkSingleToken "yield" "keyword") "yield keyword")
    (assert (checkSingleToken "this" "keyword") "this keyword")
    (assert (checkSingleToken "super" "keyword") "super keyword")
    (assert (checkSingleToken "true" "boolean") "true boolean")
    (assert (checkSingleToken "false" "boolean") "false boolean")
    (assert (checkSingleToken "null" "null") "null literal")
    (assert (checkSingleToken "myVariable" "ident") "ident myVariable")
    (assert (checkSingleToken "$dollar" "ident") "ident $dollar")
    (assert (checkSingleToken "_underscore" "ident") "ident _underscore")
    (assert (checkSingleToken "café" "ident") "ident unicode café")
    (assert (checkSingleToken "v\\u0061r" "ident") "ident with unicode escape")
    (assert (checkSingleToken "#privateField" "privateIdent") "privateIdent")
    (assert (checkIdentToken "\\u{61}bc") "ident leading unicode brace escape")
    (assert (checkIdentToken "\\u0061bc") "ident leading unicode hex escape")
    (assert (checkIdentToken "a\\u{61}b") "ident middle unicode brace escape")
    (assert (checkIdentToken "a\\u0061b") "ident middle unicode hex escape")
    (assert (checkIdentToken "ab\\u{61}") "ident trailing unicode brace escape")
    (assert (checkIdentToken "ab\\u0061") "ident trailing unicode hex escape")
    true)

fn testNumericLiterals -> Bool
  (do
    (assert (checkSingleToken "0" "number") "decimal 0")
    (assert (checkSingleToken "42" "number") "decimal 42")
    (assert (checkSingleToken "1000000" "number") "decimal 1000000")
    (assert (checkSingleToken "1_000_000" "number") "decimal with separator")
    (assert (checkSingleToken "3.14159" "number") "decimal float")
    (assert (checkSingleToken ".5" "number") "leading dot float")
    (assert (checkSingleToken "1." "number") "trailing dot float")
    (assert (checkSingleToken "1e6" "number") "exponent float")
    (assert (checkSingleToken "2.5e-4" "number") "scientific float")
    (assert (checkSingleToken "0x1a2f" "number") "hex lowercase")
    (assert (checkSingleToken "0XDEADBEEF" "number") "hex uppercase")
    (assert (checkSingleToken "0xCA_FE" "number") "hex with separator")
    (assert (checkSingleToken "0b1011" "number") "binary literal")
    (assert (checkSingleToken "0B1100_0011" "number") "binary with separator")
    (assert (checkSingleToken "0o755" "number") "octal literal")
    (assert (checkSingleToken "0O644" "number") "octal uppercase")
    (assert (checkSingleToken "42n" "bigint") "decimal bigint")
    (assert (checkSingleToken "0x1fan" "bigint") "hex bigint")
    (assert (checkSingleToken "0b101n" "bigint") "binary bigint")
    (assert (checkSingleToken "0o77n" "bigint") "octal bigint")
    true)

fn testStringLiterals -> Bool
  (do
    (assert (checkSingleToken "'hello'" "string") "single quote string")
    (assert (checkSingleToken "\"world\"" "string") "double quote string")
    (assert (checkSingleToken "''" "string") "empty single quote string")
    (assert (checkSingleToken "\"\"" "string") "empty double quote string")
    (assert (checkSingleToken "'escapes: \\n \\r \\t \\\\ \\' \\\" \\x41 \\u0041'" "string") "string escapes")
    (assert (checkSingleToken "\"line \\\ncontinuation\"" "string") "line continuation string")
    true)

fn testTemplateLiterals -> Bool
  (do
    (assert (checkSingleToken "`plain template`" "templateNoSub") "no sub template")
    (assert (checkSingleToken "`empty`" "templateNoSub") "empty template")
    (assert (checkRoundTrip "`hello ${name} and ${1 + 2} end`") "template with interpolation")
    true)

fn testRegexVsDivide -> Bool
  (do
    (assert (checkSingleToken "/[a-z]+[0-9]*/gi" "regex") "regex with flags")
    (assert (checkSingleToken "/\\/test\\//m" "regex") "regex with escaped slash")
    (assert (checkRoundTrip "const x = a / b;") "division expression")
    (assert (checkRoundTrip "const x = a /= b;") "slash assign expression")
    (assert (checkRoundTrip "return /abc/g.test(s);") "return regex")
    (assert (checkRoundTrip "const r = (/pattern/).exec(str);") "paren regex")
    (assert (checkRoundTrip "foo(/bar/, 1 / 2);") "call with regex and div")
    (assert (checkRoundTrip "pos < raw.length && /\\s/.test(raw[pos]);") "and and regex")
    true)

fn testOperatorsAndPunctuators -> Bool
  (do
    (assert (checkSingleToken "(" "lparen") "lparen")
    (assert (checkSingleToken ")" "rparen") "rparen")
    (assert (checkSingleToken "[" "lbracket") "lbracket")
    (assert (checkSingleToken "]" "rbracket") "rbracket")
    (assert (checkSingleToken "{" "lbrace") "lbrace")
    (assert (checkSingleToken "}" "rbrace") "rbrace")
    (assert (checkSingleToken ";" "semicolon") "semicolon")
    (assert (checkSingleToken "," "comma") "comma")
    (assert (checkSingleToken ":" "colon") "colon")
    (assert (checkSingleToken "?" "question") "question")
    (assert (checkSingleToken "." "dot") "dot")
    (assert (checkSingleToken "..." "ellipsis") "ellipsis")
    (assert (checkSingleToken "?." "questionDot") "questionDot")
    (assert (checkSingleToken "=>" "arrow") "arrow")
    (assert (checkSingleToken "@" "at") "at")
    (assert (checkSingleToken "=" "assign") "assign")
    (assert (checkSingleToken "==" "eqEq") "eqEq")
    (assert (checkSingleToken "===" "eqEqEq") "eqEqEq")
    (assert (checkSingleToken "!=" "bangEq") "bangEq")
    (assert (checkSingleToken "!==" "bangEqEq") "bangEqEq")
    (assert (checkSingleToken "<" "lt") "lt")
    (assert (checkSingleToken "<=" "lte") "lte")
    (assert (checkSingleToken ">" "gt") "gt")
    (assert (checkSingleToken ">=" "gte") "gte")
    (assert (checkSingleToken "++" "plusPlus") "plusPlus")
    (assert (checkSingleToken "--" "minusMinus") "minusMinus")
    (assert (checkSingleToken "+" "plus") "plus")
    (assert (checkSingleToken "-" "minus") "minus")
    (assert (checkSingleToken "*" "star") "star")
    (assert (checkSingleToken "**" "starStar") "starStar")
    (let [(tDiv (optionOr (listHead (lx/tokenizeWithGoal "/" (lx/goalDiv))) (tr/makeToken "" 0 0)))]
      (assert (= (tr/tokenKind tDiv) "slash") "slash in goalDiv"))
    (assert (checkSingleToken "%" "percent") "percent")
    (assert (checkSingleToken "&&" "ampAmp") "ampAmp")
    (assert (checkSingleToken "||" "pipePipe") "pipePipe")
    (assert (checkSingleToken "??" "questionQuestion") "questionQuestion")
    (assert (checkSingleToken "!" "bang") "bang")
    (assert (checkSingleToken "~" "tilde") "tilde")
    (assert (checkSingleToken "&" "amp") "amp")
    (assert (checkSingleToken "|" "pipe") "pipe")
    (assert (checkSingleToken "^" "caret") "caret")
    (assert (checkSingleToken "<<" "shl") "shl")
    (assert (checkSingleToken ">>" "shr") "shr")
    (assert (checkSingleToken ">>>" "shru") "shru")
    (assert (checkSingleToken "+=" "plusAssign") "plusAssign")
    (assert (checkSingleToken "-=" "minusAssign") "minusAssign")
    (assert (checkSingleToken "*=" "starAssign") "starAssign")
    (let [(tDivA (optionOr (listHead (lx/tokenizeWithGoal "/=" (lx/goalDiv))) (tr/makeToken "" 0 0)))]
      (assert (= (tr/tokenKind tDivA) "slashAssign") "slashAssign in goalDiv"))
    (assert (checkSingleToken "%=" "percentAssign") "percentAssign")
    (assert (checkSingleToken "**=" "starStarAssign") "starStarAssign")
    (assert (checkSingleToken "&&=" "ampAmpAssign") "ampAmpAssign")
    (assert (checkSingleToken "||=" "pipePipeAssign") "pipePipeAssign")
    (assert (checkSingleToken "??=" "questionQuestionAssign") "questionQuestionAssign")
    (assert (checkSingleToken "&=" "ampAssign") "ampAssign")
    (assert (checkSingleToken "|=" "pipeAssign") "pipeAssign")
    (assert (checkSingleToken "^=" "caretAssign") "caretAssign")
    (assert (checkSingleToken "<<=" "shlAssign") "shlAssign")
    (assert (checkSingleToken ">>=" "shrAssign") "shrAssign")
    (assert (checkSingleToken ">>>=" "shruAssign") "shruAssign")
    true)

fn testGoalModes -> Bool
  (do
    (let [(toksRegex (lx/tokenizeWithGoal "/abc/g" (lx/goalRegex)))]
      (assert (= (listLength toksRegex) 1) "goalRegex single token")
      (assert (= (tr/tokenKind (optionOr (listHead toksRegex) (tr/makeToken "" 0 0))) "regex") "goalRegex parses regex"))
    (let [(toksDiv (lx/tokenizeWithGoal "/abc/g" (lx/goalDiv)))]
      (assert (> (listLength toksDiv) 1) "goalDiv produces multiple tokens")
      (assert (= (tr/tokenKind (optionOr (listHead toksDiv) (tr/makeToken "" 0 0))) "slash") "goalDiv starts with slash"))
    (let [(toksJsx (lx/tokenizeWithGoal "hello world <tag>" (lx/goalJsxText)))]
      (assert (= (tr/tokenKind (optionOr (listHead toksJsx) (tr/makeToken "" 0 0))) "jsxText") "goalJsxText parses jsxText"))
    true)

fn testAsiNewlineFlags -> Bool
  (let [(code "return\n42")
        (toks (lx/tokenize code))]
    (do
      (assert (lx/hasNewlineBetween? toks 0 2) "newline detected between return and 42")
      (let [(singleLine "return 42")
            (toks2 (lx/tokenize singleLine))]
        (assert (not (lx/hasNewlineBetween? toks2 0 2)) "no newline between return and 42"))
      true))

fn testTrackedFile! path: String -> Bool
  (let [(res (fileReadString path))]
    (mt res
      ((err msg) (assert false (str "failed to read file: " path " error: " msg)))
      ((ok content)
       (let [(len (stringLength content))
             (tokens (lx/tokenize content))
             (tree (lx/tokenizeToTree content))]
         (do
           (assert (> (listLength tokens) 0) (str "tokens non-empty for: " path))
           (assert (ok? (tr/checkTokensTiling tokens len)) (str "tiling check for: " path))
           (assert (ok? (tr/checkTilingRoot tree)) (str "tree tiling for: " path))
           (let [(printed (pr/print content tree))]
             (assert (= (stringLength printed) len) (str "length matches for: " path))
             (assert (= printed content) (str "byte exact round-trip for: " path))
             true))))))

fn testTrackedFiles! -> Bool
  (do
    (assert (testTrackedFile! "asl/web/bridge/boot.js") "boot.js round-trip")
    (assert (testTrackedFile! "asl/packages/asl-syntax/tests/fixtures/js/vite.config.js.sample") "vite.config.js round-trip")
    (assert (testTrackedFile! "asl/packages/asl-syntax/tests/fixtures/js/tailwind.config.js.sample") "tailwind.config.js round-trip")
    (assert (testTrackedFile! "asl/packages/asl-syntax/tests/fixtures/js/vitePluginAsl.js.sample") "vitePluginAsl.js round-trip")
    (assert (testTrackedFile! "tests/harnessBench/cases/attention-flood/svc/vendor/uploader.min.js") "uploader.min.js round-trip")
    true)

fn testCompoundPunctErrorToken -> Bool
  (do
    (assert (checkSingleToken "#" "error") "hash without ident start yields error token")
    (assert (checkSingleToken "\\" "error") "backslash without u yields error token")
    (let [(toks (lx/tokenize "#123"))
          (t0 (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (do
        (assert (= (tr/tokenKind t0) "error") "hash before number is error token")
        (assert (= (tr/tokenStart t0) 0) "error token start 0")
        (assert (= (tr/tokenEnd t0) 1) "error token end 1")))
    (let [(toks (lx/tokenize "\\bar"))
          (t0 (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (do
        (assert (= (tr/tokenKind t0) "error") "backslash before ident is error token")
        (assert (= (tr/tokenStart t0) 0) "error token start 0")
        (assert (= (tr/tokenEnd t0) 1) "error token end 1")))
    true)

fn hasErrorToken toks: (List tr/Token) -> Bool
  (if (listEmpty? toks)
    false
    (let [(head (optionOr (listHead toks) (tr/makeToken "" 0 0)))
          (tail (optionOr (listTail toks) (list)))]
      (if (= (tr/tokenKind head) "error")
        true
        (hasErrorToken tail))))

fn isNegativeParseTest content: String -> Bool
  (and (stringContains? content "negative:")
       (stringContains? content "phase: parse"))

fn test262ExclusionReason path: String exclusions: (List (Pair String String)) -> (Option String)
  (if (listEmpty? exclusions)
    (none)
    (let [(head (optionOr (listHead exclusions) (pair "" "")))
          (tail (optionOr (listTail exclusions) (list)))]
      (if (= (pairFirst head) path)
        (some (pairSecond head))
        (test262ExclusionReason path tail))))

fn test262Exclusions -> (List (Pair String String))
  (list
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-if.js.sample" "reserved word in identifier position (syntactic parse error, not a lexical error)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-else.js.sample" "reserved word in identifier position (syntactic parse error, not a lexical error)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-while.js.sample" "reserved word in identifier position (syntactic parse error, not a lexical error)"))

fn printTest262Exclusions! cases: (List (Pair String String)) -> Bool
  (if (listEmpty? cases)
    true
    (let [(head (optionOr (listHead cases) (pair "" "")))
          (tail (optionOr (listTail cases) (list)))]
      (do
        (println (str "  test262 excluded: " (pairFirst head) " (" (pairSecond head) ")"))
        (printTest262Exclusions! tail))))

fn test262Files -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/7.8.3-3gs.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.3_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A4.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A4.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A4.2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1gs.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-2gs.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/evaluation-order.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-abrupt.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-function.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-member-expr.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-method.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-obj.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-primitive.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-template.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A4_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A4_T3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/function-body.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/statement-block.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/preceding-whitespace.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.3_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.4_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.5_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A3.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A3.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A3.3_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/7.3-15.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/7.3-5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/7.3-6.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A5.4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_continue-escaped.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_continue.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_start-escaped.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_start.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/part-digits-via-escape-hex.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/part-digits-via-escape-hex4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-if.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-else.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-while.js.sample")

fn checkTest262Files! files: (List String) runCount: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (println (str "test262 lexical suite: " (stringFromInt64 runCount) " run, " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printTest262Exclusions! (test262Exclusions))
      (assert (= (+ runCount excludedCount) 65) "all 65 test262 cases accounted for")
      (assert (= runCount 62) "62 test262 cases executed")
      (assert (= passCount 62) "62 test262 cases passed")
      (assert (= excludedCount 3) "3 test262 cases excluded with documented reasons")
      true)
    (let [(path (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (mt (test262ExclusionReason path (test262Exclusions))
        ((some _)
         (checkTest262Files! rest runCount passCount (+ excludedCount 1)))
        ((none)
         (let [(readRes (fileReadString path))]
           (do
             (assert (ok? readRes) (str "readable test262 file: " path))
             (let [(content (resultOr readRes ""))
                   (len (stringLength content))
                   (toks (lx/tokenize content))
                   (tree (lx/tokenizeToTree content))
                   (isNeg (isNegativeParseTest content))]
               (if isNeg
                 (do
                   (assert (hasErrorToken toks) (str "negative lexical test must yield error token: " path))
                   (checkTest262Files! rest (+ runCount 1) (+ passCount 1) excludedCount))
                 (do
                   (refute (hasErrorToken toks) (str "positive test must not yield error token: " path))
                   (assert (ok? (tr/checkTokensTiling toks len)) (str "tokens tile: " path))
                   (assert (ok? (tr/checkTilingRoot tree)) (str "tree tiles: " path))
                   (let [(printed (pr/print content tree))]
                     (assert (= printed content) (str "byte exact round-trip: " path))
                     (checkTest262Files! rest (+ runCount 1) (+ passCount 1) excludedCount)))))))))))

fn testPinnedtest262Cases! -> Bool
  (checkTest262Files! (test262Files) 0 0 0)

fn ! runTests -> Bool
  (do
    (assert (testDelimitersAndTrivia) "delimiters and trivia")
    (assert (testKeywordsAndIdentifiers) "keywords and identifiers")
    (assert (testNumericLiterals) "numeric literals")
    (assert (testStringLiterals) "string literals")
    (assert (testTemplateLiterals) "template literals")
    (assert (testRegexVsDivide) "regex vs divide")
    (assert (testOperatorsAndPunctuators) "operators and punctuators")
    (assert (testGoalModes) "goal modes")
    (assert (testAsiNewlineFlags) "ASI newline flags")
    (assert (testCompoundPunctErrorToken) "compound punct error token")
    (assert (testPinnedtest262Cases!) "pinned test262 cases")
    (assert (testTrackedFiles!) "4 tracked files round-trip")
    true)
