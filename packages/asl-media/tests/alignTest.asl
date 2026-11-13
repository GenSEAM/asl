(module asl-media/tests/alignTest
  :x [runTests]
  :i [(asl-media/align :a al)])

fn words s: String -> (List String)
  (al/normaliseWords s (list))

fn werRes r: (Result al/WerResult String) -> al/WerResult
  (match r
    ((ok w) w)
    ((err e) (do (assert false e) (al/WerResult :subs -1 :dels -1 :ins -1 :matches -1 :refLen -1 :hypLen -1 :errors -1 :wer -1.0))))

fn ! testWer! -> Bool
  (let [(w (werRes (al/werText "the cat sat" "the bat sat on" (list))))
        (same (werRes (al/werText "the cat sat" "The cat, sat!" (list))))
        (empty (werRes (al/werText "the cat sat" "" (list))))
        (kitten (werRes (al/werOf (list "k" "i" "t" "t" "e" "n") (list "s" "i" "t" "t" "i" "n" "g"))))
        (both (werRes (al/werText "" "" (list))))
        (extra (werRes (al/werText "" "a b" (list))))]
    (do
      (assert (and (= w.subs 1) (= w.dels 0) (= w.ins 1) (= w.matches 2)) "the cat sat / the bat sat on: one substitution, one insertion, two matches")
      (assert (and (= w.errors 2) (= w.refLen 3) (= w.hypLen 4)) "two errors over three reference words")
      (assert (< (abs (- w.wer (/ 2.0 3.0))) 0.0000001) "WER is 2/3")
      (assert (and (= same.errors 0) (= same.wer 0.0)) "case and punctuation do not count: identical text is 0")
      (assert (and (= empty.wer 1.0) (= empty.dels 3)) "an empty hypothesis is 1.0, all deletions")
      (assert (= kitten.errors 3) "kitten/sitting at symbol level is distance 3")
      (assert (and (= both.wer 0.0) (= both.refLen 0)) "empty against empty is 0, not a division")
      (assert (= extra.wer 1.0) "an empty reference with a hypothesis is 1.0")
      true))

fn ! testNormalise! -> Bool
  (do
    (assert (= (words "Don't STOP, now -- ok?") (list "dont" "stop" "now" "ok")) "lower case, apostrophes dropped, punctuation is a space")
    (assert (= (al/normaliseWords "I have 3 cats" (list (pair "3" "three"))) (list "i" "have" "three" "cats")) "a numeral map is applied to whole words")
    (assert (= (words "") (list)) "empty text has no words")
    (assert (= (words "caf\xc3\xa9 au lait") (list "caf\xc3\xa9" "au" "lait")) "multi-byte characters stay inside words")
    true)

fn ! testCer! -> Bool
  (let [(c (werRes (al/cerText "kitten" "sitting" (list))))]
    (do
      (assert (and (= c.errors 3) (= c.refLen 6)) "CER of kitten/sitting is 3 over 6 characters")
      true))

fn opKinds ops: (Result (List al/AlignOp) String) -> (List String)
  (match ops
    ((ok os) (map (fn [(o al/AlignOp)] -> String o.kind) os))
    ((err e) (list e)))

fn ! testAlignOps! -> Bool
  (do
    (assert (= (opKinds (al/alignWords (list "the" "cat" "sat") (list "the" "bat" "sat" "on") al/exactSame)) (list "match" "sub" "match" "ins")) "alignment pairs are match sub match ins")
    (assert (= (opKinds (al/alignWords (list "a" "b" "c") (list "a" "c") al/exactSame)) (list "match" "del" "match")) "a missing middle word is a deletion")
    (assert (= (opKinds (al/alignWords (list "colour") (list "color") (fn [(a String) (b String)] -> Bool (stringStartsWith? b "col")))) (list "match")) "a caller similarity can call near words equal")
    true)

fn scriptWords n: Int64 -> (List String)
  (map (fn [(i Int64)] -> String (str "w" (stringFromInt64 i))) (rangeTo 0 n))

fn rangeTo i: Int64 n: Int64 -> (List Int64)
  (if (>= i n) (list) (cons i (rangeTo (+ i 1) n)))

fn asrFor n: Int64 -> (List al/AsrWord)
  (map (fn [(i Int64)] -> al/AsrWord (al/AsrWord :text (if (= (mod i 10) 7) "wrong" (str "w" (stringFromInt64 i))) :startMs (* i 100) :endMs (+ (* i 100) 80)))
       (filter (fn [(i Int64)] -> Bool (not (= (mod i 13) 5))) (rangeTo 0 n)))

fn ! testMap! -> Bool
  (match (al/mapAsrTimes (scriptWords 200) (asrFor 200) (list) al/exactSame)
    ((err e) (do (assert false e) false))
    ((ok r)
      (let [(ws r.words)]
        (do
          (assert (= (listLength ws) 200) "every script word gets a time")
          (assert (= (map (fn [(w al/TimedWord)] -> String w.word) ws) (scriptWords 200)) "script order and text are kept")
          (assert (monotone? ws) "starts and ends are monotonic and do not overlap")
          (assert (and (> r.coverage 0.9) (< r.coverage 1.0)) "coverage counts the 15 deleted words")
          (assert (listAny? (fn [(w al/TimedWord)] -> Bool (= w.status "interp")) ws) "deleted words are interpolated")
          (assert (= (optionOr (listHead (map (fn [(w al/TimedWord)] -> Int64 w.startMs) (listDrop ws 1))) -1) 100) "a matched word keeps its ASR start")
          (assert (inGap? ws 5 400 600) "the deleted word 5 sits between word 4's end and word 6's start")
          true))))

fn inGap? ws: (List al/TimedWord) i: Int64 lo: Int64 hi: Int64 -> Bool
  (match (listGet ws i)
    ((none) false)
    ((some w) (and (>= w.startMs lo) (<= w.endMs hi))))

fn monotone? ws: (List al/TimedWord) -> Bool
  (monoLoop ws 0)

fn monoLoop ws: (List al/TimedWord) prevEnd: Int64 -> Bool
  (match (listHead ws)
    ((none) true)
    ((some w) (and (>= w.startMs prevEnd) (and (>= w.endMs w.startMs) (monoLoop (optionOr (listTail ws) (list)) w.endMs)))))

fn ! testSpread! -> Bool
  (let [(asr (list (al/AsrWord :text "a" :startMs 0 :endMs 100) (al/AsrWord :text "d" :startMs 400 :endMs 500)))]
    (match (al/mapAsrTimes (list "a" "b" "c" "d") asr (list) al/exactSame)
      ((err e) (do (assert false e) false))
      ((ok r)
        (do
          (assert (= (map (fn [(w al/TimedWord)] -> Int64 w.startMs) r.words) (list 0 100 250 400)) "two deleted words split the 100..400 gap evenly: starts")
          (assert (= (map (fn [(w al/TimedWord)] -> Int64 w.endMs) r.words) (list 100 250 400 500)) "two deleted words split the 100..400 gap evenly: ends")
          true))))

fn ! testOverlapClamp! -> Bool
  (let [(asr (list (al/AsrWord :text "a" :startMs 0 :endMs 100) (al/AsrWord :text "b" :startMs 50 :endMs 150)))]
    (match (al/mapAsrTimes (list "a" "b") asr (list) al/exactSame)
      ((err e) (do (assert false e) false))
      ((ok r)
        (do
          (assert (= (map (fn [(w al/TimedWord)] -> Int64 w.startMs) r.words) (list 0 100)) "an ASR word that overlaps its predecessor starts at the predecessor's end")
          true))))

fn ! testInsPreference! -> Bool
  (do
    (assert (= (opKinds (al/alignWords (list "x" "a") (list "a" "y") al/exactSame)) (list "sub" "sub")) "sub+sub wins the cost-2 tie against del+match+ins")
    (assert (= (opKinds (al/alignWords (list "a" "b" "c") (list "a" "x" "b" "c") al/exactSame)) (list "match" "ins" "match" "match")) "an insertion costs one")
    (assert (= (opKinds (al/alignWords (list "x" "a" "b") (list "a" "b" "y") al/exactSame)) (list "del" "match" "match" "ins")) "del and ins around two matches beat three substitutions")
    true)

fn ! testNoAnchor! -> Bool
  (do
    (assert (stringStartsWith? (match (al/mapAsrTimes (list "a" "b") (list) (list) al/exactSame) ((err e) e) ((ok _) "")) "alignNoAnchor") "no ASR word at all is a labelled err")
    (assert (match (al/mapAsrTimes (list "a" "b") (list (al/AsrWord :text "z" :startMs 0 :endMs 10)) (list) al/exactSame) ((ok r) (= (map (fn [(w al/TimedWord)] -> String w.status) r.words) (list "interp" "sub"))) ((err _) false)) "a substituted word is an anchor (ties resolve from the end), the rest is interpolated")
    true)

fn ! runTests -> Bool
  (do
    (testNormalise!)
    (testWer!)
    (testCer!)
    (testAlignOps!)
    (testMap!)
    (testNoAnchor!)
    (testSpread!)
    (testOverlapClamp!)
    (testInsPreference!)
    true)
