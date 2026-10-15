(module asl-syntax/tests/asl/lexTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/asl/lex :a lx)
      (tools/fleet/run :a run)])

fn testDelimitersAndTrivia -> Bool
  (let [(s "( [ { } ] ) , \n \r\n ; comment\n")
        (toks (lx/tokenize s))
        (tiling (tr/checkTokensTiling toks (stringLength s)))]
    (assert (ok? tiling) "delimiters and trivia tile cleanly")
    (assert (= (listLength toks) 20) "20 tokens in test string")
    (let [(t0 (optionOr (listGet toks 0) (tr/makeToken "" 0 0)))
          (t1 (optionOr (listGet toks 1) (tr/makeToken "" 0 0)))
          (t2 (optionOr (listGet toks 2) (tr/makeToken "" 0 0)))
          (t3 (optionOr (listGet toks 3) (tr/makeToken "" 0 0)))
          (t4 (optionOr (listGet toks 4) (tr/makeToken "" 0 0)))
          (t5 (optionOr (listGet toks 5) (tr/makeToken "" 0 0)))
          (t6 (optionOr (listGet toks 6) (tr/makeToken "" 0 0)))
          (t7 (optionOr (listGet toks 7) (tr/makeToken "" 0 0)))
          (t8 (optionOr (listGet toks 8) (tr/makeToken "" 0 0)))
          (t9 (optionOr (listGet toks 9) (tr/makeToken "" 0 0)))
          (t10 (optionOr (listGet toks 10) (tr/makeToken "" 0 0)))
          (t11 (optionOr (listGet toks 11) (tr/makeToken "" 0 0)))
          (t12 (optionOr (listGet toks 12) (tr/makeToken "" 0 0)))
          (t13 (optionOr (listGet toks 13) (tr/makeToken "" 0 0)))
          (t14 (optionOr (listGet toks 14) (tr/makeToken "" 0 0)))
          (t15 (optionOr (listGet toks 15) (tr/makeToken "" 0 0)))
          (t16 (optionOr (listGet toks 16) (tr/makeToken "" 0 0)))
          (t17 (optionOr (listGet toks 17) (tr/makeToken "" 0 0)))
          (t18 (optionOr (listGet toks 18) (tr/makeToken "" 0 0)))
          (t19 (optionOr (listGet toks 19) (tr/makeToken "" 0 0)))]
      (assert (lx/isLparen t0) "t0 is lparen")
      (assert (lx/isWhitespaceToken t1) "t1 is whitespace")
      (assert (lx/isLbracket t2) "t2 is lbracket")
      (assert (lx/isWhitespaceToken t3) "t3 is whitespace")
      (assert (lx/isLbrace t4) "t4 is lbrace")
      (assert (lx/isWhitespaceToken t5) "t5 is whitespace")
      (assert (lx/isRbrace t6) "t6 is rbrace")
      (assert (lx/isWhitespaceToken t7) "t7 is whitespace")
      (assert (lx/isRbracket t8) "t8 is rbracket")
      (assert (lx/isWhitespaceToken t9) "t9 is whitespace")
      (assert (lx/isRparen t10) "t10 is rparen")
      (assert (lx/isWhitespaceToken t11) "t11 is whitespace")
      (assert (lx/isComma t12) "t12 is comma")
      (assert (lx/isWhitespaceToken t13) "t13 is whitespace")
      (assert (lx/isNewlineToken t14) "t14 is newline")
      (assert (lx/isWhitespaceToken t15) "t15 is whitespace")
      (assert (lx/isNewlineToken t16) "t16 is crlf newline")
      (assert (lx/isWhitespaceToken t17) "t17 is whitespace")
      (assert (lx/isCommentToken t18) "t18 is comment")
      (assert (lx/isNewlineToken t19) "t19 is newline")
      true))

fn testAtomsAndLiterals -> Bool
  (let [(s ":pkg/name :version 123 -45 +67 3.14 -0.5 1e6 hello -> string? .5 1. : \"test\\nstr\"")
        (toks (lx/tokenize s))
        (tiling (tr/checkTokensTiling toks (stringLength s)))]
    (assert (ok? tiling) "atoms tile cleanly")
    (let [(nonWs (filter (fn [(t tr/Token)] -> Bool (not (tr/isTriviaToken t))) toks))]
      (assert (= (listLength nonWs) 15) "15 non-trivia tokens")
      (let [(k1 (optionOr (listGet nonWs 0) (tr/makeToken "" 0 0)))
            (k2 (optionOr (listGet nonWs 1) (tr/makeToken "" 0 0)))
            (i1 (optionOr (listGet nonWs 2) (tr/makeToken "" 0 0)))
            (i2 (optionOr (listGet nonWs 3) (tr/makeToken "" 0 0)))
            (i3 (optionOr (listGet nonWs 4) (tr/makeToken "" 0 0)))
            (f1 (optionOr (listGet nonWs 5) (tr/makeToken "" 0 0)))
            (f2 (optionOr (listGet nonWs 6) (tr/makeToken "" 0 0)))
            (f3 (optionOr (listGet nonWs 7) (tr/makeToken "" 0 0)))
            (s1 (optionOr (listGet nonWs 8) (tr/makeToken "" 0 0)))
            (s2 (optionOr (listGet nonWs 9) (tr/makeToken "" 0 0)))
            (s3 (optionOr (listGet nonWs 10) (tr/makeToken "" 0 0)))
            (s4 (optionOr (listGet nonWs 11) (tr/makeToken "" 0 0)))
            (s5 (optionOr (listGet nonWs 12) (tr/makeToken "" 0 0)))
            (s6 (optionOr (listGet nonWs 13) (tr/makeToken "" 0 0)))
            (str1 (optionOr (listGet nonWs 14) (tr/makeToken "" 0 0)))]
        (assert (lx/isKeywordToken k1) "k1 is keyword")
        (assert (= (lx/tokenSliceString s k1) ":pkg/name") "k1 text is :pkg/name")
        (assert (lx/isKeywordToken k2) "k2 is keyword")
        (assert (lx/isIntToken i1) "i1 is int")
        (assert (= (lx/tokenSliceString s i1) "123") "i1 text is 123")
        (assert (lx/isIntToken i2) "i2 is int")
        (assert (= (lx/tokenSliceString s i2) "-45") "i2 text is -45")
        (assert (lx/isIntToken i3) "i3 is int")
        (assert (= (lx/tokenSliceString s i3) "+67") "i3 text is +67")
        (assert (lx/isFloatToken f1) "f1 is float")
        (assert (= (lx/tokenSliceString s f1) "3.14") "f1 text is 3.14")
        (assert (lx/isFloatToken f2) "f2 is float")
        (assert (= (lx/tokenSliceString s f2) "-0.5") "f2 text is -0.5")
        (assert (lx/isFloatToken f3) "f3 is float")
        (assert (= (lx/tokenSliceString s f3) "1e6") "f3 text is 1e6")
        (assert (lx/isSymbolToken s1) "s1 is symbol")
        (assert (= (lx/tokenSliceString s s1) "hello") "s1 text is hello")
        (assert (lx/isSymbolToken s2) "s2 is symbol")
        (assert (= (lx/tokenSliceString s s2) "->") "s2 text is ->")
        (assert (lx/isSymbolToken s3) "s3 is symbol")
        (assert (= (lx/tokenSliceString s s3) "string?") "s3 text is string?")
        (assert (lx/isSymbolToken s4) "s4 (.5) is symbol")
        (assert (= (lx/tokenSliceString s s4) ".5") "s4 text is .5")
        (assert (lx/isSymbolToken s5) "s5 (1.) is symbol")
        (assert (= (lx/tokenSliceString s s5) "1.") "s5 text is 1.")
        (assert (lx/isSymbolToken s6) "s6 (lone :) is symbol")
        (assert (= (lx/tokenSliceString s s6) ":") "s6 text is :")
        (assert (lx/isStringToken str1) "str1 is string")
        (assert (= (lx/tokenSliceString s str1) "\"test\\nstr\"") "str1 slice")
        true)))

fn testUnterminatedStringAndBadEscapes -> Bool
  (let [(unterm "\"unterminated string at eof")
        (toksUnterm (lx/tokenize unterm))
        (tErr1 (optionOr (listHead toksUnterm) (tr/makeToken "" 0 0)))]
    (assert (= (listLength toksUnterm) 1) "single error token for unclosed string")
    (assert (tr/isErrorToken tErr1) "unterminated string is error token")
    (assert (= tErr1.start 0) "error token starts at 0")
    (assert (= tErr1.end (stringLength unterm)) "error token extends to end")
    (let [(unicodeAtEof "\"\\u")
          (unicodeAtEofTokens (lx/tokenize unicodeAtEof))
          (unicodeAtEofTok (optionOr (listHead unicodeAtEofTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken unicodeAtEofTok) "unclosed string ending at unicode brace probe is an error token")
      (assert (= unicodeAtEofTok.end (stringLength unicodeAtEof)) "unclosed unicode brace probe error spans input"))
    (let [(badX "\"bad \\x1g hex\"")
          (toksBadX (lx/tokenize badX))
          (tErr2 (optionOr (listHead toksBadX) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken tErr2) "bad hex escape yields error token")
      (assert (= tErr2.end (stringLength badX)) "bad hex spans whole literal"))
    (let [(badU "\"bad \\u001z unicode\"")
          (toksBadU (lx/tokenize badU))
          (tErr3 (optionOr (listHead toksBadU) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken tErr3) "bad unicode escape yields error token")
      (assert (= tErr3.end (stringLength badU)) "bad unicode spans whole literal"))
    (let [(emptyBraceU "\"\\u{}\"")
          (emptyTokens (lx/tokenize emptyBraceU))
          (emptyTok (optionOr (listHead emptyTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken emptyTok) "empty unicode brace escape is invalid")
      (assert (= emptyTok.end (stringLength emptyBraceU)) "empty unicode brace error spans literal"))
    (let [(badBraceU "\"bad \\u{1g} unicode brace\"")
          (toksBadBraceU (lx/tokenize badBraceU))
          (tErr4 (optionOr (listHead toksBadBraceU) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken tErr4) "bad unicode brace escape yields error token")
      (assert (= tErr4.end (stringLength badBraceU)) "bad unicode brace spans whole literal"))
    (let [(overRangeU "\"\\u{110000}\"")
          (overRangeTokens (lx/tokenize overRangeU))
          (overRangeTok (optionOr (listHead overRangeTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken overRangeTok) "unicode brace value above U+10FFFF is invalid")
      (assert (= overRangeTok.end (stringLength overRangeU)) "over-range unicode brace error spans literal"))
    (let [(overRangeUpperHexU "\"\\u{ABCDEF}\"")
          (overRangeUpperHexTokens (lx/tokenize overRangeUpperHexU))
          (overRangeUpperHexTok (optionOr (listHead overRangeUpperHexTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken overRangeUpperHexTok) "uppercase A–F brace digits above U+10FFFF are invalid")
      (assert (= overRangeUpperHexTok.end (stringLength overRangeUpperHexU)) "uppercase A–F over-range error spans literal"))
    (let [(unterminatedBraceU "\"\\u{1F600\"")
          (unterminatedTokens (lx/tokenize unterminatedBraceU))
          (unterminatedTok (optionOr (listHead unterminatedTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken unterminatedTok) "unterminated unicode brace escape is invalid")
      (assert (= unterminatedTok.end (stringLength unterminatedBraceU)) "unterminated unicode brace error spans literal"))
    (let [(uppercaseU "\"\\u{1F600}\"")
          (uppercaseTokens (lx/tokenize uppercaseU))
          (uppercaseTok (optionOr (listHead uppercaseTokens) (tr/makeToken "" 0 0)))]
      (assert (lx/isStringToken uppercaseTok) "uppercase hexadecimal unicode brace escape is valid")
      (assert (= uppercaseTok.end (stringLength uppercaseU)) "uppercase unicode brace token spans literal"))
    (let [(maxCodePointU "\"\\u{10FFFF}\"")
          (maxTokens (lx/tokenize maxCodePointU))
          (maxTok (optionOr (listHead maxTokens) (tr/makeToken "" 0 0)))]
      (assert (lx/isStringToken maxTok) "U+10FFFF unicode brace escape is included at the upper boundary"))
    (let [(lowerMaxCodePointU "\"\\u{10ffff}\"")
          (lowerMaxTokens (lx/tokenize lowerMaxCodePointU))
          (lowerMaxTok (optionOr (listHead lowerMaxTokens) (tr/makeToken "" 0 0)))]
      (assert (lx/isStringToken lowerMaxTok) "lowercase U+10FFFF unicode brace escape is included at the upper boundary"))
    (let [(lowerOverRangeU "\"\\u{110000f}\"")
          (lowerOverRangeTokens (lx/tokenize lowerOverRangeU))
          (lowerOverRangeTok (optionOr (listHead lowerOverRangeTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken lowerOverRangeTok) "lowercase unicode brace value above U+10FFFF is invalid")
      (assert (= lowerOverRangeTok.end (stringLength lowerOverRangeU)) "lowercase over-range unicode brace error spans literal"))
    (let [(overflowU "\"\\u{10000000000000000}\"")
          (overflowTokens (lx/tokenize overflowU))
          (overflowTok (optionOr (listHead overflowTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken overflowTok) "17-digit unicode brace overflow is invalid")
      (assert (= overflowTok.end (stringLength overflowU)) "overflow unicode brace error spans literal"))
    (let [(suffixU "\"\\u{1F600}\"tail")
          (suffixTokens (lx/tokenize suffixU))
          (stringTok (optionOr (listGet suffixTokens 0) (tr/makeToken "" 0 0)))
          (tailTok (optionOr (listGet suffixTokens 1) (tr/makeToken "" 0 0)))
          (expectedEnd (stringLength "\"\\u{1F600}\""))]
      (assert (= (listLength suffixTokens) 2) "brace escape closes before following atom")
      (assert (lx/isStringToken stringTok) "brace escape token remains a string")
      (assert (= stringTok.end expectedEnd) "string token ends immediately after closing quote")
      (assert (= tailTok.start expectedEnd) "following atom begins immediately after string token")
      (assert (= tailTok.end (stringLength suffixU)) "following atom reaches input end"))
    (let [(surrogateU "\"\\u{d800}\"")
          (surrogateTokens (lx/tokenize surrogateU))
          (surrogateTok (optionOr (listHead surrogateTokens) (tr/makeToken "" 0 0)))]
      (assert (tr/isErrorToken surrogateTok) "surrogate brace escape is invalid, as in the host reader (strict escapes)"))
    (let [(goodEsc "\"good \\x41 \\u00e9 \\u{62} \\t \\r \\n \\\" \\\\ ok\"")
          (toksGood (lx/tokenize goodEsc))
          (tGood (optionOr (listHead toksGood) (tr/makeToken "" 0 0)))]
      (assert (lx/isStringToken tGood) "valid escapes yield string token")
      (assert (not (tr/isErrorToken tGood)) "valid escapes not error"))
    true)

fn checkLiteralAgainstHost! hostExe: String lit: String -> Bool
  (let [(tmpRes (processRun "mktemp /tmp/asl_lex_diff_XXXXXX"))
        (_ (assert (= tmpRes.exitCode 0) "unique differential scratch file created"))
        (tmpFile (stringTrim tmpRes.stdout))
        (_ (fileWrite tmpFile lit))
        (cmd (str "nice -n 15 " hostExe " parse " tmpFile))
        (procRes (processRun cmd))
        (hostOk (= procRes.exitCode 0))
        (_ (pathRemove tmpFile))
        (toks (lx/tokenize lit))
        (tokCount (listLength toks))
        (tok (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
    (if hostOk
      (do
        (assert (= tokCount 1) (str "host-accepted literal has 1 token: " lit))
        (assert (lx/isStringToken tok) (str "host-accepted literal lexes as string: " lit))
        (assert (= tok.start 0) (str "token starts at 0: " lit))
        (assert (= tok.end (stringLength lit)) (str "token span matches length: " lit))
        true)
      (do
        (assert (= tokCount 1) (str "host-rejected literal has 1 token: " lit))
        (assert (tr/isErrorToken tok) (str "host-rejected literal lexes as error: " lit))
        (assert (= tok.start 0) (str "token starts at 0: " lit))
        (assert (= tok.end (stringLength lit)) (str "token span matches length: " lit))
        true)))

fn testDifferentialStringEscapes! -> Bool
  (let [(hostExe (run/legacyHost!))
        (cases (list
          "\"hello world\""
          "\"\\n\""
          "\"\\t\""
          "\"\\r\""
          "\"\\\\\""
          "\"\\\"\""
          "\"\\0\""
          "\"\\e\""
          "\"\\x62\""
          "\"\\x41\""
          "\"\\u0062\""
          "\"\\u00e9\""
          "\"\\u{62}\""
          "\"\\u{}\""
          "\"\\u{110000}\""
          "\"\\u{d800}\""
          "\"\\{\""
          "\"\\a\""
          "\"unterminated"
          "\"trailing backslash\\"
          "\"escaped quote\\\""))]
    (assert (fold (fn [(acc Bool) (lit String)] -> Bool
            (and (checkLiteralAgainstHost! hostExe lit) acc))
          true
          cases) "matching host escape corpus")
    true)

fn testLosslessPrintReconstruction -> Bool
  (let [(samples (list "(module foo :d \"doc\" :x [bar])\n\nfn bar x: Int64 -> Int64\n  ; add 1\n  (+ x 1)\n"
                       "(:c :a syntax :do \"test\" :g \"pass\")\n"
                       "{:a 1 :b [2 3] :c \"hello \\\"world\\\"\"}\n"
                       "  \t  \r\n; only comment\r\n"))
        (verifyOne (fn [(s String)] -> Bool
                     (let [(toks (lx/tokenize s))
                           (tiling (tr/checkTokensTiling toks (stringLength s)))
                           (node (lx/tokensToNode toks (stringLength s)))
                           (printed (pr/printTreeString s node))]
                       (assert (ok? tiling) "sample tiles cleanly")
                       (assert (= printed s) "printed text matches source exactly")
                       true)))]
    (assert (fold (fn [(acc Bool) (s String)] -> Bool (and acc (verifyOne s))) true samples) "all sample texts roundtrip losslessly")
    true)

fn parseFileList stdout: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit stdout "\n"))

fn checkOneFile! acc: (Pair Int64 Int64) path: String -> (Pair Int64 Int64)
  (let [(checked (pairFirst acc))
        (mismatches (pairSecond acc))]
    (mt (fileReadBytes path)
      ((err _) acc)
      ((ok bs)
       (let [(len (bytesLength bs))
             (toks (lx/tokenizeBytes bs))
             (tilingRes (tr/checkTokensTiling toks len))]
         (mt tilingRes
           ((err _) (pair (+ checked 1) (+ mismatches 1)))
           ((ok _)
            (let [(root (lx/tokensToNode toks len))
                  (outBs (pr/printTreeBytes! bs root))]
              (if (= outBs bs)
                (pair (+ checked 1) mismatches)
                (pair (+ checked 1) (+ mismatches 1))))))))))

fn testAllTrackedFilesLossless! -> Bool
  (let [(cmdRes (processRun "git ls-files '*.asl' '*.asn'"))]
    (assert (= cmdRes.exitCode 0) "git ls-files exited 0")
    (let [(files (parseFileList cmdRes.stdout))
          (stats (fold checkOneFile! (pair 0 0) files))
          (totalChecked (pairFirst stats))
          (mismatches (pairSecond stats))]
      (assert (> totalChecked 3200) "checked >3200 tracked asl and asn files")
      (assert (= mismatches 0) "zero tiling or print mismatches across all tracked files")
      true))

fn benchmarkSource! -> String
  (let [(parts (map (fn [(p String)] -> String (resultOr (fileReadString p) ""))
                    ["asl/web/site/app/docs.asl" "asl/web/site/app/home.asl" "asl/web/site/app/theme.asl" "asl/web/site/app/mascot.asl"]))
        (once (stringJoin parts "\n"))]
    (stringJoin [once once once] "\n"))

fn testBenchmarkPerformance! -> Bool
  (let [(bs (stringToBytes (benchmarkSource!)))]
    (do
       (let [(len (bytesLength bs))]
         (assert (> len 100000) "benchmark file is >100 KB")
         (let [(t0 (nowNs))
               (toks (lx/tokenizeBytes bs))
               (node (lx/tokensToNode toks len))
               (outBs (pr/printTreeBytes! bs node))
               (t1 (nowNs))
               (elapsedNs (- t1 t0))
               (elapsedMs (/ elapsedNs 1000000))
               (msPer100Kb (/ (* elapsedMs 102400) len))]
           (assert (= outBs bs) "benchmark output matches input bytes")
           (assert (<= msPer100Kb 60) (str "tokenize+print <= 60 ms per 100 KB, took: " (stringFromInt64 msPer100Kb) " ms"))
           true))))

fn ! runTests -> Bool
  (and (testDelimitersAndTrivia)
  (and (testAtomsAndLiterals)
  (and (testUnterminatedStringAndBadEscapes)
  (and (testDifferentialStringEscapes!)
  (and (testLosslessPrintReconstruction)
  (and (testAllTrackedFilesLossless!)
       (testBenchmarkPerformance!)))))))
