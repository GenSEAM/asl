(module aslAgentCore/clarify :x [ClarificationQuestion ClarificationAnswer ClarificationSession clarificationSessionCreate parseNumberedAnswers attachClarificationAnswers isClarificationResolved? unblockClarificationTask] :i [(tasktypes :a tt)])

(schema ClarificationQuestion (:f index I64) (:f text Str) (:f context Str))

(schema ClarificationAnswer (:f index I64) (:f text Str))

(schema ClarificationSession (:f taskId Str) (:f lane Str) (:f questions (List ClarificationQuestion)) (:f answers (Map I64 Str)) (:f resolved Bool))

fn clarificationSessionCreate taskId: Str lane: Str questions: (List ClarificationQuestion) -> ClarificationSession
  (ClarificationSession :taskId taskId :lane lane :questions questions :answers (mapEmpty) :resolved false)

fn isDigit? c: Str -> Bool
  (and (= (stringLength c) 1) (stringContains? "0123456789" c))

fn isNumDelim? c: Str -> Bool
  (or (= c ".") (or (= c ")") (or (= c ":") (= c "-"))))

fn collectDigits chars: (List Str) acc: Str -> (Pair Str (List Str))
  (mt (listHead chars) ((none) (pair acc (list))) ((some c) (let [(rest (optionOr (listTail chars) (list)))] (if (isDigit? c) (collectDigits rest (str acc c)) (pair acc chars)))))

fn parseNumberedToken tok: Str -> (Option ClarificationAnswer)
  (let [(trimmed (stringTrim tok)) (dotOpt (stringIndexOf trimmed "."))] (mt dotOpt ((some dIdx) (let [(prefix (stringTrim (optionOr (stringSlice trimmed 0 dIdx) ""))) (numOpt (stringToInt64 prefix))] (mt numOpt ((some n) (if (> n 0) (let [(ansText (stringTrim (optionOr (stringSlice trimmed (+ dIdx 1) (stringLength trimmed)) "")))] (some (ClarificationAnswer :index n :text ansText))) (none))) ((none) (none))))) ((none) (let [(parenOpt (stringIndexOf trimmed ")"))] (mt parenOpt ((some pIdx) (let [(prefix (stringTrim (optionOr (stringSlice trimmed 0 pIdx) ""))) (numOpt (stringToInt64 prefix))] (mt numOpt ((some n) (if (> n 0) (let [(ansText (stringTrim (optionOr (stringSlice trimmed (+ pIdx 1) (stringLength trimmed)) "")))] (some (ClarificationAnswer :index n :text ansText))) (none))) ((none) (none))))) ((none) (none)))))))

fn splitLinesAndCommas input: Str -> (List Str)
  (let [(lines (stringSplit input "\n"))] (fold (fn [(acc (List Str)) (line Str)] -> (List Str) (let [(parts (stringSplit line ","))] (listAppend acc parts))) (list) lines))

fn parseNumberedAnswers input: Str -> (List ClarificationAnswer)
  (let [(tokens (splitLinesAndCommas input))] (fold (fn [(acc (List ClarificationAnswer)) (tok Str)] -> (List ClarificationAnswer) (let [(trimmed (stringTrim tok))] (if (stringEmpty? trimmed) acc (mt (parseNumberedToken trimmed) ((some ans) (listAppend acc (list ans))) ((none) (if (listEmpty? acc) acc (let [(rev (listReverse acc)) (lastAns (optionOr (listHead rev) (ClarificationAnswer :index 0 :text ""))) (prefixRev (optionOr (listTail rev) (list))) (prefix (listReverse prefixRev)) (mergedText (str lastAns.text ", " trimmed)) (updatedLast (ClarificationAnswer :index lastAns.index :text mergedText))] (listAppend prefix (list updatedLast))))))))) (list) tokens))

fn attachClarificationAnswers session: ClarificationSession answers: (List ClarificationAnswer) -> ClarificationSession
  (let [(updatedAnswers (fold (fn [(acc (Map I64 Str)) (ans ClarificationAnswer)] -> (Map I64 Str) (mapSet acc ans.index ans.text)) session.answers answers)) (allResolved? (fold (fn [(acc Bool) (q ClarificationQuestion)] -> Bool (and acc (mapHas? updatedAnswers q.index))) true session.questions))] (with session :answers updatedAnswers :resolved allResolved?))

fn isClarificationResolved? session: ClarificationSession -> Bool
  session.resolved

fn validClarificationTransition? from: tt/TaskState to: tt/TaskState -> Bool
  (mt from ((stateClarification) (mt to ((stateRouting) true) (_ false))) (_ false))

fn assertClarificationTransition from: tt/TaskState to: tt/TaskState -> (Result tt/TaskState Str)
  (if (validClarificationTransition? from to) (ok to) (err "Illegal state transition: must transition from state-clarification to state-routing"))

fn unblockClarificationTask task: tt/TaskRecord session: ClarificationSession nowMs: I64 -> (Result tt/TaskRecord Str)
  (let [(curState task.state)] (mt curState ((stateClarification) (if (not (isClarificationResolved? session)) (err "Clarification session is not fully resolved") (let [(transRes (assertClarificationTransition curState (tt/stateRouting)))] (mt transRes ((ok nextState) (let [(envelope (fold (fn [(acc Str) (q ClarificationQuestion)] -> Str (let [(ans (optionOr (mapGet session.answers q.index) "")) (entry (str "Q" (stringFromInt64 q.index) ": " q.text " -> A: " ans))] (if (stringEmpty? acc) entry (str acc "\n" entry)))) "" session.questions)) (newPayload (str task.payload "\n[Clarification Envelope]\n" envelope))] (ok (tt/TaskRecord :id task.id :lane task.lane :projectPath task.projectPath :state nextState :priority task.priority :createdAt task.createdAt :updatedAt nowMs :payload newPayload)))) ((err e) (err e)))))) (_ (err "Task is not in state-clarification"))))
