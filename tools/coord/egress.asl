(module asl-tools/coord/egress
  :x [secretLike? memLike? secretPath? leaks? leaksWith? envLeak? clip scrubLines scrubText allowedPath? minEnvValueLength]
  :i [])

; (:m :ref FLOW-EGRESS :do "the one filter for text that may reach an external model: no memory content, no secret-looking text, no env values, no key files; pure, env values come in as data")

fn textNeedles -> (List String)
  (list "secret" "password" "apikey" "api_key" "api-key" "_key" "bearer" "ghp_" "akia"
        "xoxb-" "xoxp-" "xoxa-" "xoxr-" "xoxs-" "private key" "authorization:")

fn pathNeedles -> (List String)
  (list ".env" "secret" "credential" "token" "password" "apikey" "api_key" "api-key" "id_rsa" "id_ed25519" ".pem" ".key" ".p12" "keychain" ".netrc")

fn hits? s: String needles: (List String) -> Bool
  (listAny? (fn [(n String)] -> Bool (stringContains? s n)) needles)

fn memLike? text: String -> Bool
  (stringContains? (stringLower text) ".asl/mem")

fn keyChars -> String
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

fn valueChars -> String
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.+/=:"

fn runLen chars: (List String) allowed: String -> Int64
  (match (listHead chars)
    ((none) 0)
    ((some c) (if (stringContains? allowed c) (+ 1 (runLen (listDrop chars 1) allowed)) 0)))

fn shapeAfter? s: String marker: String allowed: String minLen: Int64 -> Bool
  (listAny? (fn [(piece String)] -> Bool (>= (runLen (stringChars (clip piece 80)) allowed) minLen))
            (listDrop (stringSplit s marker) 1))

fn keyShape? s: String -> Bool
  (or (shapeAfter? s "sk-" (keyChars) 20)
      (shapeAfter? s "key=" (valueChars) 16)
      (shapeAfter? s "token=" (valueChars) 16))

fn secretLike? text: String -> Bool
  (let [(s (stringLower text))]
    (or (memLike? s) (hits? s (textNeedles)) (keyShape? s)))

fn secretPath? path: String -> Bool
  (let [(s (stringLower path))]
    (or (memLike? s) (hits? s (pathNeedles))))

fn leaks? text: String -> Bool
  (secretLike? text)

fn minEnvValueLength -> Int64
  8

fn envLeak? values: (List String) text: String -> Bool
  (listAny? (fn [(v String)] -> Bool (and (>= (stringLength v) (minEnvValueLength)) (stringContains? text v))) values)

fn leaksWith? values: (List String) text: String -> Bool
  (or (secretLike? text) (envLeak? values text))

fn clip s: String n: Int64 -> String
  (if (> (stringLength s) n) (optionOr (stringSlice s 0 n) s) s)

fn scrubLines values: (List String) text: String maxLines: Int64 width: Int64 -> (List String)
  (listTake (map (fn [(l String)] -> String (clip l width))
                 (filter (fn [(l String)] -> Bool (and (not (stringEmpty? (stringTrim l))) (not (leaksWith? values l)))) (stringLines text)))
            maxLines)

fn scrubText values: (List String) text: String maxLines: Int64 width: Int64 -> String
  (stringJoin (scrubLines values text maxLines width) "\n")

fn allowedPath? root: String path: String -> Bool
  (cond
    ((stringEmpty? path) false)
    ((or (= path "..") (stringStartsWith? path "../") (stringContains? path "/../") (stringEndsWith? path "/..")) false)
    ((and (stringStartsWith? path "/") (not (stringStartsWith? path (str root "/")))) false)
    (else (not (secretPath? path))))
