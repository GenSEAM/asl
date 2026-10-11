(module parse/classify :x [classify])

fn flag b: Bool -> String
  (if b "T" "F")

fn render tok: String -> String
  (let [(o (stringToInt64 tok)) (r (match o ((some n) (ok n)) ((none) (err tok)))) (value (match r ((ok n) (stringFromInt64 n)) ((err e) e)))] (str (if (some? o) "some" "none") "/" (if (ok? r) "ok" "err") ":" value "|" (flag (some? o)) (flag (none? o)) (flag (ok? r)) (flag (err? r))))

fn classify a: String b: String -> (Pair String String)
  (pair (render a) (render b))
