(module asl/agentLoop/turn
  :x [TurnReply turnReply vendorRetryPause cutRestored]
  :i [(asl/agentLoop/reply :a r) (asl/agentLoop/core :a c) (asl/agentLoop/retry :a rt)])

(schema TurnReply
  (:f text String)
  (:f preBindText String)
  (:f degenerateAt (Option Int64))
  (:f degenerateRepeats Int64)
  (:f capBytes Int64)
  (:f rawBlocks Int64)
  (:f missingRaw (List String))
  (:f unfenced Int64)
  (:f facts r/ReplyFacts)
  (:f repair (Option r/AutoRepair)))

fn fenceCount s: String i: Int64 -> Int64
  (mt (stringIndexOf (optionOr (stringSlice s i (stringLength s)) "") "```")
    ((some at) (+ 1 (fenceCount s (+ i at 3))))
    ((none) 0))

fn vendorRetryPause errorCode: String retryCount: Int64 configured: (List Int64) budgetLeft: (Option Int64) -> Int64
  (let [transient (listContains? (list "ERR_VENDOR" "ERR_QUEUE_TIMEOUT" "ERR_GATEWAY_OFFLINE") errorCode)
        slot (min retryCount (listLength configured))
        pause (if (and transient (> slot 0)) (optionOr (listGet configured (- slot 1)) 0) 0)]
    (mt budgetLeft ((some left) (max 0 (min pause left))) ((none) pause)))

fn cutRestored cut: (Option r/CutInfo) parsedCut: (Option r/CutInfo) spans: (Option (List (Pair Int64 Int64))) -> Bool
  (and (not (some? parsedCut))
    (mt cut
      ((some ci)
        (mt spans
          ((some xs)
            (listAny? (fn [sp]
              (mt sp ((pair a b) (and (<= a ci.start) (< ci.start b))))) xs))
          ((none) false)))
      ((none) false)))

fn turnReply reply: String declared: (Option (List String)) -> TurnReply
  (let [deg (r/degenerateCut reply)
        cut (mt deg ((some p) (pairFirst p)) ((none) (stringLength reply)))
        kept (optionOr (stringSlice reply 0 cut) "")
        capped (r/capReply kept)
        capText (pairFirst capped)
        bound (r/bindRawBlocks capText)
        unraw bound.text
        fences (/ (fenceCount unraw 0) 2)
        plain (r/unfence unraw)
        facts0 (r/replyFacts plain declared)
        hasOps (not (listEmpty? facts0.ops))
        otherDefect (or (some? facts0.cut) (some? (r/locateParseFailure plain)) (r/hasUnclosedForm plain))
        ; (:m :ref PROSE-THRESHOLD :do "ops already parse and nothing else is wrong, but text outside the final forms is left over; strip it rather than refuse on isProseWrapped's coarser 40-word/``` floor")
        proseOnly (and (not otherDefect) hasOps (c/hasFormResidue plain))
        shouldRepair (or otherDefect (and facts0.prose hasOps) proseOnly)
        proseRepair (if proseOnly
                      (some (r/AutoRepair :text (c/joinForms plain)
                              :notice (some (str "(:repaired (:prose " (stringFromInt64 (c/residueWordCount plain)) ") :left ())"))
                              :kinds (list "prose") :left 0 :quoteCount 0 :leftSpans none))
                      none)
        repaired (mt proseRepair ((some a) proseRepair) ((none) (if shouldRepair (some (r/autoRepairReply plain)) none)))
        finalText (mt repaired ((some a) (if (stringEmpty? a.text) plain a.text)) ((none) plain))
        facts (mt repaired
          ((some a)
            (let [parsed (if (stringEmpty? a.text) facts0 (r/replyFacts finalText declared))
                  oldCut facts0.cut]
              (if (and (some? oldCut) (cutRestored oldCut parsed.cut a.leftSpans))
                (r/ReplyFacts :ops parsed.ops :repeated parsed.repeated :forms parsed.forms
                              :prose parsed.prose :dataFindings parsed.dataFindings :cut oldCut)
                parsed)))
          ((none) facts0))]
    (TurnReply :text finalText :preBindText capText :degenerateAt (mt deg ((some p) (some (pairFirst p))) ((none) none))
               :degenerateRepeats (mt deg ((some p) (pairSecond p)) ((none) 0))
               :capBytes (pairSecond capped) :rawBlocks bound.count
               :missingRaw (map (fn [p] (str (pairFirst p) " " (pairSecond p))) bound.missing)
               :unfenced fences :facts facts :repair repaired))
