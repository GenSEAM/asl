(module asl/agentLoop/plan
  :x [planOpen planAdvance planSlot planNow planSummary planField planEvidenceIds planStep planReplay
      planTree planFields planSteps isStepForm stepForm serPlanState parsePlanState
      stepId stepDoText stepCheckText makeStep
      planOn planStepList planDone planDropped planRevisions planCurrent planSince planNudgeTurn newPlan
      summarySteps summaryDone summaryDropped summaryRevisions summaryOf
      receiptId receiptOp receiptStatus makeReceipt
      Step Plan PlanSummary Receipt StepResult SexpNode SexpVal kvGet]
  :i [(asl/agentLoop/core :a c)])

enum SexpNode
  (sexpAtom text: String)
  (sexpStr text: String)
  (sexpList items: (List SexpNode))

enum SexpVal
  (valFlag bool: Bool)
  (valStr text: String)
  (valList items: (List SexpNode))

enum Step
  (stepOf id: String doText: String checkText: String)

enum Plan
  (planOf on: Bool
          steps: (List Step)
          done: (Map String String)
          dropped: (Map String String)
          revisions: Int64
          current: (Option String)
          since: Int64
          nudgeTurn: (Option Int64))

enum PlanSummary
  (summaryOf steps: Int64 done: Int64 dropped: Int64 revisions: Int64)

enum Receipt
  (receiptOf id: String op: String status: String)

enum StepResult
  (stepResult status: String
              op: String
              message: String
              error: String
              entry: (Option String)
              plan: Plan)

fn stepId s: Step -> String
  (mt s ((stepOf id _ _) id))

fn stepDoText s: Step -> String
  (mt s ((stepOf _ d _) d))

fn stepCheckText s: Step -> String
  (mt s ((stepOf _ _ c) c))

fn makeStep id: String doText: String checkText: String -> Step
  (stepOf id doText checkText)

fn planOn p: Plan -> Bool
  (mt p ((planOf on _ _ _ _ _ _ _) on))

fn planStepList p: Plan -> (List Step)
  (mt p ((planOf _ steps _ _ _ _ _ _) steps))

fn planDone p: Plan -> (Map String String)
  (mt p ((planOf _ _ done _ _ _ _ _) done))

fn planDropped p: Plan -> (Map String String)
  (mt p ((planOf _ _ _ dropped _ _ _ _) dropped))

fn planRevisions p: Plan -> Int64
  (mt p ((planOf _ _ _ _ revisions _ _ _) revisions))

fn planCurrent p: Plan -> (Option String)
  (mt p ((planOf _ _ _ _ _ current _ _) current))

fn planSince p: Plan -> Int64
  (mt p ((planOf _ _ _ _ _ _ since _) since))

fn planNudgeTurn p: Plan -> (Option Int64)
  (mt p ((planOf _ _ _ _ _ _ _ nudgeTurn) nudgeTurn))

fn newPlan on: Bool -> Plan
  (planOf on (list) (mapEmpty) (mapEmpty) 0 (none) 0 (none))

fn summarySteps s: PlanSummary -> Int64
  (mt s ((summaryOf steps _ _ _) steps))

fn summaryDone s: PlanSummary -> Int64
  (mt s ((summaryOf _ done _ _) done))

fn summaryDropped s: PlanSummary -> Int64
  (mt s ((summaryOf _ _ dropped _) dropped))

fn summaryRevisions s: PlanSummary -> Int64
  (mt s ((summaryOf _ _ _ revisions) revisions))

fn receiptId r: Receipt -> String
  (mt r ((receiptOf id _ _) id))

fn receiptOp r: Receipt -> String
  (mt r ((receiptOf _ op _) op))

fn receiptStatus r: Receipt -> String
  (mt r ((receiptOf _ _ status) status))

fn makeReceipt id: String op: String status: String -> Receipt
  (receiptOf id op status)

fn unescapeByte c: String -> String
  (cond
    ((= c "n") "\n")
    ((= c "r") "\r")
    ((= c "t") "\t")
    ((= c "\"") "\"")
    ((= c "\\") "\\")
    (else c))

fn scanString s: String n: Int64 i: Int64 acc: (List String) -> (Result (Pair String Int64) String)
  (if (>= i n)
    (err "an unbalanced '('")
    (let [c (c/ch s i)]
      (cond
        ((= c "\"") (ok (pair (c/joinAll (listReverse acc)) (+ i 1))))
        ((= c "\\")
          (if (>= (+ i 1) n)
            (err "an unbalanced '('")
            (scanString s n (+ i 2) (cons (unescapeByte (c/ch s (+ i 1))) acc))))
        (else (scanString s n (+ i 1) (cons c acc))))))

fn isSpaceChar c: String -> Bool
  (or (c/isSpace c) (= c "\n"))

fn skipSpace s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isSpaceChar (c/ch s i)))
    (skipSpace s n (+ i 1))
    i)

fn isDelimiter c: String -> Bool
  (or (isSpaceChar c)
    (or (= c "(")
      (or (= c ")") (= c "\""))))

fn scanAtomEnd s: String n: Int64 i: Int64 -> Int64
  (if (or (>= i n) (isDelimiter (c/ch s i)))
    i
    (scanAtomEnd s n (+ i 1)))

fn scanTree s: String n: Int64 i: Int64 stack: (List (List SexpNode)) -> (Result (List SexpNode) String)
  (let [cur (skipSpace s n i)]
    (if (>= cur n)
      (if (not (listEmpty? (c/restOf stack)))
        (err "an unbalanced '('")
        (ok (listReverse (c/firstOf stack))))
      (let [c (c/ch s cur)]
        (cond
          ((= c "(")
            (scanTree s n (+ cur 1) (cons (list) stack)))
          ((= c ")")
            (if (listEmpty? (c/restOf stack))
              (err "an unbalanced ')'")
              (let [topList (listReverse (c/firstOf stack))
                    parentStack (c/restOf stack)
                    parentList (c/firstOf parentStack)
                    restStack (c/restOf parentStack)]
                (scanTree s n (+ cur 1) (cons (cons (sexpList topList) parentList) restStack)))))
          ((= c "\"")
            (mt (scanString s n (+ cur 1) (list))
              ((ok pr) (mt pr ((pair strVal nextIdx)
                               (scanTree s n nextIdx (cons (cons (sexpStr strVal) (c/firstOf stack)) (c/restOf stack))))))
              ((err e) (err e))))
          (else
            (let [j (scanAtomEnd s n cur)
                  atomVal (c/sliceOf s cur j)]
              (scanTree s n j (cons (cons (sexpAtom atomVal) (c/firstOf stack)) (c/restOf stack)))))))))

fn planTree text: String -> (Result (List SexpNode) String)
  (scanTree text (stringLength text) 0 (list (list)))

fn sexpToVal node: SexpNode -> SexpVal
  (mt node
    ((sexpAtom t) (valStr t))
    ((sexpStr t) (valStr t))
    ((sexpList items) (valList items)))

fn planFieldsLoop xs: (List SexpNode) kv: (List (Pair String SexpVal)) lists: (List (List SexpNode)) -> (Pair (List (Pair String SexpVal)) (List (List SexpNode)))
  (if (listEmpty? xs)
    (pair (listReverse kv) (listReverse lists))
    (let [headNode (c/firstOf xs)
          tailNodes (c/restOf xs)]
      (mt headNode
        ((sexpAtom a)
          (if (stringStartsWith? a ":")
            (let [key (c/sliceOf a 1 (stringLength a))
                  isNextFlag (or (listEmpty? tailNodes)
                                 (mt (c/firstOf tailNodes)
                                   ((sexpAtom na) (stringStartsWith? na ":"))
                                   ((sexpStr _) false)
                                   ((sexpList _) false)))]
              (if isNextFlag
                (planFieldsLoop tailNodes (cons (pair key (valFlag true)) kv) lists)
                (let [val (sexpToVal (c/firstOf tailNodes))]
                  (planFieldsLoop (c/restOf tailNodes) (cons (pair key val) kv) lists))))
            (planFieldsLoop tailNodes kv lists)))
        ((sexpList l)
          (planFieldsLoop tailNodes kv (cons l lists)))
        ((sexpStr _)
          (planFieldsLoop tailNodes kv lists)))))

fn planFields items: (List SexpNode) -> (Pair (List (Pair String SexpVal)) (List (List SexpNode)))
  (if (listEmpty? items)
    (pair (list) (list))
    (planFieldsLoop (c/restOf items) (list) (list)))

fn kvGet kv: (List (Pair String SexpVal)) k: String -> (Option SexpVal)
  (fold (fn [acc pr]
          (mt acc
            ((some _) acc)
            ((none) (mt pr ((pair key val) (if (= key k) (some val) (none)))))))
    (none) kv)

fn kvHas kv: (List (Pair String SexpVal)) k: String -> Bool
  (some? (kvGet kv k))

fn kvGetStr kv: (List (Pair String SexpVal)) k: String -> (Option String)
  (mt (kvGet kv k)
    ((some val) (mt val ((valStr s) (some s)) ((valFlag _) (none)) ((valList _) (none))))
    ((none) (none)))

fn validPlanIdChar? c: String -> Bool
  (or (c/isWordByte c)
    (or (= c "-") (= c ".")))

fn validPlanIdChars? s: String n: Int64 i: Int64 -> Bool
  (if (>= i n)
    true
    (if (validPlanIdChar? (c/ch s i))
      (validPlanIdChars? s n (+ i 1))
      false))

fn validPlanId? s: String -> Bool
  (let [n (stringLength s)]
    (and (>= n 1)
      (and (<= n 32)
        (validPlanIdChars? s n 0))))

fn isStepForm items: (List SexpNode) -> Bool
  (mt (listHead items)
    ((some node) (mt node ((sexpAtom a) (= a ":step")) ((sexpStr _) false) ((sexpList _) false)))
    (none false))

fn planStepsLoop nodes: (List SexpNode) acc: (List Step) -> (Result (List Step) String)
  (if (listEmpty? nodes)
    (if (listEmpty? acc)
      (err "a plan holds at least one (:step :id s :do s :check s)")
      (if (> (listLength acc) 20)
        (err "a plan holds at most 20 steps")
        (ok (listReverse acc))))
    (let [node (c/firstOf nodes)
          restNodes (c/restOf nodes)]
      (mt node
        ((sexpList items)
          (if (not (isStepForm items))
            (err "each plan item is (:step :id s :do s :check s)")
            (let [fields (planFields items)
                  kv (pairFirst fields)
                  sidOpt (kvGetStr kv "id")
                  doOpt (kvGetStr kv "do")
                  chkVal (kvGet kv "check")]
              (mt sidOpt
                ((none) (err "a step :id is 1 to 32 letters, digits, '_', '.' or '-'"))
                ((some sid)
                  (if (not (validPlanId? sid))
                    (err "a step :id is 1 to 32 letters, digits, '_', '.' or '-'")
                    (mt doOpt
                      ((none) (err (str "step " sid " needs :do s, and :check is a string")))
                      ((some doText)
                        (if (stringEmpty? (stringTrim doText))
                          (err (str "step " sid " needs :do s, and :check is a string"))
                          (let [chkText (mt chkVal
                                          ((none) (some ""))
                                          ((some val) (mt val ((valStr s) (some s)) ((valFlag _) (none)) ((valList _) (none)))))]
                            (mt chkText
                              ((none) (err (str "step " sid " needs :do s, and :check is a string")))
                              ((some checkStr)
                                (if (or (> (listLength (stringChars doText)) 300) (> (listLength (stringChars checkStr)) 300))
                                  (err (str "step " sid ": :do and :check are at most 300 chars each"))
                                  (if (listAny? (fn [s] (= (stepId s) sid)) acc)
                                    (err (str "step id " sid " appears twice"))
                                    (planStepsLoop restNodes (cons (stepOf sid doText checkStr) acc))))))))))))))))
        ((sexpAtom _) (err "each plan item is (:step :id s :do s :check s)"))
        ((sexpStr _) (err "each plan item is (:step :id s :do s :check s)")))))

fn planSteps nodes: (List SexpNode) -> (Result (List Step) String)
  (planStepsLoop nodes (list))

fn planOpen plan: Plan -> (List String)
  (let [doneMap (planDone plan)
        dropMap (planDropped plan)]
    (filter (fn [id] (and (not (mapHas? doneMap id)) (not (mapHas? dropMap id))))
      (map stepId (planStepList plan))))

fn planWithCurrent p: Plan cur: (Option String) since: Int64 -> Plan
  (planOf (planOn p) (planStepList p) (planDone p) (planDropped p) (planRevisions p) cur since (planNudgeTurn p))

fn planAdvance plan: Plan turn: Int64 -> Plan
  (let [openIds (planOpen plan)
        cur (listHead openIds)]
    (if (= cur (planCurrent plan))
      plan
      (planWithCurrent plan cur turn)))

fn stepForm s: Step -> String
  (let [base (str "(:step :id " (stepId s) " :do \"" (c/escapeAsn (stepDoText s)) "\"")
        chk (stepCheckText s)]
    (if (stringEmpty? chk)
      (str base ")")
      (str base " :check \"" (c/escapeAsn chk) "\")")))

fn planSlot plan: Plan -> String
  (if (listEmpty? (planStepList plan))
    ""
    (str "(:plan " (c/joinSep (map stepForm (planStepList plan)) " ") ")"))

fn maxInt a: Int64 b: Int64 -> Int64
  (if (> a b) a b)

fn planNow plan: Plan turn: Int64 -> String
  (if (listEmpty? (planStepList plan))
    (mt (planNudgeTurn plan)
      ((some n) (if (= n turn)
                  "(:missing \"no plan yet: add (:plan (:step :id s1 :do s :check s) ...) beside your next steps\")"
                  "(:none)"))
      ((none) "(:none)"))
    (let [doneIds (filter (fn [s] (mapHas? (planDone plan) (stepId s))) (planStepList plan))
          droppedIds (filter (fn [s] (mapHas? (planDropped plan) (stepId s))) (planStepList plan))
          doneStr (c/joinSep (map stepId doneIds) " ")
          droppedStr (c/joinSep (map stepId droppedIds) " ")
          where (mt (planCurrent plan)
                  ((some cur)
                    (str ":current " cur " :turnsOnCurrent " (stringFromInt64 (maxInt 0 (- (- turn 1) (planSince plan))))))
                  ((none) ":allReconciled true"))
          droppedPart (if (stringEmpty? droppedStr) "" (str " :dropped (" droppedStr ")"))]
      (str "(:done (" doneStr ")" droppedPart " " where ")")))

fn planSummary plan: Plan -> PlanSummary
  (summaryOf (listLength (planStepList plan))
             (mapSize (planDone plan))
             (mapSize (planDropped plan))
             (planRevisions plan))

fn planField summary: PlanSummary -> String
  (str " :plan (:steps " (stringFromInt64 (summarySteps summary))
       " :done " (stringFromInt64 (summaryDone summary))
       " :dropped " (stringFromInt64 (summaryDropped summary))
       " :revisions " (stringFromInt64 (summaryRevisions summary)) ")")

fn isPlanOp op: String -> Bool
  (or (= op "plan") (or (= op "planDone") (= op "planDrop")))

fn planEvidenceIds receipts: (List Receipt) -> (List String)
  (let [valid (filter (fn [r]
                        (and (not (stringEmpty? (receiptId r)))
                             (and (not (isPlanOp (receiptOp r)))
                                  (not (= (receiptStatus r) "rejected")))))
                      receipts)]
    (fold (fn [acc r]
            (let [rid (receiptId r)]
              (if (listContains? acc rid) acc (listAppend acc (list rid)))))
          (list) valid))

fn rejectedResult rid: String name: String errCode: String why: String plan: Plan -> StepResult
  (stepResult "rejected" name why errCode (none) plan)

fn okResult rid: String name: String msg: String entry: String plan: Plan -> StepResult
  (stepResult "ok" name msg "" (some entry) plan)

fn removeAllDropped dropped: (Map String String) steps: (List Step) -> (Map String String)
  (fold (fn [d s] (mapRemove d (stepId s))) dropped steps)

fn planStep plan: Plan opName: String opForm: String rid: String evidenceIds: (List String) -> StepResult
  (mt (planTree opForm)
    ((err e) (rejectedResult rid opName "ERR_PARSE" (str "the " opName " form does not parse: " e) plan))
    ((ok tree)
      (if (not (= (listLength tree) 1))
        (rejectedResult rid opName "ERR_PARSE" (str "one (" opName " ...) form is expected") plan)
        (mt (c/firstOf tree)
          ((sexpList formItems)
            (let [fields (planFields formItems)
                  kv (pairFirst fields)
                  lists (pairSecond fields)
                  ids (map stepId (planStepList plan))]
              (cond
                ((= opName "plan")
                  (let [revise (kvHas kv "revise")
                        why (optionOr (kvGetStr kv "why") "")]
                    (cond
                      ((and revise (listEmpty? (planStepList plan)))
                        (rejectedResult rid opName "ERR_PLAN_NONE" "no plan to revise; set one with (:plan (:step :id s1 :do s :check s) ...)" plan))
                      ((and (not revise) (not (listEmpty? (planStepList plan))))
                        (rejectedResult rid opName "ERR_PLAN_SET" "a plan is set; change it with (:plan :revise ((:step ...) ...) :why s)" plan))
                      ((and revise (stringEmpty? (stringTrim why)))
                        (rejectedResult rid opName "ERR_MISSING_ARG" "a revision needs :why s" plan))
                      (else
                        (let [givenVal (kvGet kv "revise")
                              nodes (if (not revise)
                                      (map (fn [l] (sexpList l)) lists)
                                      (mt givenVal
                                        ((some val)
                                          (mt val
                                            ((valList gList)
                                              (if (isStepForm gList)
                                                (cons (sexpList gList) (map (fn [l] (sexpList l)) lists))
                                                gList))
                                            ((valStr s) (list (sexpStr s)))
                                            ((valFlag _) (list (sexpAtom "flag")))))
                                        ((none) (list))))]
                          (mt (planSteps nodes)
                            ((err e) (rejectedResult rid opName "ERR_INVALID_ARG" e plan))
                            ((ok parsedSteps)
                              (if revise
                                (let [doneSteps (filter (fn [s] (mapHas? (planDone plan) (stepId s))) (planStepList plan))
                                      notDoneParsed (filter (fn [s] (not (mapHas? (planDone plan) (stepId s)))) parsedSteps)
                                      newSteps (listAppend doneSteps notDoneParsed)]
                                  (if (> (listLength newSteps) 20)
                                    (rejectedResult rid opName "ERR_INVALID_ARG" "a plan holds at most 20 steps, done ones included" plan)
                                    (let [newDropped (removeAllDropped (planDropped plan) newSteps)
                                          newRevs (+ (planRevisions plan) 1)
                                          newPlan (planOf (planOn plan) newSteps (planDone plan) newDropped newRevs (planCurrent plan) (planSince plan) (planNudgeTurn plan))
                                          entry (str ":planRevise :why \"" (c/escapeAsn why) "\" :steps (" (c/joinSep (map stepForm newSteps) " ") ")")
                                          msg (str "plan revised: " (stringFromInt64 (listLength newSteps)) " steps")]
                                      (okResult rid opName msg entry newPlan))))
                                (let [newPlan (planOf (planOn plan) parsedSteps (planDone plan) (planDropped plan) (planRevisions plan) (planCurrent plan) (planSince plan) (planNudgeTurn plan))
                                      entry (str ":plan (" (c/joinSep (map stepForm parsedSteps) " ") ")")
                                      msg (str "plan set: " (stringFromInt64 (listLength parsedSteps)) " steps")]
                                  (okResult rid opName msg entry newPlan))))))))))

                ((listEmpty? (planStepList plan))
                  (rejectedResult rid opName "ERR_PLAN_NONE" "no plan yet; set one with (:plan (:step :id s1 :do s :check s) ...)" plan))

                ((not (listContains? ids (optionOr (kvGetStr kv "id") "")))
                  (rejectedResult rid opName "ERR_PLAN_STEP" (str "no step " (optionOr (kvGetStr kv "id") "") "; the steps are " (c/joinSep ids " ")) plan))

                ((= opName "planDone")
                  (let [sid (optionOr (kvGetStr kv "id") "")
                        ev (optionOr (kvGetStr kv "ev") "")]
                    (if (or (stringEmpty? ev) (not (listContains? evidenceIds ev)))
                      (rejectedResult rid opName "ERR_PLAN_EV" (str ":ev " ev " is no receipt :id of this run; cite the :id of a receipt that shows the step's :check") plan)
                      (let [newDropped (mapRemove (planDropped plan) sid)
                            newDone (mapSet (planDone plan) sid ev)
                            newPlan (planOf (planOn plan) (planStepList plan) newDone newDropped (planRevisions plan) (planCurrent plan) (planSince plan) (planNudgeTurn plan))
                            entry (str ":planDone :id " sid " :ev \"" (c/escapeAsn ev) "\"")
                            msg (str sid " done")]
                        (okResult rid opName msg entry newPlan)))))

                ((= opName "planDrop")
                  (let [sid (optionOr (kvGetStr kv "id") "")
                        why (optionOr (kvGetStr kv "why") "")]
                    (cond
                      ((stringEmpty? (stringTrim why))
                        (rejectedResult rid opName "ERR_MISSING_ARG" "a drop needs :why s" plan))
                      ((mapHas? (planDone plan) sid)
                        (rejectedResult rid opName "ERR_PLAN_STEP" (str sid " is done; a done step is not dropped") plan))
                      (else
                        (let [newDropped (mapSet (planDropped plan) sid why)
                              newPlan (planOf (planOn plan) (planStepList plan) (planDone plan) newDropped (planRevisions plan) (planCurrent plan) (planSince plan) (planNudgeTurn plan))
                              entry (str ":planDrop :id " sid " :why \"" (c/escapeAsn why) "\"")
                              msg (str sid " dropped")]
                          (okResult rid opName msg entry newPlan))))))

                (else (rejectedResult rid opName "ERR_UNKNOWN_OP" (str "unknown plan op: " opName) plan)))))
          ((sexpAtom _) (rejectedResult rid opName "ERR_PARSE" (str "one (" opName " ...) form is expected") plan))
          ((sexpStr _) (rejectedResult rid opName "ERR_PARSE" (str "one (" opName " ...) form is expected") plan))))))

fn serPlanState p: Plan -> String
  (str "(:planState :on " (if (planOn p) "true" "false")
       " :current " (c/serString (optionOr (planCurrent p) ""))
       " :since " (stringFromInt64 (planSince p))
       " :revisions " (stringFromInt64 (planRevisions p))
       " :nudgeTurn " (stringFromInt64 (optionOr (planNudgeTurn p) -1))
       " :steps (" (c/joinSep (map (fn [s] (str "(:step :id " (stepId s) " :do " (c/serString (stepDoText s)) " :check " (c/serString (stepCheckText s)) ")")) (planStepList p)) " ") ")"
       " :done (" (c/joinSep (map (fn [pr] (mt pr ((pair k v) (str "(:done :id " k " :ev " (c/serString v) ")")))) (mapPairs (planDone p))) " ") ")"
       " :dropped (" (c/joinSep (map (fn [pr] (mt pr ((pair k v) (str "(:dropped :id " k " :why " (c/serString v) ")")))) (mapPairs (planDropped p))) " ") ")"
       ")")

fn extractStep node: SexpNode -> (Option Step)
  (mt node
    ((sexpList items)
      (let [fields (planFields items)
            kv (pairFirst fields)]
        (mt (kvGetStr kv "id")
          ((some sid)
            (some (stepOf sid (optionOr (kvGetStr kv "do") "") (optionOr (kvGetStr kv "check") ""))))
          ((none) (none)))))
    ((sexpAtom _) (none))
    ((sexpStr _) (none)))

fn extractPair node: SexpNode valKey: String -> (Option (Pair String String))
  (mt node
    ((sexpList items)
      (let [fields (planFields items)
            kv (pairFirst fields)]
        (mt (kvGetStr kv "id")
          ((some sid)
            (some (pair sid (optionOr (kvGetStr kv valKey) ""))))
          ((none) (none)))))
    ((sexpAtom _) (none))
    ((sexpStr _) (none)))

fn parsePlanState text: String -> Plan
  (mt (planTree text)
    ((err e) (do (assert false (str "parsePlanState: " e)) (newPlan false)))
    ((ok tree)
      (if (listEmpty? tree)
        (do (assert false "parsePlanState: empty tree") (newPlan false))
        (mt (c/firstOf tree)
          ((sexpList items)
            (let [fields (planFields items)
                  kv (pairFirst fields)
                  onVal (mt (kvGet kv "on") ((some v) (mt v ((valFlag b) b) ((valStr s) (= s "true")) ((valList _) false))) ((none) true))
                  curStr (optionOr (kvGetStr kv "current") "")
                  current (if (stringEmpty? curStr) (none) (some curStr))
                  since (optionOr (stringToInt64 (optionOr (kvGetStr kv "since") "0")) 0)
                  revs (optionOr (stringToInt64 (optionOr (kvGetStr kv "revisions") "0")) 0)
                  nudgeNum (optionOr (stringToInt64 (optionOr (kvGetStr kv "nudgeTurn") "-1")) -1)
                  nudgeTurn (if (< nudgeNum 0) (none) (some nudgeNum))
                  stepsNodes (mt (kvGet kv "steps") ((some v) (mt v ((valList lst) lst) ((valStr _) (list)) ((valFlag _) (list)))) ((none) (list)))
                  doneNodes (mt (kvGet kv "done") ((some v) (mt v ((valList lst) lst) ((valStr _) (list)) ((valFlag _) (list)))) ((none) (list)))
                  droppedNodes (mt (kvGet kv "dropped") ((some v) (mt v ((valList lst) lst) ((valStr _) (list)) ((valFlag _) (list)))) ((none) (list)))
                  steps (fold (fn [acc n] (mt (extractStep n) ((some s) (listAppend acc (list s))) ((none) acc))) (list) stepsNodes)
                  donePairs (fold (fn [acc n] (mt (extractPair n "ev") ((some p) (listAppend acc (list p))) ((none) acc))) (list) doneNodes)
                  droppedPairs (fold (fn [acc n] (mt (extractPair n "why") ((some p) (listAppend acc (list p))) ((none) acc))) (list) droppedNodes)]
              (planOf onVal steps (mapFromPairs donePairs) (mapFromPairs droppedPairs) revs current since nudgeTurn)))
          ((sexpAtom _) (do (assert false "parsePlanState: expected list") (newPlan false)))
          ((sexpStr _) (do (assert false "parsePlanState: expected list") (newPlan false)))))))

fn parseTurnLine line: String -> (Option (Pair Int64 (Pair String (List (Pair String SexpVal)))))
  (if (not (stringStartsWith? line "(:turn "))
    (none)
    (let [sp1 (stringIndexOf line " ")]
      (mt sp1
        ((none) (none))
        ((some idx1)
          (let [rem (c/sliceOf line (+ idx1 1) (stringLength line))
                sp2 (stringIndexOf rem " ")]
            (mt sp2
              ((none) (none))
              ((some idx2)
                (let [turnStr (c/sliceOf rem 0 idx2)
                      turnNum (optionOr (stringToInt64 turnStr) -1)
                      rem2 (c/sliceOf rem (+ idx2 1) (stringLength rem))
                      sp3 (stringIndexOf rem2 " ")]
                  (mt sp3
                    ((none) (none))
                    ((some idx3)
                      (let [kindStr (c/sliceOf rem2 0 idx3)]
                        (if (or (< turnNum 0) (not (stringStartsWith? kindStr ":")))
                          (none)
                          (let [kind (c/sliceOf kindStr 1 (stringLength kindStr))]
                            (mt (planTree line)
                              ((err _) (none))
                              ((ok tree)
                                (if (listEmpty? tree)
                                  (none)
                                  (mt (c/firstOf tree)
                                    ((sexpList items)
                                      (let [fields (planFields items)]
                                        (some (pair turnNum (pair kind (pairFirst fields))))))
                                    ((sexpAtom _) (none))
                                    ((sexpStr _) (none)))))))))))))))))))

fn planReplayLoop lines: (List String) plan: Plan -> Plan
  (if (listEmpty? lines)
    plan
    (let [line (c/firstOf lines)
          restLines (c/restOf lines)]
      (mt (parseTurnLine line)
        ((none) (planReplayLoop restLines plan))
        ((some turnInfo)
          (mt turnInfo
            ((pair turn restInfo)
              (mt restInfo
                ((pair kind kv)
                  (cond
                ((or (= kind "plan") (= kind "planRevise"))
                  (let [rawVal (if (= kind "plan") (kvGet kv "plan") (kvGet kv "steps"))
                        nodes (mt rawVal ((some v) (mt v ((valList lst) lst) ((valStr _) (list)) ((valFlag _) (list)))) ((none) (list)))]
                    (mt (planSteps nodes)
                      ((err _) (planReplayLoop restLines plan))
                      ((ok steps)
                        (let [newDropped (removeAllDropped (planDropped plan) steps)
                              newRevs (+ (planRevisions plan) (if (= kind "planRevise") 1 0))
                              newPlan (planOf (planOn plan) steps (planDone plan) newDropped newRevs (planCurrent plan) (planSince plan) (planNudgeTurn plan))
                              advPlan (planAdvance newPlan turn)]
                          (planReplayLoop restLines advPlan))))))

                ((= kind "planDone")
                  (let [sid (optionOr (kvGetStr kv "id") "")
                        ev (kvGetStr kv "ev")]
                    (mt ev
                      ((none) (planReplayLoop restLines (planAdvance plan turn)))
                      ((some evStr)
                        (let [newDropped (mapRemove (planDropped plan) sid)
                              newDone (mapSet (planDone plan) sid evStr)
                              newPlan (planOf (planOn plan) (planStepList plan) newDone newDropped (planRevisions plan) (planCurrent plan) (planSince plan) (planNudgeTurn plan))
                              advPlan (planAdvance newPlan turn)]
                          (planReplayLoop restLines advPlan))))))

                ((= kind "planDrop")
                  (let [sid (optionOr (kvGetStr kv "id") "")
                        why (optionOr (kvGetStr kv "why") "")]
                    (if (stringEmpty? sid)
                      (planReplayLoop restLines plan)
                      (let [newDropped (mapSet (planDropped plan) sid why)
                            newPlan (planOf (planOn plan) (planStepList plan) (planDone plan) newDropped (planRevisions plan) (planCurrent plan) (planSince plan) (planNudgeTurn plan))
                            advPlan (planAdvance newPlan turn)]
                        (planReplayLoop restLines advPlan)))))

                (else (planReplayLoop restLines plan)))))))))))

fn planReplay journalText: String -> Plan
  (planReplayLoop (stringLines journalText) (newPlan true))
