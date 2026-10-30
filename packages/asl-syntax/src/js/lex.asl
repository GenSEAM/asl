(module asl-syntax/js/lex
  :x [tokenize
      tokenizeText
      tokenizeBytes
      tokenizeSource
      tokenizeToTree
      tokenizeBytesToTree
      tokenizeSourceToTree
      tokenizeWithGoal
      tokenizeBytesWithGoal
      goalDefault
      goalDiv
      goalRegex
      goalTemplate
      goalJsxText
      isWhitespaceToken
      isNewlineToken
      isCommentToken
      isIdentToken
      isKeywordToken
      isNumberToken
      isBigIntToken
      isStringToken
      isRegexToken
      isTemplateToken
      hasNewlineBetween?
      commentHasNewline?
      isAsiNewlineTrivia?]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)])

fn goalDefault -> Int64
  0

fn goalDiv -> Int64
  1

fn goalRegex -> Int64
  2

fn goalTemplate -> Int64
  3

fn goalJsxText -> Int64
  4

fn isWhitespaceToken tok: tr/Token -> Bool
  (= tok.kind "whitespace")

fn isNewlineToken tok: tr/Token -> Bool
  (= tok.kind "newline")

fn isCommentToken tok: tr/Token -> Bool
  (= tok.kind "comment")

fn isIdentToken tok: tr/Token -> Bool
  (or (= tok.kind "ident")
      (= tok.kind "privateIdent"))

fn isKeywordToken tok: tr/Token -> Bool
  (or (= tok.kind "keyword")
  (or (= tok.kind "boolean")
      (= tok.kind "null")))

fn isNumberToken tok: tr/Token -> Bool
  (or (= tok.kind "number")
      (= tok.kind "bigint"))

fn isBigIntToken tok: tr/Token -> Bool
  (= tok.kind "bigint")

fn isStringToken tok: tr/Token -> Bool
  (= tok.kind "string")

fn isRegexToken tok: tr/Token -> Bool
  (= tok.kind "regex")

fn isTemplateToken tok: tr/Token -> Bool
  (or (= tok.kind "templateNoSub")
  (or (= tok.kind "templateHead")
  (or (= tok.kind "templateMiddle")
      (= tok.kind "templateTail"))))

fn commentHasNewlineLoop bs: Bytes cur: Int64 end: Int64 -> Bool
  (if (>= cur end)
    false
    (let [(b (bytesGet bs cur))]
      (if (or (= b 10) (= b 13))
        true
        (commentHasNewlineLoop bs (+ cur 1) end))))

fn commentHasNewline? bs: Bytes tok: tr/Token -> Bool
  (commentHasNewlineLoop bs tok.start tok.end)

fn isAsiNewlineTrivia? bs: Bytes tok: tr/Token -> Bool
  (let [(k tok.kind)]
    (if (= k "newline")
      true
      (if (= k "comment")
        (commentHasNewline? bs tok)
        false)))

fn checkNewlineInRange toks: (List tr/Token) cur: Int64 endIdx: Int64 -> Bool
  (if (>= cur endIdx)
    false
    (let [(tok (optionOr (listGet toks cur) (tr/makeToken "" 0 0)))
          (k tok.kind)]
      (if (= k "newline")
        true
        (checkNewlineInRange toks (+ cur 1) endIdx))))

fn hasNewlineBetween? toks: (List tr/Token) startIdx: Int64 endIdx: Int64 -> Bool
  (checkNewlineInRange toks (+ startIdx 1) endIdx)

fn isWhitespaceByte b: Int64 -> Bool
  (or (= b 32)
  (or (= b 9)
  (or (= b 11)
      (= b 12))))

fn isDigitByte b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isHexDigitByte b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57))
  (or (and (>= b 65) (<= b 70))
      (and (>= b 97) (<= b 102))))

fn isOctalDigitByte b: Int64 -> Bool
  (and (>= b 48) (<= b 55))

fn isBinaryDigitByte b: Int64 -> Bool
  (or (= b 48) (= b 49))

fn isAsciiIdentStart b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
  (or (and (>= b 97) (<= b 122))
  (or (= b 36)
      (= b 95))))

fn isAsciiIdentPart b: Int64 -> Bool
  (or (isAsciiIdentStart b)
      (isDigitByte b))

fn isNewlineStart bs: Bytes len: Int64 i: Int64 -> Bool
  (if (>= i len)
    false
    (let [(b (bytesGet bs i))]
      (if (or (= b 10) (= b 13))
        true
        (if (and (= b 226) (and (< (+ i 2) len) (= (bytesGet bs (+ i 1)) 128)))
          (let [(b2 (bytesGet bs (+ i 2)))]
            (or (= b2 168) (= b2 169)))
          false))))

fn scanNewlineEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (let [(b (bytesGet bs i))]
    (if (= b 10)
      (+ i 1)
      (if (= b 13)
        (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 10))
          (+ i 2)
          (+ i 1))
        (if (= b 226)
          (+ i 3)
          (+ i 1)))))

fn scanWhitespace bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (isWhitespaceByte b)
        (scanWhitespace bs len (+ i 1))
        (if (and (= b 194) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 160)))
          (scanWhitespace bs len (+ i 2))
          (if (and (= b 239) (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 187) (= (bytesGet bs (+ i 2)) 191))))
            (scanWhitespace bs len (+ i 3))
            (if (and (= b 226) (< (+ i 2) len))
              (let [(b1 (bytesGet bs (+ i 1)))
                    (b2 (bytesGet bs (+ i 2)))]
                (if (and (= b1 128) (and (>= b2 128) (<= b2 138)))
                  (scanWhitespace bs len (+ i 3))
                  (if (and (= b1 128) (= b2 175))
                    (scanWhitespace bs len (+ i 3))
                    (if (and (= b1 129) (= b2 159))
                      (scanWhitespace bs len (+ i 3))
                      i))))
              (if (and (= b 227) (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 128) (= (bytesGet bs (+ i 2)) 128))))
                (scanWhitespace bs len (+ i 3))
                i)))))))

fn scanLineComment bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (isNewlineStart bs len i)
      i
      (scanLineComment bs len (+ i 1))))

fn scanBlockComment bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (and (= (bytesGet bs i) 42) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 47)))
      (+ i 2)
      (scanBlockComment bs len (+ i 1))))

fn scanToBrace bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    len
    (if (= (bytesGet bs i) 125)
      (+ i 1)
      (scanToBrace bs len (+ i 1))))

fn scanIdentEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (isAsciiIdentPart b)
        (scanIdentEnd bs len (+ i 1))
        (if (>= b 128)
          (scanIdentEnd bs len (+ i 1))
          (if (and (= b 92) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 117)))
            (if (and (< (+ i 2) len) (= (bytesGet bs (+ i 2)) 123))
              (scanIdentEnd bs len (scanToBrace bs len (+ i 3)))
              (let [(target (+ i 6))]
                (scanIdentEnd bs len (if (> target len) len target))))
            i)))))

fn scanStringEnd bs: Bytes len: Int64 i: Int64 quote: Int64 -> Int64
  (if (>= i len)
    len
    (let [(b (bytesGet bs i))]
      (if (= b quote)
        (+ i 1)
        (if (isNewlineStart bs len i)
          i
          (if (= b 92)
            (if (>= (+ i 1) len)
              len
              (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 13) (= (bytesGet bs (+ i 2)) 10)))
                (scanStringEnd bs len (+ i 3) quote)
                (scanStringEnd bs len (+ i 2) quote)))
            (scanStringEnd bs len (+ i 1) quote))))))

fn scanTemplateContent bs: Bytes len: Int64 i: Int64 isMiddle: Bool -> (Pair Int64 String)
  (if (>= i len)
    (pair len (if isMiddle "templateMiddle" "templateHead"))
    (let [(b (bytesGet bs i))]
      (if (= b 96)
        (pair (+ i 1) (if isMiddle "templateTail" "templateNoSub"))
        (if (and (= b 36) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 123)))
          (pair (+ i 2) (if isMiddle "templateMiddle" "templateHead"))
          (if (= b 92)
            (if (>= (+ i 1) len)
              (pair len (if isMiddle "templateMiddle" "templateHead"))
              (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 13) (= (bytesGet bs (+ i 2)) 10)))
                (scanTemplateContent bs len (+ i 3) isMiddle)
                (scanTemplateContent bs len (+ i 2) isMiddle)))
            (scanTemplateContent bs len (+ i 1) isMiddle))))))

fn scanRegexFlags bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (or (and (>= b 97) (<= b 122)) (and (>= b 65) (<= b 90)))
        (scanRegexFlags bs len (+ i 1))
        i)))

fn scanRegexClass bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (isNewlineStart bs len i)
      i
      (let [(b (bytesGet bs i))]
        (if (= b 92)
          (if (>= (+ i 1) len)
            len
            (scanRegexClass bs len (+ i 2)))
          (if (= b 93)
            (+ i 1)
            (scanRegexClass bs len (+ i 1)))))))

fn scanRegexEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (if (isNewlineStart bs len i)
      i
      (let [(b (bytesGet bs i))]
        (if (= b 92)
          (if (>= (+ i 1) len)
            len
            (if (isNewlineStart bs len (+ i 1))
              (+ i 1)
              (scanRegexEnd bs len (+ i 2))))
          (if (= b 91)
            (scanRegexEnd bs len (scanRegexClass bs len (+ i 1)))
            (if (= b 47)
              (scanRegexFlags bs len (+ i 1))
              (scanRegexEnd bs len (+ i 1))))))))

fn scanDigits bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (isDigitByte b)
        (scanDigits bs len (+ i 1))
        (if (and (= b 95) (and (< (+ i 1) len) (isDigitByte (bytesGet bs (+ i 1)))))
          (scanDigits bs len (+ i 2))
          i))))

fn scanHexDigits bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (isHexDigitByte b)
        (scanHexDigits bs len (+ i 1))
        (if (and (= b 95) (and (< (+ i 1) len) (isHexDigitByte (bytesGet bs (+ i 1)))))
          (scanHexDigits bs len (+ i 2))
          i))))

fn scanOctalDigits bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (isOctalDigitByte b)
        (scanOctalDigits bs len (+ i 1))
        (if (and (= b 95) (and (< (+ i 1) len) (isOctalDigitByte (bytesGet bs (+ i 1)))))
          (scanOctalDigits bs len (+ i 2))
          i))))

fn scanBinaryDigits bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (isBinaryDigitByte b)
        (scanBinaryDigits bs len (+ i 1))
        (if (and (= b 95) (and (< (+ i 1) len) (isBinaryDigitByte (bytesGet bs (+ i 1)))))
          (scanBinaryDigits bs len (+ i 2))
          i))))

fn scanNumber bs: Bytes len: Int64 start: Int64 -> (Pair Int64 String)
  (let [(b0 (bytesGet bs start))]
    (if (and (= b0 48) (< (+ start 1) len))
      (let [(b1 (bytesGet bs (+ start 1)))]
        (if (or (= b1 120) (= b1 88))
          (let [(endDigits (scanHexDigits bs len (+ start 2)))]
            (if (and (< endDigits len) (= (bytesGet bs endDigits) 110))
              (pair (+ endDigits 1) "bigint")
              (pair endDigits "number")))
          (if (or (= b1 98) (= b1 66))
            (let [(endDigits (scanBinaryDigits bs len (+ start 2)))]
              (if (and (< endDigits len) (= (bytesGet bs endDigits) 110))
                (pair (+ endDigits 1) "bigint")
                (pair endDigits "number")))
            (if (or (= b1 111) (= b1 79))
              (let [(endDigits (scanOctalDigits bs len (+ start 2)))]
                (if (and (< endDigits len) (= (bytesGet bs endDigits) 110))
                  (pair (+ endDigits 1) "bigint")
                  (pair endDigits "number")))
              (if (isOctalDigitByte b1)
                (pair (scanOctalDigits bs len (+ start 1)) "number")
                (scanDecimalNumber bs len start))))))
      (scanDecimalNumber bs len start)))

fn scanDecimalNumber bs: Bytes len: Int64 start: Int64 -> (Pair Int64 String)
  (let [(intEnd (scanDigits bs len start))
        (dotPair (if (and (< intEnd len) (= (bytesGet bs intEnd) 46))
                   (if (and (< (+ intEnd 1) len) (= (bytesGet bs (+ intEnd 1)) 46))
                     (pair intEnd false)
                     (pair (scanDigits bs len (+ intEnd 1)) true))
                   (pair intEnd false)))
        (fracEnd (pairFirst dotPair))
        (hasDot (pairSecond dotPair))
        (expPair (if (and (< fracEnd len) (or (= (bytesGet bs fracEnd) 101) (= (bytesGet bs fracEnd) 69)))
                   (let [(afterE (+ fracEnd 1))]
                     (if (and (< afterE len) (or (= (bytesGet bs afterE) 43) (= (bytesGet bs afterE) 45)))
                       (pair (scanDigits bs len (+ afterE 1)) true)
                       (pair (scanDigits bs len afterE) true)))
                   (pair fracEnd false)))
        (numEnd (pairFirst expPair))
        (hasExp (pairSecond expPair))]
    (if (and (not hasDot) (and (not hasExp) (and (< numEnd len) (= (bytesGet bs numEnd) 110))))
      (pair (+ numEnd 1) "bigint")
      (pair numEnd "number")))

fn scanJsxTextEnd bs: Bytes len: Int64 i: Int64 -> Int64
  (if (>= i len)
    i
    (let [(b (bytesGet bs i))]
      (if (or (= b 60) (= b 123))
        i
        (scanJsxTextEnd bs len (+ i 1)))))

fn classifyIdent bs: Bytes start: Int64 end: Int64 -> String
  (let [(n (- end start))]
    (if (= n 2)
      (let [(b0 (bytesGet bs start))
            (b1 (bytesGet bs (+ start 1)))]
        (if (and (= b0 100) (= b1 111)) "keyword"
        (if (and (= b0 105) (= b1 102)) "keyword"
        (if (and (= b0 105) (= b1 110)) "keyword"
        "ident"))))
      (if (= n 3)
        (let [(b0 (bytesGet bs start))
              (b1 (bytesGet bs (+ start 1)))
              (b2 (bytesGet bs (+ start 2)))]
          (if (and (= b0 102) (and (= b1 111) (= b2 114))) "keyword"
          (if (and (= b0 108) (and (= b1 101) (= b2 116))) "keyword"
          (if (and (= b0 110) (and (= b1 101) (= b2 119))) "keyword"
          (if (and (= b0 116) (and (= b1 114) (= b2 121))) "keyword"
          (if (and (= b0 118) (and (= b1 97) (= b2 114))) "keyword"
          "ident"))))))
        (if (= n 4)
          (let [(b0 (bytesGet bs start))
                (b1 (bytesGet bs (+ start 1)))
                (b2 (bytesGet bs (+ start 2)))
                (b3 (bytesGet bs (+ start 3)))]
            (if (and (= b0 99) (and (= b1 97) (and (= b2 115) (= b3 101)))) "keyword"
            (if (and (= b0 101) (and (= b1 108) (and (= b2 115) (= b3 101)))) "keyword"
            (if (and (= b0 101) (and (= b1 110) (and (= b2 117) (= b3 109)))) "keyword"
            (if (and (= b0 110) (and (= b1 117) (and (= b2 108) (= b3 108)))) "null"
            (if (and (= b0 116) (and (= b1 104) (and (= b2 105) (= b3 115)))) "keyword"
            (if (and (= b0 116) (and (= b1 114) (and (= b2 117) (= b3 101)))) "boolean"
            (if (and (= b0 118) (and (= b1 111) (and (= b2 105) (= b3 100)))) "keyword"
            (if (and (= b0 119) (and (= b1 105) (and (= b2 116) (= b3 104)))) "keyword"
            "ident")))))))))
          (if (= n 5)
            (let [(b0 (bytesGet bs start))
                  (b1 (bytesGet bs (+ start 1)))
                  (b2 (bytesGet bs (+ start 2)))
                  (b3 (bytesGet bs (+ start 3)))
                  (b4 (bytesGet bs (+ start 4)))]
              (if (and (= b0 97) (and (= b1 115) (and (= b2 121) (and (= b3 110) (= b4 99))))) "keyword"
              (if (and (= b0 97) (and (= b1 119) (and (= b2 97) (and (= b3 105) (= b4 116))))) "keyword"
              (if (and (= b0 98) (and (= b1 114) (and (= b2 101) (and (= b3 97) (= b4 107))))) "keyword"
              (if (and (= b0 99) (and (= b1 97) (and (= b2 116) (and (= b3 99) (= b4 104))))) "keyword"
              (if (and (= b0 99) (and (= b1 108) (and (= b2 97) (and (= b3 115) (= b4 115))))) "keyword"
              (if (and (= b0 99) (and (= b1 111) (and (= b2 110) (and (= b3 115) (= b4 116))))) "keyword"
              (if (and (= b0 102) (and (= b1 97) (and (= b2 108) (and (= b3 115) (= b4 101))))) "boolean"
              (if (and (= b0 115) (and (= b1 117) (and (= b2 112) (and (= b3 101) (= b4 114))))) "keyword"
              (if (and (= b0 116) (and (= b1 104) (and (= b2 114) (and (= b3 111) (= b4 119))))) "keyword"
              (if (and (= b0 119) (and (= b1 104) (and (= b2 105) (and (= b3 108) (= b4 101))))) "keyword"
              (if (and (= b0 121) (and (= b1 105) (and (= b2 101) (and (= b3 108) (= b4 100))))) "keyword"
              "ident"))))))))))))
            (if (= n 6)
              (let [(b0 (bytesGet bs start))
                    (b1 (bytesGet bs (+ start 1)))
                    (b2 (bytesGet bs (+ start 2)))
                    (b3 (bytesGet bs (+ start 3)))
                    (b4 (bytesGet bs (+ start 4)))
                    (b5 (bytesGet bs (+ start 5)))]
                (if (and (= b0 100) (and (= b1 101) (and (= b2 108) (and (= b3 101) (and (= b4 116) (= b5 101)))))) "keyword"
                (if (and (= b0 101) (and (= b1 120) (and (= b2 112) (and (= b3 111) (and (= b4 114) (= b5 116)))))) "keyword"
                (if (and (= b0 105) (and (= b1 109) (and (= b2 112) (and (= b3 111) (and (= b4 114) (= b5 116)))))) "keyword"
                (if (and (= b0 114) (and (= b1 101) (and (= b2 116) (and (= b3 117) (and (= b4 114) (= b5 110)))))) "keyword"
                (if (and (= b0 115) (and (= b1 119) (and (= b2 105) (and (= b3 116) (and (= b4 99) (= b5 104)))))) "keyword"
                (if (and (= b0 116) (and (= b1 121) (and (= b2 112) (and (= b3 101) (and (= b4 111) (= b5 102)))))) "keyword"
                "ident")))))))
              (if (= n 7)
                (let [(b0 (bytesGet bs start))
                      (b1 (bytesGet bs (+ start 1)))
                      (b2 (bytesGet bs (+ start 2)))
                      (b3 (bytesGet bs (+ start 3)))
                      (b4 (bytesGet bs (+ start 4)))
                      (b5 (bytesGet bs (+ start 5)))
                      (b6 (bytesGet bs (+ start 6)))]
                  (if (and (= b0 100) (and (= b1 101) (and (= b2 102) (and (= b3 97) (and (= b4 117) (and (= b5 108) (= b6 116))))))) "keyword"
                  (if (and (= b0 101) (and (= b1 120) (and (= b2 116) (and (= b3 101) (and (= b4 110) (and (= b5 100) (= b6 115))))))) "keyword"
                  (if (and (= b0 102) (and (= b1 105) (and (= b2 110) (and (= b3 97) (and (= b4 108) (and (= b5 108) (= b6 121))))))) "keyword"
                  "ident"))))
                (if (= n 8)
                  (let [(b0 (bytesGet bs start))
                        (b1 (bytesGet bs (+ start 1)))
                        (b2 (bytesGet bs (+ start 2)))
                        (b3 (bytesGet bs (+ start 3)))
                        (b4 (bytesGet bs (+ start 4)))
                        (b5 (bytesGet bs (+ start 5)))
                        (b6 (bytesGet bs (+ start 6)))
                        (b7 (bytesGet bs (+ start 7)))]
                    (if (and (= b0 99) (and (= b1 111) (and (= b2 110) (and (= b3 116) (and (= b4 105) (and (= b5 110) (and (= b6 117) (= b7 101)))))))) "keyword"
                    (if (and (= b0 100) (and (= b1 101) (and (= b2 98) (and (= b3 117) (and (= b4 103) (and (= b5 103) (and (= b6 101) (= b7 114)))))))) "keyword"
                    (if (and (= b0 102) (and (= b1 117) (and (= b2 110) (and (= b3 99) (and (= b4 116) (and (= b5 105) (and (= b6 111) (= b7 110)))))))) "keyword"
                    "ident"))))
                  (if (= n 10)
                    (if (and (= (bytesGet bs start) 105)
                        (and (= (bytesGet bs (+ start 1)) 110)
                        (and (= (bytesGet bs (+ start 2)) 115)
                        (and (= (bytesGet bs (+ start 3)) 116)
                        (and (= (bytesGet bs (+ start 4)) 97)
                        (and (= (bytesGet bs (+ start 5)) 110)
                        (and (= (bytesGet bs (+ start 6)) 99)
                        (and (= (bytesGet bs (+ start 7)) 101)
                        (and (= (bytesGet bs (+ start 8)) 111)
                             (= (bytesGet bs (+ start 9)) 102))))))))))
                      "keyword"
                      "ident")
                    "ident")))))))))

fn prevKindForIdent kind: String bs: Bytes start: Int64 end: Int64 -> String
  (if (or (= kind "boolean") (= kind "null"))
    "primaryExpr"
    (if (= kind "keyword")
      (let [(n (- end start))]
        (if (= n 2) "exprKw"
        (if (= n 4)
          (let [(b0 (bytesGet bs start))]
            (if (or (= b0 99) (or (= b0 101) (= b0 118))) "exprKw"
            (if (= b0 116) "primaryExpr"
            "keyword")))
          (if (= n 5)
            (let [(b0 (bytesGet bs start))]
              (if (or (= b0 97) (or (= b0 116) (= b0 121))) "exprKw"
              (if (= b0 115) "primaryExpr"
              "keyword")))
            (if (= n 6)
              (let [(b0 (bytesGet bs start))]
                (if (or (= b0 100) (or (= b0 114) (= b0 116))) "exprKw"
                "keyword"))
              (if (= n 7) "exprKw"
              (if (= n 10) "exprKw"
              "keyword")))))))
      (if (= kind "ident")
        "ident"
        "primaryExpr")))

fn isRegexContext? prevKind: String -> Bool
  (or (= prevKind "")
  (or (= prevKind "punct")
  (or (= prevKind "exprKw")
      (= prevKind "keyword"))))

fn tokenizeLoop bs: Bytes len: Int64 i: Int64 goal: Int64 prevKind: String tmplStack: (List Int64) braceDepth: Int64 acc: (List tr/Token) -> (List tr/Token)
  (if (>= i len)
    (listReverse acc)
    (if (and (= goal 4) (and (!= (bytesGet bs i) 60) (!= (bytesGet bs i) 123)))
      (let [(end (scanJsxTextEnd bs len i))
            (tok (tr/makeToken "jsxText" i end))]
        (tokenizeLoop bs len end goal "primaryExpr" tmplStack braceDepth (cons tok acc)))
      (if (and (= i 0) (and (< (+ i 1) len) (and (= (bytesGet bs 0) 35) (= (bytesGet bs 1) 33))))
        (let [(end (scanLineComment bs len 2))
              (tok (tr/makeToken "comment" 0 end))]
          (tokenizeLoop bs len end goal prevKind tmplStack braceDepth (cons tok acc)))
        (if (isNewlineStart bs len i)
          (let [(end (scanNewlineEnd bs len i))
                (tok (tr/makeToken "newline" i end))]
            (tokenizeLoop bs len end goal prevKind tmplStack braceDepth (cons tok acc)))
          (let [(b (bytesGet bs i))]
            (if (or (isWhitespaceByte b) (or (= b 194) (or (= b 239) (or (= b 226) (= b 227)))))
              (let [(end (scanWhitespace bs len i))]
                (if (> end i)
                  (tokenizeLoop bs len end goal prevKind tmplStack braceDepth (cons (tr/makeToken "whitespace" i end) acc))
                  (tokenizeRest bs len i b goal prevKind tmplStack braceDepth acc)))
              (tokenizeRest bs len i b goal prevKind tmplStack braceDepth acc)))))))

fn tokenizeRest bs: Bytes len: Int64 i: Int64 b: Int64 goal: Int64 prevKind: String tmplStack: (List Int64) braceDepth: Int64 acc: (List tr/Token) -> (List tr/Token)
  (if (= b 47)
    (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 47))
      (let [(end (scanLineComment bs len (+ i 2)))
            (tok (tr/makeToken "comment" i end))]
        (tokenizeLoop bs len end goal prevKind tmplStack braceDepth (cons tok acc)))
      (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 42))
        (let [(end (scanBlockComment bs len (+ i 2)))
              (tok (tr/makeToken "comment" i end))]
          (tokenizeLoop bs len end goal prevKind tmplStack braceDepth (cons tok acc)))
        (let [(isReg (if (= goal 2) true (if (= goal 1) false (isRegexContext? prevKind))))]
          (if isReg
            (let [(end (scanRegexEnd bs len (+ i 1)))
                  (tok (tr/makeToken "regex" i end))]
              (tokenizeLoop bs len end goal "primaryExpr" tmplStack braceDepth (cons tok acc)))
            (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
              (let [(tok (tr/makeToken "slashAssign" i (+ i 2)))]
                (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons tok acc)))
              (let [(tok (tr/makeToken "slash" i (+ i 1)))]
                (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons tok acc))))))))
    (if (or (= b 39) (= b 34))
      (let [(end (scanStringEnd bs len (+ i 1) b))
            (tok (tr/makeToken "string" i end))]
        (tokenizeLoop bs len end goal "primaryExpr" tmplStack braceDepth (cons tok acc)))
      (if (= b 96)
        (let [(res (scanTemplateContent bs len (+ i 1) false))
              (end (pairFirst res))
              (kind (pairSecond res))
              (tok (tr/makeToken kind i end))
              (newStack (if (= kind "templateHead") (cons braceDepth tmplStack) tmplStack))]
          (tokenizeLoop bs len end goal "primaryExpr" newStack braceDepth (cons tok acc)))
        (if (= b 125)
          (if (or (= goal 3) (and (not (listEmpty? tmplStack)) (= braceDepth (optionOr (listHead tmplStack) -1))))
            (let [(res (scanTemplateContent bs len (+ i 1) true))
                  (end (pairFirst res))
                  (kind (pairSecond res))
                  (tok (tr/makeToken kind i end))
                  (newStack (if (= kind "templateTail") (optionOr (listTail tmplStack) (list)) tmplStack))]
              (tokenizeLoop bs len end goal "primaryExpr" newStack braceDepth (cons tok acc)))
            (let [(tok (tr/makeToken "rbrace" i (+ i 1)))]
              (tokenizeLoop bs len (+ i 1) goal "primaryExpr" tmplStack (- braceDepth 1) (cons tok acc))))
          (if (= b 123)
            (let [(tok (tr/makeToken "lbrace" i (+ i 1)))]
              (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack (+ braceDepth 1) (cons tok acc)))
            (if (isDigitByte b)
              (let [(res (scanNumber bs len i))
                    (end (pairFirst res))
                    (kind (pairSecond res))
                    (tok (tr/makeToken kind i end))]
                (tokenizeLoop bs len end goal "primaryExpr" tmplStack braceDepth (cons tok acc)))
              (if (and (= b 46) (and (< (+ i 1) len) (isDigitByte (bytesGet bs (+ i 1)))))
                (let [(res (scanNumber bs len i))
                      (end (pairFirst res))
                      (kind (pairSecond res))
                      (tok (tr/makeToken kind i end))]
                  (tokenizeLoop bs len end goal "primaryExpr" tmplStack braceDepth (cons tok acc)))
                (if (and (= b 35) (and (< (+ i 1) len) (isAsciiIdentStart (bytesGet bs (+ i 1)))))
                  (let [(end (scanIdentEnd bs len (+ i 2)))
                        (tok (tr/makeToken "privateIdent" i end))]
                    (tokenizeLoop bs len end goal "ident" tmplStack braceDepth (cons tok acc)))
                  (if (or (isAsciiIdentStart b) (or (>= b 128) (and (= b 92) (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 117)))))
                    (let [(end (scanIdentEnd bs len i))
                          (kind (classifyIdent bs i end))
                          (nextPrev (prevKindForIdent kind bs i end))
                          (tok (tr/makeToken kind i end))]
                      (tokenizeLoop bs len end goal nextPrev tmplStack braceDepth (cons tok acc)))
                    (tokenizePunct bs len i b goal prevKind tmplStack braceDepth acc))))))))))

fn tokenizePunct bs: Bytes len: Int64 i: Int64 b: Int64 goal: Int64 prevKind: String tmplStack: (List Int64) braceDepth: Int64 acc: (List tr/Token) -> (List tr/Token)
  (if (= b 40)
    (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "lparen" i (+ i 1)) acc))
    (if (= b 41)
      (tokenizeLoop bs len (+ i 1) goal "primaryExpr" tmplStack braceDepth (cons (tr/makeToken "rparen" i (+ i 1)) acc))
      (if (= b 91)
        (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "lbracket" i (+ i 1)) acc))
        (if (= b 93)
          (tokenizeLoop bs len (+ i 1) goal "primaryExpr" tmplStack braceDepth (cons (tr/makeToken "rbracket" i (+ i 1)) acc))
          (if (= b 59)
            (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "semicolon" i (+ i 1)) acc))
            (if (= b 44)
              (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "comma" i (+ i 1)) acc))
              (if (= b 58)
                (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "colon" i (+ i 1)) acc))
                (if (= b 126)
                  (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "tilde" i (+ i 1)) acc))
                  (if (= b 64)
                    (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "at" i (+ i 1)) acc))
                    (tokenizeCompoundPunct bs len i b goal prevKind tmplStack braceDepth acc))))))))))

fn tokenizeCompoundPunct bs: Bytes len: Int64 i: Int64 b: Int64 goal: Int64 prevKind: String tmplStack: (List Int64) braceDepth: Int64 acc: (List tr/Token) -> (List tr/Token)
  (if (= b 63)
    (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 63) (= (bytesGet bs (+ i 2)) 61)))
      (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "questionQuestionAssign" i (+ i 3)) acc))
      (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 63))
        (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "questionQuestion" i (+ i 2)) acc))
        (if (and (< (+ i 1) len) (and (= (bytesGet bs (+ i 1)) 46) (not (and (< (+ i 2) len) (isDigitByte (bytesGet bs (+ i 2)))))))
          (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "questionDot" i (+ i 2)) acc))
          (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "question" i (+ i 1)) acc)))))
    (if (= b 46)
      (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 46) (= (bytesGet bs (+ i 2)) 46)))
        (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "ellipsis" i (+ i 3)) acc))
        (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "dot" i (+ i 1)) acc)))
      (if (= b 61)
        (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 61) (= (bytesGet bs (+ i 2)) 61)))
          (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "eqEqEq" i (+ i 3)) acc))
          (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
            (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "eqEq" i (+ i 2)) acc))
            (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 62))
              (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "arrow" i (+ i 2)) acc))
              (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "assign" i (+ i 1)) acc)))))
        (if (= b 33)
          (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 61) (= (bytesGet bs (+ i 2)) 61)))
            (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "bangEqEq" i (+ i 3)) acc))
            (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
              (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "bangEq" i (+ i 2)) acc))
              (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "bang" i (+ i 1)) acc))))
          (if (= b 43)
            (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 43))
              (tokenizeLoop bs len (+ i 2) goal "primaryExpr" tmplStack braceDepth (cons (tr/makeToken "plusPlus" i (+ i 2)) acc))
              (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "plusAssign" i (+ i 2)) acc))
                (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "plus" i (+ i 1)) acc))))
            (if (= b 45)
              (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 45))
                (tokenizeLoop bs len (+ i 2) goal "primaryExpr" tmplStack braceDepth (cons (tr/makeToken "minusMinus" i (+ i 2)) acc))
                (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                  (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "minusAssign" i (+ i 2)) acc))
                  (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "minus" i (+ i 1)) acc))))
              (if (= b 42)
                (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 42) (= (bytesGet bs (+ i 2)) 61)))
                  (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "starStarAssign" i (+ i 3)) acc))
                  (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 42))
                    (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "starStar" i (+ i 2)) acc))
                    (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                      (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "starAssign" i (+ i 2)) acc))
                      (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "star" i (+ i 1)) acc)))))
                (if (= b 37)
                  (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                    (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "percentAssign" i (+ i 2)) acc))
                    (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "percent" i (+ i 1)) acc)))
                  (if (= b 38)
                    (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 38) (= (bytesGet bs (+ i 2)) 61)))
                      (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "ampAmpAssign" i (+ i 3)) acc))
                      (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 38))
                        (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "ampAmp" i (+ i 2)) acc))
                        (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                          (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "ampAssign" i (+ i 2)) acc))
                          (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "amp" i (+ i 1)) acc)))))
                    (if (= b 124)
                      (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 124) (= (bytesGet bs (+ i 2)) 61)))
                        (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "pipePipeAssign" i (+ i 3)) acc))
                        (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 124))
                          (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "pipePipe" i (+ i 2)) acc))
                          (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                            (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "pipeAssign" i (+ i 2)) acc))
                            (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "pipe" i (+ i 1)) acc)))))
                      (if (= b 94)
                        (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                          (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "caretAssign" i (+ i 2)) acc))
                          (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "caret" i (+ i 1)) acc)))
                        (if (= b 60)
                          (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 60) (= (bytesGet bs (+ i 2)) 61)))
                            (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "shlAssign" i (+ i 3)) acc))
                            (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 60))
                              (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "shl" i (+ i 2)) acc))
                              (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                                (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "lte" i (+ i 2)) acc))
                                (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "lt" i (+ i 1)) acc)))))
                          (if (= b 62)
                            (if (and (< (+ i 3) len) (and (= (bytesGet bs (+ i 1)) 62) (and (= (bytesGet bs (+ i 2)) 62) (= (bytesGet bs (+ i 3)) 61))))
                              (tokenizeLoop bs len (+ i 4) goal "punct" tmplStack braceDepth (cons (tr/makeToken "shruAssign" i (+ i 4)) acc))
                              (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 62) (= (bytesGet bs (+ i 2)) 62)))
                                (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "shru" i (+ i 3)) acc))
                                (if (and (< (+ i 2) len) (and (= (bytesGet bs (+ i 1)) 62) (= (bytesGet bs (+ i 2)) 61)))
                                  (tokenizeLoop bs len (+ i 3) goal "punct" tmplStack braceDepth (cons (tr/makeToken "shrAssign" i (+ i 3)) acc))
                                  (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 62))
                                    (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "shr" i (+ i 2)) acc))
                                    (if (and (< (+ i 1) len) (= (bytesGet bs (+ i 1)) 61))
                                      (tokenizeLoop bs len (+ i 2) goal "punct" tmplStack braceDepth (cons (tr/makeToken "gte" i (+ i 2)) acc))
                                      (tokenizeLoop bs len (+ i 1) goal "punct" tmplStack braceDepth (cons (tr/makeToken "gt" i (+ i 1)) acc)))))))
                            (tokenizeLoop bs len (+ i 1) goal prevKind tmplStack braceDepth (cons (tr/makeToken "error" i (+ i 1)) acc)))))))))))))))

fn tokenizeBytesWithGoal bs: Bytes goal: Int64 -> (List tr/Token)
  (tokenizeLoop bs (bytesLength bs) 0 goal "" (list) 0 (list))

fn tokenizeWithGoal text: String goal: Int64 -> (List tr/Token)
  (tokenizeBytesWithGoal (stringToBytes text) goal)

fn tokenizeBytes bs: Bytes -> (List tr/Token)
  (tokenizeBytesWithGoal bs 0)

fn tokenizeText text: String -> (List tr/Token)
  (tokenizeBytes (stringToBytes text))

fn tokenize text: String -> (List tr/Token)
  (tokenizeText text)

fn tokenizeSource s: src/Source -> (List tr/Token)
  (tokenizeBytes (src/sourceBytes s))

fn tokensToElements tokens: (List tr/Token) acc: (List tr/TreeElement) -> (List tr/TreeElement)
  (if (listEmpty? tokens)
    (listReverse acc)
    (let [(tok (optionOr (listHead tokens) (tr/makeToken "" 0 0)))
          (rest (optionOr (listTail tokens) (list)))]
      (tokensToElements rest (cons (tr/elemToken tok) acc))))

fn tokenizeBytesToTree bs: Bytes -> tr/Node
  (let [(len (bytesLength bs))
        (tokens (tokenizeBytes bs))
        (elems (tokensToElements tokens (list)))]
    (tr/makeNode "program" 0 len elems))

fn tokenizeToTree text: String -> tr/Node
  (tokenizeBytesToTree (stringToBytes text))

fn tokenizeSourceToTree s: src/Source -> tr/Node
  (tokenizeBytesToTree (src/sourceBytes s))
