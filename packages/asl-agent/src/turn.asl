(module aslAgent/turn
  :x [TurnReply turnReply vendorRetryPause cutRestored moduleWrite]
  :i [(aslAgent/reply :a r) (aslAgent/core :a c) (aslAgent/retry :a rt) (aslAgent/toolCalls :a tc)])

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
  (:f repair (Option r/AutoRepair))
  (:f shapeRepaired (List String))
  (:f shapeLeft (List String)))

fn fenceCount s: String i: Int64 -> Int64
  (match (stringIndexOf (optionOr (stringSlice s i (stringLength s)) "") "```")
    ((some at) (+ 1 (fenceCount s (+ i at 3))))
    ((none) 0))

fn vendorRetryPause errorCode: String retryCount: Int64 configured: (List Int64) budgetLeft: (Option Int64) -> Int64
  (let [transient (listContains? (list "ERR_VENDOR" "ERR_QUEUE_TIMEOUT" "ERR_GATEWAY_OFFLINE") errorCode)
        slot (min retryCount (listLength configured))
        pause (if (and transient (> slot 0)) (optionOr (listGet configured (- slot 1)) 0) 0)]
    (match budgetLeft ((some left) (max 0 (min pause left))) ((none) pause)))

fn cutRestored cut: (Option r/CutInfo) parsedCut: (Option r/CutInfo) spans: (Option (List (Pair Int64 Int64))) -> Bool
  (and (not (some? parsedCut))
    (match cut
      ((some ci)
        (match spans
          ((some xs)
            (listAny? (fn [sp]
              (match sp ((pair a b) (and (<= a ci.start) (< ci.start b))))) xs))
          ((none) false)))
      ((none) false)))

fn dropThink text: String -> String
  (match (stringIndexOf text "<think>")
    ((none) text)
    ((some a)
      (let [rest (optionOr (stringSlice text (+ a 7) (stringLength text)) "")]
        (match (stringIndexOf rest "</think>")
          ((none) text)
          ((some b) (dropThink (str (optionOr (stringSlice text 0 a) "") (optionOr (stringSlice rest (+ b 8) (stringLength rest)) ""))))))))

; (:m :ref ABSORB-AGENT-LOWS :do "the layout form keeps an ERR_ code the model copied into its reply as :error, so exec still marks the refusal :echoed and the copied code is not counted as a new attempt")
fn echoedError reply: String -> String
  (match (stringIndexOf reply ":error \"ERR_")
    ((some at) (let [rest (c/sliceOf reply (+ at 8) (stringLength reply))] (match (stringIndexOf rest "\"") ((some e) (c/sliceOf rest 0 e)) ((none) ""))))
    ((none) ""))

fn layoutForm op: String file: String echo: String -> String
  (str "(:step :op \"" (if (= op "edit") "edit" "write") "\" :file \"" (c/escapeAsn file) "\" " (if (= op "edit") ":old :raw :new :raw" ":content :raw") (if (stringEmpty? echo) "" (str " :error \"" echo "\"")) ")")

fn turnReply reply0: String declared: (Option (List String)) -> TurnReply
  (let [reply (dropThink (pairFirst (tc/untagToolCalls reply0)))
        deg (r/degenerateCut reply)
        cut (match deg ((some p) (pairFirst p)) ((none) (stringLength reply)))
        kept (optionOr (stringSlice reply 0 cut) "")
        capped (r/capReply kept)
        capText (pairFirst capped)
        bound (r/bindRawBlocks capText)
        unraw bound.text
        fences (/ (fenceCount unraw 0) 2)
        ; (:m :ref LEON-WRITE-FAIL-TOP :do "step shapes are made canonical after raw blocks are bound and fences dropped, so written content already sits in strings the scan skips")
        shape (tc/canonSteps (r/unfence unraw))
        ; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "a reply whose raw blocks do not bind whole runs none of its steps: it is read as the first unbound write or edit alone, still with its :raw field, so exec answers one ERR_RAW_MISSING with the canonical layout and nothing else in the reply is executed (grader 2026-11-18: a step beside one whose block was refused ran with a neighbour's content)")
        plain (match (listHead bound.missing) ((some m) (layoutForm (pairFirst m) (pairSecond m) (echoedError capText))) ((none) shape.text))
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
        repaired (match proseRepair ((some a) proseRepair) ((none) (if shouldRepair (some (r/autoRepairReply plain)) none)))
        finalText (match repaired ((some a) (if (stringEmpty? a.text) plain a.text)) ((none) plain))
        facts (match repaired
          ((some a)
            (let [parsed (if (stringEmpty? a.text) facts0 (r/replyFacts finalText declared))
                  oldCut facts0.cut]
              (if (and (some? oldCut) (cutRestored oldCut parsed.cut a.leftSpans))
                (r/ReplyFacts :ops parsed.ops :repeated parsed.repeated :forms parsed.forms
                              :prose parsed.prose :dataFindings parsed.dataFindings :cut oldCut)
                parsed)))
          ((none) facts0))]
    (TurnReply :text finalText :preBindText capText :degenerateAt (match deg ((some p) (some (pairFirst p))) ((none) none))
               :degenerateRepeats (match deg ((some p) (pairSecond p)) ((none) 0))
               :capBytes (pairSecond capped) :rawBlocks bound.count
               :missingRaw (map (fn [p] (str (pairFirst p) " " (pairSecond p))) bound.missing)
               :unfenced fences :facts facts :repair repaired
               :shapeRepaired shape.repaired :shapeLeft shape.left))

fn baseName path: String -> String
  (let [last (optionOr (listLast (stringSplit path "/")) path)]
    (if (stringEndsWith? last ".asl") (c/sliceOf last 0 (- (stringLength last) 4)) last))

fn testsPath? s: String -> Bool
  (listContains? (stringSplit s "/") "tests")

fn plainPath? p: String -> Bool
  (not (listAny? (fn [x] (stringContains? p x)) (list "*" "?" "[" "{")))

fn unwrapFence t: String -> String
  (let [lines (stringSplit t "\n") n (listLength lines)]
    (if (and (>= n 3) (and (stringStartsWith? (optionOr (listHead lines) "") "```") (= (stringTrim (optionOr (listLast lines) "")) "```")))
      (stringJoin (optionOr (listSlice lines 1 (- n 1)) (list)) "\n")
      t))

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "a reply that is only the text of an .asl file, (module NAME ...) with no step around it, is the write of the one plain .asl file the session owns when NAME maps to that path without doubt: its last segment is the file's base name and both or neither are tests; otherwise none and the reply is answered as before (node2 2026-11-17, whole files sent bare)")
fn moduleWrite reply: String owns: (List String) -> (Option (List (Pair String c/KvVal)))
  (let [text (stringTrim (unwrapFence (stringTrim reply)))
        files (filter (fn [p] (and (plainPath? p) (stringEndsWith? p ".asl"))) owns)
        head (optionOr (listHead (stringSplit text "\n")) "")
        name (optionOr (listGet (stringSplit (stringTrim head) " ") 1) "")
        file (optionOr (listHead files) "")]
    (if (and (stringStartsWith? text "(module ")
          (and (= (listLength files) 1)
            (and (= (listLength owns) 1)
              (and (not (stringEmpty? name))
                (and (= (optionOr (listLast (stringSplit name "/")) "") (baseName file))
                  (= (testsPath? name) (testsPath? file)))))))
      (some (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr "write")) (pair "file" (c/kvStr file)) (pair "content" (c/kvStr (str text "\n")))))
      none))
