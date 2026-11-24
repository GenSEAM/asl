(module asl-text/shellWords :x [splitWords joinWords] :i [])

fn splitLoop chars: (List String) mode: Int64 cur: String started: Bool acc: (List String) -> (Result (List String) String)
  (match (listHead chars)
    ((none) (if (!= mode 0) (err "unterminated quote") (ok (if started (listAppend acc (list cur)) acc))))
    ((some c)
      (let [(rest (optionOr (listTail chars) (list)))]
        (cond
          ((= mode 1) (if (= c "'") (splitLoop rest 0 cur started acc) (splitLoop rest 1 (str cur c) true acc)))
          ((= mode 2) (cond
            ((= c "\"") (splitLoop rest 0 cur started acc))
            ((= c "\\") (match (listHead rest)
              ((none) (err "trailing backslash"))
              ((some d) (splitLoop (optionOr (listTail rest) (list)) 2 (str cur d) true acc))))
            (else (splitLoop rest 2 (str cur c) true acc))))
          ((or (= c " ") (or (= c "\t") (= c "\n"))) (if started (splitLoop rest 0 "" false (listAppend acc (list cur))) (splitLoop rest 0 "" false acc)))
          ((= c "'") (splitLoop rest 1 cur true acc))
          ((= c "\"") (splitLoop rest 2 cur true acc))
          ((= c "\\") (match (listHead rest)
            ((none) (err "trailing backslash"))
            ((some d) (splitLoop (optionOr (listTail rest) (list)) 0 (str cur d) true acc))))
          (else (splitLoop rest 0 (str cur c) true acc))))))

fn splitWords s: String -> (Result (List String) String)
  (splitLoop (stringChars s) 0 "" false (list))

fn safeChar? c: String -> Bool
  (let [(b (charCode c))]
    (or (and (>= b 97) (<= b 122))
        (or (and (>= b 65) (<= b 90))
            (or (and (>= b 48) (<= b 57))
                (listContains? (list "-" "_" "." "/" ":" "=" "@" "%" "+" ",") c)))))

fn needsQuoting? w: String -> Bool
  (or (stringEmpty? w) (not (listAll? safeChar? (stringChars w))))

fn escapeDouble s: String -> String
  (fold (fn [(acc String) (c String)] -> String
          (cond
            ((= c "\\") (str acc "\\\\"))
            ((= c "\"") (str acc "\\\""))
            (else (str acc c))))
        "" (stringChars s))

fn quoteWord w: String -> String
  (if (not (needsQuoting? w)) w
    (if (not (stringContains? w "'")) (str "'" w "'")
      (str "\"" (escapeDouble w) "\"")))

fn joinWords ws: (List String) -> String
  (stringJoin (map quoteWord ws) " ")
