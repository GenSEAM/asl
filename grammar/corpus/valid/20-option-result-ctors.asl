"Both polarities of every Option and Result predicate, inside a single case: one"

"half of the pair parses and one does not, so a predicate stuck at `true` fails"

"on the other half. The pair is returned positionally, which is what makes an"

"argument swap in `pair` visible at all — both components are String."

(module parse/classify :x [classify])

fn flag b: Bool -> String
  (if b "T" "F")

fn render tok: String -> String
  (let [(o (stringToInt64 tok)) (r (match o ((some n) (ok n)) ((none) (err tok)))) (value (match r ((ok n) (stringFromInt64 n)) ((err e) e)))] (str (if (some? o) "some" "none") "/" (if (ok? r) "ok" "err") ":" value "|" (flag (some? o)) (flag (none? o)) (flag (ok? r)) (flag (err? r))))

fn classify a: String b: String -> (Pair String String)
  (pair (render a) (render b))
