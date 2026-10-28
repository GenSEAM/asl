(module asl-tools/coord/triggers
  :x [TrigIn blankTrigIn fired decide actionOf triggerIds]
  :i [])

; (:m :ref FLOW-TRIG :do "static trigger table of design section 3: one flat record in, trigger ids and one action string out; pure, no IO, no model; the conductor fills TrigIn from CUnit, Res, the pace row and journal counts")
; (:m :do "fields: cu* mirror CUnit (sig fails waited parked), res* mirror Res (ok claimedGreen exit asserts sig), the rest are conductor facts: journal counts, store lease, pace, ladder, base distance")
(schema TrigIn
  (:f cuSig String) (:f cuFails Int64) (:f cuWaited Int64) (:f cuParked Int64) (:f maxWait Int64)
  (:f resOk Int64) (:f resClaimedGreen Int64) (:f resExit Int64) (:f resAsserts Int64) (:f resSig String)
  (:f infraClass String)
  (:f hasRes Bool) (:f hasRedBefore Bool) (:f baseGreen Bool) (:f missCount Int64)
  (:f declaredAsserts Int64) (:f constantCond Bool) (:f revertGreen Bool) (:f rerunRed Bool)
  (:f ownsOutside Bool) (:f widenGranted Bool)
  (:f sigCount Int64)
  (:f stepEscalate Bool) (:f rung Int64)
  (:f riskHigh Bool) (:f closureChanged Bool)
  (:f paceFactorPct Int64) (:f usedPct Int64) (:f windowReset Bool)
  (:f deadlinePassed Bool) (:f pidDead Bool) (:f leaseStageSeen Int64)
  (:f mergesBehind Int64) (:f touchedChanged Bool)
  (:f claudeOnline Bool) (:f claudeAllowance Int64)
  (:f requestEnded Bool))

fn blankTrigIn -> TrigIn
  (TrigIn :cuSig "" :cuFails 0 :cuWaited 0 :cuParked 0 :maxWait 20
          :resOk 1 :resClaimedGreen 0 :resExit 0 :resAsserts 1 :resSig ""
          :infraClass ""
          :hasRes false :hasRedBefore true :baseGreen false :missCount 0
          :declaredAsserts 1 :constantCond false :revertGreen false :rerunRed false
          :ownsOutside false :widenGranted false
          :sigCount 0
          :stepEscalate false :rung 1
          :riskHigh false :closureChanged false
          :paceFactorPct 100 :usedPct 0 :windowReset false
          :deadlinePassed false :pidDead false :leaseStageSeen 0
          :mergesBehind 0 :touchedChanged false
          :claudeOnline false :claudeAllowance 0
          :requestEnded false)

fn actionOf id: String in: TrigIn -> String
  (cond
    ((= id "redBeforeMissing") (if (>= in.missCount 1) "testgen stage" "fix with defect gate-not-red-on-base"))
    ((= id "gateVacuous") "fix; counts as a signature")
    ((= id "revertGreen") "fix with defect gate-does-not-pin-change")
    ((= id "claimedGreenMismatch") "count as a fail and add one :lie row for the lane")
    ((= id "ownsViolation") "fix with the path list; never merged")
    ((= id "sig2") "next attempt goes to the next writer tier with the witness")
    ((= id "sig3") "blocked, :witness row, notify; new hypothesis from the strong lane or Claude")
    ((= id "infra") "retry the same lane with backoff; excluded from signatures and from model quality")
    ((= id "reviewerSplit") (if (>= in.rung 3) "blocked awaiting Claude" "next rung"))
    ((= id "riskHigh") "startRung R2, held-out cases mandatory, native comparison and seed fixpoint x3 in the gate set")
    ((= id "paceSoft") "lane weight falls; order re-ranked in the gateway spread")
    ((= id "paceHard") "park in awaitWrite or awaitReview with :awaitLane")
    ((= id "windowReset") "wake! lane: parked units become ready in id order")
    ((= id "leaseExpired") "kill tree, release lease, ready; the stage counts as infra once, then as a signature")
    ((= id "stale") "mechanical rebase; conflict -> fix kind with the conflict hunks")
    ((= id "waitTooLong") "one (:escalate :unit :seen :tried) row and notify; no state change")
    ((= id "claudeOnline") "blocked units in id order to the Claude lane, release gate if a release is due")
    ((= id "request") "validate per section 4; grant or refuse row; one transition")
    (else ""))

; (:m :do "an infra class (rate, overload, 502, timeout) never yields a signature trigger: only infra fires, lease and pace facts aside")
fn infraOnly in: TrigIn -> Bool
  (not (stringEmpty? in.infraClass))

fn resTriggers in: TrigIn -> (List String)
  (let [(red (and in.hasRes (not in.hasRedBefore)))
        (base (and in.hasRes in.baseGreen))]
    (filter (fn [(id String)] -> Bool (not (stringEmpty? id)))
      (list
        (if (or red base) "redBeforeMissing" "")
        (if (and in.hasRes (or (= in.resAsserts 0) (!= in.declaredAsserts in.resAsserts) in.constantCond)) "gateVacuous" "")
        (if (and in.hasRes in.revertGreen) "revertGreen" "")
        (if (and in.hasRes (= in.resClaimedGreen 1) in.rerunRed) "claimedGreenMismatch" "")
        (if (and in.ownsOutside (not in.widenGranted)) "ownsViolation" ""))))

fn tailTriggers in: TrigIn -> (List String)
  (filter (fn [(id String)] -> Bool (not (stringEmpty? id)))
    (list
      (if (>= in.sigCount 3) "sig3" (if (>= in.sigCount 2) "sig2" ""))
      (if in.stepEscalate "reviewerSplit" "")
      (if (or in.riskHigh in.closureChanged) "riskHigh" "")
      (if (or (= in.paceFactorPct 0) (>= in.usedPct 95)) "paceHard" (if (< in.paceFactorPct 100) "paceSoft" ""))
      (if in.windowReset "windowReset" "")
      (if (or in.deadlinePassed in.pidDead) "leaseExpired" "")
      (if (or (>= in.mergesBehind 20) in.touchedChanged) "stale" "")
      (if (> (+ in.cuWaited in.cuParked) in.maxWait) "waitTooLong" "")
      (if (or in.claudeOnline (> in.claudeAllowance 0)) "claudeOnline" "")
      (if in.requestEnded "request" "")))

; (:m :do "trigger ids in priority order; infra suppresses every signature-bearing trigger")
fn triggerIds in: TrigIn -> (List String)
  (if (infraOnly in)
      (filter (fn [(id String)] -> Bool (or (= id "infra") (= id "leaseExpired") (= id "paceHard") (= id "paceSoft") (= id "windowReset") (= id "stale") (= id "waitTooLong") (= id "claudeOnline")))
        (listAppend (list "infra") (tailTriggers in)))
      (listAppend (resTriggers in) (tailTriggers in)))

fn fired in: TrigIn -> (List String)
  (triggerIds in)

; (:m :do "the action of the highest-priority fired trigger as id then action, empty when none fires")
fn decide in: TrigIn -> String
  (match (listHead (triggerIds in))
    ((some id) (str id ": " (actionOf id in)))
    (none ""))
