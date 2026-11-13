enum Token (number value: Int64) (word text: String) (symbol text: String) (unknown)

fn allIn? text: String alphabet: String -> Bool
  (and (not (stringEmpty? text)) (listAll? (fn [c] (stringContains? alphabet c)) (stringChars text)))

fn classifyToken text: String -> Token
  (cond
    ((allIn? text "0123456789") (number (optionOr (stringToInt64 text) 0)))
    ((allIn? text "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") (word text))
    ((and (= (stringLength text) 1) (!= text " ")) (symbol text))
    (else (unknown)))
