(module asl-text/dotenv :x [parseDotenv renderDotenv] :i [])

fn joinChars cs: (List String) -> String
  (fold (fn [(acc String) (c String)] -> String (str acc c)) "" cs)

fn isWs c: String -> Bool
  (or (= c " ") (or (= c "\t") (= c "\r")))

fn revCs cs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (c String)] -> (List String) (cons c acc)) (list) cs)

fn trimLeftCs cs: (List String) -> (List String)
  (match (listHead cs)
    ((none) (list))
    ((some c) (if (isWs c)
      (trimLeftCs (optionOr (listTail cs) (list)))
      cs)))

fn trim s: String -> String
  (joinChars (revCs (trimLeftCs (revCs (trimLeftCs (stringChars s))))))

fn startsWithCs cs: (List String) ps: (List String) -> Bool
  (match (listHead ps)
    ((none) true)
    ((some p) (match (listHead cs)
      ((none) false)
      ((some c) (if (= c p)
        (startsWithCs (optionOr (listTail cs) (list)) (optionOr (listTail ps) (list)))
        false)))))

fn dropN cs: (List String) n: Int64 -> (List String)
  (if (= n 0)
    cs
    (dropN (optionOr (listTail cs) (list)) (- n 1)))

fn stripExportCs cs: (List String) -> (List String)
  (if (startsWithCs cs (stringChars "export "))
    (dropN cs 7)
    cs)

fn splitEq cs: (List String) key: String -> (Option (Pair String (List String)))
  (match (listHead cs)
    ((none) (none))
    ((some c) (if (= c "=")
      (some (pair key (optionOr (listTail cs) (list))))
      (splitEq (optionOr (listTail cs) (list)) (str key c)))))

fn lastChar cs: (List String) -> String
  (fold (fn [(acc String) (c String)] -> String c) "" cs)

fn dropLastCs cs: (List String) -> (List String)
  (revCs (optionOr (listTail (revCs cs)) (list)))

fn decodeEsc c: String -> String
  (if (= c "n") "\n"
    (if (= c "t") "\t"
      (if (= c "r") "\r" c)))

fn unescapeCs cs: (List String) -> String
  (pairFirst
    (fold (fn [(st (Pair String Bool)) (c String)] -> (Pair String Bool)
      (if (pairSecond st)
        (pair (str (pairFirst st) (decodeEsc c)) false)
        (if (= c "\\")
          (pair (pairFirst st) true)
          (pair (str (pairFirst st) c) false))))
      (pair "" false)
      cs))

fn stripQuotes s: String -> String
  (let [(cs (stringChars s))
        (n (listLength cs))
        (h (optionOr (listHead cs) ""))
        (l (lastChar cs))]
    (if (and (and (>= n 2) (or (= h "\"") (= h "'"))) (= l h))
      (let [(inner (dropLastCs (optionOr (listTail cs) (list))))]
        (if (= h "\"")
          (unescapeCs inner)
          (joinChars inner)))
      s))

fn parseKV rawKey: String rawVal: String -> (Option (Pair String String))
  (let [(key (trim rawKey))
        (val (stripQuotes (trim rawVal)))]
    (if (= key "")
      (none)
      (some (pair key val))))

fn parseAssign s: String -> (Option (Pair String String))
  (match (splitEq (stringChars s) "")
    ((none) (none))
    ((some kv) (parseKV (pairFirst kv) (joinChars (pairSecond kv)))))

fn parseLine line: String -> (Option (Pair String String))
  (let [(t (trim line))]
    (if (or (= t "") (= (optionOr (listHead (stringChars t)) "") "#"))
      (none)
      (parseAssign (joinChars (stripExportCs (stringChars t))))))

fn splitLinesFrom cs: (List String) cur: String -> (List String)
  (match (listHead cs)
    ((none) (list cur))
    ((some c) (if (= c "\n")
      (cons cur (splitLinesFrom (optionOr (listTail cs) (list)) ""))
      (splitLinesFrom (optionOr (listTail cs) (list)) (str cur c)))))

fn prependRow row: (Option (Pair String String)) rest: (List (Pair String String)) -> (List (Pair String String))
  (match row
    ((none) rest)
    ((some p) (cons p rest)))

fn parseLines lines: (List String) -> (List (Pair String String))
  (match (listHead lines)
    ((none) (list))
    ((some l) (prependRow (parseLine l) (parseLines (optionOr (listTail lines) (list))))))

fn parseDotenv s: String -> (List (Pair String String))
  (parseLines (splitLinesFrom (stringChars s) ""))

fn escChar c: String -> String
  (if (= c "\\") "\\\\"
    (if (= c "\"") "\\\""
      (if (= c "\n") "\\n"
        (if (= c "\r") "\\r"
          (if (= c "\t") "\\t" c)))))

fn specialChar c: String -> Bool
  (or (= c "\"") (or (= c "'") (or (= c "\\") (or (= c "#") (or (= c "\n") (= c "\r"))))))

fn edgeWs c: String -> Bool
  (or (= c " ") (= c "\t"))

fn needsQuote v: String -> Bool
  (let [(cs (stringChars v))]
    (or (listAny? (fn [(c String)] -> Bool (specialChar c)) cs)
      (or (edgeWs (optionOr (listHead cs) "")) (edgeWs (lastChar cs)))))

fn renderValue v: String -> String
  (if (needsQuote v)
    (str (str "\"" (joinChars (map escChar (stringChars v)))) "\"")
    v)

fn renderDotenv rows: (List (Pair String String)) -> String
  (fold (fn [(acc String) (row (Pair String String))] -> String
    (str (str (str (str acc (pairFirst row)) "=") (renderValue (pairSecond row))) "\n"))
    ""
    rows)
