(module asl-syntax/css/lex
  :x [tokenizeText
      tokenizeBytes
      tokenizeSource
      tokenizeToTree
      tokenizeBytesToTree
      tokenizeSourceToTree
      isCssIdent?
      isCssWhitespace?
      isCssNumber?]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)])

fn isWhitespace b: Int64 -> Bool
  (or (= b 32)
  (or (= b 9)
  (or (= b 10)
  (or (= b 13)
      (= b 12)))))

fn isDigit b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isHexDigit b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57))
  (or (and (>= b 65) (<= b 70))
      (and (>= b 97) (<= b 102))))

fn isNameStart b: Int64 -> Bool
  (or (= b 0)
  (or (and (>= b 65) (<= b 90))
  (or (and (>= b 97) (<= b 122))
  (or (= b 95)
      (>= b 128)))))

fn isNameCodePoint b: Int64 -> Bool
  (or (isNameStart b)
  (or (isDigit b)
      (= b 45)))

fn isValidEscape bs: Bytes len: Int64 idx: Int64 -> Bool
  (if (>= idx len)
    false
    (if (!= (bytesGet bs idx) 92)
      false
      (if (>= (+ idx 1) len)
        true
        (let [(b1 (bytesGet bs (+ idx 1)))]
          (not (or (= b1 10) (or (= b1 13) (= b1 12))))))))

fn consumeHexDigits bs: Bytes len: Int64 cur: Int64 remaining: Int64 -> Int64
  (if (or (<= remaining 0) (>= cur len))
    cur
    (if (isHexDigit (bytesGet bs cur))
      (consumeHexDigits bs len (+ cur 1) (- remaining 1))
      cur))

fn consumeEscape bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= (+ idx 1) len)
    len
    (let [(b1 (bytesGet bs (+ idx 1)))]
      (if (isHexDigit b1)
        (let [(afterHex (consumeHexDigits bs len (+ idx 1) 6))]
          (if (< afterHex len)
            (if (and (< (+ afterHex 1) len)
                     (= (bytesGet bs afterHex) 13)
                     (= (bytesGet bs (+ afterHex 1)) 10))
              (+ afterHex 2)
              (if (isWhitespace (bytesGet bs afterHex))
                (+ afterHex 1)
                afterHex))
            afterHex))
        (+ idx 2))))

fn startsIdent bs: Bytes len: Int64 idx: Int64 -> Bool
  (if (>= idx len)
    false
    (let [(b0 (bytesGet bs idx))]
      (cond
        ((= b0 45)
         (if (>= (+ idx 1) len)
           false
           (let [(b1 (bytesGet bs (+ idx 1)))]
             (or (isNameStart b1)
             (or (= b1 45)
                 (isValidEscape bs len (+ idx 1)))))))
        ((isNameStart b0) true)
        ((= b0 92) (isValidEscape bs len idx))
        (else false))))

fn consumeName bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isValidEscape bs len idx)
      (consumeName bs len (consumeEscape bs len idx))
      (if (isNameCodePoint (bytesGet bs idx))
        (consumeName bs len (+ idx 1))
        idx)))

fn startsNumber bs: Bytes len: Int64 idx: Int64 -> Bool
  (if (>= idx len)
    false
    (let [(b0 (bytesGet bs idx))]
      (cond
        ((or (= b0 43) (= b0 45))
         (if (>= (+ idx 1) len)
           false
           (let [(b1 (bytesGet bs (+ idx 1)))]
             (if (isDigit b1)
               true
               (if (and (= b1 46) (< (+ idx 2) len))
                 (isDigit (bytesGet bs (+ idx 2)))
                 false)))))
        ((= b0 46)
         (if (< (+ idx 1) len)
           (isDigit (bytesGet bs (+ idx 1)))
           false))
        ((isDigit b0) true)
        (else false))))

fn consumeDigits bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isDigit (bytesGet bs idx))
      (consumeDigits bs len (+ idx 1))
      idx))

fn consumeNumber bs: Bytes len: Int64 idx: Int64 -> Int64
  (let [(cur (if (or (= (bytesGet bs idx) 43) (= (bytesGet bs idx) 45)) (+ idx 1) idx))
        (afterInt (consumeDigits bs len cur))
        (afterFrac (if (and (< (+ afterInt 1) len)
                            (= (bytesGet bs afterInt) 46)
                            (isDigit (bytesGet bs (+ afterInt 1))))
                     (consumeDigits bs len (+ afterInt 2))
                     afterInt))]
    (if (and (< afterFrac len)
             (let [(e (bytesGet bs afterFrac))]
               (or (= e 101) (= e 69))))
      (if (< (+ afterFrac 1) len)
        (let [(e1 (bytesGet bs (+ afterFrac 1)))]
          (if (isDigit e1)
            (consumeDigits bs len (+ afterFrac 2))
            (if (and (or (= e1 43) (= e1 45))
                     (< (+ afterFrac 2) len)
                     (isDigit (bytesGet bs (+ afterFrac 2))))
              (consumeDigits bs len (+ afterFrac 3))
              afterFrac)))
        afterFrac)
      afterFrac))

fn consumeNumericToken bs: Bytes len: Int64 idx: Int64 -> tr/Token
  (let [(numEnd (consumeNumber bs len idx))]
    (if (startsIdent bs len numEnd)
      (let [(dimEnd (consumeName bs len numEnd))]
        (tr/makeToken "dimension" idx dimEnd))
      (if (and (< numEnd len) (= (bytesGet bs numEnd) 37))
        (tr/makeToken "percentage" idx (+ numEnd 1))
        (tr/makeToken "number" idx numEnd))))

fn scanString bs: Bytes len: Int64 idx: Int64 cur: Int64 quote: Int64 -> tr/Token
  (if (>= cur len)
    (tr/makeToken "string" idx len)
    (let [(b (bytesGet bs cur))]
      (cond
        ((= b quote)
         (tr/makeToken "string" idx (+ cur 1)))
        ((or (= b 10) (or (= b 13) (= b 12)))
         (tr/makeToken "bad-string" idx cur))
        ((= b 92)
         (if (>= (+ cur 1) len)
           (tr/makeToken "string" idx len)
           (let [(b1 (bytesGet bs (+ cur 1)))]
             (cond
               ((and (= b1 13) (< (+ cur 2) len) (= (bytesGet bs (+ cur 2)) 10))
                (scanString bs len idx (+ cur 3) quote))
               ((or (= b1 10) (or (= b1 13) (= b1 12)))
                (scanString bs len idx (+ cur 2) quote))
               ((isValidEscape bs len cur)
                (scanString bs len idx (consumeEscape bs len cur) quote))
               (else
                (scanString bs len idx (+ cur 1) quote))))))
        (else
         (scanString bs len idx (+ cur 1) quote)))))

fn isUrlIdent bs: Bytes idx: Int64 nameEnd: Int64 -> Bool
  (and (= (- nameEnd idx) 3)
  (and (let [(u (bytesGet bs idx))] (or (= u 117) (= u 85)))
  (and (let [(r (bytesGet bs (+ idx 1)))] (or (= r 114) (= r 82)))
       (let [(l (bytesGet bs (+ idx 2)))] (or (= l 108) (= l 76))))))

fn skipWhitespace bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isWhitespace (bytesGet bs idx))
      (skipWhitespace bs len (+ idx 1))
      idx))

fn consumeBadUrlRemnants bs: Bytes len: Int64 cur: Int64 -> Int64
  (if (>= cur len)
    len
    (let [(b (bytesGet bs cur))]
      (if (= b 41)
        (+ cur 1)
        (if (isValidEscape bs len cur)
          (consumeBadUrlRemnants bs len (consumeEscape bs len cur))
          (consumeBadUrlRemnants bs len (+ cur 1))))))

fn scanUrl bs: Bytes len: Int64 startIdx: Int64 cur: Int64 -> tr/Token
  (if (>= cur len)
    (tr/makeToken "url" startIdx len)
    (let [(b (bytesGet bs cur))]
      (cond
        ((= b 41)
         (tr/makeToken "url" startIdx (+ cur 1)))
        ((isWhitespace b)
         (let [(afterWs (skipWhitespace bs len cur))]
           (if (>= afterWs len)
             (tr/makeToken "url" startIdx len)
             (if (= (bytesGet bs afterWs) 41)
               (tr/makeToken "url" startIdx (+ afterWs 1))
               (let [(badEnd (consumeBadUrlRemnants bs len afterWs))]
                 (tr/makeToken "bad-url" startIdx badEnd))))))
        ((or (= b 34) (or (= b 39) (or (= b 40)
         (or (and (>= b 1) (<= b 8))
         (or (= b 11)
         (or (and (>= b 14) (<= b 31))
             (= b 127)))))))
         (let [(badEnd (consumeBadUrlRemnants bs len cur))]
           (tr/makeToken "bad-url" startIdx badEnd)))
        ((= b 92)
         (if (isValidEscape bs len cur)
           (scanUrl bs len startIdx (consumeEscape bs len cur))
           (let [(badEnd (consumeBadUrlRemnants bs len cur))]
             (tr/makeToken "bad-url" startIdx badEnd))))
        (else
         (scanUrl bs len startIdx (+ cur 1))))))

fn consumeIdentLike bs: Bytes len: Int64 idx: Int64 -> tr/Token
  (let [(nameEnd (consumeName bs len idx))]
    (if (and (isUrlIdent bs idx nameEnd)
             (< nameEnd len)
             (= (bytesGet bs nameEnd) 40))
      (let [(afterWs (skipWhitespace bs len (+ nameEnd 1)))]
        (if (and (< afterWs len)
                 (let [(q (bytesGet bs afterWs))]
                   (or (= q 34) (= q 39))))
          (tr/makeToken "function" idx (+ nameEnd 1))
          (scanUrl bs len idx afterWs)))
      (if (and (< nameEnd len) (= (bytesGet bs nameEnd) 40))
        (tr/makeToken "function" idx (+ nameEnd 1))
        (tr/makeToken "ident" idx nameEnd))))

fn startsUnicodeRange bs: Bytes len: Int64 idx: Int64 -> Bool
  (if (>= (+ idx 2) len)
    false
    (let [(b0 (bytesGet bs idx))]
      (if (not (or (= b0 85) (= b0 117)))
        false
        (if (!= (bytesGet bs (+ idx 1)) 43)
          false
          (let [(b2 (bytesGet bs (+ idx 2)))]
            (or (isHexDigit b2) (= b2 63)))))))

fn scanHexOrQuestion bs: Bytes len: Int64 cur: Int64 remaining: Int64 hasQuestion: Bool -> (Pair Int64 Bool)
  (if (or (<= remaining 0) (>= cur len))
    (pair cur hasQuestion)
    (let [(b (bytesGet bs cur))]
      (if (isHexDigit b)
        (if hasQuestion
          (pair cur hasQuestion)
          (scanHexOrQuestion bs len (+ cur 1) (- remaining 1) false))
        (if (= b 63)
          (scanHexOrQuestion bs len (+ cur 1) (- remaining 1) true)
          (pair cur hasQuestion)))))

fn scanHexOnly bs: Bytes len: Int64 cur: Int64 remaining: Int64 -> Int64
  (if (or (<= remaining 0) (>= cur len))
    cur
    (if (isHexDigit (bytesGet bs cur))
      (scanHexOnly bs len (+ cur 1) (- remaining 1))
      cur))

fn consumeUnicodeRange bs: Bytes len: Int64 idx: Int64 -> tr/Token
  (let [(p (scanHexOrQuestion bs len (+ idx 2) 6 false))
        (end1 (pairFirst p))
        (hadQ (pairSecond p))]
    (if (and (not hadQ)
             (< end1 len)
             (= (bytesGet bs end1) 45)
             (< (+ end1 1) len)
             (isHexDigit (bytesGet bs (+ end1 1))))
      (let [(end2 (scanHexOnly bs len (+ end1 1) 6))]
        (tr/makeToken "unicode-range" idx end2))
      (tr/makeToken "unicode-range" idx end1)))

fn scanComment bs: Bytes len: Int64 idx: Int64 cur: Int64 -> tr/Token
  (if (>= cur len)
    (tr/makeToken "comment" idx len)
    (if (and (< (+ cur 1) len)
             (= (bytesGet bs cur) 42)
             (= (bytesGet bs (+ cur 1)) 47))
      (tr/makeToken "comment" idx (+ cur 2))
      (scanComment bs len idx (+ cur 1))))

fn consumeNextToken bs: Bytes len: Int64 idx: Int64 -> tr/Token
  (if (and (= idx 0)
           (>= len 3)
           (= (bytesGet bs 0) 239)
           (= (bytesGet bs 1) 187)
           (= (bytesGet bs 2) 191))
    (tr/makeToken "bom" 0 3)
    (let [(b (bytesGet bs idx))]
      (cond
        ((isWhitespace b)
         (tr/makeToken "whitespace" idx (skipWhitespace bs len (+ idx 1))))
        ((and (= b 47) (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 42))
         (scanComment bs len idx (+ idx 2)))
        ((or (= b 34) (= b 39))
         (scanString bs len idx (+ idx 1) b))
        ((= b 35)
         (if (and (< (+ idx 1) len)
                  (or (isNameCodePoint (bytesGet bs (+ idx 1)))
                      (isValidEscape bs len (+ idx 1))))
           (tr/makeToken "hash" idx (consumeName bs len (+ idx 1)))
           (tr/makeToken "delim" idx (+ idx 1))))
        ((= b 64)
         (if (startsIdent bs len (+ idx 1))
           (tr/makeToken "at-keyword" idx (consumeName bs len (+ idx 1)))
           (tr/makeToken "delim" idx (+ idx 1))))
        ((= b 40) (tr/makeToken "lparen" idx (+ idx 1)))
        ((= b 41) (tr/makeToken "rparen" idx (+ idx 1)))
        ((= b 91) (tr/makeToken "lbracket" idx (+ idx 1)))
        ((= b 93) (tr/makeToken "rbracket" idx (+ idx 1)))
        ((= b 123) (tr/makeToken "lbrace" idx (+ idx 1)))
        ((= b 125) (tr/makeToken "rbrace" idx (+ idx 1)))
        ((= b 58) (tr/makeToken "colon" idx (+ idx 1)))
        ((= b 59) (tr/makeToken "semicolon" idx (+ idx 1)))
        ((= b 44) (tr/makeToken "comma" idx (+ idx 1)))
        ((and (= b 126) (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 61))
         (tr/makeToken "include-match" idx (+ idx 2)))
        ((= b 124)
         (if (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 61))
           (tr/makeToken "dash-match" idx (+ idx 2))
           (if (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 124))
             (tr/makeToken "column" idx (+ idx 2))
             (tr/makeToken "delim" idx (+ idx 1)))))
        ((and (= b 94) (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 61))
         (tr/makeToken "prefix-match" idx (+ idx 2)))
        ((and (= b 36) (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 61))
         (tr/makeToken "suffix-match" idx (+ idx 2)))
        ((and (= b 42) (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 61))
         (tr/makeToken "substring-match" idx (+ idx 2)))
        ((startsNumber bs len idx)
         (consumeNumericToken bs len idx))
        ((and (= b 60)
              (< (+ idx 3) len)
              (= (bytesGet bs (+ idx 1)) 33)
              (= (bytesGet bs (+ idx 2)) 45)
              (= (bytesGet bs (+ idx 3)) 45))
         (tr/makeToken "cdo" idx (+ idx 4)))
        ((and (= b 45)
              (< (+ idx 2) len)
              (= (bytesGet bs (+ idx 1)) 45)
              (= (bytesGet bs (+ idx 2)) 62))
         (tr/makeToken "cdc" idx (+ idx 3)))
        ((startsUnicodeRange bs len idx)
         (consumeUnicodeRange bs len idx))
        ((startsIdent bs len idx)
         (consumeIdentLike bs len idx))
        (else
         (tr/makeToken "delim" idx (+ idx 1))))))

fn tokenizeLoop bs: Bytes len: Int64 idx: Int64 acc: (List tr/Token) -> (List tr/Token)
  (if (>= idx len)
    (listReverse acc)
    (let [(tok (consumeNextToken bs len idx))
          (nextIdx (tr/tokenEnd tok))]
      (if (<= nextIdx idx)
        (listReverse (cons (tr/makeToken "delim" idx (+ idx 1)) acc))
        (tokenizeLoop bs len nextIdx (cons tok acc)))))

fn tokenizeBytes bs: Bytes -> (List tr/Token)
  (tokenizeLoop bs (bytesLength bs) 0 (list))

fn tokenizeText text: String -> (List tr/Token)
  (tokenizeBytes (stringToBytes text))

fn tokenizeSource s: src/Source -> (List tr/Token)
  (tokenizeBytes (src/sourceBytes s))

fn tokenizeBytesToTree bs: Bytes -> tr/Node
  (let [(len (bytesLength bs))
        (tokens (tokenizeBytes bs))
        (elems (map (fn [(t tr/Token)] -> tr/TreeElement (tr/elemToken t)) tokens))]
    (tr/makeNode "stylesheet" 0 len elems))

fn tokenizeToTree text: String -> tr/Node
  (tokenizeBytesToTree (stringToBytes text))

fn tokenizeSourceToTree s: src/Source -> tr/Node
  (tokenizeBytesToTree (src/sourceBytes s))

fn isCssIdent? text: String -> Bool
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))]
    (if (= len 0)
      false
      (and (startsIdent bs len 0)
           (= (consumeName bs len 0) len))))

fn isCssWhitespace? text: String -> Bool
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))]
    (if (= len 0)
      false
      (= (skipWhitespace bs len 0) len)))

fn isCssNumber? text: String -> Bool
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))]
    (if (= len 0)
      false
      (and (startsNumber bs len 0)
           (= (consumeNumber bs len 0) len))))
