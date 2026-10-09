(module aslHarness/eval
  :x [Defect
      ExpectedGate
      TruthData
      Finding
      ActualGate
      PlanSummary
      AgentReceipt
      EvalRun
      EvalSummary
      round2
      parseTruth
      parseReceipt
      matchFindingToDefect
      scoreScout
      scoreImplement
      scoreCase
      buildInvocation
      summarizeEvalRuns
      evalSummaryPassed?
      formatEvalRun
      formatEvalSummary]
  :i [])

(schema Defect
  (:f file String)
  (:f anchor String)
  (:f kind String)
  (:f line (Option Int64))
  (:f symbol String)
  (:f raw String))

(schema ExpectedGate
  (:f cmd String)
  (:f exitCode Int64)
  (:f raw String))

(schema TruthData
  (:f mode String)
  (:f defects (List Defect))
  (:f gates (List ExpectedGate)))

(schema Finding
  (:f file String)
  (:f anchor String)
  (:f claim String)
  (:f line (Option Int64))
  (:f raw String))

(schema ActualGate
  (:f cmd String)
  (:f exitCode Int64))

(schema PlanSummary
  (:f steps Int64)
  (:f done Int64)
  (:f dropped Int64)
  (:f revisions Int64))

(schema AgentReceipt
  (:f status String)
  (:f mode String)
  (:f deliver String)
  (:f written (List String))
  (:f turns Int64)
  (:f opsPerTurn Float64)
  (:f singleOpShare Float64)
  (:f tokens Int64)
  (:f queueWaitSec Float64)
  (:f execSec Float64)
  (:f gates (List ActualGate))
  (:f findings (List Finding))
  (:f plan (Option PlanSummary))
  (:f raw String))

(schema EvalRun
  (:f date String)
  (:f model String)
  (:f caseId String)
  (:f recall Float64)
  (:f precision Float64)
  (:f turns Int64)
  (:f opsPerTurn Float64)
  (:f singleOpShare Float64)
  (:f tokens Int64)
  (:f wallSec Float64)
  (:f queueWaitSec Float64)
  (:f status String)
  (:f defect String)
  (:f plan (Option PlanSummary))
  (:f form String))

(schema EvalSummary
  (:f date String)
  (:f model String)
  (:f totalCases Int64)
  (:f passedCases Int64)
  (:f failedCases Int64)
  (:f avgRecall Float64)
  (:f avgPrecision Float64)
  (:f avgWallSec Float64)
  (:f form String))

fn round2 x: Float64 -> Float64
  (/ (round (* x 100.0)) 100.0)

fn isDigitChar c: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? "0123456789" c))

fn isNumChar c: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? "0123456789.-" c))

fn isWordChar c: String -> Bool
  (and (not (stringEmpty? c)) (not (stringContains? " \t\n\r()[]{}\";" c)))

fn skipWs s: String i: Int64 n: Int64 -> Int64
  (if (>= i n)
    i
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))
        (skipWs s (+ i 1) n)
        i)))

fn findFormEnd text: String j: Int64 n: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (or (>= j n) (<= depth 0))
    j
    (let [(c (optionOr (stringSlice text j (+ j 1)) ""))]
      (cond
        (esc (findFormEnd text (+ j 1) n depth inStr false))
        ((and (= c "\\") inStr) (findFormEnd text (+ j 1) n depth inStr true))
        ((= c "\"") (findFormEnd text (+ j 1) n depth (not inStr) false))
        (inStr (findFormEnd text (+ j 1) n depth true false))
        ((= c "(") (findFormEnd text (+ j 1) n (+ depth 1) false false))
        ((= c ")") (findFormEnd text (+ j 1) n (- depth 1) false false))
        (else (findFormEnd text (+ j 1) n depth false false)))))

fn parseAsnFormsLoop text: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    acc
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (if (= c "(")
        (let [(j (findFormEnd text (+ i 1) n 1 false false))]
          (parseAsnFormsLoop text j n (listAppend acc (list (optionOr (stringSlice text i j) "")))))
        (parseAsnFormsLoop text (+ i 1) n acc))))

fn parseAsnForms text: String -> (List String)
  (parseAsnFormsLoop text 0 (stringLength text) (list))

fn findAgentReceipt text: String -> String
  (mt (stringIndexOf text "(:agentReceipt")
    ((some idx)
     (let [(n (stringLength text))
           (j (findFormEnd text (+ idx 1) n 1 false false))]
       (optionOr (stringSlice text idx j) text)))
    ((none) text))

fn findStringEnd s: String j: Int64 n: Int64 esc: Bool -> Int64
  (if (>= j n)
    j
    (let [(c (optionOr (stringSlice s j (+ j 1)) ""))]
      (cond
        (esc (findStringEnd s (+ j 1) n false))
        ((= c "\\") (findStringEnd s (+ j 1) n true))
        ((= c "\"") j)
        (else (findStringEnd s (+ j 1) n false)))))

fn unescapeStr raw: String -> String
  (let [(s1 (stringReplace raw "\\\"" "\""))
        (s2 (stringReplace s1 "\\\\" "\\"))
        (s3 (stringReplace s2 "\\n" "\n"))]
    s3)

fn extractStrPropAt form: String afterKey: Int64 -> (Option String)
  (let [(n (stringLength form))
        (startWs (skipWs form afterKey n))]
    (if (>= startWs n)
      (none)
      (let [(c (optionOr (stringSlice form startWs (+ startWs 1)) ""))]
        (if (= c "\"")
          (let [(strStart (+ startWs 1))
                (strEnd (findStringEnd form strStart n false))]
            (mt (stringSlice form strStart strEnd)
              ((some s) (some (unescapeStr s)))
              ((none) (none))))
          (none)))))

fn extractStrProp form: String key: String -> (Option String)
  (let [(cand (stringIndexOf form (str key " ")))]
    (mt cand
      ((some idx) (extractStrPropAt form (+ idx (stringLength key))))
      ((none)
       (mt (stringIndexOf form (str key "\n"))
         ((some idx2) (extractStrPropAt form (+ idx2 (stringLength key))))
         ((none) (none))))))

fn findNumEnd s: String j: Int64 n: Int64 -> Int64
  (if (>= j n)
    j
    (let [(c (optionOr (stringSlice s j (+ j 1)) ""))]
      (if (isNumChar c)
        (findNumEnd s (+ j 1) n)
        j)))

fn extractNumStrAt form: String afterKey: Int64 -> (Option String)
  (let [(n (stringLength form))
        (startWs (skipWs form afterKey n))
        (numEnd (findNumEnd form startWs n))]
    (if (>= startWs numEnd)
      (none)
      (stringSlice form startWs numEnd)))

fn extractIntProp form: String key: String -> (Option Int64)
  (let [(cand (stringIndexOf form (str key " ")))]
    (mt cand
      ((some idx)
       (mt (extractNumStrAt form (+ idx (stringLength key)))
         ((some s) (stringToInt64 s))
         ((none) (none))))
      ((none)
       (mt (stringIndexOf form (str key "\n"))
         ((some idx2)
          (mt (extractNumStrAt form (+ idx2 (stringLength key)))
            ((some s) (stringToInt64 s))
            ((none) (none))))
         ((none) (none))))))

fn extractFloatProp form: String key: String -> (Option Float64)
  (let [(cand (stringIndexOf form (str key " ")))]
    (mt cand
      ((some idx)
       (mt (extractNumStrAt form (+ idx (stringLength key)))
         ((some s) (stringToFloat64 s))
         ((none) (none))))
      ((none)
       (mt (stringIndexOf form (str key "\n"))
         ((some idx2)
          (mt (extractNumStrAt form (+ idx2 (stringLength key)))
            ((some s) (stringToFloat64 s))
            ((none) (none))))
         ((none) (none))))))

fn findWordEnd s: String j: Int64 n: Int64 -> Int64
  (if (>= j n)
    j
    (let [(c (optionOr (stringSlice s j (+ j 1)) ""))]
      (if (isWordChar c)
        (findWordEnd s (+ j 1) n)
        j)))

fn stripColon s: String -> String
  (if (stringStartsWith? s ":")
    (optionOr (stringSlice s 1 (stringLength s)) "")
    s)

fn extractWordStrAt form: String afterKey: Int64 -> (Option String)
  (let [(n (stringLength form))
        (startWs (skipWs form afterKey n))
        (wordEnd (findWordEnd form startWs n))]
    (if (>= startWs wordEnd)
      (none)
      (mt (stringSlice form startWs wordEnd)
        ((some rawWord)
         (let [(trimmed (stripColon (stringTrim rawWord)))]
           (if (stringEmpty? trimmed) (none) (some trimmed))))
        ((none) (none)))))

fn extractSymProp form: String key: String -> (Option String)
  (let [(cand (stringIndexOf form (str key " ")))]
    (mt cand
      ((some idx) (extractWordStrAt form (+ idx (stringLength key))))
      ((none)
       (mt (stringIndexOf form (str key "\n"))
         ((some idx2) (extractWordStrAt form (+ idx2 (stringLength key))))
         ((none) (none))))))

fn extractBalancedBlockFrom form: String key: String start: Int64 -> (Option String)
  (let [(n (stringLength form))]
    (if (>= start n)
      (none)
      (let [(slice (optionOr (stringSlice form start n) ""))
            (relOpt (stringIndexOf slice key))]
        (mt relOpt
          ((none) (none))
          ((some rel)
           (let [(idx (+ start rel))
                 (keyLen (stringLength key))
                 (validPre (or (= idx 0)
                               (let [(prev (optionOr (stringSlice form (- idx 1) idx) ""))]
                                 (or (= prev " ") (or (= prev "\n") (or (= prev "\t") (= prev "(")))))))
                 (afterC (optionOr (stringSlice form (+ idx keyLen) (+ idx keyLen 1)) ""))
                 (validPost (or (= afterC " ") (or (= afterC "\n") (or (= afterC "\t") (= afterC "(")))))]
             (if (and validPre validPost)
               (let [(startIdx (skipWs form (+ idx keyLen) n))]
                 (if (>= startIdx n)
                   (none)
                   (let [(c (optionOr (stringSlice form startIdx (+ startIdx 1)) ""))]
                     (if (= c "(")
                       (let [(endIdx (findFormEnd form (+ startIdx 1) n 1 false false))]
                         (stringSlice form startIdx endIdx))
                       (extractBalancedBlockFrom form key (+ idx keyLen))))))
               (extractBalancedBlockFrom form key (+ idx 1)))))))))

fn extractBalancedBlock form: String key: String -> (Option String)
  (extractBalancedBlockFrom form key 0)

fn extractStringListLoop s: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    acc
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (= c "\"")
        (let [(startStr (+ i 1))
              (endStr (findStringEnd s startStr n false))]
          (mt (stringSlice s startStr endStr)
            ((some strVal)
             (extractStringListLoop s (+ endStr 1) n (listAppend acc (list (unescapeStr strVal)))))
            ((none) (extractStringListLoop s (+ endStr 1) n acc))))
        (extractStringListLoop s (+ i 1) n acc))))

fn extractStringList block: String -> (List String)
  (extractStringListLoop block 0 (stringLength block) (list))

fn findDigitsEnd s: String j: Int64 n: Int64 -> Int64
  (if (>= j n)
    j
    (let [(c (optionOr (stringSlice s j (+ j 1)) ""))]
      (if (isDigitChar c)
        (findDigitsEnd s (+ j 1) n)
        j)))

fn isWordChar? c: String -> Bool
  (and (= (stringLength c) 1)
       (stringContains? "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_" c))

fn extractLineFromTextFrom text: String start: Int64 -> (Option Int64)
  (let [(n (stringLength text))]
    (if (>= start n)
      (none)
      (let [(slice (optionOr (stringSlice text start n) ""))
            (lineIdxOpt (stringIndexOf slice "line"))]
        (mt lineIdxOpt
          ((none) (none))
          ((some rel)
           (let [(idx (+ start rel))
                 (leftOk (or (= idx 0)
                             (let [(prev (optionOr (stringSlice text (- idx 1) idx) ""))]
                               (not (isWordChar? prev)))))
                 (afterLine (+ idx 4))
                 (hasS (if (< afterLine n)
                         (= (optionOr (stringSlice text afterLine (+ afterLine 1)) "") "s")
                         false))
                 (afterKey (if hasS (+ afterLine 1) afterLine))
                 (startNum (skipWs text afterKey n))
                 (endNum (findDigitsEnd text startNum n))]
             (if (and leftOk (> endNum startNum))
               (mt (stringSlice text startNum endNum)
                 ((some s) (stringToInt64 s))
                 ((none) (extractLineFromTextFrom text (+ idx 4))))
               (extractLineFromTextFrom text (+ idx 4)))))))))

fn extractLineFromText text: String -> (Option Int64)
  (extractLineFromTextFrom (stringLower text) 0)

fn parseFinding form: String -> Finding
  (let [(fileVal (optionOr (extractStrProp form ":file") (optionOr (extractStrProp form ":path") (optionOr (extractStrProp form ":at") ""))))
        (anchorVal (optionOr (extractStrProp form ":anchor") ""))
        (claimVal (optionOr (extractStrProp form ":claim") ""))
        (lineVal (mt (extractIntProp form ":line")
                   ((some l) (some l))
                   ((none) (extractLineFromText (str claimVal " " form)))))]
    (Finding :file fileVal :anchor anchorVal :claim claimVal :line lineVal :raw form))

fn stripOuterParens s: String -> String
  (if (and (stringStartsWith? s "(") (stringEndsWith? s ")"))
    (optionOr (stringSlice s 1 (- (stringLength s) 1)) "")
    s)
fn isFindingsContainer f: String -> Bool
  (or (stringStartsWith? f "(:findings")
      (stringStartsWith? f "(findings"))

fn parseFindingsFromBlock block: String -> (List Finding)
  (let [(inner (stripOuterParens (stringTrim block)))
        (forms (parseAsnForms inner))]
    (fold (fn [(acc (List Finding)) (f String)] -> (List Finding)
            (let [(trimmed (stringTrim f))]
              (if (isFindingsContainer trimmed)
                (let [(subForms (parseAsnForms (stripOuterParens trimmed)))]
                  (if (listEmpty? subForms)
                    (listAppend acc (list (parseFinding trimmed)))
                    (fold (fn [(subAcc (List Finding)) (sf String)] -> (List Finding)
                            (listAppend subAcc (list (parseFinding sf))))
                          acc subForms)))
                (listAppend acc (list (parseFinding trimmed))))))
          (list) forms))

fn parseGatesFromBlock block: String -> (List ActualGate)
  (let [(inner (stripOuterParens (stringTrim block)))
        (forms (parseAsnForms inner))
        (cmdMap (fold (fn [(m (Map String Int64)) (f String)] -> (Map String Int64)
                        (let [(cmd (optionOr (extractStrProp f ":cmd") ""))
                              (code (optionOr (extractIntProp f ":exit") 1))]
                          (if (stringEmpty? cmd) m (mapSet m cmd code))))
                      (mapEmpty) forms))]
    (map (fn [(p (Pair String Int64))] -> ActualGate
           (ActualGate :cmd (pairFirst p) :exitCode (pairSecond p)))
         (mapPairs cmdMap)))

fn parseReceipt receiptText: String -> AgentReceipt
  (let [(targetText (findAgentReceipt receiptText))
        (statusVal (optionOr (extractSymProp targetText ":status") "unknown"))
        (deliverVal (optionOr (extractSymProp targetText ":deliver") ""))
        (modeVal (cond
                   ((= deliverVal "findings") "scout")
                   ((= deliverVal "patch") "implement")
                   (else (optionOr (extractSymProp targetText ":mode") ""))))
        (writtenList (mt (extractBalancedBlock targetText ":written")
                       ((some wb) (extractStringList wb))
                       ((none) (list))))
        (turnsVal (optionOr (extractIntProp targetText ":turns") 0))
        (queueWait (optionOr (extractFloatProp targetText ":queueWaitSec") 0.0))
        (execSecVal (optionOr (extractFloatProp targetText ":execSec") 0.0))
        (batchingBlock (extractBalancedBlock targetText ":batching"))
        (opsPerTurnVal (mt batchingBlock
                         ((some bb) (optionOr (extractFloatProp bb ":opsPerTurn") 0.0))
                         ((none) 0.0)))
        (singleOpShareVal (mt batchingBlock
                            ((some bb) (optionOr (extractFloatProp bb ":singleOpShare") 0.0))
                            ((none) 0.0)))
        (usageBlock (extractBalancedBlock targetText ":usage"))
        (tokensVal (mt usageBlock
                     ((some ub)
                      (let [(inTok (optionOr (extractIntProp ub ":input") 0))
                            (outTok (optionOr (extractIntProp ub ":output") 0))]
                        (+ inTok outTok)))
                     ((none) 0)))
        (planBlock (extractBalancedBlock targetText ":plan"))
        (planVal (mt planBlock
                   ((some pb)
                    (some (PlanSummary
                            :steps (optionOr (extractIntProp pb ":steps") 0)
                            :done (optionOr (extractIntProp pb ":done") 0)
                            :dropped (optionOr (extractIntProp pb ":dropped") 0)
                            :revisions (optionOr (extractIntProp pb ":revisions") 0))))
                   ((none) (none))))
        (gatesList (mt (extractBalancedBlock targetText ":gates")
                     ((some gb) (parseGatesFromBlock gb))
                     ((none) (list))))
        (findingsList (mt (extractBalancedBlock targetText ":findings")
                        ((some fb) (parseFindingsFromBlock fb))
                        ((none) (list))))]
    (AgentReceipt
      :status statusVal
      :mode modeVal
      :deliver deliverVal
      :written writtenList
      :turns turnsVal
      :opsPerTurn opsPerTurnVal
      :singleOpShare singleOpShareVal
      :tokens tokensVal
      :queueWaitSec queueWait
      :execSec execSecVal
      :gates gatesList
      :findings findingsList
      :plan planVal
      :raw targetText))

fn extractPositionalCmd form: String -> String
  (let [(inner (stripOuterParens (stringTrim form)))
        (words (stringSplit inner " "))]
    (if (>= (listLength words) 2)
      (let [(cand (stringJoin (optionOr (listTail words) (list)) " "))
            (firstQuote (stringIndexOf cand "\""))]
        (mt firstQuote
          ((some qIdx)
           (let [(n (stringLength cand))
                 (qEnd (findStringEnd cand (+ qIdx 1) n false))]
             (mt (stringSlice cand (+ qIdx 1) qEnd)
               ((some s) (unescapeStr s))
               ((none) ""))))
          ((none) "")))
      ""))

fn flattenTruthForms forms: (List String) acc: (List String) -> (List String)
  (if (listEmpty? forms)
    acc
    (let [(head (optionOr (listHead forms) ""))
          (tail (optionOr (listTail forms) (list)))
          (trimmed (stringTrim head))]
      (cond
        ((stringStartsWith? trimmed "(:defects")
         (let [(subForms (parseAsnForms (stripOuterParens trimmed)))]
           (flattenTruthForms (listAppend subForms tail) acc)))
        ((stringStartsWith? trimmed "(:truth")
         (let [(subForms (parseAsnForms (stripOuterParens trimmed)))]
           (flattenTruthForms (listAppend subForms tail) acc)))
        ((stringStartsWith? trimmed "(:gates")
         (let [(subForms (parseAsnForms (stripOuterParens trimmed)))]
           (flattenTruthForms (listAppend subForms tail) acc)))
        ((stringStartsWith? trimmed "(:defect")
         (flattenTruthForms tail (listAppend acc (list trimmed))))
        ((stringStartsWith? trimmed "(:expectedGate")
         (flattenTruthForms tail (listAppend acc (list trimmed))))
        ((stringStartsWith? trimmed "(:gate")
         (flattenTruthForms tail (listAppend acc (list trimmed))))
        (else
         (flattenTruthForms tail acc)))))

fn categorizeTruth forms: (List String) defects: (List Defect) gates: (List ExpectedGate) -> TruthData
  (if (listEmpty? forms)
    (cond
      ((> (listLength defects) 0) (TruthData :mode "scout" :defects defects :gates (list)))
      ((> (listLength gates) 0) (TruthData :mode "implement" :defects (list) :gates gates))
      (else (TruthData :mode "unknown" :defects (list) :gates (list))))
    (let [(head (optionOr (listHead forms) ""))
          (tail (optionOr (listTail forms) (list)))
          (trimmed (stringTrim head))]
      (if (stringStartsWith? trimmed "(:defect")
        (let [(fileVal (optionOr (extractStrProp trimmed ":file") (optionOr (extractStrProp trimmed ":path") (optionOr (extractStrProp trimmed ":at") ""))))
              (anchorVal (optionOr (extractStrProp trimmed ":anchor") ""))
              (kindVal (optionOr (extractStrProp trimmed ":kind") ""))
              (lineVal (extractIntProp trimmed ":line"))
              (symbolVal (optionOr (extractStrProp trimmed ":symbol") ""))
              (d (Defect :file fileVal :anchor anchorVal :kind kindVal :line lineVal :symbol symbolVal :raw trimmed))]
          (categorizeTruth tail (listAppend defects (list d)) gates))
        (let [(cmdVal (optionOr (extractStrProp trimmed ":cmd") (extractPositionalCmd trimmed)))
              (exitVal (optionOr (extractIntProp trimmed ":exit") 0))
              (g (ExpectedGate :cmd cmdVal :exitCode exitVal :raw trimmed))]
          (categorizeTruth tail defects (listAppend gates (list g)))))))

fn parseTruth truthText: String -> TruthData
  (let [(forms (parseAsnForms truthText))
        (flattened (flattenTruthForms forms (list)))]
    (categorizeTruth flattened (list) (list)))

fn normalizePath p: String -> String
  (let [(t (stringTrim p))
        (noQuote (stringReplace (stringReplace t "\"" "") "'" ""))]
    (if (stringStartsWith? noQuote "./")
      (optionOr (stringSlice noQuote 2 (stringLength noQuote)) "")
      noQuote))

fn basename p: String -> String
  (let [(parts (stringSplit p "/"))]
    (optionOr (listLast parts) p))

fn lastComponent s: String sep: String -> String
  (let [(parts (stringSplit s sep))]
    (optionOr (listLast parts) s))

fn normalizeWs s: String -> String
  (let [(s1 (stringReplace s "\n" " "))
        (s2 (stringReplace s1 "\t" " "))
        (s3 (stringReplace s2 "\r" " "))
        (words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit s3 " ")))]
    (stringJoin words " "))

fn containsWordBoundaryFrom? text: String word: String start: Int64 -> Bool
  (let [(n (stringLength text))
        (wLen (stringLength word))]
    (if (or (> start n) (stringEmpty? word))
      false
      (let [(slice (optionOr (stringSlice text start n) ""))
            (relOpt (stringIndexOf slice word))]
        (mt relOpt
          ((none) false)
          ((some rel)
           (let [(idx (+ start rel))
                 (leftOk (or (= idx 0)
                             (let [(prev (optionOr (stringSlice text (- idx 1) idx) ""))]
                               (not (isWordChar? prev)))))
                 (afterIdx (+ idx wLen))
                 (rightOk (or (>= afterIdx n)
                              (let [(nxt (optionOr (stringSlice text afterIdx (+ afterIdx 1)) ""))]
                                (not (isWordChar? nxt)))))]
             (if (and leftOk rightOk)
               true
               (containsWordBoundaryFrom? text word (+ idx 1)))))))))

fn containsWordBoundary? text: String word: String -> Bool
  (containsWordBoundaryFrom? text word 0)

fn checkLineMatch dLineOpt: (Option Int64) fLineOpt: (Option Int64) fullText: String -> Bool
  (mt dLineOpt
    ((none) false)
    ((some dLine)
     (mt fLineOpt
       ((some fLine) (<= (abs (- fLine dLine)) 2))
       ((none)
        (mt (extractLineFromText fullText)
          ((some parsedLine) (<= (abs (- parsedLine dLine)) 2))
          ((none) false))))))

fn checkAnchorMatch finding: Finding defect: Defect fullText: String -> Bool
  (let [(dAnchor defect.anchor)
        (dSymbol defect.symbol)
        (fAnchor finding.anchor)
        (normFinding (normalizeWs (stringLower fullText)))
        (anchorMatched
          (if (stringEmpty? dAnchor)
            false
            (let [(normD (normalizeWs (stringLower dAnchor)))
                  (normF (normalizeWs (stringLower fAnchor)))]
              (cond
                ((stringContains? normFinding normD) true)
                ((and (not (stringEmpty? normF)) (or (stringContains? normD normF) (stringContains? normF normD))) true)
                ((>= (stringLength normD) 15)
                 (let [(sub (optionOr (stringSlice normD 0 (min 20 (stringLength normD))) ""))]
                   (stringContains? normFinding sub)))
                (else false)))))
        (symbolMatched
          (if (or anchorMatched (stringEmpty? dSymbol))
            false
            (let [(lastSym (lastComponent dSymbol "."))
                  (fAnchorRaw (stringTrim fAnchor))
                  (fAnchorNoDef (if (stringStartsWith? fAnchorRaw "def ") (optionOr (stringSlice fAnchorRaw 4 (stringLength fAnchorRaw)) "") fAnchorRaw))
                  (fAnchorNoClass (if (stringStartsWith? fAnchorNoDef "class ") (optionOr (stringSlice fAnchorNoDef 6 (stringLength fAnchorNoDef)) "") fAnchorNoDef))
                  (fName (stringTrim (optionOr (listHead (stringSplit fAnchorNoClass "(")) "")))]
              (cond
                ((or (= fName dSymbol) (= fName lastSym)) true)
                ((containsWordBoundary? fullText dSymbol) true)
                (else false)))))]
    (or anchorMatched symbolMatched))

fn matchFindingToDefect finding: Finding defect: Defect -> Bool
  (let [(fFile (normalizePath finding.file))
        (dFile (normalizePath defect.file))
        (fullText (str finding.claim " " finding.raw))
        (fileMatched
          (cond
            ((and (not (stringEmpty? fFile)) (not (stringEmpty? dFile)))
             (or (= fFile dFile) (or (stringEndsWith? dFile fFile) (or (stringEndsWith? fFile dFile) (= (basename fFile) (basename dFile))))))
            ((not (stringEmpty? dFile))
             (or (stringContains? fullText dFile) (stringContains? fullText (basename dFile))))
            (else false)))]
    (if (not fileMatched)
      false
      (or (checkAnchorMatch finding defect fullText)
          (checkLineMatch defect.line finding.line fullText))))

fn findMatchingFinding defect: Defect findings: (List Finding) fi: Int64 used: (List Int64) -> (Option Int64)
  (if (>= fi (listLength findings))
    (none)
    (if (listContains? used fi)
      (findMatchingFinding defect findings (+ fi 1) used)
      (let [(f (optionOr (listGet findings fi) (Finding :file "" :anchor "" :claim "" :line (none) :raw "")))]
        (if (matchFindingToDefect f defect)
          (some fi)
          (findMatchingFinding defect findings (+ fi 1) used)))))

fn scoutBipartiteMatch defects: (List Defect) findings: (List Finding) di: Int64 used: (List Int64) tp: Int64 -> Int64
  (if (>= di (listLength defects))
    tp
    (let [(d (optionOr (listGet defects di) (Defect :file "" :anchor "" :kind "" :line (none) :symbol "" :raw "")))
          (matchIdx (findMatchingFinding d findings 0 used))]
      (mt matchIdx
        ((some fi) (scoutBipartiteMatch defects findings (+ di 1) (listAppend used (list fi)) (+ tp 1)))
        ((none) (scoutBipartiteMatch defects findings (+ di 1) used tp)))))

fn scoreScout defects: (List Defect) findings: (List Finding) receiptStatus: String -> (Pair (Pair Float64 Float64) String)
  (let [(totalD (listLength defects))
        (totalF (listLength findings))]
    (if (= totalD 0)
      (let [(prec (if (= totalF 0) 1.0 0.0))
            (st (if (= receiptStatus "ok") "ok" "failed"))]
        (pair (pair 1.0 prec) st))
      (let [(tp (scoutBipartiteMatch defects findings 0 (list) 0))
            (recall (round2 (/ (int64ToFloat64 tp) (int64ToFloat64 totalD))))
            (precision (if (> totalF 0) (round2 (/ (int64ToFloat64 tp) (int64ToFloat64 totalF))) 0.0))
            (st (if (and (= recall 1.0) (and (> precision 0.0) (= receiptStatus "ok"))) "ok" "failed"))]
        (pair (pair recall precision) st))))

fn findGateMatch eg: ExpectedGate actual: (List ActualGate) idx: Int64 -> Bool
  (if (>= idx (listLength actual))
    false
    (let [(ag (optionOr (listGet actual idx) (ActualGate :cmd "" :exitCode 0)))
          (egCmd (stringTrim eg.cmd))
          (agCmd (stringTrim ag.cmd))
          (cmdMatch (or (= egCmd agCmd) (or (stringContains? agCmd egCmd) (stringContains? egCmd agCmd))))]
      (if (and cmdMatch (= eg.exitCode ag.exitCode))
        true
        (findGateMatch eg actual (+ idx 1)))))

fn checkAllGatesPassed expected: (List ExpectedGate) actual: (List ActualGate) idx: Int64 -> Bool
  (if (>= idx (listLength expected))
    true
    (let [(eg (optionOr (listGet expected idx) (ExpectedGate :cmd "" :exitCode 0 :raw "")))]
      (if (findGateMatch eg actual 0)
        (checkAllGatesPassed expected actual (+ idx 1))
        false)))

fn scoreImplement expectedGates: (List ExpectedGate) actualGates: (List ActualGate) receiptStatus: String -> (Pair (Pair Float64 Float64) String)
  (if (listEmpty? expectedGates)
    (let [(st (if (= receiptStatus "ok") "ok" "failed"))]
      (pair (pair 1.0 1.0) st))
    (let [(allPassed (checkAllGatesPassed expectedGates actualGates 0))]
      (if (and allPassed (= receiptStatus "ok"))
        (pair (pair 1.0 1.0) "ok")
        (pair (pair 0.0 0.0) "failed"))))

fn scoreCase receiptText: String truthText: String caseId: String model: String wallSec: Float64 dateStr: String -> (Result EvalRun String)
  (if (stringEmpty? dateStr)
    (err (str "ERR_DATE: case " caseId " has no run date (YYYY-MM-DD)"))
    (ok (scoreDated receiptText truthText caseId model wallSec dateStr)))

fn scoreDated receiptText: String truthText: String caseId: String model: String wallSec: Float64 dateVal: String -> EvalRun
  (let [(truthData (parseTruth truthText))
        (truthData (parseTruth truthText))
        (receiptData (parseReceipt receiptText))
        (mode (cond
                ((not (= truthData.mode "unknown")) truthData.mode)
                ((not (stringEmpty? receiptData.mode)) receiptData.mode)
                (else "scout")))
        (receiptStatus receiptData.status)
        (scoreRes (if (= mode "scout")
                    (scoreScout truthData.defects receiptData.findings receiptStatus)
                    (scoreImplement truthData.gates receiptData.gates receiptStatus)))
        (recall (pairFirst (pairFirst scoreRes)))
        (precision (pairSecond (pairFirst scoreRes)))
        (prelimStatus (pairSecond scoreRes))
        (findingsRun (or (= receiptData.deliver "findings") (and (stringEmpty? receiptData.deliver) (= mode "scout"))))
        (writtenCount (listLength receiptData.written))
        (defectMsg (if (and findingsRun (> writtenCount 0))
                     (str "wrote " (stringFromInt64 writtenCount) " files on a findings deliverable")
                     ""))
        (evalStatus (if (not (stringEmpty? defectMsg)) "failed" prelimStatus))
        (wSec (if (> wallSec 0.0) (round2 wallSec) (round2 receiptData.execSec)))
        (turnsVal receiptData.turns)
        (opsPerTurn receiptData.opsPerTurn)
        (singleOpShare receiptData.singleOpShare)
        (tokensVal receiptData.tokens)
        (qWaitSec (round2 receiptData.queueWaitSec))
        (planVal receiptData.plan)
        (defectPart (if (not (stringEmpty? defectMsg)) (str " :defect \"" defectMsg "\"") ""))
        (planPart (mt planVal
                    ((some pl) (str " :plan (:steps " (stringFromInt64 pl.steps) " :done " (stringFromInt64 pl.done) " :dropped " (stringFromInt64 pl.dropped) " :revisions " (stringFromInt64 pl.revisions) ")"))
                    ((none) "")))
        (formStr (str "(:evalRun :date \"" dateVal "\" :model \"" model "\" :case \"" caseId "\" :recall " (stringFromFloat64 recall) " :precision " (stringFromFloat64 precision) " :turns " (stringFromInt64 turnsVal) " :opsPerTurn " (stringFromFloat64 opsPerTurn) " :singleOpShare " (stringFromFloat64 singleOpShare) " :tokens " (stringFromInt64 tokensVal) " :wallSec " (stringFromFloat64 wSec) " :queueWaitSec " (stringFromFloat64 qWaitSec) " :status :" evalStatus defectPart planPart ")"))]
    (EvalRun
      :date dateVal
      :model model
      :caseId caseId
      :recall recall
      :precision precision
      :turns turnsVal
      :opsPerTurn opsPerTurn
      :singleOpShare singleOpShare
      :tokens tokensVal
      :wallSec wSec
      :queueWaitSec qWaitSec
      :status evalStatus
      :defect defectMsg
      :plan planVal
      :form formStr))

fn stringLastIndexOfLoop s: String ch: String i: Int64 -> (Option Int64)
  (if (< i 0)
    (none)
    (let [(c (optionOr (stringSlice s i (+ i 1)) ""))]
      (if (= c ch)
        (some i)
        (stringLastIndexOfLoop s ch (- i 1)))))

fn stringLastIndexOf s: String ch: String -> (Option Int64)
  (stringLastIndexOfLoop s ch (- (stringLength s) 1))

fn insertBeforeLastCloseParen text: String kv: String -> String
  (mt (stringLastIndexOf text ")")
    ((some idx)
     (let [(before (optionOr (stringSlice text 0 idx) ""))
           (after (optionOr (stringSlice text idx (stringLength text)) ""))]
       (str before " " kv after)))
    ((none) (str text " " kv)))

fn normalizeAllWs text: String -> String
  (let [(s1 (stringReplace text "\n" " "))
        (s2 (stringReplace s1 "\t" " "))
        (s3 (stringReplace s2 "\r" " "))
        (words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit s3 " ")))]
    (stringJoin words " "))

fn buildInvocation taskText: String model: String profileEnv: String -> String
  (let [(trimmed (stringTrim taskText))
        (withBackend (if (stringContains? trimmed ":backend")
                       trimmed
                       (insertBeforeLastCloseParen trimmed ":backend \"agy\"")))
        (profiled (or (not (stringEmpty? profileEnv)) (or (stringEmpty? model) (= model "none"))))
        (withModel (if (or (stringContains? withBackend ":model") profiled)
                     withBackend
                     (insertBeforeLastCloseParen withBackend (str ":model \"" model "\""))))]
    (normalizeAllWs withModel))

fn summarizeEvalRuns runs: (List EvalRun) -> EvalSummary
  (let [(tot (listLength runs))]
    (if (= tot 0)
      (EvalSummary :date "" :model "" :totalCases 0 :passedCases 0 :failedCases 0 :avgRecall 0.0 :avgPrecision 0.0 :avgWallSec 0.0 :form "(:evalSummary :date \"\" :model \"\" :cases 0 :passed 0 :failed 0 :avgRecall 0.0 :avgPrecision 0.0 :avgWallSec 0.0)")
      (let [(firstRun (optionOr (listHead runs) (EvalRun :date "" :model "" :caseId "" :recall 0.0 :precision 0.0 :turns 0 :opsPerTurn 0.0 :singleOpShare 0.0 :tokens 0 :wallSec 0.0 :queueWaitSec 0.0 :status "" :defect "" :plan (none) :form "")))
            (dateVal firstRun.date)
            (modelVal firstRun.model)
            (passedCount (fold (fn [(cnt Int64) (r EvalRun)] -> Int64 (if (= r.status "ok") (+ cnt 1) cnt)) 0 runs))
            (failedCount (- tot passedCount))
            (totF (int64ToFloat64 tot))
            (sumRecall (fold (fn [(acc Float64) (r EvalRun)] -> Float64 (+ acc r.recall)) 0.0 runs))
            (sumPrecision (fold (fn [(acc Float64) (r EvalRun)] -> Float64 (+ acc r.precision)) 0.0 runs))
            (sumWall (fold (fn [(acc Float64) (r EvalRun)] -> Float64 (+ acc r.wallSec)) 0.0 runs))
            (avgRec (round2 (/ sumRecall totF)))
            (avgPrec (round2 (/ sumPrecision totF)))
            (avgWall (round2 (/ sumWall totF)))
            (formStr (str "(:evalSummary :date \"" dateVal "\" :model \"" modelVal "\" :cases " (stringFromInt64 tot) " :passed " (stringFromInt64 passedCount) " :failed " (stringFromInt64 failedCount) " :avgRecall " (stringFromFloat64 avgRec) " :avgPrecision " (stringFromFloat64 avgPrec) " :avgWallSec " (stringFromFloat64 avgWall) ")"))]
        (EvalSummary
          :date dateVal
          :model modelVal
          :totalCases tot
          :passedCases passedCount
          :failedCases failedCount
          :avgRecall avgRec
          :avgPrecision avgPrec
          :avgWallSec avgWall
          :form formStr))))

fn formatEvalRun run: EvalRun -> String
  run.form

fn formatEvalSummary summary: EvalSummary -> String
  summary.form

fn evalSummaryPassed? summary: EvalSummary runs: (List EvalRun) -> Bool
  (and (= summary.failedCases 0)
       (= (fold (fn [(cnt Int64) (r EvalRun)] -> Int64 (if (= r.turns 0) (+ cnt 1) cnt)) 0 runs) 0))
