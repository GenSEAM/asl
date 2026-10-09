"Querying a string. Both arguments are String, so a haystack/needle swap"

"type-checks and compiles: the cases assert the index, not merely that one was"

"found. The needle sits at the start in one case and at the end in another,"

"which is what separates stringStartsWith? from stringEndsWith?, and the"

"last case is non-ASCII, where a byte offset and a character offset differ."

(module string/query :x [query cut])

fn mark b: Bool -> String
  (if b "T" "F")

fn showInt o: (Option Int64) -> String
  (match o ((some n) (str "some " (stringFromInt64 n))) ((none) "none"))

fn query hay: String needle: String -> String
  (stringJoin (list (stringFromInt64 (stringLength hay)) (showInt (stringIndexOf hay needle)) (mark (stringContains? hay needle)) (mark (stringStartsWith? hay needle)) (mark (stringEndsWith? hay needle)) (mark (stringEmpty? hay)) (stringFromInt64 (listLength (stringChars hay)))) "|")

fn cut hay: String a: Int64 b: Int64 -> (Option String)
  (stringSlice hay a b)
