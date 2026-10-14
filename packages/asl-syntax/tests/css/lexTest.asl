(module asl-syntax/tests/css/lexTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/corpus :a crp)
      (asl-syntax/css/lex :a lex)
      (asl-json/json :a j)])

fn checkSingleToken input: String expectedKind: String -> Bool
  (let [(tokens (lex/tokenizeText input))
        (len (stringLength input))
        (tree (lex/tokenizeToTree input))]
    (do
      (assert (= (listLength tokens) 1) (str "single token count for: " input))
      (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))]
        (assert (= (tr/tokenKind tok) expectedKind) (str "expected token kind " expectedKind " for: " input)))
      (assert (ok? (tr/checkTokensTiling tokens len)) (str "tokens tile for: " input))
      (assert (ok? (tr/checkTilingRoot tree)) (str "tree tiles for: " input))
      (assert (= (pr/print input tree) input) (str "round-trip for: " input))
      true))

fn checkRoundTrip input: String -> Bool
  (let [(tokens (lex/tokenizeText input))
        (len (stringLength input))
        (tree (lex/tokenizeToTree input))]
    (do
      (assert (> (listLength tokens) 0) (str "tokens produced for: " input))
      (assert (ok? (tr/checkTokensTiling tokens len)) (str "tokens tile for: " input))
      (assert (ok? (tr/checkTilingRoot tree)) (str "tree tiles for: " input))
      (assert (= (pr/print input tree) input) (str "round-trip for: " input))
      true))

fn testPinnedIdents -> Bool
  (do
    (assert (checkSingleToken "color" "ident") "ident color")
    (assert (checkSingleToken "background-color" "ident") "ident background-color")
    (assert (checkSingleToken "_custom" "ident") "ident _custom")
    (assert (checkSingleToken "--theme-color" "ident") "ident --theme-color")
    (assert (checkSingleToken "-moz-box" "ident") "ident -moz-box")
    (assert (checkSingleToken "\\31 23" "ident") "ident with escape \\31 23")
    (assert (checkSingleToken "c\\6f lor" "ident") "ident with escape c\\6f lor")
    (assert (checkSingleToken "café" "ident") "ident unicode café")
    (assert (checkSingleToken "---" "ident") "ident ---")
    true)

fn testPinnedNumbers -> Bool
  (do
    (assert (checkSingleToken "9" "number") "number 9")
    (assert (checkSingleToken "42" "number") "number 42")
    (assert (checkSingleToken "+100" "number") "number +100")
    (assert (checkSingleToken "-50" "number") "number -50")
    (assert (checkSingleToken "0.5" "number") "number 0.5")
    (assert (checkSingleToken ".5" "number") "number .5")
    (assert (checkSingleToken "+0.75" "number") "number +0.75")
    (assert (checkSingleToken "-10.25" "number") "number -10.25")
    (assert (checkSingleToken "1e3" "number") "number 1e3")
    (assert (checkSingleToken "2.5e-4" "number") "number 2.5e-4")
    (assert (checkSingleToken "-3.14E+2" "number") "number -3.14E+2")
    (assert (checkSingleToken "100%" "percentage") "percentage 100%")
    (assert (checkSingleToken "0%" "percentage") "percentage 0%")
    (assert (checkSingleToken "-10%" "percentage") "percentage -10%")
    (assert (checkSingleToken "10px" "dimension") "dimension 10px")
    (assert (checkSingleToken "2.5rem" "dimension") "dimension 2.5rem")
    (assert (checkSingleToken "100vh" "dimension") "dimension 100vh")
    (assert (checkSingleToken "45deg" "dimension") "dimension 45deg")
    (assert (checkSingleToken "300ms" "dimension") "dimension 300ms")
    (assert (checkSingleToken "2s" "dimension") "dimension 2s")
    (assert (checkSingleToken "-5px" "dimension") "dimension -5px")
    true)

fn testPinnedStrings -> Bool
  (do
    (assert (checkSingleToken "\"hello world\"" "string") "double quoted string")
    (assert (checkSingleToken "'single quoted'" "string") "single quoted string")
    (assert (checkSingleToken "\"escaped \\\" quote\"" "string") "escaped double quote")
    (assert (checkSingleToken "'escaped \\' quote'" "string") "escaped single quote")
    (assert (checkSingleToken "\"multi\\\nline\"" "string") "string line continuation")
    (assert (checkSingleToken "\"unclosed at eof" "string") "unclosed string at eof")
    true)

fn testPinnedAtKeywordsAndHash -> Bool
  (do
    (assert (checkSingleToken "@import" "at-keyword") "@import")
    (assert (checkSingleToken "@media" "at-keyword") "@media")
    (assert (checkSingleToken "@keyframes" "at-keyword") "@keyframes")
    (assert (checkSingleToken "@layer" "at-keyword") "@layer")
    (assert (checkSingleToken "@supports" "at-keyword") "@supports")
    (assert (checkSingleToken "#main" "hash") "#main")
    (assert (checkSingleToken "#nav-bar" "hash") "#nav-bar")
    (assert (checkSingleToken "#_id" "hash") "#_id")
    (assert (checkSingleToken "#123" "hash") "#123")
    (assert (checkSingleToken "#fff" "hash") "#fff")
    (assert (checkSingleToken "#c0ffee" "hash") "#c0ffee")
    true)

fn testPinnedFunctionsAndUrls -> Bool
  (do
    (assert (checkSingleToken "rgb(" "function") "function rgb(")
    (assert (checkSingleToken "calc(" "function") "function calc(")
    (assert (checkSingleToken "var(" "function") "function var(")
    (assert (checkSingleToken "url(https://example.com/asset.png)" "url") "unquoted url")
    (assert (checkSingleToken "url(test.svg)" "url") "unquoted url relative")
    (assert (checkSingleToken "url(  spaced.png  )" "url") "unquoted url spaced")
    (assert (checkSingleToken "url(unclosed" "url") "unclosed url")
    (assert (checkRoundTrip "url(\"https://example.com/quoted.png\")") "quoted url function")
    (assert (checkRoundTrip "url('https://example.com/quoted2.png')") "single quoted url function")
    true)

fn testPinnedCommentsAndCd -> Bool
  (do
    (assert (checkSingleToken "/* simple */" "comment") "simple comment")
    (assert (checkSingleToken "/* multi\nline\ncomment */" "comment") "multiline comment")
    (assert (checkSingleToken "/*******/" "comment") "asterisk comment")
    (assert (checkSingleToken "/* unclosed" "comment") "unclosed comment")
    (assert (checkSingleToken "<!--" "cdo") "cdo")
    (assert (checkSingleToken "-->" "cdc") "cdc")
    true)

fn testPinnedUnicodeRange -> Bool
  (do
    (assert (checkSingleToken "U+0020-007F" "unicode-range") "unicode-range 0020-007F")
    (assert (checkSingleToken "U+4???" "unicode-range") "unicode-range wildcard")
    (assert (checkSingleToken "U+26" "unicode-range") "unicode-range 26")
    (assert (checkSingleToken "U+0-7F" "unicode-range") "unicode-range 0-7F")
    (assert (checkSingleToken "u+A5" "unicode-range") "unicode-range u+A5")
    true)

fn testPinnedDelimitersAndPunctuation -> Bool
  (do
    (assert (checkSingleToken "{" "lbrace") "lbrace")
    (assert (checkSingleToken "}" "rbrace") "rbrace")
    (assert (checkSingleToken "(" "lparen") "lparen")
    (assert (checkSingleToken ")" "rparen") "rparen")
    (assert (checkSingleToken "[" "lbracket") "lbracket")
    (assert (checkSingleToken "]" "rbracket") "rbracket")
    (assert (checkSingleToken ":" "colon") "colon")
    (assert (checkSingleToken ";" "semicolon") "semicolon")
    (assert (checkSingleToken "," "comma") "comma")
    (assert (checkSingleToken "." "delim") "delim .")
    (assert (checkSingleToken "+" "delim") "delim +")
    (assert (checkSingleToken "-" "delim") "delim -")
    (assert (checkSingleToken ">" "delim") "delim >")
    (assert (checkSingleToken "~" "delim") "delim ~")
    (assert (checkSingleToken "*" "delim") "delim *")
    (assert (checkSingleToken "/" "delim") "delim /")
    (assert (checkSingleToken "!" "delim") "delim !")
    (assert (checkSingleToken "=" "delim") "delim =")
    (assert (checkSingleToken "@" "delim") "delim @")
    (assert (checkSingleToken "#" "delim") "delim #")
    true)

fn testBadTokensRecovery -> Bool
  (do
    (assert (checkRoundTrip "\"unterminated\nsecond line\"") "bad string recovers and round-trips")
    (assert (checkRoundTrip "url(bad \" quote)") "bad url recovers and round-trips")
    (let [(tokensBadStr (lex/tokenizeText "\"bad\nnext"))]
      (do
        (assert (> (listLength tokensBadStr) 1) "bad string split into tokens")
        (let [(t0 (optionOr (listHead tokensBadStr) (tr/makeToken "" 0 0)))]
          (assert (= (tr/tokenKind t0) "bad-string") "first token is bad-string"))))
    (let [(tokensBadUrl (lex/tokenizeText "url(bad \" quote)"))]
      (do
        (assert (> (listLength tokensBadUrl) 0) "bad url tokens produced")
        (let [(t0 (optionOr (listHead tokensBadUrl) (tr/makeToken "" 0 0)))]
          (assert (= (tr/tokenKind t0) "bad-url") "first token is bad-url"))))
    true)

fn testComplexCssRule -> Bool
  (let [(css "@media (min-width: 768px) { .card:hover { transform: translate3d(0, -2px, 0); box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); } }")]
    (checkRoundTrip css))

fn findSubString text: String needle: String from: Int64 -> (Option Int64)
  (let [(len (stringLength text))]
    (if (>= from len)
      (none)
      (mt (stringSlice text from len)
        ((none) (none))
        ((some sub)
         (mt (stringIndexOf sub needle)
           ((none) (none))
           ((some rel) (some (+ from rel))))))))

fn extractStyleBodies html: String idx: Int64 acc: (List String) -> (List String)
  (let [(lower (stringLower html))
        (openPos (findSubString lower "<style" idx))]
    (mt openPos
      ((none) (listReverse acc))
      ((some o)
       (let [(tagClose (findSubString lower ">" o))]
         (mt tagClose
           ((none) (listReverse acc))
           ((some tc)
            (let [(bodyStart (+ tc 1))
                  (endPos (findSubString lower "</style>" bodyStart))]
              (mt endPos
                ((none) (listReverse acc))
                ((some ep)
                 (mt (stringSlice html bodyStart ep)
                   ((none) (listReverse acc))
                   ((some b) (extractStyleBodies html (+ ep 8) (cons b acc)))))))))))))

fn checkStyleBlock path: String style: String -> Bool
  (let [(len (stringLength style))
        (tokens (lex/tokenizeText style))
        (tree (lex/tokenizeToTree style))
        (roundTrip (pr/print style tree))]
    (do
      (assert (ok? (tr/checkTokensTiling tokens len)) (str "style block tokens tile: " path))
      (assert (ok? (tr/checkTilingRoot tree)) (str "style block tree tiles: " path))
      (assert (= roundTrip style) (str "style block round-trips: " path))
      true))

fn testHtmlStyleBodies! path: String -> Bool
  (mt (fileReadString path)
    ((err e) (do (assert false (str "failed to read html file " path ": " e)) false))
    ((ok html)
     (let [(styles (extractStyleBodies html 0 (list)))]
       (fold (fn [(prev Bool) (style String)] -> Bool
               (let [(r (checkStyleBlock path style))]
                 (and prev r)))
             true
             styles))))

fn testAllHtmlStyles! -> Bool
  (let [(cmd "git ls-files \"*.html\"")
        (res (processRun cmd))]
    (do
      (assert (= res.exitCode 0) "git ls-files html exited 0")
      (let [(files (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit res.stdout "\n")))]
        (do
          (assert (> (listLength files) 0) "found tracked html files")
          (fold (fn [(prev Bool) (file String)] -> Bool
                  (let [(r (testHtmlStyleBodies! file))]
                    (and prev r)))
                true
                files)))))

fn testIndexCss! -> Bool
  (mt (fileReadBytes "asl/packages/asl-syntax/tests/fixtures/css/tailwindIndex.css.sample")
    ((err e) (do (assert false (str "failed to read index.css: " e)) false))
    ((ok bs)
     (let [(len (bytesLength bs))
           (tokens (lex/tokenizeBytes bs))
           (tree (lex/tokenizeBytesToTree bs))
           (roundTrip (pr/printTreeBytes! bs tree))]
       (assert (> len 0) "index.css is non-empty")
       (assert (> (listLength tokens) 0) "index.css produced tokens")
       (assert (ok? (tr/checkTokensTiling tokens len)) "index.css tokens tile")
       (assert (ok? (tr/checkTilingRoot tree)) "index.css tree tiles")
       (assert (= roundTrip bs) "index.css round-trips exactly")
       true)))

fn testAllTrackedCss! -> Bool
  (let [(cmd "git ls-files \"*.css\"")
        (res (processRun cmd))]
    (do
      (assert (= res.exitCode 0) "git ls-files css exited 0")
      (let [(files (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit res.stdout "\n")))]
        (do
          (assert (> (listLength files) 0) "found tracked css files")
          (fold (fn [(prev Bool) (file String)] -> Bool
                  (mt (fileReadBytes file)
                    ((err e) (do (assert false (str "failed to read css file " file ": " e)) false))
                    ((ok bs)
                     (let [(len (bytesLength bs))
                           (tokens (lex/tokenizeBytes bs))
                           (tree (lex/tokenizeBytesToTree bs))
                           (roundTrip (pr/printTreeBytes! bs tree))]
                       (do
                         (assert (ok? (tr/checkTokensTiling tokens len)) (str "tracked css tokens tile: " file))
                         (assert (ok? (tr/checkTilingRoot tree)) (str "tracked css tree tiles: " file))
                         (assert (= roundTrip bs) (str "tracked css round-trips: " file))
                         (and prev true))))))
                true
                files)))))

fn testPredicates -> Bool
  (do
    (assert (lex/isCssIdent? "color") "isCssIdent? color")
    (assert (lex/isCssIdent? "--custom-var") "isCssIdent? --custom-var")
    (assert (not (lex/isCssIdent? "123")) "isCssIdent? 123 is false")
    (assert (not (lex/isCssIdent? "")) "isCssIdent? empty is false")
    (assert (lex/isCssWhitespace? "  \t\n\r ") "isCssWhitespace? whitespace")
    (assert (not (lex/isCssWhitespace? "  a ")) "isCssWhitespace? with text is false")
    (assert (lex/isCssNumber? "123.45") "isCssNumber? 123.45")
    (assert (lex/isCssNumber? "-0.5e+2") "isCssNumber? -0.5e+2")
    (assert (not (lex/isCssNumber? "10px")) "isCssNumber? 10px is false")
    true)

fn filterCommentTokens tokens: (List tr/Token) acc: (List tr/Token) -> (List tr/Token)
  (if (listEmpty? tokens)
    (listReverse acc)
    (let [(head (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (tail (optionOr (listTail tokens) (list)))]
      (if (= (tr/tokenKind head) "comment")
        (filterCommentTokens tail acc)
        (filterCommentTokens tail (cons head acc)))))

fn appendRev xs: (List String) acc: (List String) -> (List String)
  (if (listEmpty? xs)
    acc
    (let [(head (optionOr (listHead xs) ""))
          (tail (optionOr (listTail xs) (list)))]
      (appendRev tail (cons head acc))))

fn appendList xs: (List String) ys: (List String) -> (List String)
  (appendRev (listReverse xs) ys)

fn flattenExpectedItem item: j/Json -> (List String)
  (mt item
    ((j/jstr s)
     (cond
       ((= s " ") (list "whitespace"))
       ((= s "~=") (list "include-match"))
       ((= s "|=") (list "dash-match"))
       ((= s "^=") (list "prefix-match"))
       ((= s "$=") (list "suffix-match"))
       ((= s "*=") (list "substring-match"))
       ((= s "||") (list "column"))
       ((= s "<!--") (list "cdo"))
       ((= s "-->") (list "cdc"))
       ((= s ":") (list "colon"))
       ((= s ";") (list "semicolon"))
       ((= s ",") (list "comma"))
       ((= s "]") (list "rbracket"))
       ((= s ")") (list "rparen"))
       ((= s "}") (list "rbrace"))
       (else (list "delim"))))
    ((j/jarr xs)
     (if (listEmpty? xs)
       (list)
       (let [(firstVal (optionOr (listHead xs) (j/jstr "")))
             (tag (mt firstVal ((j/jstr t) t) (_ "")))]
         (cond
           ((= tag "{}")
            (let [(inner (flattenExpectedList (optionOr (listTail xs) (list))))]
              (cons "lbrace" (appendList inner (list "rbrace")))))
           ((= tag "[]")
            (let [(inner (flattenExpectedList (optionOr (listTail xs) (list))))]
              (cons "lbracket" (appendList inner (list "rbracket")))))
           ((= tag "()")
            (let [(inner (flattenExpectedList (optionOr (listTail xs) (list))))]
              (cons "lparen" (appendList inner (list "rparen")))))
           ((= tag "function")
            (let [(tail1 (optionOr (listTail xs) (list)))
                  (children (optionOr (listTail tail1) (list)))
                  (inner (flattenExpectedList children))]
              (cons "function" (appendList inner (list "rparen")))))
           ((= tag "error")
            (let [(errNameVal (optionOr (listGet xs 1) (j/jstr "")))
                  (errName (mt errNameVal ((j/jstr e) e) (_ "")))]
              (cond
                ((= errName "bad-string") (list "bad-string"))
                ((= errName "bad-url") (list "bad-url"))
                ((= errName "eof-in-string") (list))
                ((= errName "eof-in-url") (list))
                (else (list "error")))))
           ((or (= tag "ident")
            (or (= tag "at-keyword")
            (or (= tag "hash")
            (or (= tag "string")
            (or (= tag "bad-string")
            (or (= tag "url")
            (or (= tag "bad-url")
            (or (= tag "number")
            (or (= tag "percentage")
            (or (= tag "dimension")
                (= tag "unicode-range")))))))))))
            (list tag))
           (else
            (flattenExpectedList xs))))))
    (_ (list)))

fn flattenExpectedList items: (List j/Json) -> (List String)
  (if (listEmpty? items)
    (list)
    (let [(head (optionOr (listHead items) (j/jnull)))
          (tail (optionOr (listTail items) (list)))]
      (appendList (flattenExpectedItem head) (flattenExpectedList tail))))

fn compareKinds tokens: (List tr/Token) expected: (List String) idx: Int64 -> Bool
  (if (and (listEmpty? tokens) (listEmpty? expected))
    true
    (if (or (listEmpty? tokens) (listEmpty? expected))
      false
      (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
            (toks (optionOr (listTail tokens) (list)))
            (exp (optionOr (listHead expected) ""))
            (exps (optionOr (listTail expected) (list)))]
        (if (!= (tr/tokenKind tok) exp)
          false
          (compareKinds toks exps (+ idx 1))))))

fn excludedCasesData -> (List (Pair Int64 String))
  (list
    (pair 8 "unclosed nested functions at EOF")
    (pair 16 "unclosed url() function at EOF")
    (pair 19 "unclosed url() function at EOF")
    (pair 20 "unclosed url() function at EOF")
    (pair 21 "unclosed url() function at EOF")
    (pair 23 "unclosed url() function at EOF")
    (pair 49 "mismatched unclosed brackets at EOF"))

fn getCaseExclusionReason cases: (List (Pair Int64 String)) targetIdx: Int64 -> (Option String)
  (if (listEmpty? cases)
    (none)
    (let [(head (optionOr (listHead cases) (pair 0 "")))
          (tail (optionOr (listTail cases) (list)))]
      (if (= (pairFirst head) targetIdx)
        (some (pairSecond head))
        (getCaseExclusionReason tail targetIdx))))

fn isCaseExcluded caseIdx: Int64 -> Bool
  (some? (getCaseExclusionReason (excludedCasesData) caseIdx))

fn printExcludedReasons! cases: (List (Pair Int64 String)) -> Bool
  (if (listEmpty? cases)
    true
    (let [(head (optionOr (listHead cases) (pair 0 "")))
          (tail (optionOr (listTail cases) (list)))]
      (do
        (println (stringConcat "  excluded case " (stringConcat (stringFromInt64 (pairFirst head)) (stringConcat ": " (pairSecond head)))))
        (printExcludedReasons! tail))))

fn checkUpstreamRoundTrip items: (List j/Json) idx: Int64 maxIdx: Int64 -> Bool
  (if (>= idx maxIdx)
    true
    (let [(inVal (optionOr (listGet items idx) (j/jstr "")))
          (inputStr (mt inVal ((j/jstr s) s) (_ "")))
          (tokens (lex/tokenizeText inputStr))
          (len (stringLength inputStr))
          (tree (lex/tokenizeToTree inputStr))]
      (do
        (assert (ok? (tr/checkTokensTiling tokens len)) (stringConcat "tokens tile for upstream case " (stringFromInt64 (/ idx 2))))
        (assert (ok? (tr/checkTilingRoot tree)) (stringConcat "tree tiles for upstream case " (stringFromInt64 (/ idx 2))))
        (assert (= (pr/print inputStr tree) inputStr) (stringConcat "round trip for upstream case " (stringFromInt64 (/ idx 2))))
        (checkUpstreamRoundTrip items (+ idx 2) maxIdx))))

fn checkUpstreamComponentValues! items: (List j/Json) caseIdx: Int64 totalCases: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (>= caseIdx totalCases)
    (do
      (println (stringConcat "CSS upstream component values: "
                 (stringConcat (stringFromInt64 passCount)
                   (stringConcat " compared and passed, "
                     (stringConcat (stringFromInt64 excludedCount) " excluded by reason:")))))
      (printExcludedReasons! (excludedCasesData))
      (assert (= (+ passCount excludedCount) totalCases) "all cases accounted for")
      (assert (= passCount 43) "43 upstream cases compared and passed")
      (assert (= excludedCount 7) "7 upstream cases excluded with documented reasons")
      true)
    (if (isCaseExcluded caseIdx)
      (checkUpstreamComponentValues! items (+ caseIdx 1) totalCases passCount (+ excludedCount 1))
      (let [(inVal (optionOr (listGet items (* caseIdx 2)) (j/jstr "")))
            (inputStr (mt inVal ((j/jstr s) s) (_ "")))
            (outVal (optionOr (listGet items (+ (* caseIdx 2) 1)) (j/jarr (list))))
            (expectedList (mt outVal ((j/jarr xs) xs) (_ (list))))
            (tokens (filterCommentTokens (lex/tokenizeText inputStr) (list)))
            (expectedKinds (flattenExpectedList expectedList))
            (kindsMatch (compareKinds tokens expectedKinds 0))]
        (do
          (assert kindsMatch (stringConcat "upstream token kinds match case " (stringFromInt64 caseIdx)))
          (checkUpstreamComponentValues! items (+ caseIdx 1) totalCases (+ passCount 1) excludedCount)))))

fn testManifestVerifierSha256! -> Bool
  (let [(fixturePath "asl/packages/asl-syntax/tests/fixtures/upstream/css/component_value_list.json.sample")
        (contentRes (fileReadBytes fixturePath))]
    (do
      (assert (ok? contentRes) "component_value_list.json file read succeeds")
      (let [(bs (resultOr contentRes (stringToBytes "")))
            (actualSha (bytesSha256 bs))
            (expectedSha "a8d7a5252373b892cfcac359360930ad9a57ed918a84331bcf0c872b80f83200")]
        (do
          (assert (= actualSha expectedSha) "component_value_list.json sha256 matches manifest")
          (let [(entry (crp/makeUpstreamEntry
                         "https://github.com/SimonSapin/css-parsing-tests"
                         "203ce36bffd617db7f118c551e32794561fb273d"
                         expectedSha
                         "CC0-1.0"
                         fixturePath))]
            (do
              (assert (ok? (crp/verifyUpstreamEntry! entry)) "manifest-verifier verifyUpstreamEntry passes")
              true))))))

fn testUpstreamSuite! -> Bool
  (do
    (assert (testManifestVerifierSha256!) "manifest verifier sha256")
    (let [(contentRes (fileReadString "asl/packages/asl-syntax/tests/fixtures/upstream/css/component_value_list.json.sample"))]
      (assert (ok? contentRes) "fixture file read succeeds")
      (let [(jsonStr (resultOr contentRes ""))
            (parseRes (j/jsonParse jsonStr))]
        (assert (ok? parseRes) "fixture parses as JSON")
        (mt (resultOr parseRes (j/jnull))
          ((j/jarr items)
           (do
             (assert (= (listLength items) 100) "100 items in component_value_list.json")
             (assert (checkUpstreamRoundTrip items 0 (listLength items)) "all 50 upstream cases round-trip")
             (assert (checkUpstreamComponentValues! items 0 50 0 0) "upstream component values agree")
             true))
          (_ (assert false "expected jarr"))))))

fn ! runTests -> Bool
  (do
    (assert (testPinnedIdents) "pinned idents")
    (assert (testPinnedNumbers) "pinned numbers")
    (assert (testPinnedStrings) "pinned strings")
    (assert (testPinnedAtKeywordsAndHash) "pinned at-keywords and hash")
    (assert (testPinnedFunctionsAndUrls) "pinned functions and urls")
    (assert (testPinnedCommentsAndCd) "pinned comments and CDO/CDC")
    (assert (testPinnedUnicodeRange) "pinned unicode-range")
    (assert (testPinnedDelimitersAndPunctuation) "pinned delimiters")
    (assert (testBadTokensRecovery) "bad tokens recovery")
    (assert (testComplexCssRule) "complex css rule")
    (assert (testIndexCss!) "index.css round-trip")
    (assert (testAllTrackedCss!) "all tracked css round-trip")
    (assert (testAllHtmlStyles!) "all html style blocks round-trip")
    (assert (testPredicates) "css predicates")
    (assert (testUpstreamSuite!) "upstream css parsing test suite")
    true)
