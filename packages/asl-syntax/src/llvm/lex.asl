(module asl-syntax/llvm/lex
  :x [tokenizeText
      tokenizeBytes
      tokenize
      isLlvmWhitespace?
      isLlvmNewline?
      isLlvmDigit?
      isLlvmAlpha?
      isLlvmIdentChar?
      tokenSlice]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)])

fn isLlvmWhitespace? b: Int64 -> Bool
  (or (= b 32) (= b 9))

fn isLlvmNewline? b: Int64 -> Bool
  (or (= b 10) (= b 13))

fn isLlvmDigit? b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn isLlvmAlpha? b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90))
      (and (>= b 97) (<= b 122)))

fn isHexDigit? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57))
  (or (and (>= b 65) (<= b 70))
      (and (>= b 97) (<= b 102))))

fn isLlvmIdentChar? b: Int64 -> Bool
  (or (isLlvmAlpha? b)
  (or (isLlvmDigit? b)
  (or (= b 95)
  (or (= b 36)
  (or (= b 46)
      (= b 45))))))

fn tokenSlice tok: tr/Token text: String -> String
  (let [(s (tr/tokenStart tok))
        (e (tr/tokenEnd tok))]
    (if (or (< s 0) (> e (stringLength text)))
      ""
      (optionOr (stringSlice text s e) "")))

fn consumeWhitespace bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isLlvmWhitespace? (bytesGet bs idx))
      (consumeWhitespace bs len (+ idx 1))
      idx))

fn consumeNewline bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (let [(b (bytesGet bs idx))]
      (if (= b 13)
        (if (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 10))
          (+ idx 2)
          (+ idx 1))
        (if (= b 10)
          (+ idx 1)
          idx))))

fn consumeComment bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (let [(b (bytesGet bs idx))]
      (if (isLlvmNewline? b)
        idx
        (consumeComment bs len (+ idx 1)))))

fn consumeString bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (let [(b (bytesGet bs idx))]
      (cond
        ((= b 34) (+ idx 1))
        ((isLlvmNewline? b) idx)
        ((= b 92)
         (if (>= (+ idx 1) len)
           (+ idx 1)
           (let [(b1 (bytesGet bs (+ idx 1)))]
             (if (and (isHexDigit? b1) (< (+ idx 2) len) (isHexDigit? (bytesGet bs (+ idx 2))))
               (consumeString bs len (+ idx 3))
               (consumeString bs len (+ idx 2))))))
        (else
         (consumeString bs len (+ idx 1))))))

fn consumeIdent bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isLlvmIdentChar? (bytesGet bs idx))
      (consumeIdent bs len (+ idx 1))
      idx))

fn consumeNumber bs: Bytes len: Int64 idx: Int64 -> Int64
  (let [(afterSign (if (and (< idx len) (= (bytesGet bs idx) 45)) (+ idx 1) idx))]
    (let [(digits1 (consumeDigits bs len afterSign))]
      (let [(afterDot (if (and (< digits1 len) (= (bytesGet bs digits1) 46) (< (+ digits1 1) len) (isLlvmDigit? (bytesGet bs (+ digits1 1))))
                        (consumeDigits bs len (+ digits1 1))
                        digits1))]
        (if (and (< afterDot len) (or (= (bytesGet bs afterDot) 101) (= (bytesGet bs afterDot) 69)))
          (let [(afterExp (+ afterDot 1))
                (afterExpSign (if (and (< afterExp len) (or (= (bytesGet bs afterExp) 43) (= (bytesGet bs afterExp) 45))) (+ afterExp 1) afterExp))]
            (consumeDigits bs len afterExpSign))
          afterDot))))

fn consumeDigits bs: Bytes len: Int64 idx: Int64 -> Int64
  (if (>= idx len)
    idx
    (if (isLlvmDigit? (bytesGet bs idx))
      (consumeDigits bs len (+ idx 1))
      idx))


fn punctStr b: Int64 -> String
  (cond
    ((= b 40) "(")
    ((= b 41) ")")
    ((= b 91) "[")
    ((= b 93) "]")
    ((= b 123) "{")
    ((= b 125) "}")
    ((= b 60) "<")
    ((= b 62) ">")
    ((= b 44) ",")
    ((= b 61) "=")
    ((= b 42) "*")
    ((= b 58) ":")
    (else "punct"))

fn nextToken bs: Bytes len: Int64 idx: Int64 -> tr/Token
  (if (>= idx len)
    (tr/makeToken "eof" idx idx)
    (let [(b (bytesGet bs idx))]
      (cond
        ((isLlvmWhitespace? b)
         (let [(end (consumeWhitespace bs len idx))]
           (tr/makeToken "whitespace" idx end)))
        ((isLlvmNewline? b)
         (let [(end (consumeNewline bs len idx))]
           (tr/makeToken "newline" idx end)))
        ((= b 59)
         (let [(end (consumeComment bs len (+ idx 1)))]
           (tr/makeToken "comment" idx end)))
        ((= b 64)
         (if (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 34))
           (let [(end (consumeString bs len (+ idx 2)))]
             (tr/makeToken "global" idx end))
           (let [(end (consumeIdent bs len (+ idx 1)))]
             (tr/makeToken "global" idx end))))
        ((= b 37)
         (if (and (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 34))
           (let [(end (consumeString bs len (+ idx 2)))]
             (tr/makeToken "local" idx end))
           (let [(end (consumeIdent bs len (+ idx 1)))]
             (tr/makeToken "local" idx end))))
        ((= b 33)
         (if (and (< (+ idx 1) len) (isLlvmIdentChar? (bytesGet bs (+ idx 1))))
           (let [(end (consumeIdent bs len (+ idx 1)))]
             (tr/makeToken "metadata" idx end))
           (tr/makeToken "!" idx (+ idx 1))))
        ((= b 35)
         (let [(end (consumeIdent bs len (+ idx 1)))]
           (tr/makeToken "attrgroup" idx end)))
        ((and (= b 99) (< (+ idx 1) len) (= (bytesGet bs (+ idx 1)) 34))
         (let [(end (consumeString bs len (+ idx 2)))]
           (tr/makeToken "string" idx end)))
        ((= b 34)
         (let [(end (consumeString bs len (+ idx 1)))]
           (tr/makeToken "string" idx end)))
        ((or (= b 40) (= b 41) (= b 91) (= b 93) (= b 123) (= b 125)
             (= b 60) (= b 62) (= b 44) (= b 61) (= b 42) (= b 58))
         (tr/makeToken (punctStr b) idx (+ idx 1)))
        ((or (isLlvmDigit? b) (and (= b 45) (< (+ idx 1) len) (isLlvmDigit? (bytesGet bs (+ idx 1)))))
         (let [(identEnd (consumeIdent bs len idx))]
           (if (and (< identEnd len) (= (bytesGet bs identEnd) 58))
             (tr/makeToken "label" idx (+ identEnd 1))
             (let [(numEnd (consumeNumber bs len idx))]
               (tr/makeToken "number" idx numEnd)))))
        ((or (isLlvmAlpha? b) (= b 95) (= b 46) (= b 36))
         (let [(identEnd (consumeIdent bs len idx))]
           (if (and (< identEnd len) (= (bytesGet bs identEnd) 58))
             (tr/makeToken "label" idx (+ identEnd 1))
             (tr/makeToken "ident" idx identEnd))))
        (else
         (tr/makeToken "punct" idx (+ idx 1))))))

fn tokenizeLoop bs: Bytes len: Int64 idx: Int64 acc: (List tr/Token) -> (List tr/Token)
  (if (>= idx len)
    (listReverse acc)
    (let [(tok (nextToken bs len idx))
          (nextIdx (tr/tokenEnd tok))]
      (if (<= nextIdx idx)
        (listReverse (cons (tr/makeToken "error" idx len) acc))
        (tokenizeLoop bs len nextIdx (cons tok acc)))))

fn tokenizeBytes bs: Bytes -> (List tr/Token)
  (tokenizeLoop bs (bytesLength bs) 0 (list))

fn tokenizeText text: String -> (List tr/Token)
  (tokenizeBytes (stringToBytes text))

fn tokenize text: String -> (List tr/Token)
  (tokenizeText text)
