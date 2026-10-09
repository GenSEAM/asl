(module asl/agentLoop/metrics
  :x [isAslOrAsn stripFences classifyDefect readJournalDefects analyzeDefects analyzeDefectFiles! formatParseDefects
      analyzeEditJournals analyzeJournals! formatEditMetric
      flattenFlushed Receipt
      EditSeq JournalEditSummary FailuresByKind EditMetricsResult
      DefectCauseCount ParseDefectsResult DefectEntry JournalDefects
      FencedBody UsageTokens]
  :i [(asl/agentLoop/core :a c)])


(schema EditSeq
  (:f journal String)
  (:f file String)
  (:f retries Int64)
  (:f accepted Bool)
  (:f tokens Int64)
  (:f failures (List String)))


(schema JournalEditSummary
  (:f journal String)
  (:f totalSequences Int64)
  (:f acceptedSequences Int64)
  (:f firstPassSequences Int64)
  (:f sequences (List EditSeq)))


(schema FailuresByKind
  (:f syntaxUnbalanced Int64)
  (:f syntaxParseDefect Int64)
  (:f syntaxCheckFailed Int64)
  (:f semanticNoMatch Int64)
  (:f semanticOwns Int64)
  (:f semanticRaw Int64)
  (:f semanticOther Int64)
  (:f gateFailure Int64))


(schema EditMetricsResult
  (:f totalJournalsScanned Int64)
  (:f aslAsnJournalsCount Int64)
  (:f totalAttempts Int64)
  (:f acceptedAttempts Int64)
  (:f failedAttempts Int64)
  (:f totalSequences Int64)
  (:f acceptedSequences Int64)
  (:f firstPassSequences Int64)
  (:f totalFailures Int64)
  (:f syntaxFailures Int64)
  (:f semanticFailures Int64)
  (:f gateFailures Int64)
  (:f failuresByKind FailuresByKind)
  (:f firstPassRate Float64)
  (:f avgRetriesPerAccepted Float64)
  (:f avgTokensPerAccepted Float64)
  (:f syntaxShare Float64)
  (:f semanticShare Float64)
  (:f gateShare Float64)
  (:f sequences (List EditSeq))
  (:f byJournal (List JournalEditSummary)))


(schema DefectCauseCount
  (:f cause String)
  (:f count Int64)
  (:f sample String))


(schema ParseDefectsResult
  (:f runs Int64)
  (:f turns Int64)
  (:f defects Int64)
  (:f byCause (List DefectCauseCount))
  (:f unreadable Int64))


(schema DefectEntry
  (:f reply String)
  (:f cut Bool))


(schema JournalDefects
  (:f turns Int64)
  (:f defects (List DefectEntry)))


(schema ScanResult
  (:f depth Int64)
  (:f inStr Bool)
  (:f stray Bool)
  (:f quote Bool)
  (:f heads (List String))
  (:f outside String))


(schema FencedBody
  (:f body String)
  (:f fences Int64)
  (:f fenceOpen Bool))


(schema UsageTokens
  (:f input Int64)
  (:f cached Int64)
  (:f output Int64))


(schema Receipt
  (:f op String)
  (:f file String)
  (:f status String)
  (:f error String)
  (:f flushed (List String)))


(schema SeqState
  (:f retries Int64)
  (:f tokens Int64)
  (:f failures (List String)))


(schema TurnLine
  (:f turn Int64)
  (:f key String)
  (:f rest String))


fn isAslOrAsn filename: String -> Bool
  (if (stringEmpty? filename)
    false
    (let [fn (stringLower filename)]
      (or (stringEndsWith? fn ".asl") (stringEndsWith? fn ".asn"))))


fn isSpace c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\r") (= c "\n"))))


fn isAsciiAlnum c: String -> Bool
  (or (and (>= c "a") (<= c "z"))
    (or (and (>= c "A") (<= c "Z"))
      (and (>= c "0") (<= c "9"))))


fn isAsciiDigit c: String -> Bool
  (and (>= c "0") (<= c "9"))


fn scanDigits text: String n: Int64 i: Int64 -> Int64
  (if (>= i n)
    i
    (if (isAsciiDigit (c/sliceOf text i (+ i 1)))
      (scanDigits text n (+ i 1))
      i))


fn scanWordOrHyphen text: String n: Int64 i: Int64 -> Int64
  (if (>= i n)
    i
    (let [c (c/sliceOf text i (+ i 1))]
      (if (or (c/isWordByte c) (= c "-"))
        (scanWordOrHyphen text n (+ i 1))
        i)))


fn skipWhitespace text: String n: Int64 i: Int64 -> Int64
  (if (>= i n)
    i
    (if (isSpace (c/sliceOf text i (+ i 1)))
      (skipWhitespace text n (+ i 1))
      i))


fn isFenceLine text: String n: Int64 i: Int64 -> Bool
  (cond
    ((>= i n) false)
    ((or (= (c/sliceOf text i (+ i 1)) " ") (= (c/sliceOf text i (+ i 1)) "\t"))
      (isFenceLine text n (+ i 1)))
    ((<= (+ i 3) n)
      (= (c/sliceOf text i (+ i 3)) "```"))
    (else false))


fn findFenceMarks text: String n: Int64 i: Int64 atLineStart: Bool acc: (List Int64) -> (List Int64)
  (cond
    ((>= i n) (listReverse acc))
    (atLineStart
      (if (isFenceLine text n i)
        (let [sub (optionOr (stringSlice text i n) "")
              nl (stringIndexOf sub "\n")
              nextI (mt nl ((some off) (+ (+ i off) 1)) ((none) n))]
          (findFenceMarks text n nextI true (cons i acc)))
        (let [c (c/sliceOf text i (+ i 1))]
          (findFenceMarks text n (+ i 1) (= c "\n") acc))))
    (else
      (let [c (c/sliceOf text i (+ i 1))]
        (findFenceMarks text n (+ i 1) (= c "\n") acc))))


fn fencePartsLoop marks: (List Int64) k: Int64 text: String n: Int64 pos: Int64 acc: (List String) -> FencedBody
  (if (listEmpty? marks)
    (let [lastPart (c/sliceOf text pos n)
          allParts (cons lastPart acc)
          body (stringJoin (listReverse allParts) " ")]
      (FencedBody :body body :fences (/ k 2) :fenceOpen false))
    (let [markK (c/firstOf marks)
          part (c/sliceOf text pos markK)
          marksRest (c/restOf marks)]
      (if (listEmpty? marksRest)
        (let [allParts (cons part acc)
              body (stringJoin (listReverse allParts) " ")]
          (FencedBody :body body :fences (+ (/ k 2) 1) :fenceOpen true))
        (let [markK1 (c/firstOf marksRest)
              sub (optionOr (stringSlice text markK1 n) "")
              nl (stringIndexOf sub "\n")
              nextPos (mt nl ((some off) (+ markK1 off)) ((none) n))]
          (fencePartsLoop (c/restOf marksRest) (+ k 2) text n nextPos (cons part acc))))))


fn stripFences text: String -> FencedBody
  (let [n (stringLength text)
        marks (findFenceMarks text n 0 true (list))]
    (fencePartsLoop marks 0 text n 0 (list)))


fn matchHead body: String start: Int64 n: Int64 -> String
  (let [j (skipWhitespace body n start)]
    (if (>= j n)
      ""
      (let [c (c/sliceOf body j (+ j 1))]
        (cond
          ((= c ":")
            (let [k (scanWordOrHyphen body n (+ j 1))]
              (c/sliceOf body j k)))
          ((or (c/isWordByte c) (= c "-"))
            (let [k (scanWordOrHyphen body n j)]
              (c/sliceOf body j k)))
          (else "")))))


fn scanLoop body: String n: Int64 i: Int64 stack: (List String) inStr: Bool esc: Bool stray: Bool quote: Bool heads: (List String) outsideAcc: (List String) -> ScanResult
  (if (>= i n)
    (ScanResult :depth (listLength stack) :inStr inStr :stray stray :quote quote :heads (listReverse heads) :outside (c/joinAll (listReverse outsideAcc)))
    (let [c (c/sliceOf body i (+ i 1))]
      (if inStr
        (let [newOut (if (listEmpty? stack) (cons c outsideAcc) outsideAcc)]
          (cond
            (esc
              (scanLoop body n (+ i 1) stack true false stray quote heads newOut))
            ((= c "\\")
              (scanLoop body n (+ i 1) stack true true stray quote heads newOut))
            ((= c "\"")
              (let [nxt (if (< (+ i 1) n) (c/sliceOf body (+ i 1) (+ i 2)) "")
                    badQuote (and (!= nxt "") (and (not (isSpace nxt)) (not (stringContains? "([{}])" nxt))))]
                (scanLoop body n (+ i 1) stack false false stray (or quote badQuote) heads newOut)))
            (else
              (scanLoop body n (+ i 1) stack true false stray quote heads newOut))))
        (cond
          ((= c "\"")
            (let [newOut (if (listEmpty? stack) (cons c outsideAcc) outsideAcc)]
              (scanLoop body n (+ i 1) stack true false stray quote heads newOut)))
          ((and (= c ";") (listEmpty? stack))
            (let [sub (optionOr (stringSlice body i n) "")
                  nl (stringIndexOf sub "\n")
                  nextI (mt nl ((some off) (+ i off)) ((none) n))]
              (scanLoop body n nextI stack false false stray quote heads outsideAcc)))
          ((stringContains? "([{" c)
            (let [newHeads (if (and (listEmpty? stack) (= c "("))
                             (cons (matchHead body (+ i 1) n) heads)
                             heads)]
              (scanLoop body n (+ i 1) (cons c stack) false false stray quote newHeads outsideAcc)))
          ((stringContains? ")]}" c)
            (let [expected (if (= c ")") "(" (if (= c "]") "[" "{"))]
              (if (and (not (listEmpty? stack)) (= (c/firstOf stack) expected))
                (scanLoop body n (+ i 1) (c/restOf stack) false false stray quote heads outsideAcc)
                (scanLoop body n (+ i 1) stack false false true quote heads outsideAcc))))
          (else
            (let [newOut (if (listEmpty? stack) (cons c outsideAcc) outsideAcc)]
              (scanLoop body n (+ i 1) stack false false stray quote heads newOut)))))))


fn scanBody body: String -> ScanResult
  (scanLoop body (stringLength body) 0 (list) false false false false (list) (list))


fn countWordsLoop s: String n: Int64 i: Int64 inWord: Bool k: Int64 -> Int64
  (if (>= i n)
    k
    (let [c (c/sliceOf s i (+ i 1))]
      (if (isAsciiAlnum c)
        (if inWord
          (countWordsLoop s n (+ i 1) true k)
          (countWordsLoop s n (+ i 1) true (+ k 1)))
        (countWordsLoop s n (+ i 1) false k))))


fn countWords s: String -> Int64
  (countWordsLoop s (stringLength s) 0 false 0)


fn checkRawMarkerAt body: String n: Int64 i: Int64 keyLen: Int64 -> (Option Int64)
  (let [afterKey (+ i keyLen)]
    (if (and (< afterKey n) (isSpace (c/sliceOf body afterKey (+ afterKey 1))))
      (let [afterSpace (skipWhitespace body n afterKey)]
        (if (and (<= (+ afterSpace 4) n) (= (c/sliceOf body afterSpace (+ afterSpace 4)) ":raw"))
          (let [afterRaw (+ afterSpace 4)]
            (if (or (>= afterRaw n)
                    (let [c (c/sliceOf body afterRaw (+ afterRaw 1))]
                      (not (or (c/isWordByte c) (= c "-")))))
              (some afterRaw)
              (none)))
          (none)))
      (none)))


fn countRawMarkersLoop body: String n: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= i n)
    acc
    (let [c (c/sliceOf body i (+ i 1))]
      (if (= c ":")
        (let [matchContent (if (and (<= (+ i 8) n) (= (c/sliceOf body i (+ i 8)) ":content"))
                             (checkRawMarkerAt body n i 8)
                             (none))
              matchOld (if (and (<= (+ i 4) n) (= (c/sliceOf body i (+ i 4)) ":old"))
                         (checkRawMarkerAt body n i 4)
                         (none))
              matchNew (if (and (<= (+ i 4) n) (= (c/sliceOf body i (+ i 4)) ":new"))
                         (checkRawMarkerAt body n i 4)
                         (none))]
          (mt matchContent
            ((some nextI) (countRawMarkersLoop body n nextI (+ acc 1)))
            ((none)
              (mt matchOld
                ((some nextI) (countRawMarkersLoop body n nextI (+ acc 1)))
                ((none)
                  (mt matchNew
                    ((some nextI) (countRawMarkersLoop body n nextI (+ acc 1)))
                    ((none) (countRawMarkersLoop body n (+ i 1) acc))))))))
        (countRawMarkersLoop body n (+ i 1) acc))))


fn countRawMarkers body: String -> Int64
  (countRawMarkersLoop body (stringLength body) 0 0)


fn isStepShape op: String -> Bool
  (or (listContains? (list "write" "edit" "read" "query" "outline" "check" "diff" "flush" "discard" "test" "tree" "fix" "txn" "tools" "help" "findings" "evidence" "escalate" "done") op)
    (listContains? (list "gitDiff" "gitLog" "gitShow" "gate" "run" "delete" "manage" "note" "observe" "search" "research" "crawl") op))


fn isKnownHead head: String -> Bool
  (or (isStepShape head)
    (listContains? (list "step" "intent" "plan" "retract" "claim") head))


fn extractOpIdent body: String n: Int64 i: Int64 -> String
  (let [j (skipWhitespace body n i)
        start (if (and (< j n) (= (c/sliceOf body j (+ j 1)) "\"")) (+ j 1) j)]
    (if (>= start n)
      ""
      (let [c (c/sliceOf body start (+ start 1))]
        (if (or (and (>= c "a") (<= c "z")) (and (>= c "A") (<= c "Z")))
          (let [end (scanWordOrHyphen body n (+ start 1))]
            (c/sliceOf body start end))
          ""))))


fn findOpInStep body: String n: Int64 i: Int64 -> (Option String)
  (if (>= i n)
    (none)
    (let [c (c/sliceOf body i (+ i 1))]
      (cond
        ((or (= c "(") (= c ")")) (none))
        ((and (= c ":") (and (<= (+ i 3) n) (= (c/sliceOf body i (+ i 3)) ":op")))
          (let [afterOp (+ i 3)]
            (if (and (< afterOp n) (isSpace (c/sliceOf body afterOp (+ afterOp 1))))
              (let [ident (extractOpIdent body n afterOp)]
                (if (stringEmpty? ident) (none) (some ident)))
              (findOpInStep body n (+ i 1)))))
        (else (findOpInStep body n (+ i 1))))))


fn hasUnknownStepOpLoop body: String n: Int64 i: Int64 -> Bool
  (if (>= i n)
    false
    (let [c (c/sliceOf body i (+ i 1))]
      (if (and (= c "(") (and (<= (+ i 6) n) (= (c/sliceOf body i (+ i 6)) "(:step")))
        (let [afterStep (+ i 6)
              hasBoundary (or (>= afterStep n) (or (isSpace (c/sliceOf body afterStep (+ afterStep 1))) (= (c/sliceOf body afterStep (+ afterStep 1)) ")")))]
          (if hasBoundary
            (mt (findOpInStep body n afterStep)
              ((some op)
                (if (not (isStepShape op))
                  true
                  (hasUnknownStepOpLoop body n afterStep)))
              ((none)
                (hasUnknownStepOpLoop body n afterStep)))
            (hasUnknownStepOpLoop body n (+ i 1))))
        (hasUnknownStepOpLoop body n (+ i 1)))))


fn hasUnknownStepOp body: String -> Bool
  (hasUnknownStepOpLoop body (stringLength body) 0)


fn anyStartsWithColon heads: (List String) -> Bool
  (cond
    ((listEmpty? heads) false)
    ((stringStartsWith? (c/firstOf heads) ":") true)
    (else (anyStartsWithColon (c/restOf heads))))


fn anyInvalidHead heads: (List String) -> Bool
  (cond
    ((listEmpty? heads) false)
    (else
      (let [h (c/firstOf heads)]
        (if (or (not (stringStartsWith? h ":")) (not (isKnownHead (c/sliceOf h 1 (stringLength h)))))
          true
          (anyInvalidHead (c/restOf heads))))))


fn classifyDefect reply: String cut: Bool -> String
  (let [fb (stripFences reply)
        body fb.body
        fences fb.fences
        fenceOpen fb.fenceOpen
        s (scanBody body)
        trimmed (stringTrim body)
        tail (if (stringEmpty? trimmed) "" (c/sliceOf trimmed (- (stringLength trimmed) 1) (stringLength trimmed)))
        tailInClosers (stringContains? ")]}" tail)]
    (cond
      ((or s.stray (and (> s.depth 0) (and (not s.inStr) (and (not cut) tailInClosers))))
        "unbalanced")
      (s.quote
        "quote")
      (else
        (let [markers (countRawMarkers body)
              words (countWords s.outside)
              keywordForms (anyStartsWithColon s.heads)]
          (cond
            ((or (> words 40) (or (> fences markers) (and (> words 0) (not keywordForms))))
              "prose")
            ((or (> s.depth 0) s.inStr)
              "truncated")
            ((or (hasUnknownStepOp body) (anyInvalidHead s.heads))
              "unknownOp")
            ((or fenceOpen (< fences markers))
              "raw")
            (else
              "other"))))))


fn extractQuotedString s: String -> String
  (let [trimmed (stringTrim s)
        n (stringLength trimmed)]
    (if (and (>= n 2) (and (stringStartsWith? trimmed "\"") (stringEndsWith? trimmed "\"")))
      (c/sliceOf trimmed 1 (- n 1))
      trimmed))


fn parseTurnLine line: String -> (Option TurnLine)
  (if (not (stringStartsWith? line "(:turn "))
    (none)
    (let [n (stringLength line)]
      (if (not (stringEndsWith? line ")"))
        (none)
        (let [digitsEnd (scanDigits line n 7)]
          (if (<= digitsEnd 7)
            (none)
            (let [turn (optionOr (stringToInt64 (c/sliceOf line 7 digitsEnd)) -1)]
              (if (< turn 0)
                (none)
                (let [afterTurn (skipWhitespace line n digitsEnd)]
                  (if (or (>= afterTurn n) (!= (c/sliceOf line afterTurn (+ afterTurn 1)) ":"))
                    (none)
                    (let [keyEnd (scanWordOrHyphen line n (+ afterTurn 1))
                          key (c/sliceOf line (+ afterTurn 1) keyEnd)
                          restStart (skipWhitespace line n keyEnd)
                          rest (c/sliceOf line restStart (- n 1))]
                      (some (TurnLine :turn turn :key key :rest (stringTrim rest)))))))))))))


fn checkAfterRetry text: String n: Int64 i: Int64 -> Bool
  (let [j (skipWhitespace text n i)]
    (stringStartsWith? (optionOr (stringSlice text j n) "") "reply was not parseable"))


fn matchesDefectBrief text: String -> Bool
  (cond
    ((stringStartsWith? text "reply was not parseable") true)
    ((stringStartsWith? text "Retry ")
      (let [n (stringLength text)
            sub (optionOr (stringSlice text 6 n) "")
            colon (stringIndexOf sub ":")]
        (mt colon
          ((some off)
            (let [afterColon (+ (+ 6 off) 1)]
              (checkAfterRetry text n afterColon)))
          ((none) false))))
    (else false))


fn addUniqueInt list: (List Int64) item: Int64 -> (List Int64)
  (if (listContains? list item) list (cons item list))


fn readJournalLines lines: (List String) turnsSet: (List Int64) replies: (Map Int64 String) defects: (List Int64) cutFlags: (Map Int64 Bool) -> (Pair (List Int64) (List (Pair Int64 DefectEntry)))
  (if (listEmpty? lines)
    (let [sortedDefects (listSort defects)
          entries (map (fn [t]
                         (let [rep (optionOr (mapGet replies t) "")
                               cut (optionOr (mapGet cutFlags t) false)
                               unesc (c/asnUnescape rep)]
                           (pair t (DefectEntry :reply unesc :cut cut))))
                       sortedDefects)]
      (pair turnsSet entries))
    (let [line (c/firstOf lines)
          tlOpt (parseTurnLine line)]
      (mt tlOpt
        ((none)
          (readJournalLines (c/restOf lines) turnsSet replies defects cutFlags))
        ((some tl)
          (let [t tl.turn
                key tl.key
                rest tl.rest
                text (extractQuotedString rest)]
            (cond
              ((= key "reply")
                (let [newTurns (addUniqueInt turnsSet t)
                      newReplies (mapSet replies t text)]
                  (readJournalLines (c/restOf lines) newTurns newReplies defects cutFlags)))
              ((or (= key "parse-defect") (= key "parseDefect"))
                (let [newDefects (addUniqueInt defects t)]
                  (readJournalLines (c/restOf lines) turnsSet replies newDefects cutFlags)))
              ((= key "retryBrief")
                (let [isDefect (matchesDefectBrief text)
                      newDefects (if isDefect (addUniqueInt defects t) defects)
                      subBrief (c/sliceOf text 0 (min 200 (stringLength text)))
                      isCut (stringContains? subBrief "cut at the output token ceiling")
                      newCuts (if isCut (mapSet cutFlags t true) cutFlags)]
                  (readJournalLines (c/restOf lines) turnsSet replies newDefects newCuts)))
              (else
                (readJournalLines (c/restOf lines) turnsSet replies defects cutFlags))))))))


fn readJournalDefects content: String -> JournalDefects
  (let [lines (stringLines content)]
    (mt (readJournalLines lines (list) (mapEmpty) (list) (mapEmpty))
      ((pair turns entries)
        (JournalDefects :turns (listLength turns) :defects (map (fn [p] (pairSecond p)) entries)))))


fn allDefectCauses -> (List String)
  (list "unbalanced" "quote" "prose" "truncated" "unknownOp" "raw" "other")


fn tallyDefects entries: (List DefectEntry) counts: (Map String Int64) samples: (Map String String) -> (Pair (Map String Int64) (Map String String))
  (if (listEmpty? entries)
    (pair counts samples)
    (let [entry (c/firstOf entries)
          cause (classifyDefect entry.reply entry.cut)
          curCount (optionOr (mapGet counts cause) 0)
          newCounts (mapSet counts cause (+ curCount 1))
          hasSample (mapHas? samples cause)
          newSamples (if (and (not hasSample) (!= entry.reply ""))
                       (mapSet samples cause (c/sliceOf entry.reply 0 (min 120 (stringLength entry.reply))))
                       samples)]
      (tallyDefects (c/restOf entries) newCounts newSamples)))


fn causeIndex causes: (List String) target: String idx: Int64 -> Int64
  (cond
    ((listEmpty? causes) 999)
    ((= (c/firstOf causes) target) idx)
    (else (causeIndex (c/restOf causes) target (+ idx 1))))


fn sortDefectCauses causes: (List DefectCauseCount) -> (List DefectCauseCount)
  (let [order (allDefectCauses)]
    (listSortBy (fn [c]
                  (let [cIdx (causeIndex order c.cause 0)]
                    (- (* (- 0 c.count) 1000) (- 1000 cIdx))))
                causes))


fn collectDefectsJournals journals: (List (Pair String String)) runs: Int64 totalTurns: Int64 allEntries: (List DefectEntry) -> (Pair (Pair Int64 Int64) (List DefectEntry))
  (if (listEmpty? journals)
    (pair (pair runs totalTurns) allEntries)
    (let [content (pairSecond (c/firstOf journals))
          jd (readJournalDefects content)
          newRuns (+ runs 1)
          newTurns (+ totalTurns jd.turns)
          newEntries (listAppend allEntries jd.defects)]
      (collectDefectsJournals (c/restOf journals) newRuns newTurns newEntries)))


fn analyzeDefects journals: (List (Pair String String)) unreadable: Int64 -> ParseDefectsResult
  (mt (collectDefectsJournals journals 0 0 (list))
    ((pair pRunsTurns allEntries)
      (let [runs (pairFirst pRunsTurns)
            totalTurns (pairSecond pRunsTurns)]
        (mt (tallyDefects allEntries (mapEmpty) (mapEmpty))
          ((pair counts samples)
            (let [causesPresent (filter (fn [c] (> (optionOr (mapGet counts c) 0) 0)) (allDefectCauses))
                  causeCounts (map (fn [c]
                                     (let [cnt (optionOr (mapGet counts c) 0)
                                           smp (optionOr (mapGet samples c) "")]
                                       (DefectCauseCount :cause c :count cnt :sample smp)))
                                   causesPresent)
                  sortedCauses (sortDefectCauses causeCounts)]
              (ParseDefectsResult :runs runs :turns totalTurns :defects (listLength allEntries) :byCause sortedCauses :unreadable unreadable)))))))

fn collectDefectFiles! paths: (List String) journals: (List (Pair String String)) unreadable: Int64 -> (Pair (List (Pair String String)) Int64)
  (if (listEmpty? paths)
    (pair journals unreadable)
    (let [path (c/firstOf paths)]
      (mt (fileReadString path)
        ((ok content) (collectDefectFiles! (c/restOf paths) (listAppend journals (list (pair path content))) unreadable))
        ((err _) (collectDefectFiles! (c/restOf paths) journals (+ unreadable 1))))))

fn analyzeDefectFiles! paths: (List String) -> ParseDefectsResult
  (let [collected (collectDefectFiles! paths (list) 0)]
    (analyzeDefects (pairFirst collected) (pairSecond collected)))


fn formatCauseCount c: DefectCauseCount -> String
  (str "(:cause " c.cause " :n " (stringFromInt64 c.count) " :sample " (c/serString c.sample) ")")


fn formatParseDefects res: ParseDefectsResult -> String
  (let [byCauses (stringJoin (map formatCauseCount res.byCause) " ")
        extra (if (> res.unreadable 0) (str " :unreadable " (stringFromInt64 res.unreadable)) "")]
    (str "(:parseDefects :runs " (stringFromInt64 res.runs) " :turns " (stringFromInt64 res.turns) " :defects " (stringFromInt64 res.defects) " :byCause (" byCauses ")" extra ")"))


fn extractAllQuotedStringsLoop s: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [c (c/sliceOf s i (+ i 1))]
      (if (= c "\"")
        (let [sub (optionOr (stringSlice s (+ i 1) n) "")
              nextQ (stringIndexOf sub "\"")]
          (mt nextQ
            ((some off)
              (let [val (c/sliceOf s (+ i 1) (+ (+ i 1) off))]
                (extractAllQuotedStringsLoop s n (+ (+ (+ i 1) off) 1) (cons val acc))))
            ((none) (listReverse acc))))
        (extractAllQuotedStringsLoop s n (+ i 1) acc))))


fn extractAllQuotedStrings s: String -> (List String)
  (extractAllQuotedStringsLoop s (stringLength s) 0 (list))


fn extractFieldStr form: String field: String -> String
  (let [target (str field " \"")
        n (stringLength form)
        idx (stringIndexOf form target)]
    (mt idx
      ((some start)
        (let [valStart (+ start (stringLength target))
              sub (optionOr (stringSlice form valStart n) "")
              endQuote (stringIndexOf sub "\"")]
          (mt endQuote
            ((some off) (c/sliceOf form valStart (+ valStart off)))
            ((none) ""))))
      ((none) "")))


fn extractFieldKw form: String field: String -> String
  (let [target (str field " :")
        n (stringLength form)
        idx (stringIndexOf form target)]
    (mt idx
      ((some start)
        (let [valStart (+ start (stringLength target))
              endWord (scanWordOrHyphen form n valStart)]
          (c/sliceOf form valStart endWord)))
      ((none) "")))


fn extractQuotedList form: String field: String -> (List String)
  (let [target (str field " (")
        n (stringLength form)
        idx (stringIndexOf form target)]
    (mt idx
      ((some start)
        (let [valStart (+ start (stringLength target))
              sub (optionOr (stringSlice form valStart n) "")
              closeParen (stringIndexOf sub ")")]
          (mt closeParen
            ((some off)
              (let [inner (c/sliceOf form valStart (+ valStart off))]
                (extractAllQuotedStrings inner)))
            ((none) (list)))))
      ((none) (list))))


fn parseSingleReceipt rText: String -> Receipt
  (let [op (extractFieldStr rText ":op")
        file (extractFieldStr rText ":file")
        status (extractFieldKw rText ":status")
        err (extractFieldKw rText ":error")
        flushed (extractQuotedList rText ":flushed")]
    (Receipt :op op :file file :status status :error err :flushed flushed))


fn findClosingQuote text: String n: Int64 i: Int64 -> Int64
  (cond
    ((>= i n) -1)
    (else
      (let [c (c/sliceOf text i (+ i 1))]
        (cond
          ((= c "\\") (findClosingQuote text n (+ i 2)))
          ((= c "\"") (+ i 1))
          (else (findClosingQuote text n (+ i 1)))))))


fn formParenEnd text: String n: Int64 i: Int64 depth: Int64 -> Int64
  (cond
    ((<= depth 0) i)
    ((>= i n) -1)
    (else
      (let [c (c/sliceOf text i (+ i 1))]
        (cond
          ((= c "\\")
            (formParenEnd text n (+ i 2) depth))
          ((= c "\"")
            (let [closeQ (findClosingQuote text n (+ i 1))]
              (if (< closeQ 0) -1 (formParenEnd text n closeQ depth))))
          ((= c "(")
            (formParenEnd text n (+ i 1) (+ depth 1)))
          ((= c ")")
            (formParenEnd text n (+ i 1) (- depth 1)))
          (else
            (formParenEnd text n (+ i 1) depth))))))


fn findReceiptForms text: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [sub (optionOr (stringSlice text i n) "")
          idx (stringIndexOf sub "(:receipt")]
      (mt idx
        ((some off)
          (let [start (+ i off)
                formEnd (formParenEnd text n (+ start 9) 1)]
            (if (< formEnd 0)
              (listReverse acc)
              (let [rForm (c/sliceOf text start formEnd)]
                (findReceiptForms text n formEnd (cons rForm acc))))))
        ((none) (listReverse acc)))))


fn parseReceiptsFromText text: String -> (List Receipt)
  (let [forms (findReceiptForms text (stringLength text) 0 (list))]
    (map parseSingleReceipt forms))


fn extractIntField s: String key: String -> Int64
  (let [target (str key " ")
        n (stringLength s)
        idx (stringIndexOf s target)]
    (mt idx
      ((some start)
        (let [valStart (skipWhitespace s n (+ start (stringLength target)))
              valEnd (scanDigits s n valStart)]
          (if (> valEnd valStart)
            (optionOr (stringToInt64 (c/sliceOf s valStart valEnd)) 0)
            0)))
      ((none) 0)))


fn unescapeIfQuoted s: String -> String
  (let [inner (extractQuotedString s)]
    (c/asnUnescape inner))


fn pathBasename path: String -> String
  (let [sub (stringReplace path "\\" "/")]
    (mt (stringIndexOf sub "/")
      ((none) sub)
      ((some _)
        (let [parts (stringSplit sub "/")
              nonEmpty (filter (fn [p] (!= p "")) parts)]
          (if (listEmpty? nonEmpty) sub (c/firstOf (listReverse nonEmpty)))))))


fn extractResultWritten content: String -> (List String)
  (let [idx (stringIndexOf content ":written (")
        n (stringLength content)]
    (mt idx
      ((some start)
        (let [valStart (+ start 10)
              sub (optionOr (stringSlice content valStart n) "")
              closeParen (stringIndexOf sub ")")]
          (mt closeParen
            ((some off)
              (let [inner (c/sliceOf content valStart (+ valStart off))]
                (extractAllQuotedStrings inner)))
            ((none) (list)))))
      ((none) (list))))


fn findNextParen s: String n: Int64 i: Int64 -> Int64
  (if (>= i n)
    i
    (let [c (c/sliceOf s i (+ i 1))]
      (if (or (= c "(") (= c ")"))
        i
        (findNextParen s n (+ i 1)))))

fn extractEditFilesFromReplyLoop s: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [c (c/sliceOf s i (+ i 1))]
      (if (!= c "(")
        (extractEditFilesFromReplyLoop s n (+ i 1) acc)
        (let [afterOpen (skipWhitespace s n (+ i 1))]
          (cond
            ((and (<= (+ afterOpen 5) n) (= (c/sliceOf s afterOpen (+ afterOpen 5)) ":step"))
              (let [afterStep (+ afterOpen 5)]
                (if (not (or (>= afterStep n) (or (isSpace (c/sliceOf s afterStep (+ afterStep 1))) (= (c/sliceOf s afterStep (+ afterStep 1)) ")"))))
                  (extractEditFilesFromReplyLoop s n (+ i 1) acc)
                  (let [endP (findNextParen s n afterStep)
                        header (c/sliceOf s afterStep endP)
                        hasEditOp (or (stringContains? header ":op \"edit\"") (stringContains? header ":op \"write\""))
                        fileIdx (stringIndexOf header ":file \"")]
                    (mt fileIdx
                      ((none) (extractEditFilesFromReplyLoop s n (+ i 1) acc))
                      ((some start)
                        (if (not hasEditOp)
                          (extractEditFilesFromReplyLoop s n (+ i 1) acc)
                          (let [valStart (+ start 7)
                                sub (optionOr (stringSlice header valStart (stringLength header)) "")
                                qIdx (stringIndexOf sub "\"")]
                            (mt qIdx
                              ((none) (extractEditFilesFromReplyLoop s n (+ i 1) acc))
                              ((some qOff)
                                (let [fn (c/sliceOf header valStart (+ valStart qOff))]
                                  (if (isAslOrAsn fn)
                                    (extractEditFilesFromReplyLoop s n (+ i 1) (cons fn acc))
                                    (extractEditFilesFromReplyLoop s n (+ i 1) acc)))))))))))))
            ((or (and (<= (+ afterOpen 5) n) (= (c/sliceOf s afterOpen (+ afterOpen 5)) ":edit"))
                 (and (<= (+ afterOpen 6) n) (= (c/sliceOf s afterOpen (+ afterOpen 6)) ":write")))
              (let [cmdLen (if (= (c/sliceOf s afterOpen (+ afterOpen 5)) ":edit") 5 6)
                    afterCmd (+ afterOpen cmdLen)]
                (if (not (or (>= afterCmd n) (or (isSpace (c/sliceOf s afterCmd (+ afterCmd 1))) (= (c/sliceOf s afterCmd (+ afterCmd 1)) ")"))))
                  (extractEditFilesFromReplyLoop s n (+ i 1) acc)
                  (let [endP (findNextParen s n afterCmd)
                        header (c/sliceOf s afterCmd endP)
                        fileIdx (stringIndexOf header ":file \"")]
                    (mt fileIdx
                      ((none) (extractEditFilesFromReplyLoop s n (+ i 1) acc))
                      ((some start)
                        (let [valStart (+ start 7)
                              sub (optionOr (stringSlice header valStart (stringLength header)) "")
                              qIdx (stringIndexOf sub "\"")]
                          (mt qIdx
                            ((none) (extractEditFilesFromReplyLoop s n (+ i 1) acc))
                            ((some qOff)
                              (let [fn (c/sliceOf header valStart (+ valStart qOff))]
                                (if (isAslOrAsn fn)
                                  (extractEditFilesFromReplyLoop s n (+ i 1) (cons fn acc))
                                  (extractEditFilesFromReplyLoop s n (+ i 1) acc))))))))))))
            (else
              (extractEditFilesFromReplyLoop s n (+ i 1) acc)))))))

fn extractEditFilesFromReply reply: String -> (List String)
  (extractEditFilesFromReplyLoop reply (stringLength reply) 0 (list))

fn extractFailedFilesFromErrors errors: (List String) -> (List String)
  (filter isAslOrAsn
    (map (fn [errLine]
           (if (or (stringContains? errLine ":op \"edit\"") (stringContains? errLine ":op \"write\""))
             (extractFieldStr errLine ":file")
             ""))
         errors))


fn determineFailType isParseDefect: Bool errStr: String sigStr: String obsStr: String gateExits: (List Int64) retryBrief: String failedFiles: (List String) turnRecs: (List Receipt) stagedOrFlushed: (List String) -> (Option String)
  (if isParseDefect
    (some "syntax_parse_defect")
    (cond
      ((or (stringContains? errStr "ERR_UNBALANCED")
         (or (stringContains? obsStr "unbalanced")
           (or (stringContains? obsStr "balance")
             (or (stringContains? obsStr "delimiters")
               (or (stringContains? errStr "ERR_TXN_FLUSH_FAILED")
                 (stringContains? sigStr "ERR_TXN_FLUSH_FAILED"))))))
        (some "syntax_unbalanced"))
      ((or (stringContains? errStr "ERR_CHECK_FAILED")
         (or (stringContains? errStr "ERR_SYNTAX")
           (stringContains? obsStr ":syntax :error")))
        (some "syntax_check_failed"))
      ((or (stringContains? errStr "ERR_NO_MATCH")
         (or (stringContains? obsStr "Old target string not found")
           (stringContains? errStr "ERR_AMBIGUOUS")))
        (some "semantic_no_match"))
      ((or (stringContains? errStr "ERR_OWNS")
         (or (stringContains? errStr "ERR_ROOT")
           (stringContains? errStr "ERR_BOUNDARY")))
        (some "semantic_owns"))
      ((or (stringContains? errStr "ERR_RAW_MISSING")
         (stringContains? errStr "ERR_USE_RAW"))
        (some "semantic_raw"))
      ((or (listAny? (fn [e] (!= e 0)) gateExits)
         (and (stringContains? retryBrief "gate")
           (stringContains? retryBrief "exit code: 1")))
        (some "gate_failure"))
      ((or (not (listEmpty? failedFiles))
         (or (listAny? (fn [r] (or (= r.status "rejected") (= r.status "failed"))) turnRecs)
           (or (stringContains? obsStr ":status :rejected")
             (or (stringContains? obsStr ":status :failed")
               (or (stringContains? errStr "ERR_EFFECT_UNDECLARED")
                 (!= sigStr ""))))))
        (some "semantic_other"))
      ((listEmpty? stagedOrFlushed)
        (none))
      (else
        (some "ok"))))


(schema ParseJournalState
  (:f replies (Map Int64 String))
  (:f usages (Map Int64 UsageTokens))
  (:f parseDefects (List Int64))
  (:f formatNudges (List Int64))
  (:f errors (Map Int64 (List String)))
  (:f observations (Map Int64 String))
  (:f retryBriefs (Map Int64 String))
  (:f signals (Map Int64 String))
  (:f gates (Map Int64 (List Int64)))
  (:f curTurn Int64))


fn parseJournalLinesLoop lines: (List String) state: ParseJournalState -> ParseJournalState
  (if (listEmpty? lines)
    state
    (let [line (c/firstOf lines)]
      (cond
        ((stringStartsWith? line "(:turn ")
          (let [tlOpt (parseTurnLine line)]
            (mt tlOpt
              ((none) (parseJournalLinesLoop (c/restOf lines) state))
              ((some tl)
                (let [t tl.turn
                      key tl.key
                      rest tl.rest
                      curUsages state.usages
                      curReplies state.replies
                      curErrors state.errors
                      curObs state.observations
                      curBriefs state.retryBriefs
                      curSigs state.signals
                      curGates state.gates
                      newState (with state :replies curReplies :usages curUsages :errors curErrors :observations curObs :retryBriefs curBriefs :signals curSigs :gates curGates :curTurn t)]
                  (cond
                    ((= key "reply")
                      (let [text (extractQuotedString rest)]
                        (parseJournalLinesLoop (c/restOf lines)
                          (with state :replies (mapSet curReplies t text) :usages curUsages :errors curErrors :observations curObs :retryBriefs curBriefs :signals curSigs :gates curGates :curTurn t))))
                    ((= key "usage")
                      (let [mi (extractIntField rest ":input")
                            mc (extractIntField rest ":cached")
                            mo (extractIntField rest ":output")]
                        (parseJournalLinesLoop (c/restOf lines)
                          (with state :replies curReplies :usages (mapSet curUsages t (UsageTokens :input mi :cached mc :output mo)) :errors curErrors :observations curObs :retryBriefs curBriefs :signals curSigs :gates curGates :curTurn t))))
                    ((or (= key "parse-defect") (= key "parseDefect"))
                      (parseJournalLinesLoop (c/restOf lines)
                        (with state :replies curReplies :usages curUsages :parseDefects (cons t state.parseDefects) :errors curErrors :observations curObs :retryBriefs curBriefs :signals curSigs :gates curGates :curTurn t)))
                    ((= key "formatNudge")
                      (parseJournalLinesLoop (c/restOf lines)
                        (with state :replies curReplies :usages curUsages :formatNudges (cons t state.formatNudges) :errors curErrors :observations curObs :retryBriefs curBriefs :signals curSigs :gates curGates :curTurn t)))
                    ((= key "error")
                      (let [curList (optionOr (mapGet curErrors t) (list))]
                        (parseJournalLinesLoop (c/restOf lines)
                          (with state :replies curReplies :usages curUsages :errors (mapSet curErrors t (cons rest curList)) :observations curObs :retryBriefs curBriefs :signals curSigs :gates curGates :curTurn t))))
                    ((= key "observation")
                      (parseJournalLinesLoop (c/restOf lines)
                        (with state :replies curReplies :usages curUsages :errors curErrors :observations (mapSet curObs t rest) :retryBriefs curBriefs :signals curSigs :gates curGates :curTurn t)))
                    ((= key "retryBrief")
                      (parseJournalLinesLoop (c/restOf lines)
                        (with state :replies curReplies :usages curUsages :errors curErrors :observations curObs :retryBriefs (mapSet curBriefs t rest) :signals curSigs :gates curGates :curTurn t)))
                    ((= key "signal")
                      (parseJournalLinesLoop (c/restOf lines)
                        (with state :replies curReplies :usages curUsages :errors curErrors :observations curObs :retryBriefs curBriefs :signals (mapSet curSigs t rest) :gates curGates :curTurn t)))
                    ((= key "gateOp")
                      (if (stringContains? rest ":exit ")
                        (let [exit (extractIntField rest ":exit")
                              curList (optionOr (mapGet curGates t) (list))]
                          (parseJournalLinesLoop (c/restOf lines)
                            (with state :replies curReplies :usages curUsages :errors curErrors :observations curObs :retryBriefs curBriefs :signals curSigs :gates (mapSet curGates t (cons exit curList)) :curTurn t)))
                        (parseJournalLinesLoop (c/restOf lines) newState)))
                    (else
                      (parseJournalLinesLoop (c/restOf lines) newState))))))))
        ((and (stringStartsWith? line "(:gate ") (>= state.curTurn 0))
          (if (stringContains? line ":exit ")
            (let [t state.curTurn
                  exit (extractIntField line ":exit")
                  curGates state.gates
                  curList (optionOr (mapGet curGates t) (list))]
              (parseJournalLinesLoop (c/restOf lines)
                (with state :gates (mapSet curGates t (cons exit curList)) :curTurn t)))
            (parseJournalLinesLoop (c/restOf lines) state)))
        (else
          (parseJournalLinesLoop (c/restOf lines) state)))))


fn buildReceiptsMap turns: (List Int64) obs: (Map Int64 String) retryBriefs: (Map Int64 String) acc: (Map Int64 (List Receipt)) -> (Map Int64 (List Receipt))
  (if (listEmpty? turns)
    acc
    (let [t (c/firstOf turns)
          obsText (mt (mapGet obs t) ((some s) (unescapeIfQuoted s)) ((none) ""))
          briefText (mt (mapGet retryBriefs t) ((some s) (unescapeIfQuoted s)) ((none) ""))
          r1 (if (!= obsText "") (parseReceiptsFromText obsText) (list))
          r2 (if (!= briefText "") (parseReceiptsFromText briefText) (list))
          allR (listAppend r1 r2)]
      (buildReceiptsMap (c/restOf turns) obs retryBriefs (mapSet acc t allR))))


(schema TurnProcessResult
  (:f sequences (List EditSeq))
  (:f jSequences (List EditSeq))
  (:f activeSeqs (Map String SeqState))
  (:f fbk FailuresByKind)
  (:f totalAttempts Int64)
  (:f acceptedAttempts Int64)
  (:f failedAttempts Int64)
  (:f hadAslAsn Bool))


fn addFailureByKind fbk: FailuresByKind failType: String -> FailuresByKind
  (cond
    ((= failType "syntax_unbalanced")
      (with fbk :syntaxUnbalanced (+ fbk.syntaxUnbalanced 1)))
    ((= failType "syntax_parse_defect")
      (with fbk :syntaxParseDefect (+ fbk.syntaxParseDefect 1)))
    ((= failType "syntax_check_failed")
      (with fbk :syntaxCheckFailed (+ fbk.syntaxCheckFailed 1)))
    ((= failType "semantic_no_match")
      (with fbk :semanticNoMatch (+ fbk.semanticNoMatch 1)))
    ((= failType "semantic_owns")
      (with fbk :semanticOwns (+ fbk.semanticOwns 1)))
    ((= failType "semantic_raw")
      (with fbk :semanticRaw (+ fbk.semanticRaw 1)))
    ((= failType "semantic_other")
      (with fbk :semanticOther (+ fbk.semanticOther 1)))
    ((= failType "gate_failure")
      (with fbk :gateFailure (+ fbk.gateFailure 1)))
    (else fbk))


fn updateActiveSequences files: (List String) journalBase: String turnFailed: Bool failType: String totTokens: Int64 activeSeqs: (Map String SeqState) seqs: (List EditSeq) jSeqs: (List EditSeq) fbk: FailuresByKind totAtt: Int64 accAtt: Int64 failAtt: Int64 -> TurnProcessResult
  (if (listEmpty? files)
    (TurnProcessResult :sequences seqs :jSequences jSeqs :activeSeqs activeSeqs :fbk fbk :totalAttempts totAtt :acceptedAttempts accAtt :failedAttempts failAtt :hadAslAsn true)
    (let [fn (c/firstOf files)
          curSeq (mt (mapGet activeSeqs fn) ((some s) s) ((none) (SeqState :retries 0 :tokens 0 :failures (list))))
          newTokens (+ curSeq.tokens totTokens)
          nextTotAtt (+ totAtt 1)]
      (if turnFailed
        (let [nextFailAtt (+ failAtt 1)
              nextFbk (addFailureByKind fbk failType)
              nextRetries (+ curSeq.retries 1)
              nextFailures (listAppend curSeq.failures (list failType))
              nextActive (mapSet activeSeqs fn (SeqState :retries nextRetries :tokens newTokens :failures nextFailures))]
          (updateActiveSequences (c/restOf files) journalBase turnFailed failType totTokens nextActive seqs jSeqs nextFbk nextTotAtt accAtt nextFailAtt))
        (let [nextAccAtt (+ accAtt 1)
              entry (EditSeq :journal journalBase :file fn :retries curSeq.retries :accepted true :tokens newTokens :failures curSeq.failures)
              nextSeqs (cons entry seqs)
              nextJSeqs (cons entry jSeqs)
              nextActive (mapSet activeSeqs fn (SeqState :retries 0 :tokens 0 :failures (list)))]
          (updateActiveSequences (c/restOf files) journalBase turnFailed failType totTokens nextActive nextSeqs nextJSeqs fbk nextTotAtt nextAccAtt failAtt)))))


fn allZero exits: (List Int64) -> Bool
  (cond
    ((listEmpty? exits) true)
    ((!= (c/firstOf exits) 0) false)
    (else (allZero (c/restOf exits))))


fn flattenFlushed recs: (List Receipt) -> (List String)
  (if (listEmpty? recs)
    (list)
    (listAppend (filter isAslOrAsn (c/firstOf recs).flushed)
                (flattenFlushed (c/restOf recs))))


fn processJournalTurns turns: (List Int64) lastTurn: Int64 pjState: ParseJournalState receiptsMap: (Map Int64 (List Receipt)) journalBase: String hasCommit: Bool isResOk: Bool resultWritten: (List String) cur: TurnProcessResult -> TurnProcessResult
  (if (listEmpty? turns)
    cur
    (let [t (c/firstOf turns)
          rawReply (optionOr (mapGet pjState.replies t) "")
          unescReply (c/asnUnescape rawReply)
          retryBrief (mt (mapGet pjState.retryBriefs t) ((some b) b) ((none) ""))
          isParseDefect (or (listContains? pjState.parseDefects t) (stringContains? retryBrief "reply was not parseable"))
          isFormatNudged (listContains? pjState.formatNudges t)
          turnRecs (optionOr (mapGet receiptsMap t) (list))
          
          recEditFiles (filter (fn [r] (and (or (= r.op "edit") (= r.op "write")) (isAslOrAsn r.file))) turnRecs)
          receiptFiles1 (map (fn [r] r.file) recEditFiles)
          staged1 (map (fn [r] r.file) (filter (fn [r] (= r.status "ok")) recEditFiles))
          failed1 (map (fn [r] r.file) (filter (fn [r] (!= r.status "ok")) recEditFiles))
          
          txnRecs (filter (fn [r] (= r.op "txn")) turnRecs)
          txnFlushed (flattenFlushed txnRecs)
          txnOk (filter (fn [r] (= r.status "ok")) txnRecs)
          txnFailed (filter (fn [r] (!= r.status "ok")) txnRecs)
          txnFlushedOk (flattenFlushed txnOk)
          txnFlushedFail (flattenFlushed txnFailed)
          
          receiptFiles2 (listAppend receiptFiles1 txnFlushed)
          staged2 (listAppend staged1 txnFlushedOk)
          failed2 (listAppend failed1 txnFlushedFail)
          
          hasTurnErrors (mapHas? pjState.errors t)
          replyStepFiles (if (and (or isParseDefect hasTurnErrors) (not isFormatNudged))
                           (extractEditFilesFromReply unescReply)
                           (list))
          
          turnErrors (optionOr (mapGet pjState.errors t) (list))
          errFiles (extractFailedFilesFromErrors turnErrors)
          receiptFiles3 (listAppend receiptFiles2 errFiles)
          failed3 (listAppend failed2 errFiles)
          
          turnGates (optionOr (mapGet pjState.gates t) (list))
          isLastTurnFallBack (and (= t lastTurn) (and (or hasCommit isResOk) (and (listEmpty? receiptFiles3) (listEmpty? replyStepFiles))))
          fallbackOk (and isLastTurnFallBack (and (not (listEmpty? turnGates)) (allZero turnGates)))
          
          fallbackReplyFiles (if fallbackOk (extractEditFilesFromReply unescReply) (list))
          fallbackWrittenFiles (if fallbackOk (filter isAslOrAsn resultWritten) (list))
          fallbackAll (listAppend fallbackReplyFiles fallbackWrittenFiles)
          
          finalReceiptFiles (listAppend receiptFiles3 fallbackAll)
          finalStaged (listAppend staged2 fallbackAll)
          
          allTargetsRaw (listAppend finalReceiptFiles replyStepFiles)
          targetFiles (listSort (filter (fn [f] (!= f "")) (mapKeys (mapFromPairs (map (fn [f] (pair f true)) allTargetsRaw)))))]
      (if (listEmpty? targetFiles)
        (processJournalTurns (c/restOf turns) lastTurn pjState receiptsMap journalBase hasCommit isResOk resultWritten cur)
        (let [usageT (mt (mapGet pjState.usages t) ((some u) u) ((none) (UsageTokens :input 0 :cached 0 :output 0)))
              totTokens (+ (+ usageT.input usageT.cached) usageT.output)
              errStr (str (stringJoin turnErrors " ") " " (stringJoin (map (fn [r] r.error) turnRecs) " "))
              sigStr (optionOr (mapGet pjState.signals t) "")
              obsStr (optionOr (mapGet pjState.observations t) "")
              failTypeOpt (determineFailType isParseDefect errStr sigStr obsStr turnGates retryBrief failed3 turnRecs finalStaged)]
          (mt failTypeOpt
            ((none)
              (processJournalTurns (c/restOf turns) lastTurn pjState receiptsMap journalBase hasCommit isResOk resultWritten cur))
            ((some ft)
              (let [turnFailed (!= ft "ok")
                    res (updateActiveSequences targetFiles journalBase turnFailed ft totTokens cur.activeSeqs cur.sequences cur.jSequences cur.fbk cur.totalAttempts cur.acceptedAttempts cur.failedAttempts)]
                (processJournalTurns (c/restOf turns) lastTurn pjState receiptsMap journalBase hasCommit isResOk resultWritten res))))))))


(schema AnalysisAccumulator
  (:f scanned Int64)
  (:f aslAsnJournals (List String))
  (:f sequences (List EditSeq))
  (:f byJournal (List JournalEditSummary))
  (:f fbk FailuresByKind)
  (:f totalAttempts Int64)
  (:f acceptedAttempts Int64)
  (:f failedAttempts Int64))


fn analyzeJournalsLoop journals: (List (Pair String String)) acc: AnalysisAccumulator -> EditMetricsResult
  (if (listEmpty? journals)
    (let [totalSeq (listLength acc.sequences)
          allSeqs (listReverse acc.sequences)
          acceptedSeq (filter (fn [s] s.accepted) allSeqs)
          firstPassSeq (filter (fn [s] (and s.accepted (= s.retries 0))) allSeqs)
          numAccepted (listLength acceptedSeq)
          numFirstPass (listLength firstPassSeq)
          firstPassRate (if (> totalSeq 0) (/ (int64ToFloat64 numFirstPass) (int64ToFloat64 totalSeq)) 0.0)
          totalRetries (listSum (map (fn [s] s.retries) acceptedSeq))
          avgRetries (if (> numAccepted 0) (/ (int64ToFloat64 totalRetries) (int64ToFloat64 numAccepted)) 0.0)
          totalTokens (listSum (map (fn [s] s.tokens) acceptedSeq))
          avgTokens (if (> numAccepted 0) (/ (int64ToFloat64 totalTokens) (int64ToFloat64 numAccepted)) 0.0)
          fbk acc.fbk
          syntaxFailures (+ fbk.syntaxUnbalanced (+ fbk.syntaxParseDefect fbk.syntaxCheckFailed))
          semanticFailures (+ fbk.semanticNoMatch (+ fbk.semanticOwns (+ fbk.semanticRaw fbk.semanticOther)))
          gateFailures fbk.gateFailure
          totalFailures (+ syntaxFailures (+ semanticFailures gateFailures))
          syntaxShare (if (> totalFailures 0) (/ (int64ToFloat64 syntaxFailures) (int64ToFloat64 totalFailures)) 0.0)
          semanticShare (if (> totalFailures 0) (/ (int64ToFloat64 semanticFailures) (int64ToFloat64 totalFailures)) 0.0)
          gateShare (if (> totalFailures 0) (/ (int64ToFloat64 gateFailures) (int64ToFloat64 totalFailures)) 0.0)]
      (EditMetricsResult :totalJournalsScanned acc.scanned
                         :aslAsnJournalsCount (listLength acc.aslAsnJournals)
                         :totalAttempts acc.totalAttempts
                         :acceptedAttempts acc.acceptedAttempts
                         :failedAttempts acc.failedAttempts
                         :totalSequences totalSeq
                         :acceptedSequences numAccepted
                         :firstPassSequences numFirstPass
                         :totalFailures totalFailures
                         :syntaxFailures syntaxFailures
                         :semanticFailures semanticFailures
                         :gateFailures gateFailures
                         :failuresByKind fbk
                         :firstPassRate firstPassRate
                         :avgRetriesPerAccepted avgRetries
                         :avgTokensPerAccepted avgTokens
                         :syntaxShare syntaxShare
                         :semanticShare semanticShare
                         :gateShare gateShare
                         :sequences allSeqs
                         :byJournal (listReverse acc.byJournal)))
    (let [jp (pairFirst (c/firstOf journals))
          content (pairSecond (c/firstOf journals))
          jBase (pathBasename jp)
          nextScanned (+ acc.scanned 1)
          hasAslAsn (or (stringContains? content ".asl") (stringContains? content ".asn"))
          hasEditSignal (or (stringContains? content ":op \\\"edit\\\"")
                          (or (stringContains? content ":op \\\"write\\\"")
                            (or (stringContains? content ":op \"edit\"")
                              (or (stringContains? content ":op \"write\"")
                                (or (stringContains? content "(:write")
                                  (or (stringContains? content "(:edit")
                                    (or (stringContains? content ":parse-defect")
                                      (stringContains? content "reply was not parseable"))))))))]
      (if (or (stringEmpty? content) (not (and hasAslAsn hasEditSignal)))
        (analyzeJournalsLoop (c/restOf journals)
          (with acc :scanned nextScanned))
        (let [lines (stringLines content)
              emptyState (ParseJournalState :replies (mapEmpty) :usages (mapEmpty) :parseDefects (list) :formatNudges (list) :errors (mapEmpty) :observations (mapEmpty) :retryBriefs (mapEmpty) :signals (mapEmpty) :gates (mapEmpty) :curTurn -1)
              pjState (parseJournalLinesLoop lines emptyState)
              allTurnsToScan (listSort (filter (fn [t] (or (mapHas? pjState.observations t) (mapHas? pjState.retryBriefs t))) (mapKeys pjState.replies)))
              receiptsMap (buildReceiptsMap allTurnsToScan pjState.observations pjState.retryBriefs (mapEmpty))
              repliesKeys (listSort (mapKeys pjState.replies))
              lastTurn (if (listEmpty? repliesKeys) -1 (c/firstOf (listReverse repliesKeys)))
              hasCommit (stringContains? content "(:commit \"")
              isResOk (stringContains? content "(:result :status :ok")
              resultWritten (extractResultWritten content)
              initResult (TurnProcessResult :sequences (list) :jSequences (list) :activeSeqs (mapEmpty) :fbk acc.fbk :totalAttempts acc.totalAttempts :acceptedAttempts acc.acceptedAttempts :failedAttempts acc.failedAttempts :hadAslAsn false)
              res (processJournalTurns repliesKeys lastTurn pjState receiptsMap jBase hasCommit isResOk resultWritten initResult)
              
              activePairs (mapPairs res.activeSeqs)
              trailingPairs (filter (fn [p] (> (pairSecond p).retries 0)) activePairs)
              trailingEntries (map (fn [p] (EditSeq :journal jBase :file (pairFirst p) :retries (pairSecond p).retries :accepted false :tokens (pairSecond p).tokens :failures (pairSecond p).failures)) trailingPairs)
              finalJSeqs (listReverse (listAppend trailingEntries res.jSequences))
              finalSeqs (listAppend trailingEntries res.sequences)
              
              nextAslAsnJournals (if res.hadAslAsn (cons jBase acc.aslAsnJournals) acc.aslAsnJournals)
              jAcc (filter (fn [s] s.accepted) finalJSeqs)
              jFp (filter (fn [s] (and s.accepted (= s.retries 0))) finalJSeqs)
              jSummary (JournalEditSummary :journal jBase :totalSequences (listLength finalJSeqs) :acceptedSequences (listLength jAcc) :firstPassSequences (listLength jFp) :sequences finalJSeqs)
              nextByJournal (cons jSummary acc.byJournal)]
          (analyzeJournalsLoop (c/restOf journals)
            (AnalysisAccumulator :scanned nextScanned :aslAsnJournals nextAslAsnJournals :sequences (listAppend finalSeqs acc.sequences) :byJournal nextByJournal :fbk res.fbk :totalAttempts res.totalAttempts :acceptedAttempts res.acceptedAttempts :failedAttempts res.failedAttempts))))))


fn analyzeEditJournals journals: (List (Pair String String)) -> EditMetricsResult
  (let [initFbk (FailuresByKind :syntaxUnbalanced 0 :syntaxParseDefect 0 :syntaxCheckFailed 0 :semanticNoMatch 0 :semanticOwns 0 :semanticRaw 0 :semanticOther 0 :gateFailure 0)
        initAcc (AnalysisAccumulator :scanned 0 :aslAsnJournals (list) :sequences (list) :byJournal (list) :fbk initFbk :totalAttempts 0 :acceptedAttempts 0 :failedAttempts 0)]
    (analyzeJournalsLoop journals initAcc))


fn readJournalContents! paths: (List String) acc: (List (Pair String String)) -> (Result (List (Pair String String)) String)
  (if (listEmpty? paths)
    (ok acc)
    (let [path (c/firstOf paths)]
      (mt (fileReadString path)
        ((ok content) (readJournalContents! (c/restOf paths) (listAppend acc (list (pair path content)))))
        ((err e) (err (str path ": " e))))))

fn analyzeJournals! paths: (List String) -> (Result EditMetricsResult String)
  (mt (readJournalContents! paths (list))
    ((ok pairs) (ok (analyzeEditJournals pairs)))
    ((err e) (err e)))


fn formatPct val: Float64 -> String
  (let [tenths (optionOr (float64ToInt64 (+ (* (* val 100.0) 10.0) 0.5)) 0)
        whole (/ tenths 10)
        frac (mod tenths 10)]
    (str (stringFromInt64 whole) "." (stringFromInt64 frac) "%"))


fn formatTwoDecimals val: Float64 -> String
  (let [hundredths (optionOr (float64ToInt64 (+ (* val 100.0) 0.5)) 0)
        whole (/ hundredths 100)
        rem (mod hundredths 100)]
    (str (stringFromInt64 whole) "." (if (< rem 10) (str "0" (stringFromInt64 rem)) (stringFromInt64 rem))))


fn formatEditMetric m: EditMetricsResult date: String journalsDir: String -> String
  (let [dateStr (if (stringEmpty? date) "2026-09-26" date)
        dirStr (if (stringEmpty? journalsDir) "tests/acceptance/agentLoop/fixtures/editMetrics" journalsDir)
        fpPct (formatPct m.firstPassRate)
        synPct (formatPct m.syntaxShare)
        semPct (formatPct m.semanticShare)
        gatePct (formatPct m.gateShare)
        retriesStr (formatTwoDecimals m.avgRetriesPerAccepted)
        tokensStr (stringFromInt64 (optionOr (float64ToInt64 m.avgTokensPerAccepted) 0))
        fbk m.failuresByKind]
    (str "(:metric editFirstPass\n"
         "  :pipeline :baseline :stage \"before G3\" :date \"" dateStr "\"\n"
         "  :scope \".asl/.asn\" :journalsScanned " (stringFromInt64 m.totalJournalsScanned) " :journalsWithEdits " (stringFromInt64 m.aslAsnJournalsCount) "\n"
         "  :journalsDir \"" dirStr "\"\n"
         "  :method \"Leon journals in " dirStr " per edit sequence of .asl/.asn files\"\n"
         "  :editFirstPassRate \"" fpPct "\" :acceptedFirstPass " (stringFromInt64 m.firstPassSequences) " :totalEdits " (stringFromInt64 m.totalSequences) "\n"
         "  :retriesPerAccepted " retriesStr " :tokensPerAccepted " tokensStr "\n"
         "  :failureShare (:syntax \"" synPct "\" :semantic \"" semPct "\" :gate \"" gatePct "\")\n"
         "  :syntaxBreakdown (:unbalanced " (stringFromInt64 fbk.syntaxUnbalanced) " :parseDefect " (stringFromInt64 fbk.syntaxParseDefect) " :checkFailed " (stringFromInt64 fbk.syntaxCheckFailed) ")\n"
         "  :attemptCounts (:attempts " (stringFromInt64 m.totalAttempts) " :accepted " (stringFromInt64 m.acceptedAttempts) " :failed " (stringFromInt64 m.failedAttempts) "))"))
