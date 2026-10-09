(module aslVoice/heardName :x [NameMatch transliterateCyrillic levenshteinDistance matchHeardName] :i [])

(schema NameMatch (:f rawInput Str) (:f transliterated Str) (:f matchedTarget Str) (:f levenshteinDistance I64) (:f score F64) (:f isMatch Bool))

(schema CandidateBest (:f target Str) (:f dist I64))

fn transliterateCyrillic text: Str -> Str
  (let [(u1 (stringReplace text "Щ" "sch")) (u2 (stringReplace u1 "Ч" "ch")) (u3 (stringReplace u2 "Ш" "sh")) (u4 (stringReplace u3 "Ж" "zh")) (u5 (stringReplace u4 "Ю" "yu")) (u6 (stringReplace u5 "Я" "ya")) (u7 (stringReplace u6 "Э" "eh")) (u8 (stringReplace u7 "Ц" "ts")) (u9 (stringReplace u8 "Х" "kh")) (u10 (stringReplace u9 "Ё" "yo")) (u11 (stringReplace u10 "А" "a")) (u12 (stringReplace u11 "Б" "b")) (u13 (stringReplace u12 "В" "v")) (u14 (stringReplace u13 "Г" "g")) (u15 (stringReplace u14 "Д" "d")) (u16 (stringReplace u15 "Е" "e")) (u17 (stringReplace u16 "З" "z")) (u18 (stringReplace u17 "И" "i")) (u19 (stringReplace u18 "Й" "y")) (u20 (stringReplace u19 "К" "k")) (u21 (stringReplace u20 "Л" "l")) (u22 (stringReplace u21 "М" "m")) (u23 (stringReplace u22 "Н" "n")) (u24 (stringReplace u23 "О" "o")) (u25 (stringReplace u24 "П" "p")) (u26 (stringReplace u25 "Р" "r")) (u27 (stringReplace u26 "С" "s")) (u28 (stringReplace u27 "Т" "t")) (u29 (stringReplace u28 "У" "u")) (u30 (stringReplace u29 "Ф" "f")) (u31 (stringReplace u30 "Ъ" "")) (u32 (stringReplace u31 "Ы" "y")) (u33 (stringReplace u32 "Ь" "")) (t0 (stringLower u33)) (t1 (stringReplace t0 "щ" "sch")) (t2 (stringReplace t1 "ч" "ch")) (t3 (stringReplace t2 "ш" "sh")) (t4 (stringReplace t3 "ж" "zh")) (t5 (stringReplace t4 "ю" "yu")) (t6 (stringReplace t5 "я" "ya")) (t7 (stringReplace t6 "э" "eh")) (t8 (stringReplace t7 "ц" "ts")) (t9 (stringReplace t8 "х" "kh")) (t10 (stringReplace t9 "ё" "yo")) (t11 (stringReplace t10 "а" "a")) (t12 (stringReplace t11 "б" "b")) (t13 (stringReplace t12 "в" "v")) (t14 (stringReplace t13 "г" "g")) (t15 (stringReplace t14 "д" "d")) (t16 (stringReplace t15 "е" "e")) (t17 (stringReplace t16 "з" "z")) (t18 (stringReplace t17 "и" "i")) (t19 (stringReplace t18 "й" "y")) (t20 (stringReplace t19 "к" "k")) (t21 (stringReplace t20 "л" "l")) (t22 (stringReplace t21 "м" "m")) (t23 (stringReplace t22 "н" "n")) (t24 (stringReplace t23 "о" "o")) (t25 (stringReplace t24 "п" "p")) (t26 (stringReplace t25 "р" "r")) (t27 (stringReplace t26 "с" "s")) (t28 (stringReplace t27 "т" "t")) (t29 (stringReplace t28 "у" "u")) (t30 (stringReplace t29 "ф" "f")) (t31 (stringReplace t30 "ъ" "")) (t32 (stringReplace t31 "ы" "y")) (t33 (stringReplace t32 "ь" ""))] t33)

fn makeInitialRow targetLen: I64 curr: I64 -> (List I64)
  (if (> curr targetLen) (list) (cons curr (makeInitialRow targetLen (+ curr 1))))

fn computeDpCell c1: Str c2List: (List Str) prevLeft: I64 prevTail: (List I64) currLeft: I64 -> (List I64)
  (if (listEmpty? c2List) (list) (let [(c2 (optionOr (listHead c2List) "")) (c2Tail (optionOr (listTail c2List) (list))) (prevAbove (optionOr (listHead prevTail) 0)) (nextPrevTail (optionOr (listTail prevTail) (list))) (cost (if (= c1 c2) 0 1)) (ins (+ currLeft 1)) (del (+ prevAbove 1)) (sub (+ prevLeft cost)) (cell (min ins (min del sub)))] (cons cell (computeDpCell c1 c2Tail prevAbove nextPrevTail cell))))

fn computeDpRow c1: Str s2Chars: (List Str) prevRow: (List I64) rowIdx: I64 -> (List I64)
  (let [(p0 (optionOr (listHead prevRow) 0)) (pTail (optionOr (listTail prevRow) (list)))] (cons rowIdx (computeDpCell c1 s2Chars p0 pTail rowIdx)))

fn runLevenshteinDp s1Chars: (List Str) s2Chars: (List Str) prevRow: (List I64) rowIdx: I64 -> (List I64)
  (if (listEmpty? s1Chars) prevRow (let [(c1 (optionOr (listHead s1Chars) "")) (s1Tail (optionOr (listTail s1Chars) (list))) (nextRow (computeDpRow c1 s2Chars prevRow rowIdx))] (runLevenshteinDp s1Tail s2Chars nextRow (+ rowIdx 1))))

fn getLastElement lst: (List I64) -> I64
  (if (listEmpty? lst) 0 (let [(t (optionOr (listTail lst) (list)))] (if (listEmpty? t) (optionOr (listHead lst) 0) (getLastElement t))))

fn levenshteinDistance s1: Str s2: Str -> I64
  (let [(c1 (stringChars s1)) (c2 (stringChars s2)) (len2 (listLength c2)) (r0 (makeInitialRow len2 0)) (finalRow (runLevenshteinDp c1 c2 r0 1))] (getLastElement finalRow))

fn findBestMatch trans: Str candidates: (List Str) currBest: CandidateBest -> CandidateBest
  (if (listEmpty? candidates) currBest (let [(cand (optionOr (listHead candidates) "")) (tailCand (optionOr (listTail candidates) (list))) (d (levenshteinDistance trans cand))] (if (< d currBest.dist) (findBestMatch trans tailCand (CandidateBest :target cand :dist d)) (findBestMatch trans tailCand currBest))))

fn matchHeardName rawHeard: Str candidates: (List Str) maxDistance: I64 -> NameMatch
  (let [(trans (transliterateCyrillic rawHeard)) (init (CandidateBest :target "" :dist 999999)) (best (findBestMatch trans candidates init)) (bDist best.dist) (bTarget best.target) (lenT (stringLength trans)) (lenC (stringLength bTarget)) (maxLen (if (> lenT lenC) lenT lenC)) (isMatched (and (> (stringLength bTarget) 0) (<= bDist maxDistance))) (score (if (<= maxLen 0) 1.0 (- 1.0 (/ (int64ToFloat64 bDist) (int64ToFloat64 maxLen)))))] (NameMatch :rawInput rawHeard :transliterated trans :matchedTarget bTarget :levenshteinDistance bDist :score score :isMatch isMatched))
