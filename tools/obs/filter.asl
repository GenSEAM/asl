(module ws/asl/tools/obs/filter
  :x [redact firstLine clip safeText maxText]
  :i [])

; (:m :ref OBSCORPUS :do "the only text an observation may carry is one clipped first line that passed redact: secret-looking tokens, NAME=value environment pairs and .asl/mem paths are replaced by fixed markers, never stored; prompts and bodies never reach this module")
fn maxText -> Int64
  200

fn alnum? b: Int64 -> Bool
  (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122))))

fn digit? b: Int64 -> Bool
  (and (>= b 48) (<= b 57))

fn letter? b: Int64 -> Bool
  (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))

fn upperName? w: String -> Bool
  (let [(bs (stringToBytes w))]
    (and (>= (bytesLength bs) 3)
         (listAll? (fn [(i Int64)] -> Bool (let [(b (bytesGet bs i))] (or (and (>= b 65) (<= b 90)) (or (digit? b) (= b 95))))) (range 0 (bytesLength bs)))))

fn stripLead w: String -> String
  (let [(bs (stringToBytes w))
        (n (bytesLength bs))
        (k (fold (fn [(acc Int64) (i Int64)] -> Int64 (if (and (= acc i) (not (alnum? (bytesGet bs i)))) (+ acc 1) acc)) 0 (range 0 n)))]
    (optionOr (stringSlice w k n) ""))

fn longOpaque? w: String -> Bool
  (let [(bs (stringToBytes w))
        (n (bytesLength bs))
        (idx (range 0 n))]
    (and (>= n 32)
         (and (listAny? (fn [(i Int64)] -> Bool (digit? (bytesGet bs i))) idx)
              (and (listAny? (fn [(i Int64)] -> Bool (letter? (bytesGet bs i))) idx)
                   (listAll? (fn [(i Int64)] -> Bool (let [(b (bytesGet bs i))] (or (alnum? b) (or (= b 43) (or (= b 47) (or (= b 95) (or (= b 61) (= b 45)))))))) idx)))))

fn secretName? lhs: String -> Bool
  (let [(l (stringLower lhs))]
    (or (stringContains? l "key") (or (stringContains? l "token") (or (stringContains? l "secret") (or (stringContains? l "pass") (or (stringContains? l "auth") (stringContains? l "cred")))))))

fn prefixSecret? w: String -> Bool
  (let [(s (stripLead w))]
    (or (stringStartsWith? s "sk-") (or (stringStartsWith? s "ghp_") (or (stringStartsWith? s "AIza") (or (stringStartsWith? s "xox") (or (stringStartsWith? s "glpat-") (stringStartsWith? s "eyJ")))))))

fn cleanToken prev: String w: String -> String
  (cond
    ((stringContains? w ".asl/mem") "<mem>")
    ((or (= prev "Bearer") (= prev "Authorization:")) "<secret>")
    ((and (prefixSecret? w) (>= (stringLength w) 10)) "<secret>")
    ((stringContains? w "=")
      (let [(lhs (optionOr (stringSlice w 0 (optionOr (stringIndexOf w "=") 0)) ""))]
        (if (or (secretName? lhs) (upperName? lhs))
          (str lhs "=<redacted>")
          (if (longOpaque? (stripLead w)) "<secret>" w))))
    ((longOpaque? (stripLead w)) "<secret>")
    (else w))

fn redact text: String -> String
  (let [(words (stringSplit (stringReplace text "/Users/purplelephant" "~") " "))
        (res (fold (fn [(acc (Pair String (List String))) (w String)] -> (Pair String (List String))
                     (pair w (cons (cleanToken (pairFirst acc) w) (pairSecond acc))))
                   (pair "" (list)) words))]
    (stringJoin (listReverse (pairSecond res)) " "))

fn firstLine text: String -> String
  (stringTrim (optionOr (listHead (stringSplit (stringReplace text "\r" "") "\n")) ""))

fn clip text: String n: Int64 -> String
  (if (> (stringLength text) n) (optionOr (stringSlice text 0 n) text) text)

fn safeText text: String -> String
  (clip (redact (firstLine text)) (maxText))
