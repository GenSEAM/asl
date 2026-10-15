(module asl-html/asn
  :x [unbalanced unquote stringAtom? keywordAtom? bare valueText kebab atomOf headOf lookup]
  :i [(asl-parser/reader :a rd) (asl-parser/balance :a bal)])

fn unquote atom: String -> String
  (let [(inner (optionOr (stringSlice atom 1 (- (stringLength atom) 1)) ""))
        (held (stringReplace inner "\\\\" "\u{1}"))]
    (stringReplace (stringReplace (stringReplace (stringReplace held "\\n" "\n") "\\t" "\t") "\\\"" "\"") "\u{1}" "\\"))

fn stringAtom? a: String -> Bool
  (and (stringStartsWith? a "\"") (stringEndsWith? a "\""))

fn keywordAtom? a: String -> Bool
  (stringStartsWith? a ":")

fn bare a: String -> String
  (if (keywordAtom? a) (optionOr (stringSlice a 1 (stringLength a)) a) a)

fn valueText a: String -> String
  (cond ((stringAtom? a) (unquote a)) ((keywordAtom? a) (bare a)) (else a))

fn upper? c: String -> Bool
  (and (>= c "A") (<= c "Z"))

fn kebab name: String -> String
  (stringJoin (map (fn [(c String)] -> String (if (upper? c) (str "-" (stringLower c)) c)) (stringChars name)) "")

fn atomOf e: rd/SExpr -> (Option String)
  (mt e ((rd/sexprAtom v) (some v)) (_ (none)))

fn headOf e: rd/SExpr -> String
  (mt e ((rd/sexprList items) (bare (optionOr (atomOf (optionOr (listHead items) (rd/makeAtom ""))) ""))) (_ ""))

fn lookup table: (List (Pair String String)) key: String -> (Option String)
  (optionMap pairSecond (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) key)) table)))

fn unbalanced source: String -> (Option (List String))
  (let [(b (bal/checkDelimiterBalanceIn false source))]
    (if b.balanced
      (none)
      (some [(str "unbalanced input: " (stringFromInt64 b.openParens) " unclosed '(', " (stringFromInt64 b.openBrackets) " unclosed '[', " (stringFromInt64 b.openBraces) " unclosed '{' (negative means extra closers)")])))
