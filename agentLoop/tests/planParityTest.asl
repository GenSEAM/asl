(module asl/agentLoop/tests/planParityTest
  :x [runTests]
  :i [(asl/agentLoop/plan :a p) (asl/agentLoop/core :a c)])

fn getKvStr kv: (List (Pair String c/KvVal)) k: String -> String
  (mt (c/dictGet kv k)
    ((some v) (mt v ((c/kvStr s) s) ((c/kvInt s) s)))
    (none ""))

fn getKvInt kv: (List (Pair String c/KvVal)) k: String -> Int64
  (mt (c/dictGet kv k)
    ((some v) (mt v ((c/kvInt s) (optionOr (stringToInt64 s) 0)) ((c/kvStr s) (optionOr (stringToInt64 s) 0))))
    (none 0))

fn serNode node: p/SexpNode -> String
  (mt node
    ((p/sexpAtom a) (str "(atom " (c/serString a) ")"))
    ((p/sexpStr s) (str "(str " (c/serString s) ")"))
    ((p/sexpList items) (str "(list" (c/joinAll (map (fn [it] (str " " (serNode it))) items)) ")")))

fn checkPlanStepCases -> Bool
  (let [p0 (p/newPlan true)
        res1 (p/planStep p0 "plan" "(:plan (:step :id s1 :do \"d1\" :check \"c1\") (:step :id s2 :do \"d2\"))" "r1" (list))]
    (mt res1
      ((p/stepResult st1 op1 msg1 err1 ent1 p1)
        (do
          (assert (= st1 "ok") "step_plan_init status ok")
          (assert (= msg1 "plan set: 2 steps") "step_plan_init message")
          (assert (= (optionOr ent1 "") ":plan ((:step :id s1 :do \"d1\" :check \"c1\") (:step :id s2 :do \"d2\"))") "step_plan_init entry")
          (let [res2 (p/planStep p1 "plan" "(:plan (:step :id s3 :do \"d3\"))" "r2" (list))]
            (mt res2
              ((p/stepResult st2 op2 msg2 err2 ent2 p2)
                (do
                  (assert (= st2 "rejected") "step_plan_already_set status")
                  (assert (= err2 "ERR_PLAN_SET") "step_plan_already_set error")
                  (let [res3 (p/planStep p1 "plan" "(:plan :revise ((:step :id s3 :do \"d3\")))" "r3" (list))]
                    (mt res3
                      ((p/stepResult st3 op3 msg3 err3 ent3 p3)
                        (do
                          (assert (= st3 "rejected") "step_plan_revise_no_why status")
                          (assert (= err3 "ERR_MISSING_ARG") "step_plan_revise_no_why error")
                          (let [res4 (p/planStep p1 "planDone" "(:planDone :id s1 :ev \"e1\")" "r4" (list "e1"))]
                            (mt res4
                              ((p/stepResult st4 op4 msg4 err4 ent4 p4)
                                (do
                                  (assert (= st4 "ok") "step_plan_done_ok status")
                                  (assert (= msg4 "s1 done") "step_plan_done_ok message")
                                  (assert (= (optionOr ent4 "") ":planDone :id s1 :ev \"e1\"") "step_plan_done_ok entry")
                                  (let [res5 (p/planStep p4 "planDone" "(:planDone :id s2 :ev \"fake\")" "r5" (list "e1"))]
                                    (mt res5
                                      ((p/stepResult st5 op5 msg5 err5 ent5 p5)
                                        (do
                                          (assert (= st5 "rejected") "step_plan_done_fake_ev status")
                                          (assert (= err5 "ERR_PLAN_EV") "step_plan_done_fake_ev error")
                                          (let [res6 (p/planStep p4 "planDrop" "(:planDrop :id s2 :why \"unneeded\")" "r6" (list))]
                                            (mt res6
                                              ((p/stepResult st6 op6 msg6 err6 ent6 p6)
                                                (do
                                                  (assert (= st6 "ok") "step_plan_drop_ok status")
                                                  (assert (= msg6 "s2 dropped") "step_plan_drop_ok message")
                                                  (assert (= (optionOr ent6 "") ":planDrop :id s2 :why \"unneeded\"") "step_plan_drop_ok entry")
                                                  (let [res7 (p/planStep p6 "planDrop" "(:planDrop :id s1 :why \"already done\")" "r7" (list))]
                                                    (mt res7
                                                      ((p/stepResult st7 op7 msg7 err7 ent7 p7)
                                                        (do
                                                          (assert (= st7 "rejected") "step_plan_drop_done status")
                                                          (assert (= err7 "ERR_PLAN_STEP") "step_plan_drop_done error")
                                                          (let [res8 (p/planStep p6 "plan" "(:plan :revise ((:step :id s3 :do \"d3\")) :why \"changed mind\")" "r8" (list))]
                                                            (mt res8
                                                              ((p/stepResult st8 op8 msg8 err8 ent8 p8)
                                                                (do
                                                                  (assert (= st8 "ok") "step_plan_revise_ok status")
                                                                  (assert (= msg8 "plan revised: 2 steps") "step_plan_revise_ok message")
                                                                  (assert (= (optionOr ent8 "") ":planRevise :why \"changed mind\" :steps ((:step :id s1 :do \"d1\" :check \"c1\") (:step :id s3 :do \"d3\"))") "step_plan_revise_ok entry")
                                                                  (assert (= (c/joinSep (map p/stepId (p/planStepList p8)) " ") "s1 s3") "step_plan_revise_ok step ids")
                                                                  (assert (= (p/planRevisions p8) 1) "step_plan_revise_ok revisions")
                                                                  true))))))))))))))))))))))))))))))))

fn checkCase line: String -> Bool
  (let [kv (c/parseKv line)
        cid (getKvStr kv "id")
        fnName (getKvStr kv "fn")
        input (getKvStr kv "input")
        want (getKvStr kv "want")
        status (getKvStr kv "status")]
    (cond
      ((= fnName "planTree")
        (mt (p/planTree input)
          ((ok _) (do (assert (= status "ok") (str cid " planTree should be ok")) true))
          ((err e) (do
                     (assert (= status "err") (str cid " planTree should be err"))
                     (assert (= e want) (str cid " error message should match"))
                     true))))

      ((= fnName "planFields")
        (mt (p/planTree input)
          ((ok tree)
            (let [items (mt (listHead tree)
                          ((some h) (mt h ((p/sexpList it) it) ((p/sexpAtom _) tree) ((p/sexpStr _) tree)))
                          (none (list)))
                  fields (p/planFields items)
                  kvField (pairFirst fields)
                  listsField (pairSecond fields)
                  got (str "(fields (kv"
                        (c/joinAll (map (fn [pr]
                                          (mt pr ((pair k val)
                                            (mt val
                                              ((p/valFlag b) (str " (" k " " (if b "true" "false") ")"))
                                              ((p/valStr s) (str " (" k " " (c/serString s) ")"))
                                              ((p/valList l) (str " (" k " (list" (c/joinAll (map (fn [n] (str " " (serNode n))) l)) "))"))))))
                                        kvField))
                        ") (lists"
                        (c/joinAll (map (fn [l] (str " (list" (c/joinAll (map (fn [n] (str " " (serNode n))) l)) ")")) listsField))
                        "))")]
              (do
                (assert (= status "ok") (str cid " planFields should be ok"))
                (assert (= got want) (str cid " fields should match"))
                true)))
          ((err _) (do (assert false (str cid " planTree failed for planFields input")) false))))

      ((= fnName "planSteps")
        (mt (p/planTree input)
          ((ok tree)
            (let [nodes (mt (listHead tree)
                          ((some h) (mt h ((p/sexpList items) (if (p/isStepForm items) tree items)) ((p/sexpAtom _) tree) ((p/sexpStr _) tree)))
                          (none (list)))]
              (mt (p/planSteps nodes)
                ((ok steps) (do
                              (assert (= status "ok") (str cid " planSteps should be ok"))
                              (assert (= (str "(" (c/joinSep (map p/stepForm steps) " ") ")") want) (str cid " steps should match"))
                              true))
                ((err e) (do
                           (assert (= status "err") (str cid " planSteps should be err"))
                           (assert (= e want) (str cid " error message should match"))
                           true)))))
          ((err _) (do (assert false (str cid " planTree failed for planSteps input")) false))))

      ((= fnName "planOpen")
        (let [plan (p/parsePlanState input)
              openIds (p/planOpen plan)
              got (c/joinSep openIds " ")]
          (do (assert (= got want) (str cid " planOpen should match want")) true)))

      ((= fnName "planAdvance")
        (let [plan (p/parsePlanState input)
              turn (getKvInt kv "turn")
              wantCur (getKvStr kv "wantCurrent")
              wantSince (getKvInt kv "wantSince")
              advanced (p/planAdvance plan turn)]
          (do
            (assert (= (optionOr (p/planCurrent advanced) "") wantCur) (str cid " current should match"))
            (assert (= (p/planSince advanced) wantSince) (str cid " since should match"))
            true)))

      ((= fnName "planSlot")
        (let [plan (p/parsePlanState input)
              slot (p/planSlot plan)]
          (do (assert (= slot want) (str cid " slot should match")) true)))

      ((= fnName "planNow")
        (let [plan (p/parsePlanState input)
              turn (getKvInt kv "turn")
              now (p/planNow plan turn)]
          (do (assert (= now want) (str cid " planNow should match")) true)))

      ((= fnName "planSummary")
        (let [plan (p/parsePlanState input)
              s (p/planSummary plan)
              got (str (stringFromInt64 (p/summarySteps s)) " "
                       (stringFromInt64 (p/summaryDone s)) " "
                       (stringFromInt64 (p/summaryDropped s)) " "
                       (stringFromInt64 (p/summaryRevisions s)))]
          (do (assert (= got want) (str cid " summary should match")) true)))

      ((= fnName "planField")
        (let [steps (getKvInt kv "steps")
              done (getKvInt kv "done")
              dropped (getKvInt kv "dropped")
              revs (getKvInt kv "revisions")
              s (p/summaryOf steps done dropped revs)
              got (p/planField s)]
          (do (assert (= got want) (str cid " planField should match")) true)))

      ((= fnName "planEvidenceIds")
        (let [receipts (list (p/makeReceipt "e1" "read" "ok")
                             (p/makeReceipt "e2" "plan" "ok")
                             (p/makeReceipt "e3" "planDone" "ok")
                             (p/makeReceipt "e4" "read" "rejected")
                             (p/makeReceipt "e5" "write" "ok"))
              got (c/joinSep (p/planEvidenceIds receipts) " ")]
          (do (assert (= got want) (str cid " evidenceIds should match")) true)))

      ((= fnName "planStep")
        (let [planInput (getKvStr kv "plan")
              plan (if (stringEmpty? planInput) (p/newPlan true) (p/parsePlanState planInput))
              opName (getKvStr kv "op")
              opForm (getKvStr kv "form")
              evStr (getKvStr kv "evidenceIds")
              evIds (if (stringEmpty? (stringTrim evStr)) (list) (filter (fn [s] (not (stringEmpty? s))) (stringSplit (stringTrim evStr) " ")))
              res (p/planStep plan opName opForm "r1" evIds)]
          (mt res
            ((p/stepResult st op msg err ent newP)
              (do
                (assert (= st status) (str cid " status"))
                (assert (= msg (getKvStr kv "msg")) (str cid " msg"))
                (if (= status "ok")
                  (do
                    (assert (= (optionOr ent "") (getKvStr kv "entry")) (str cid " entry"))
                    (if (not (stringEmpty? (getKvStr kv "steps")))
                      (do (assert (= (c/joinSep (map p/stepId (p/planStepList newP)) " ") (getKvStr kv "steps")) (str cid " steps")) true)
                      true)
                    (if (> (getKvInt kv "revs") 0)
                      (do (assert (= (p/planRevisions newP) (getKvInt kv "revs")) (str cid " revs")) true)
                      true)
                    true)
                  (do
                    (assert (= err (getKvStr kv "err")) (str cid " err"))
                    true)))))))

      ((= fnName "planReplay")
        (let [plan (p/planReplay input)
              stepsGot (c/joinSep (map p/stepId (p/planStepList plan)) " ")
              nowTurn (getKvInt kv "nowTurn")
              turnNum (if (> nowTurn 0) nowTurn 5)
              nowResult (p/planNow plan turnNum)
              wantNow (let [n (getKvStr kv "now")] (if (stringEmpty? n) (getKvStr kv "now5") n))]
          (do
            (assert (= stepsGot (getKvStr kv "steps")) (str cid " replay steps match"))
            (assert (= (p/planRevisions plan) (getKvInt kv "revisions")) (str cid " replay revisions match"))
            (assert (= nowResult wantNow) (str cid " replay now match"))
            true)))

      (else true)))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        content (resultOr (fileReadString (str root "/asl/agentLoop/tests/planParityFixture.asn")) "")
        lines (filter (fn [l] (stringStartsWith? l "(:case ")) (stringLines content))
        n (listLength lines)]
    (do
      (assert (>= n 15) "the parity fixture holds at least 15 cases")
      (assert (checkPlanStepCases) "planStep cases passed")
      (fold (fn [acc line] (and (checkCase line) acc)) true lines)))
