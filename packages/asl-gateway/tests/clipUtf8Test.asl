(module aslGateway/tests/clipUtf8Test
  :x [runTests]
  :i [(aslGateway/wire :a w) (aslGateway/server :a sv) (aslGateway/usageLedger :a ul) (aslGateway/upstream :a u)])

; (:m :ref UTF8-CLIP-SWEEP :do "each gateway cap lands inside a 3-byte CJK character (U+6F22) after cap - 1 ASCII bytes; the ledger reason, the upstream error text and the unbalanced-reply raw field keep the ASCII bytes and drop the whole character")
fn tail cap: Int64 -> String
  (str (stringRepeat "a" (- cap 1)) "漢" "zz")

fn prefix cap: Int64 -> String
  (stringRepeat "a" (- cap 1))

fn ! testFallbackErrorText -> Bool
  (do (assert (= (w/fallbackErrorText (tail 500) "none") (prefix 500)) "fallbackErrorText: a 500-byte cut keeps the 499 ASCII bytes")
      (assert (= (w/fallbackErrorText " bad 漢 " "none") "bad 漢") "fallbackErrorText: short text is trimmed and kept")
      true)

fn ! testSanitizeRaw -> Bool
  (do (assert (= (w/sanitizeAsnContent (tail 197)) (str "(:error :reason \"unbalanced_non_asn\" :raw \"" (prefix 197) "...\")")) "sanitizeAsnContent: the raw field cut at 197 bytes keeps the 196 ASCII bytes")
      true)

fn ! testFailureReason -> Bool
  (do (assert (= (sv/failureReason (u/httpFailure 502 "Bad Gateway" (tail 400) (list))) (str "502 Bad Gateway: " (prefix 400))) "failureReason: the body cut at 400 bytes keeps the 399 ASCII bytes")
      true)

fn ! testRedactReason -> Bool
  (let [(head (str (stringRepeat "ab " 66) "c"))]
    (do (assert (= (ul/redactReason (str head "漢zz")) head) "redactReason: the 200-byte cut inside a CJK character keeps the 199 bytes before it")
        (assert (= (ul/redactReason "plain 漢") "plain 漢") "redactReason: short text is kept")
        true))

fn ! runTests -> Bool
  (do (assert (testFallbackErrorText) "fallbackErrorText")
      (assert (testSanitizeRaw) "sanitizeAsnContent")
      (assert (testFailureReason) "failureReason")
      (assert (testRedactReason) "redactReason")
      true)
