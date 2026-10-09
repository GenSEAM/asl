(module asl-audio/heardname :x [latinizeCyrillic foldStemPhonemes splitCamelCaseStems levenshteinDistance scoreStringMatch matchVoiceQueryToAstSymbol AstSymbolCandidate makeAstSymbolCandidate AstMatchResult] :i [])

(schema AstSymbolCandidate
  (:f symbol String)
  (:f targetPath String)
  (:f kind String))

(schema AstMatchResult
  (:f rawQuery String)
  (:f latinizedQuery String)
  (:f matchedSymbol String)
  (:f matchedPath String)
  (:f confidence Float64)
  (:f isMatched Bool))

fn makeAstSymbolCandidate symbol: String targetPath: String kind: String -> AstSymbolCandidate
  (AstSymbolCandidate :symbol symbol :targetPath targetPath :kind kind)

fn latinizeCyrillic text: String -> String
  (let [(t1 (stringReplace text "Щ" "shch"))
        (t2 (stringReplace t1 "щ" "shch"))
        (t3 (stringReplace t2 "Ч" "ch"))
        (t4 (stringReplace t3 "ч" "ch"))
        (t5 (stringReplace t4 "Ш" "sh"))
        (t6 (stringReplace t5 "ш" "sh"))
        (t7 (stringReplace t6 "Ж" "zh"))
        (t8 (stringReplace t7 "ж" "zh"))
        (t9 (stringReplace t8 "Ц" "ts"))
        (t10 (stringReplace t9 "ц" "ts"))
        (t11 (stringReplace t10 "Ю" "yu"))
        (t12 (stringReplace t11 "ю" "yu"))
        (t13 (stringReplace t12 "Я" "ya"))
        (t14 (stringReplace t13 "я" "ya"))
        (t15 (stringReplace t14 "Э" "e"))
        (t16 (stringReplace t15 "э" "e"))
        (t17 (stringReplace t16 "Х" "kh"))
        (t18 (stringReplace t17 "х" "kh"))
        (t19 (stringReplace t18 "Ё" "yo"))
        (t20 (stringReplace t19 "ё" "yo"))
        (t21 (stringReplace t20 "А" "a"))
        (t22 (stringReplace t21 "а" "a"))
        (t23 (stringReplace t22 "Б" "b"))
        (t24 (stringReplace t23 "б" "b"))
        (t25 (stringReplace t24 "В" "v"))
        (t26 (stringReplace t25 "в" "v"))
        (t27 (stringReplace t26 "Г" "g"))
        (t28 (stringReplace t27 "г" "g"))
        (t29 (stringReplace t28 "Д" "d"))
        (t30 (stringReplace t29 "д" "d"))
        (t31 (stringReplace t30 "Е" "e"))
        (t32 (stringReplace t31 "е" "e"))
        (t33 (stringReplace t32 "З" "z"))
        (t34 (stringReplace t33 "з" "z"))
        (t35 (stringReplace t34 "И" "i"))
        (t36 (stringReplace t35 "и" "i"))
        (t37 (stringReplace t36 "Й" "y"))
        (t38 (stringReplace t37 "й" "y"))
        (t39 (stringReplace t38 "К" "k"))
        (t40 (stringReplace t39 "к" "k"))
        (t41 (stringReplace t40 "Л" "l"))
        (t42 (stringReplace t41 "л" "l"))
        (t43 (stringReplace t42 "М" "m"))
        (t44 (stringReplace t43 "м" "m"))
        (t45 (stringReplace t44 "Н" "n"))
        (t46 (stringReplace t45 "н" "n"))
        (t47 (stringReplace t46 "О" "o"))
        (t48 (stringReplace t47 "о" "o"))
        (t49 (stringReplace t48 "П" "p"))
        (t50 (stringReplace t49 "п" "p"))
        (t51 (stringReplace t50 "Р" "r"))
        (t52 (stringReplace t51 "р" "r"))
        (t53 (stringReplace t52 "С" "s"))
        (t54 (stringReplace t53 "с" "s"))
        (t55 (stringReplace t54 "Т" "t"))
        (t56 (stringReplace t55 "т" "t"))
        (t57 (stringReplace t56 "У" "u"))
        (t58 (stringReplace t57 "у" "u"))
        (t59 (stringReplace t58 "Ф" "f"))
        (t60 (stringReplace t59 "ф" "f"))
        (t61 (stringReplace t60 "Ы" "y"))
        (t62 (stringReplace t61 "ы" "y"))
        (t63 (stringReplace t62 "Ъ" ""))
        (t64 (stringReplace t63 "ъ" ""))
        (t65 (stringReplace t64 "Ь" ""))
        (t66 (stringReplace t65 "ь" ""))]
    t66)

fn foldStemPhonemes s: String -> String
  (let [(low (stringLower s))
        (f1 (stringReplace low "ph" "f"))
        (f2 (stringReplace f1 "shch" "sh"))
        (f3 (stringReplace f2 "th" "t"))
        (f4 (stringReplace f3 "ck" "k"))
        (f5 (stringReplace f4 "oo" "u"))
        (f6 (stringReplace f5 "ee" "i"))
        (f7 (stringReplace f6 "ea" "i"))
        (f8 (stringReplace f7 "kh" "h"))
        (f9 (stringReplace f8 "c" "k"))
        (f10 (stringReplace f9 "q" "k"))
        (f11 (stringReplace f10 "w" "v"))]
    f11)

fn isUpperChar? c: String -> Bool
  (or (or (or (or (or (= c "A") (= c "B")) (or (= c "C") (= c "D")))
              (or (or (= c "E") (= c "F")) (or (= c "G") (= c "H"))))
          (or (or (or (= c "I") (= c "J")) (or (= c "K") (= c "L")))
              (or (or (= c "M") (= c "N")) (or (= c "O") (= c "P")))))
      (or (or (or (or (= c "Q") (= c "R")) (or (= c "S") (= c "T")))
              (or (or (= c "U") (= c "V")) (or (= c "W") (= c "X"))))
          (or (= c "Y") (= c "Z"))))

fn splitCamelCaseStems name: String -> String
  (let [(chars (stringChars name))]
    (fold (fn [(acc String) (ch String)] -> String
            (if (isUpperChar? ch)
              (if (= acc "") (stringLower ch) (str acc " " (stringLower ch)))
              (str acc ch)))
          ""
          chars))

fn makeInitialRow len: Int64 curr: Int64 -> (List Int64)
  (if (> curr len)
    (list)
    (cons curr (makeInitialRow len (+ curr 1))))

fn min3 a: Int64 b: Int64 c: Int64 -> Int64
  (let [(m (if (<= a b) a b))]
    (if (<= m c) m c))

fn computeNextCell c1: String c2List: (List String) prevRow: (List Int64) prevLeft: Int64 pDiag: Int64 -> (List Int64)
  (if (or (listEmpty? c2List) (listEmpty? prevRow))
    (list)
    (let [(c2 (optionOr (listHead c2List) ""))
          (pUp (optionOr (listHead prevRow) 0))
          (cost (if (= c1 c2) 0 1))]
      (let [(curr (min3 (+ prevLeft 1) (+ pUp 1) (+ pDiag cost)))
            (c2Tail (optionOr (listTail c2List) (list)))
            (prevTail (optionOr (listTail prevRow) (list)))]
        (cons curr (computeNextCell c1 c2Tail prevTail curr pUp)))))

fn computeNextRow c1: String c2List: (List String) prevRow: (List Int64) rowIdx: Int64 -> (List Int64)
  (let [(p0 (optionOr (listHead prevRow) 0))
        (pTail (optionOr (listTail prevRow) (list)))]
    (cons rowIdx (computeNextCell c1 c2List pTail rowIdx p0)))

fn levenshteinDpLoop s1Chars: (List String) s2Chars: (List String) prevRow: (List Int64) rowIdx: Int64 -> (List Int64)
  (if (listEmpty? s1Chars)
    prevRow
    (let [(c1 (optionOr (listHead s1Chars) ""))
          (s1Tail (optionOr (listTail s1Chars) (list)))]
      (let [(nextRow (computeNextRow c1 s2Chars prevRow rowIdx))]
        (levenshteinDpLoop s1Tail s2Chars nextRow (+ rowIdx 1)))))

fn getLastElement lst: (List Int64) -> Int64
  (if (listEmpty? lst)
    0
    (let [(t (optionOr (listTail lst) (list)))]
      (if (listEmpty? t)
        (optionOr (listHead lst) 0)
        (getLastElement t))))

fn levenshteinDistance s1: String s2: String -> Int64
  (let [(c1 (stringChars s1))
        (c2 (stringChars s2))]
    (let [(len2 (listLength c2))]
      (let [(r0 (makeInitialRow len2 0))]
        (let [(finalRow (levenshteinDpLoop c1 c2 r0 1))]
          (getLastElement finalRow)))))

fn scoreStringMatch query: String target: String -> Float64
  (let [(qFold (foldStemPhonemes query))
        (tFold (foldStemPhonemes target))]
    (let [(lenQ (stringLength qFold))
          (lenT (stringLength tFold))]
      (if (and (>= lenT 3) (stringContains? qFold tFold))
        0.92
        (if (and (>= lenQ 3) (stringContains? tFold qFold))
          (* 0.90 (/ (int64ToFloat64 lenQ) (int64ToFloat64 lenT)))
          (let [(dist (levenshteinDistance qFold tFold))]
            (let [(maxLen (if (> lenQ lenT) lenQ lenT))]
              (if (<= maxLen 0)
                1.0
                (let [(rawScore (- 1.0 (/ (int64ToFloat64 dist) (int64ToFloat64 maxLen))))]
                  (if (< rawScore 0.0) 0.0 rawScore)))))))))

(schema BestCandidateMatch
  (:f cand AstSymbolCandidate)
  (:f score Float64))

fn findBestMatchLoop candidates: (List AstSymbolCandidate) query: String bestCand: AstSymbolCandidate bestScore: Float64 -> BestCandidateMatch
  (if (listEmpty? candidates)
    (BestCandidateMatch :cand bestCand :score bestScore)
    (let [(c (optionOr (listHead candidates) (AstSymbolCandidate :symbol "" :targetPath "" :kind "")))
          (restCands (optionOr (listTail candidates) (list)))]
      (let [(stems (splitCamelCaseStems c.symbol))]
        (let [(score (scoreStringMatch query stems))
              (scoreDirect (scoreStringMatch query c.symbol))
              (scorePath (scoreStringMatch query c.targetPath))]
          (let [(maxS1 (if (>= score scoreDirect) score scoreDirect))]
            (let [(effectiveScore (if (>= maxS1 scorePath) maxS1 scorePath))]
              (if (> effectiveScore bestScore)
                (findBestMatchLoop restCands query c effectiveScore)
                (findBestMatchLoop restCands query bestCand bestScore))))))))

fn matchVoiceQueryToAstSymbol rawVoice: String candidates: (List AstSymbolCandidate) minConfidence: Float64 -> AstMatchResult
  (let [(latin (latinizeCyrillic rawVoice))]
    (let [(foldedQuery (foldStemPhonemes latin))]
      (let [(defaultCand (AstSymbolCandidate :symbol "" :targetPath "" :kind ""))]
        (let [(best (findBestMatchLoop candidates foldedQuery defaultCand 0.0))]
          (let [(matchedCand best.cand)
                (bestScore best.score)]
            (let [(isMatched (>= bestScore minConfidence))]
              (AstMatchResult
                :rawQuery rawVoice
                :latinizedQuery latin
                :matchedSymbol (if isMatched matchedCand.symbol "")
                :matchedPath (if isMatched matchedCand.targetPath "")
                :confidence bestScore
                :isMatched isMatched)))))))
