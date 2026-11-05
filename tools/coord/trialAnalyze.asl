(module asl-tools/coord/trialAnalyze
  :x [Facts Rule Verdict taxonomy parseForms atomOf unq kvOf factsOf rules swapRules classifyWith classify classifyText reportOf reportText writeRow? recordsOf main]
  :i [(asl-parser/reader :a rd)])

; (:m :ref TRIAL-ANALYZE :do "pure stall classifier for the Leon trial, taxonomy trialStall-v1 (scratchpad leonTrialDesign.asn :analysis): a (:trialRun ...) record, or a partial record from a production (:t ... :stage write) row, becomes one class and its insertion point; the class comes from the first stage that did not pass, inside write from the Leon :stop, the last signal and the gate output, checked in the order of rules; no rule matching means :unclassified with a reason, never a guess")

(schema Facts
  (:f id String) (:f alias String) (:f served String) (:f pinBroken Bool) (:f pinUnknown Bool) (:f known String) (:f seeded Bool) (:f partial Bool) (:f defect String)
  (:f hasLeon Bool) (:f stop String) (:f signals (List String)) (:f cause String)
  (:f opsKnown Bool) (:f ops (List (Pair String Int64))) (:f opErrors (List (Pair String Int64)))
  (:f ownsRejected Int64) (:f needsConfirm Int64) (:f turns Int64) (:f malformed Int64) (:f errClass String)
  (:f gateExit Int64) (:f gateError String) (:f gateFailed Int64)
  (:f hasWrite Bool) (:f writeOk Bool) (:f writeSig String) (:f cond String) (:f killed Bool)
  (:f hasGates Bool) (:f gatesExit Int64) (:f executed Int64) (:f redBefore Bool)
  (:f hasReview Bool) (:f reviewVerdict String) (:f reviewSig String) (:f reviewers Int64) (:f reviewersEmpty Int64) (:f leadCheck String)
  (:f hasMerge Bool) (:f mergeOk Bool) (:f mergeSig String))

(schema Rule
  (:f class String) (:f stage String) (:f insert String) (:f alt String) (:f test (fn [Facts] -> Bool)))

(schema Verdict
  (:f id String) (:f model String) (:f class String) (:f insert String) (:f alt String) (:f why String) (:f partial Bool) (:f pinBroken Bool) (:f pinUnknown Bool))

fn taxonomy -> String
  "trialStall-v1"


fn atomOf s: rd/SExpr -> String
  (if (rd/isAtom? s) (rd/sexprHead s) "")

fn itemsOf s: rd/SExpr -> (List rd/SExpr)
  (rd/sexprToList s)

fn unq a: String -> String
  (let [(n (stringLength a))]
    (if (and (>= n 2) (and (stringStartsWith? a "\"") (stringEndsWith? a "\"")))
      (stringReplace (stringReplace (optionOr (stringSlice a 1 (- n 1)) "") "\\\"" "\"") "\\\\" "\\")
      a))

fn bare a: String -> String
  (let [(u (unq a))]
    (if (stringStartsWith? u ":") (optionOr (stringSlice u 1 (stringLength u)) u) u))

; (:m :ref TRIAL-ANALYZE :do "a form is (:head k v k v ...); keys are read pairwise after the head, so a keyword value such as :status :escalated is never taken for a key")
fn kvPairs xs: (List rd/SExpr) key: String -> (Option rd/SExpr)
  (match (listHead xs)
    ((none) none)
    ((some k)
      (let [(rest (optionOr (listTail xs) (list)))]
        (if (= (atomOf k) key) (listHead rest) (kvPairs (optionOr (listTail rest) (list)) key)))))

fn kvOf s: rd/SExpr key: String -> (Option rd/SExpr)
  (kvPairs (optionOr (listTail (itemsOf s)) (list)) key)

fn strOf s: rd/SExpr key: String -> String
  (match (kvOf s key) ((some v) (bare (atomOf v))) ((none) ""))

fn rawOf s: rd/SExpr key: String -> String
  (match (kvOf s key) ((some v) (unq (atomOf v))) ((none) ""))

fn intOf s: rd/SExpr key: String dflt: Int64 -> Int64
  (match (kvOf s key) ((some v) (optionOr (stringToInt64 (atomOf v)) dflt)) ((none) dflt))

fn boolOf s: rd/SExpr key: String -> Bool
  (= (strOf s key) "true")

fn has? s: rd/SExpr key: String -> Bool
  (some? (kvOf s key))

fn subOf s: rd/SExpr key: String -> rd/SExpr
  (optionOr (kvOf s key) (rd/makeList (list)))

; (:m :ref TRIAL-ANALYZE :do "a plain property list such as :leon (:stop provider :turns 37) or :redBefore (:exit 1 :executed 4) has no head; headed gives it one so the pairwise readers apply")
fn headed s: rd/SExpr -> rd/SExpr
  (rd/makeList (cons (rd/makeAtom ":plist") (itemsOf s)))

fn stageOf stages: rd/SExpr name: String -> (Option rd/SExpr)
  (listFind (fn [(x rd/SExpr)] -> Bool (= (rd/sexprHead x) name)) (itemsOf stages))

; (:m :ref TRIAL-ANALYZE :do "counts are (:name n) forms: :ops ((:read 12) (:write 2)) and :opErrors ((:ERR_NATIVE_STALE 4))")
fn countsOf s: rd/SExpr -> (List (Pair String Int64))
  (map (fn [(x rd/SExpr)] -> (Pair String Int64)
         (pair (bare (rd/sexprHead x)) (optionOr (stringToInt64 (atomOf (optionOr (listGet (itemsOf x) 1) (rd/makeAtom "")))) 0)))
       (filter (fn [(x rd/SExpr)] -> Bool (not (stringEmpty? (rd/sexprHead x)))) (itemsOf s)))

fn countFor xs: (List (Pair String Int64)) name: String -> Int64
  (fold (fn [(acc Int64) (p (Pair String Int64))] -> Int64 (if (= (pairFirst p) name) (+ acc (pairSecond p)) acc)) 0 xs)

; (:m :ref TRIAL-ANALYZE :do "a signal is an atom (readStreak or :readStreak) or a form (:readStreak :cause notFound) or (:signal :readStreak :cause notFound); its name has no colon")
fn signalName x: rd/SExpr -> String
  (cond
    ((rd/isAtom? x) (bare (rd/sexprHead x)))
    ((rd/isList? x)
      (let [(h (bare (rd/sexprHead x)))]
        (if (= h "signal") (bare (atomOf (optionOr (listGet (itemsOf x) 1) (rd/makeAtom "")))) h)))
    (else ""))

fn signalCause x: rd/SExpr -> String
  (if (rd/isList? x)
    (let [(items (itemsOf x))]
      (if (= (bare (rd/sexprHead x)) "signal")
        (kvCause (optionOr (listTail (optionOr (listTail items) (list))) (list)))
        (kvCause (optionOr (listTail items) (list)))))
    "")

fn kvCause xs: (List rd/SExpr) -> String
  (match (kvPairs xs ":cause") ((some v) (bare (atomOf v))) ((none) ""))

; (:m :ref TRIAL-ANALYZE-M2 :do "required keys per stage: write :ok and merge :ok are true or false, gates :exit and :executed are plain integers, review has a :verdict; Leon counts and the lastGate, err and redBefore numbers, when present, are plain integers; a missing or malformed key makes the record unclassified with a reason naming the key and stage, never a nearby class, and a quoted integer is malformed, never a default")
fn okKind v: rd/SExpr kind: String -> Bool
  (cond
    ((= kind "int") (and (rd/isAtom? v) (some? (stringToInt64 (atomOf v)))))
    ((= kind "bool") (and (rd/isAtom? v) (listContains? (list "true" "false") (atomOf v))))
    (else true))

fn keyDefect s: rd/SExpr key: String stage: String kind: String -> String
  (match (kvOf s key)
    ((none) (str "missing " key " in " stage))
    ((some v) (if (okKind v kind) "" (str "malformed " key " in " stage))))

fn optDefect s: rd/SExpr key: String stage: String kind: String -> String
  (if (has? s key) (keyDefect s key stage kind) "")

fn firstDefect ds: (List String) -> String
  (optionOr (listFind (fn [(d String)] -> Bool (not (stringEmpty? d))) ds) "")

fn stageDefects st: (Option rd/SExpr) checks: (fn [rd/SExpr] -> (List String)) -> (List String)
  (match st ((some x) (checks x)) ((none) (list)))

fn dropPrefix s: String ps: (List String) -> String
  (match (listFind (fn [(p String)] -> Bool (stringStartsWith? s p)) ps)
    ((some p) (optionOr (stringSlice s (stringLength p) (stringLength s)) ""))
    ((none) s))

; (:m :ref TRIAL-ANALYZE-M1 :do "a tierHop A->B: wrapper is the conductor's own prefix before the verdict it moved; it is dropped as often as it repeats")
fn stripWrap s: String -> String
  (if (stringStartsWith? s "tierHop ")
    (match (stringIndexOf s ": ")
      ((some at) (stripWrap (optionOr (stringSlice s (+ at 2) (stringLength s)) "")))
      ((none) s))
    s)

fn verdictBody v: String -> String
  (dropPrefix (stripWrap (stringTrim v)) (list "fail: " "escalated: " "providerFail: "))

fn infraPrefixes -> (List String)
  (list "settle" "writeGuard" "waitedOut" "aheadGreen" "pool unreachable" "worktree attach failed" "worktree add failed" "stale branch recreate failed" "stage died" "stage run row lost" "ERR_HUB_CLIENT_MISSING")

; (:m :ref TRIAL-ANALYZE-M1 :do "the conductor-authored kind of a write verdict or Res sig, matched only as the verdict's own prefix after its tierHop wrappers and its fail:, escalated: or providerFail: tag: receipt when the body is a form, else stalled, vacuousGate, noEdit, leaseEnded, infra, written, provider for a providerFail tag with no receipt, or empty; text inside a receipt or a sig is never searched")
fn condOf v: String -> String
  (let [(s (stripWrap (stringTrim v)))
        (body (verdictBody v))]
    (cond
      ((stringStartsWith? body "(") "receipt")
      ((or (= body "stalled") (stringStartsWith? body "stalled:")) "stalled")
      ((stringStartsWith? body "vacuousGate: ") "vacuousGate")
      ((= body "noEdit") "noEdit")
      ((stringStartsWith? body "lease ended before") "leaseEnded")
      ((listAny? (fn [(p String)] -> Bool (stringStartsWith? body p)) (infraPrefixes)) "infra")
      ((= body "written") "written")
      ((stringStartsWith? s "providerFail: ") "provider")
      (else "")))

; (:m :ref TRIAL-ANALYZE-M1 :do "the Leon receipt inside a verdict body, read with the ASN reader: the body itself when its head is :agentReceipt, or the :receipt key of an (:agent ...) wrapper; a receipt cut short by the conductor still yields the keys before the cut")
fn receiptOf body: String -> (Option rd/SExpr)
  (let [(x (rd/parseSexpr (stringReplace body "\\" "")))
        (h (rd/sexprHead x))]
    (cond
      ((= h ":agentReceipt") (some x))
      ((= h ":agent") (match (kvOf x ":receipt") ((some y) (if (= (rd/sexprHead y) ":agentReceipt") (some y) none)) ((none) none)))
      (else none)))

; (:m :ref TRIAL-ANALYZE-L3 :do "the served alias of a receipt counts only when its quoted string is whole; the conductor cuts long verdicts, and a cut alias is unknown, not a new model")
fn servedOf rc: rd/SExpr -> String
  (let [(a (match (kvOf rc ":servedAlias") ((some v) (atomOf v)) ((none) "")))
        (n (stringLength a))]
    (cond
      ((and (>= n 2) (and (stringStartsWith? a "\"") (stringEndsWith? a "\""))) (unq a))
      ((stringContains? a "\"") "")
      (else a)))

fn emptyFacts -> Facts
  (Facts :id "" :alias "" :served "" :pinBroken false :pinUnknown false :known "" :seeded false :partial false :defect ""
         :hasLeon false :stop "" :signals (list) :cause ""
         :opsKnown false :ops (list) :opErrors (list)
         :ownsRejected 0 :needsConfirm 0 :turns 0 :malformed 0 :errClass ""
         :gateExit -1 :gateError "" :gateFailed 0
         :hasWrite false :writeOk false :writeSig "" :cond "" :killed false
         :hasGates false :gatesExit -1 :executed 0 :redBefore false
         :hasReview false :reviewVerdict "" :reviewSig "" :reviewers 0 :reviewersEmpty 0 :leadCheck ""
         :hasMerge false :mergeOk false :mergeSig "")

fn trialFacts r: rd/SExpr -> Facts
  (let [(stages (subOf r ":stages"))
        (leon (kvOf r ":leon"))
        (lf (headed (optionOr leon (rd/makeList (list)))))
        (sigs (itemsOf (subOf lf ":signals")))
        (lastSig (listLast sigs))
        (gate (headed (subOf lf ":lastGate")))
        (w (stageOf stages ":write"))
        (g (stageOf stages ":gates"))
        (rv (stageOf stages ":review"))
        (m (stageOf stages ":merge"))
        (wf (optionOr w (rd/makeList (list))))
        (gf (optionOr g (rd/makeList (list))))
        (rf (optionOr rv (rd/makeList (list))))
        (mf (optionOr m (rd/makeList (list))))
        (revs (itemsOf (subOf rf ":reviewers")))
        (known (strOf r ":known"))
        (rb (match (kvOf gf ":redBefore") ((some x) (some (headed x))) ((none) none)))
        (defect (firstDefect (flatten (list
                  (stageDefects w (fn [(x rd/SExpr)] -> (List String) (list (keyDefect x ":ok" "write" "bool") (optDefect x ":killed" "write" "bool"))))
                  (stageDefects g (fn [(x rd/SExpr)] -> (List String) (list (keyDefect x ":exit" "gates" "int") (keyDefect x ":executed" "gates" "int"))))
                  (stageDefects rb (fn [(x rd/SExpr)] -> (List String) (list (optDefect x ":exit" "redBefore" "int"))))
                  (stageDefects rv (fn [(x rd/SExpr)] -> (List String) (list (keyDefect x ":verdict" "review" "any"))))
                  (stageDefects m (fn [(x rd/SExpr)] -> (List String) (list (keyDefect x ":ok" "merge" "bool"))))
                  (stageDefects leon (fn [(x rd/SExpr)] -> (List String)
                    (map (fn [(k String)] -> String (optDefect lf k "leon" "int")) (list ":turns" ":ownsRejected" ":needsConfirm" ":malformed"))))
                  (list (optDefect gate ":exit" "lastGate" "int") (optDefect gate ":failed" "lastGate" "int"))))))]
    (with (emptyFacts)
      :id (strOf r ":id") :alias (strOf r ":alias") :served (strOf r ":served")
      :pinBroken (boolOf r ":pinBroken") :known known :defect defect
      :seeded (or (boolOf r ":seeded") (or (= known "reviewFail") (= known "refuse")))
      :hasLeon (some? leon) :stop (strOf lf ":stop")
      :signals (map signalName sigs)
      :cause (match lastSig ((some x) (signalCause x)) ((none) ""))
      :opsKnown (has? lf ":ops") :ops (countsOf (subOf lf ":ops")) :opErrors (countsOf (subOf lf ":opErrors"))
      :ownsRejected (intOf lf ":ownsRejected" 0) :needsConfirm (intOf lf ":needsConfirm" 0)
      :turns (intOf lf ":turns" 0) :malformed (intOf lf ":malformed" 0)
      :errClass (strOf (headed (subOf lf ":err")) ":class")
      :gateExit (intOf gate ":exit" -1) :gateError (rawOf gate ":error") :gateFailed (intOf gate ":failed" 0)
      :hasWrite (some? w) :writeOk (boolOf wf ":ok") :writeSig (rawOf wf ":sig") :cond (condOf (rawOf wf ":sig")) :killed (boolOf wf ":killed")
      :hasGates (some? g) :gatesExit (intOf gf ":exit" -1) :executed (intOf gf ":executed" 0)
      :redBefore (match rb ((some x) (!= (intOf x ":exit" 0) 0)) ((none) false))
      :hasReview (some? rv) :reviewVerdict (strOf rf ":verdict") :reviewSig (rawOf rf ":sig")
      :reviewers (listLength revs) :reviewersEmpty (listLength (filter (fn [(x rd/SExpr)] -> Bool (boolOf (headed x) ":empty")) revs))
      :leadCheck (strOf rf ":leadCheck")
      :hasMerge (some? m) :mergeOk (boolOf mf ":ok") :mergeSig (rawOf mf ":sig")))

fn flatten xss: (List (List String)) -> (List String)
  (fold (fn [(acc (List String)) (xs (List String))] -> (List String) (listAppend acc xs)) (list) xss)

; (:m :ref TRIAL-ANALYZE-M1 :do "a production write row (:t :unit U :from writing :to T :stage write :model M :verdict V): the conductor kind of V by anchored prefix, and when V's body is a receipt its own :stop and :servedAlias read by key; ops are unknown, so read-loop and refusal evidence is absent; a receipt served by another alias than a real :model sets :pinUnknown (L3) and the row is counted under the served alias")
fn rowFacts r: rd/SExpr -> Facts
  (let [(v (rawOf r ":verdict"))
        (to (strOf r ":to"))
        (kind (condOf v))
        (rc (if (= kind "receipt") (receiptOf (verdictBody v)) none))
        (rf (optionOr rc (rd/makeList (list))))
        (stop (strOf rf ":stop"))
        (served (servedOf rf))
        (model (rawOf r ":model"))]
    (with (emptyFacts)
      :id (rawOf r ":unit") :alias (if (stringEmpty? served) model served) :partial true
      :defect (if (has? r ":verdict") "" "missing :verdict in row")
      :pinUnknown (and (not (stringEmpty? served)) (and (not (stringEmpty? model)) (and (!= model "unknown") (!= model served))))
      :hasLeon (some? rc) :stop stop
      :signals (if (stringEmpty? stop) (list) (list stop))
      :hasWrite true :writeOk (or (= to "gating") (= kind "written")) :writeSig v :cond kind))

fn factsOf r: rd/SExpr -> Facts
  (if (= (rd/sexprHead r) ":t") (rowFacts r) (trialFacts r))

fn writeRow? r: rd/SExpr -> Bool
  (and (= (rd/sexprHead r) ":t") (and (= (strOf r ":stage") "write") (= (strOf r ":from") "writing")))

fn lastSignal f: Facts -> String
  (optionOr (listLast f.signals) "")

fn signalled f: Facts name: String -> Bool
  (or (= (lastSignal f) name) (= f.stop name))

fn stopSignals -> (List String)
  (list "readStreak" "malformedReply" "parseDefect" "repeatFailure" "doneNoWrite" "modelEscalated" "wallBudget" "gateIntegrity" "stalled" "needsReview" "noWrite" "turnBudget")

fn noStopSignal f: Facts -> Bool
  (and (listEmpty? f.signals) (not (listContains? (stopSignals) f.stop)))

fn writeOps f: Facts -> Int64
  (+ (+ (countFor f.ops "write") (countFor f.ops "edit")) (+ (countFor f.ops "txn") (countFor f.ops "patch")))

fn hasErr f: Facts code: String -> Bool
  (> (countFor f.opErrors code) 0)

fn writeFailed f: Facts -> Bool
  (and f.hasWrite (not f.writeOk))

fn writePassed f: Facts -> Bool
  (or (and f.hasWrite f.writeOk) (and (not f.hasWrite) f.seeded))

fn gatesPassed f: Facts -> Bool
  (and (writePassed f) (and f.hasGates (and (= f.gatesExit 0) (and (> f.executed 0) f.redBefore))))

fn reviewPassed f: Facts -> Bool
  (and (gatesPassed f) (and f.hasReview (= f.reviewVerdict "pass")))

fn firstWord s: String -> String
  (let [(w (optionOr (listHead (stringSplit (stringTrim s) " ")) ""))]
    (if (stringEndsWith? w ":") (optionOr (stringSlice w 0 (- (stringLength w) 1)) w) w))

; (:m :ref TRIAL-ANALYZE-L1 :do "the gate's own error code is the first token that starts with ERR_, colons trimmed; an assertion text that says parse error is ERR_ASSERT, not a compile error")
fn firstErrCode text: String -> String
  (let [(toks (map (fn [(t String)] -> String (stringReplace t ":" "")) (stringSplit text " ")))]
    (optionOr (listFind (fn [(t String)] -> Bool (stringStartsWith? t "ERR_")) toks) ""))

fn compileCodes -> (List String)
  (list "ERR_UNRESOLVED_IMPORT" "ERR_UNKNOWN_SYMBOL" "ERR_TYPE_MISMATCH" "ERR_ARITY" "ERR_NOT_EXPORTED" "ERR_UNDEFINED_EXPORT" "ERR_UNTYPED_PARAM" "ERR_PARSE" "ERR_UNBALANCED")

fn compileCode? code: String -> Bool
  (or (listContains? (compileCodes) code) (stringStartsWith? code "ERR_READ_"))

; (:m :ref TRIAL-ANALYZE :do "wReadLoop's turn cap: 20 turns with no write op and no stop signal, the turn Leon's noWriteNudge names as the no-write stop (adopted); H1 on node2 was 37 read turns")
fn readLoopCap -> Int64
  20

fn pProvider f: Facts -> Bool
  (and (writeFailed f) (or (= f.stop "provider") (or (= f.errClass "transient") (= f.cond "provider"))))

fn pPinBroken f: Facts -> Bool
  (or f.pinBroken (and (not f.partial) (and (not (stringEmpty? f.served)) (and (not (stringEmpty? f.alias)) (!= f.served f.alias)))))

fn pToolRoot f: Facts -> Bool
  (and (writeFailed f) (hasErr f "ERR_NATIVE_STALE"))

fn pInfra f: Facts -> Bool
  (and (writeFailed f) (and (not f.hasLeon) (= f.cond "infra")))

fn pMalformed f: Facts -> Bool
  (and (writeFailed f) (or (signalled f "malformedReply") (or (signalled f "parseDefect") (> f.malformed 0))))

fn pReadLoop f: Facts -> Bool
  (and (writeFailed f)
       (or (and (signalled f "readStreak") (= f.cause "notFound"))
           (or (and (signalled f "readStreak") (and (stringEmpty? f.cause) (and f.opsKnown (= (writeOps f) 0))))
               (and (noStopSignal f) (and f.opsKnown (and (= (writeOps f) 0) (>= f.turns (readLoopCap))))))))

fn pRefused f: Facts -> Bool
  (and (writeFailed f)
       (or (and (signalled f "readStreak") (= f.cause "refusedWrites"))
           (or (> f.ownsRejected 0)
               (or (> f.needsConfirm 0)
                   (and (signalled f "readStreak") (and (stringEmpty? f.cause) (or (hasErr f "ERR_TXN_ABORTED") (hasErr f "ERR_OWNS"))))))))

fn pRepeat f: Facts -> Bool
  (and (writeFailed f) (signalled f "repeatFailure"))

fn pDoneNoWrite f: Facts -> Bool
  (and (writeFailed f) (signalled f "doneNoWrite"))

fn pEscalated f: Facts -> Bool
  (and (writeFailed f) (signalled f "modelEscalated"))

; (:m :ref TRIAL-ANALYZE :do "wWall also takes the conductor verdict lease ended before the pooled run did: the run outlived its lease, a limit (node2 2026-11-04, 6 rows)")
fn pWall f: Facts -> Bool
  (and (writeFailed f) (or (signalled f "wallBudget") (or f.killed (= f.cond "leaseEnded"))))

; (:m :ref TRIAL-ANALYZE :do "three classes added to v1 on 2026-11-05 from the node2 slice: wStallKill, the conductor stall sweep killed the writer (verdict stalled, 146 rows); wRevertGreen, Leon's own revert check found the gate green with the change reverted (stop gateIntegrity, 71 rows); wNeedsReview, Leon stopped asking for review (stop needsReview, 20 rows)")
fn pStallKill f: Facts -> Bool
  (and (writeFailed f) (or (= f.cond "stalled") (= f.stop "stalled")))

fn pRevertGreen f: Facts -> Bool
  (and (writeFailed f) (signalled f "gateIntegrity"))

fn pNeedsReview f: Facts -> Bool
  (and (writeFailed f) (signalled f "needsReview"))

fn pCompile f: Facts -> Bool
  (and (writeFailed f) (and (> f.gateExit 0) (compileCode? (firstErrCode f.gateError))))

fn pGateRed f: Facts -> Bool
  (and (writeFailed f) (and (> f.gateExit 0) (> f.gateFailed 0)))

fn pNoEdit f: Facts -> Bool
  (and (writeFailed f) (= f.cond "noEdit"))

fn pVacuous f: Facts -> Bool
  (and (writeFailed f) (= f.cond "vacuousGate"))

fn pRerunRed f: Facts -> Bool
  (and (writePassed f) (and f.hasGates (and (!= f.gatesExit 0) (= f.gateExit 0))))

fn pNoAsserts f: Facts -> Bool
  (and (writePassed f) (and f.hasGates (and (= f.gatesExit 0) (= f.executed 0))))

fn pNotRedBefore f: Facts -> Bool
  (and (writePassed f) (and f.hasGates (and (= f.gatesExit 0) (and (> f.executed 0) (not f.redBefore)))))

fn pEmpty f: Facts -> Bool
  (and (gatesPassed f)
       (and f.hasReview
            (or (listContains? (list "empty" "") f.reviewVerdict)
                (and (> f.reviewers 0) (= f.reviewers f.reviewersEmpty)))))

; (:m :ref TRIAL-ANALYZE-L2 :do "review and merge sigs are matched by their first word, colon trimmed: noDiff or diffUnreadable; refused, promote or fetch; train or commitError")
fn pNoDiff f: Facts -> Bool
  (and (gatesPassed f) (and f.hasReview (listContains? (list "noDiff" "diffUnreadable") (firstWord f.reviewSig))))

fn pFalseBlock f: Facts -> Bool
  (and (gatesPassed f) (and (= f.reviewVerdict "block") (and (= f.known "merge") (= f.leadCheck "notHold"))))

fn pTrueBlock f: Facts -> Bool
  (and (gatesPassed f) (and (= f.reviewVerdict "block") (= f.leadCheck "holds")))

fn pFalsePass f: Facts -> Bool
  (and f.seeded (reviewPassed f))

fn pMergeRefused f: Facts -> Bool
  (and (reviewPassed f) (and f.hasMerge (and (not f.mergeOk) (listContains? (list "refused" "promote" "fetch") (firstWord f.mergeSig)))))

fn pTrainRed f: Facts -> Bool
  (and (reviewPassed f) (and f.hasMerge (and (not f.mergeOk) (listContains? (list "train" "commitError") (firstWord f.mergeSig)))))

fn pMerged f: Facts -> Bool
  (and (reviewPassed f) (and f.hasMerge f.mergeOk))

fn rule c: String stage: String ins: String alt: String t: (fn [Facts] -> Bool) -> Rule
  (Rule :class c :stage stage :insert ins :alt alt :test t)

; (:m :ref TRIAL-ANALYZE :do "the precedence of trialStall-v1, the design's row order plus wStallKill after wInfra (a sweep kill is a harness verdict on the run, read before Leon's own signals) and wRevertGreen and wNeedsReview after wWall (Leon's own stop explains the end before the gate output does): write rows first, then gates, review and merge; wPinBroken sits second and applies at any stage, because a cell served by another alias says nothing about its pinned model; rFalsePass precedes merged so a seeded-bad cell that merged is never counted as merged")
fn rules -> (List Rule)
  (list (rule "wProvider" "write" "limit" "" pProvider)
        (rule "wPinBroken" "write" "harness" "" pPinBroken)
        (rule "wToolRoot" "write" "tool" "" pToolRoot)
        (rule "wInfra" "write" "harness" "" pInfra)
        (rule "wStallKill" "write" "harness" "" pStallKill)
        (rule "wMalformed" "write" "tool" "" pMalformed)
        (rule "wReadLoop" "write" "hint" "limit" pReadLoop)
        (rule "wRefused" "write" "tool" "task" pRefused)
        (rule "wRepeat" "write" "tool" "" pRepeat)
        (rule "wDoneNoWrite" "write" "hint" "" pDoneNoWrite)
        (rule "wEscalated" "write" "harness" "" pEscalated)
        (rule "wWall" "write" "limit" "" pWall)
        (rule "wRevertGreen" "write" "harness" "task" pRevertGreen)
        (rule "wNeedsReview" "write" "harness" "" pNeedsReview)
        (rule "wCompile" "write" "hint" "tool" pCompile)
        (rule "wGateRed" "write" "model" "hint" pGateRed)
        (rule "wNoEdit" "write" "harness" "" pNoEdit)
        (rule "wVacuous" "write" "task" "hint" pVacuous)
        (rule "gRerunRed" "gates" "harness" "" pRerunRed)
        (rule "gNoAsserts" "gates" "task" "" pNoAsserts)
        (rule "gNotRedBefore" "gates" "task" "" pNotRedBefore)
        (rule "rEmpty" "review" "harness" "" pEmpty)
        (rule "rNoDiff" "review" "harness" "" pNoDiff)
        (rule "rFalseBlock" "review" "hint" "" pFalseBlock)
        (rule "rTrueBlock" "review" "model" "" pTrueBlock)
        (rule "rFalsePass" "review" "hint" "harness" pFalsePass)
        (rule "mRefused" "merge" "harness" "" pMergeRefused)
        (rule "mTrainRed" "merge" "harness" "task" pTrainRed)
        (rule "merged" "merge" "none" "" pMerged))

; (:m :ref TRIAL-ANALYZE :do "swapRules a b exchanges two precedence steps by class name; the test uses it to prove each overlap fixture pins its order")
fn swapRules rs: (List Rule) a: String b: String -> (List Rule)
  (let [(ra (listFind (fn [(r Rule)] -> Bool (= r.class a)) rs))
        (rb (listFind (fn [(r Rule)] -> Bool (= r.class b)) rs))]
    (match ra
      ((none) rs)
      ((some x)
        (match rb
          ((none) rs)
          ((some y) (map (fn [(r Rule)] -> Rule (if (= r.class a) y (if (= r.class b) x r))) rs))))))

fn whyUnmatched f: Facts -> String
  (cond
    ((and (not f.hasWrite) (not f.seeded)) "no write stage")
    ((and f.partial f.writeOk) "write passed; later stages are not in a write row")
    ((and (writeFailed f) (and (signalled f "readStreak") (stringEmpty? f.cause))) "readStreak without :cause and without op evidence")
    ((writeFailed f) (str "write failed, stop " (if (stringEmpty? f.stop) "none" f.stop) ", no rule matched"))
    ((and f.hasGates (!= f.gatesExit 0)) "gates red without Leon's own gate result")
    ((and f.hasReview (= f.reviewVerdict "block")) "review block without a lead check")
    ((and f.hasMerge (not f.mergeOk)) "merge failed with a sig that is not a merge verdict")
    ((writePassed f) (str "stopped after " (if f.hasReview "review" (if f.hasGates "gates" "write")) " with no further stage"))
    (else "no rule matched"))

fn classifyWith rs: (List Rule) r: rd/SExpr -> Verdict
  (let [(f (factsOf r))
        (hit (if (stringEmpty? f.defect) (listFind (fn [(x Rule)] -> Bool (x.test f)) rs) none))
        (model (if (stringEmpty? f.alias) "unknown" f.alias))]
    (match hit
      ((some x) (Verdict :id f.id :model model :class x.class :insert x.insert :alt x.alt :why "" :partial f.partial :pinBroken (pPinBroken f) :pinUnknown f.pinUnknown))
      ((none) (Verdict :id f.id :model model :class "unclassified" :insert "" :alt ""
                       :why (if (stringEmpty? f.defect) (whyUnmatched f) f.defect) :partial f.partial :pinBroken (pPinBroken f) :pinUnknown f.pinUnknown))))

fn classify r: rd/SExpr -> Verdict
  (classifyWith (rules) r)

fn esc s: String -> String
  (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"")

fn classifyText v: Verdict -> String
  (str "(:trialClass :id \"" (esc v.id) "\" :model \"" (esc v.model) "\" :class " v.class
       (if (stringEmpty? v.insert) "" (str " :insert " v.insert))
       (if (stringEmpty? v.alt) "" (str " :alt " v.alt))
       (if (stringEmpty? v.why) "" (str " :why \"" (esc v.why) "\""))
       (if v.partial " :partial true" "") (if v.pinBroken " :pinBroken true" "") (if v.pinUnknown " :pinUnknown true" "") ")")

fn bump xs: (List (Pair String Int64)) k: String -> (List (Pair String Int64))
  (if (listAny? (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) k)) xs)
    (map (fn [(p (Pair String Int64))] -> (Pair String Int64) (if (= (pairFirst p) k) (pair k (+ (pairSecond p) 1)) p)) xs)
    (listAppend xs (list (pair k 1))))

fn uniq xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn n i: Int64 -> String
  (stringFromInt64 i)

fn classOrder -> (List String)
  (listAppend (map (fn [(r Rule)] -> String r.class) (rules)) (list "unclassified"))

fn insertOf c: String -> String
  (match (listFind (fn [(r Rule)] -> Bool (= r.class c)) (rules)) ((some r) r.insert) ((none) ""))

fn countsText xs: (List (Pair String Int64)) -> String
  (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(:" (pairFirst p) " " (n (pairSecond p)) ")")) xs) " ")

fn ordered xs: (List (Pair String Int64)) order: (List String) -> (List (Pair String Int64))
  (filter (fn [(p (Pair String Int64))] -> Bool (> (pairSecond p) 0))
    (map (fn [(k String)] -> (Pair String Int64) (pair k (countFor xs k))) order))

fn modelText vs: (List Verdict) alias: String -> String
  (let [(mine (filter (fn [(v Verdict)] -> Bool (= v.model alias)) vs))
        (classes (fold (fn [(acc (List (Pair String Int64))) (v Verdict)] -> (List (Pair String Int64)) (bump acc v.class)) (list) mine))]
    (str "(:alias \"" (esc alias) "\" :cells " (n (listLength mine))
         " :merged " (n (listLength (filter (fn [(v Verdict)] -> Bool (= v.class "merged")) mine)))
         " :classes (" (countsText (ordered classes (classOrder))) "))"))

fn classText vs: (List Verdict) c: String -> String
  (let [(mine (filter (fn [(v Verdict)] -> Bool (= v.class c)) vs))
        (ins (insertOf c))]
    (str "(:class " c " :n " (n (listLength mine)) (if (stringEmpty? ins) "" (str " :insert " ins))
         " :models (" (stringJoin (map (fn [(m String)] -> String (str "\"" (esc m) "\"")) (uniq (map (fn [(v Verdict)] -> String v.model) mine))) " ")
         ") :exemplar \"" (esc (match (listHead mine) ((some v) v.id) ((none) ""))) "\")"))

; (:m :ref TRIAL-ANALYZE :do "the report: :runs counts every record, :byModel leaves out pinBroken records (their served model is not the pinned one), :pinUnknown counts production rows served by another alias than their :model, :byClass lists the classes present in precedence order with unclassified last, :insert totals classified records per insertion point, :unclassifiedWhy groups the reasons")
fn reportOf vs: (List Verdict) date: String -> String
  (let [(modelVs (filter (fn [(v Verdict)] -> Bool (not v.pinBroken)) vs))
        (models (listSortBy (fn [(m String)] -> String m) (uniq (map (fn [(v Verdict)] -> String v.model) modelVs))))
        (classes (fold (fn [(acc (List (Pair String Int64))) (v Verdict)] -> (List (Pair String Int64)) (bump acc v.class)) (list) vs))
        (present (map pairFirst (ordered classes (classOrder))))
        (inserts (fold (fn [(acc (List (Pair String Int64))) (v Verdict)] -> (List (Pair String Int64)) (if (stringEmpty? v.insert) acc (bump acc v.insert))) (list) vs))
        (whys (fold (fn [(acc (List (Pair String Int64))) (v Verdict)] -> (List (Pair String Int64)) (if (stringEmpty? v.why) acc (bump acc v.why))) (list) vs))
        (unc (countFor classes "unclassified"))]
    (str "(:trialReport :taxonomy " (taxonomy) " :date \"" (esc date) "\" :runs " (n (listLength vs))
         " :merged " (n (countFor classes "merged")) " :unclassified " (n unc)
         " :partial " (n (listLength (filter (fn [(v Verdict)] -> Bool v.partial) vs)))
         " :pinBroken " (n (listLength (filter (fn [(v Verdict)] -> Bool v.pinBroken) vs)))
         " :pinUnknown " (n (listLength (filter (fn [(v Verdict)] -> Bool v.pinUnknown) vs)))
         " :byModel (" (stringJoin (map (fn [(m String)] -> String (modelText modelVs m)) models) " ")
         ") :byClass (" (stringJoin (map (fn [(c String)] -> String (classText vs c)) present) " ")
         ") :insert (" (countsText (ordered inserts (list "hint" "tool" "limit" "harness" "task" "model" "none")))
         ") :unclassifiedWhy (" (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(:why \"" (esc (pairFirst p)) "\" :n " (n (pairSecond p)) ")")) whys) " ")
         "))"))

fn reportText records: (List rd/SExpr) date: String -> String
  (reportOf (map classify records) date)


; (:m :ref TRIAL-ANALYZE :do "a file of forms, one or more per line; lines starting with ; are dropped; the whole text is read as one list so a form may span lines")
fn parseForms text: String -> (List rd/SExpr)
  (let [(kept (filter (fn [(l String)] -> Bool (not (stringStartsWith? (stringTrim l) ";"))) (stringLines text)))]
    (filter (fn [(x rd/SExpr)] -> Bool (not (stringEmpty? (rd/sexprHead x))))
      (itemsOf (rd/parseSexpr (str "(" (stringJoin kept "\n") ")")))))

fn journalRow? l: String -> Bool
  (listAny? (fn [(p String)] -> Bool (stringStartsWith? l p)) (list "(:t " "(:wip " "(:profile " "(:lead " "(:escalate "))

; (:m :ref TRIAL-ANALYZE :do "records of a file: every (:trialRun ...) form and every production write row; a journal row is one line and is parsed alone after a text pre-filter, so a receipt cut inside an escape cannot swallow the rows after it and a 3 MB journal parses only its write rows; other lines are read as forms that may span lines")
fn recordsOf text: String -> (List rd/SExpr)
  (let [(lines (stringLines text))
        (rows (map rd/parseSexpr (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:t ") (and (stringContains? l ":stage write") (stringContains? l ":from writing")))) lines)))
        (forms (parseForms (stringJoin (filter (fn [(l String)] -> Bool (not (journalRow? l))) lines) "\n")))]
    (listAppend (filter (fn [(x rd/SExpr)] -> Bool (= (rd/sexprHead x) ":trialRun")) forms) (filter writeRow? rows)))

fn flagVal args: (List String) name: String -> String
  (match (listIndexOf args name)
    ((some i) (optionOr (listGet args (+ i 1)) ""))
    ((none) ""))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (path (flagVal args "--in"))]
    (if (or (stringEmpty? path) (not (listContains? (list "classify" "report") cmd)))
      (let [(_ (println "(:trialAnalyze :usage \"run trialAnalyze.asl classify|report --in FILE [--date D]\")"))] (ok 2))
      (match (fileReadString path)
        ((err e) (let [(_ (println (str "(:trialAnalyze :error \"" (esc e) "\" :in \"" (esc path) "\")")))] (ok 1)))
        ((ok text)
          (let [(recs (recordsOf text))]
            (if (= cmd "classify")
              (let [(_ (map (fn [(r rd/SExpr)] -> Unit (println (classifyText (classify r)))) recs))] (ok 0))
              (let [(_ (println (reportText recs (flagVal args "--date"))))] (ok 0))))))))
