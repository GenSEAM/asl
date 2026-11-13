(module asl-tools/coord/tests/conductorClipTest
  :x [runTests]
  :i [(asl-tools/coord/conductor :a cd)])

; (:m :ref JOURNAL-UTF8-CUT :do "the conductor's journal clips cut at a character boundary: a verdict whose 400th byte falls inside a three-byte character keeps whole characters and stays valid UTF-8, a short text is unchanged, an ASCII text is cut at exactly the limit")
fn cjk n: Int64 acc: String -> String
  (if (<= n 0) acc (cjk (- n 1) (str acc "那")))

; (:m :ref JOURNAL-UTF8-CUT :do "valid UTF-8 by structure: a lead byte under 128 stands alone, 194-223 takes one continuation byte, 224-239 two, 240-244 three; continuation bytes are 128-191; anything else is invalid")
fn contAt? bs: Bytes i: Int64 k: Int64 n: Int64 -> Bool
  (cond
    ((= k 0) true)
    ((>= i n) false)
    (else (let [(b (bytesGet bs i))] (and (>= b 128) (and (< b 192) (contAt? bs (+ i 1) (- k 1) n))))))

fn validFrom? bs: Bytes i: Int64 n: Int64 -> Bool
  (if (>= i n) true
    (let [(b (bytesGet bs i))
          (k (cond ((< b 128) 0) ((and (>= b 194) (< b 224)) 1) ((and (>= b 224) (< b 240)) 2) ((and (>= b 240) (< b 245)) 3) (else -1)))]
      (and (>= k 0) (and (contAt? bs (+ i 1) k n) (validFrom? bs (+ i 1 k) n)))))

fn utf8Ok? s: String -> Bool
  (let [(bs (stringToBytes s))] (validFrom? bs 0 (bytesLength bs)))

fn ! sites -> Unit
  (let [(tail (str "xy" (cjk 200 "")))
        (tail1 (str "x" (cjk 200 "")))]
    (do (assert (not (utf8Ok? (optionOr (stringSlice tail 0 160) ""))) "fixture: a raw 160-byte cut of the CJK tail is invalid UTF-8")
        (assert (not (utf8Ok? (optionOr (stringSlice tail1 0 200) ""))) "fixture: a raw 200-byte cut of the 1-byte-prefixed tail is invalid UTF-8")
        (assert (not (utf8Ok? (optionOr (stringSlice tail 0 120) ""))) "fixture: a raw 120-byte cut is invalid UTF-8")
        (assert (utf8Ok? (cd/repoClip tail)) "repoClip (160) keeps valid UTF-8")
        (assert (utf8Ok? (cd/mergeCheckWhy (str "(:mergeCheck :unverified (" tail ") :x 1)") ":unverified")) "mergeCheckWhy (300) keeps valid UTF-8")
        (assert (utf8Ok? (cd/mergeHoldWhy 3 tail)) "the mergeCheck hold text (160) keeps valid UTF-8")
        (assert (utf8Ok? (cd/spawnFailedSig tail)) "spawnFailed stderr (120) keeps valid UTF-8")
        (assert (utf8Ok? (cd/gateSig (str "FAIL " tail1))) "gateSig (160) keeps valid UTF-8")
        (assert (utf8Ok? (cd/modelEscalatedSig (str "(:agent :status :failed :receipt (:agentReceipt :status :escalated :stop modelEscalated :escalate (:escalate :reason \"" tail1 "\" :seen \"x\") :usage (:input 1)))"))) "modelEscalatedSig reason (200) keeps valid UTF-8")
        (assert (> (stringLength (cd/modelEscalatedSig (str "(:agent :status :failed :receipt (:agentReceipt :status :escalated :stop modelEscalated :escalate (:escalate :reason \"" tail1 "\" :seen \"x\") :usage (:input 1)))"))) 180) "modelEscalatedSig carries the reason it clipped")
        (assert (utf8Ok? (cd/verdictSig tail)) "verdictSig (400) keeps valid UTF-8")))

fn ! runTests -> Bool
  (let [(sig (str "xy" (cjk 200 "")))
        (cut (cd/verdictSig sig))
        (cutBytes (bytesLength (stringToBytes cut)))
        (ascii (cd/utf8Clip "abcdefghij" 4))
        (mid (cd/utf8Clip "ab那些" 4))]
    (do (sites)
        (assert (= (bytesLength (stringToBytes sig)) 602) "fixture: 2 ASCII bytes then 200 three-byte characters")
        (assert (= cutBytes 398) (str "the 400-byte verdict cut, which falls inside a character, backs off to its start: " cutBytes " bytes"))
        (assert (= cut (str "xy" (cjk 132 ""))) "the cut verdict is whole characters, valid UTF-8")
        (assert (= (listLength (stringChars cut)) 134) "every character of the cut verdict is complete")
        (assert (= ascii "abcd") "ASCII cuts at exactly the limit")
        (assert (= mid "ab") "a limit inside the first multibyte character drops it whole")
        (assert (= (cd/utf8Clip "ab那些" 5) "ab那") "a limit at a character end keeps it")
        (assert (= (cd/utf8Clip "short" 160) "short") "text under the limit is unchanged")
        true))
