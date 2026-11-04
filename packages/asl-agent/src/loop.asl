(module aslAgent/loop
  :x [sessionHeader endStatus finalGatesGreen preserveFiles handBackRestore loopBoundary specCheckKind finalOutcome specCheckAction]
  :i [(aslAgent/core :a c)])

fn quoteAsn s: String -> String
  (str "\"" (c/escapeAsn s) "\"")

fn quoteList xs: (List String) -> String
  (str "(" (c/joinSep (map quoteAsn xs) " ") ")")

fn sessionHeader session: String task: String modeHint: String intent: String root: String owns: (List String) gates: (List String) base: String model: String profile: String transport: String gateTimeout: String contextTokens: String wallBudget: String plan: Bool -> String
  (str "(:session :id " (quoteAsn session) " :task " (quoteAsn task)
       (if (= modeHint "") "" (str " :modeHint " (quoteAsn modeHint)))
       " :intent " (quoteAsn intent) " :root " (quoteAsn root)
       " :owns " (quoteList owns) " :gates " (quoteList gates)
       " :base " (quoteAsn base) " :model " (quoteAsn model) " :profile " (quoteAsn profile) " " transport
       " :gateTimeout " gateTimeout " :contextTokens " contextTokens
       (if (= wallBudget "") "" (str " :wallBudget " wallBudget))
       (if plan " :plan true" "") ")\n")

; (:m :ref ENDSTATUS-FALSEFAIL :do "a non-claim-backed finding only downgrades a scout/report delivery; a patch delivery that carries stale ad-hoc findings data (e.g. a parser fallback that wrapped a reply fragment as a finding on an earlier turn) must not be thrown away once its own gate and gateIntegrity already passed")
fn endStatus status: String deliver: String hasFindings: Bool hasClaim: Bool -> String
  (if (and (= status "ok")
           (and (!= deliver "patch") (and hasFindings (not hasClaim))))
    "failed"
    status)

fn finalGatesGreen results: (List String) -> Bool
  (if (listEmpty? results)
    true
    (and (= (c/firstOf results) "1") (finalGatesGreen (c/restOf results))))

fn preserveFiles status: String escalate: String gateRetries: Int64 stepRetries: Int64 parseDefects: Int64 gatesGreen: Bool -> Bool
  (and (= status "escalated")
    (and (= gateRetries 0)
      (and (= stepRetries 0)
        (and (= parseDefects 0) gatesGreen))))

fn handBackRestore status: String preserve: Bool -> Bool
  (and (not (= status "ok")) (and (not (= status "needsReview")) (not preserve)))

fn noWriteLimitReached runTurns: Float64 turnLimit: Float64 wallBudget: Int64 elapsed: Float64 share: Float64 -> Bool
  (or (>= runTurns turnLimit)
    (and (> wallBudget 0)
      (>= elapsed (* (optionOr (stringToFloat64 (stringFromInt64 wallBudget)) 0.0) share))))

; (:m :ref LEON-TURN-RUNAWAY-20261017 :do "the noWriteTurns/noWriteWall branch below only ever applies once the model has declared deliver=patch; a reply with no parseable op at all (pure inert prose, no :intent, no :done) never sets deliver, so a model that just rambles turn after turn was caught by nothing shorter than the full turn budget (default 3000) -- ccBeam's implement-constraints-from-spec run took 165 consecutive non-actionable replies before its first real op; parseDefects (a same-turn streak, reset by noteParseTurn on any non-defect turn) closes that gap independent of deliver")
; (:m :ref FREEBENCH-TOKENBUDGET-20261017 :do "a case-level cumulative input-token cap, independent of the turn-count budget above: a verbose model can burn a real-money token budget in a handful of turns, long before the 3000-turn default ever trips; inputTokenBudget 0 means no cap (unset, the default for every caller outside the bench harness)")
; (:m :ref LEON-WALLBUDGET-ORPHAN :do "a run past its :wallBudget ends at the next turn boundary with a receipt, whatever else it is doing; before this only a run that had written nothing ever looked at the wall clock")
fn loopBoundary redGate: Bool readStreak: Int64 readLimit: Int64 deliver: String writesPersisted: Bool runTurns: Float64 noWriteTurnLimit: Float64 wallBudget: Int64 elapsed: Float64 share: Float64 nextTurn: Int64 budget: Int64 parseDefects: Int64 parseDefectLimit: Int64 inputTokens: Int64 inputTokenBudget: Int64 -> String
  (cond
    ((and redGate (>= readStreak readLimit)) "readStreak")
    ((>= parseDefects parseDefectLimit) "parseDefect")
    ((and (> share 0.0) (= deliver "patch") (not writesPersisted) (> runTurns 0.0)
          (noWriteLimitReached runTurns noWriteTurnLimit wallBudget elapsed share))
      (if (>= runTurns noWriteTurnLimit) "noWriteTurns" "noWriteWall"))
    ((and (> wallBudget 0) (>= elapsed (int64ToFloat64 wallBudget))) "wallBudget")
    ((> nextTurn budget) "budget")
    ((and (> inputTokenBudget 0) (>= inputTokens inputTokenBudget)) "tokenBudget")
    (else "continue"))

fn specCheckKind turnBlocked: Bool enabled: Bool deliver: String writesPersisted: Bool hasFindings: Bool findingsCheckEnabled: Bool checksDone: Int64 checksMax: Int64 -> String
  (cond
    ((and (not turnBlocked) (and enabled (and (= deliver "patch") (and writesPersisted (< checksDone checksMax))))) "patch")
    ((and (not turnBlocked) (and enabled (and (= deliver "findings") (and hasFindings (and findingsCheckEnabled (< checksDone checksMax)))))) "findings")
    (else "none"))

fn finalOutcome status: String deliver: String hasFindings: Bool hasClaim: Bool baseUnbacked: Int64 planUnmet: Int64 -> String
  (str (endStatus status deliver hasFindings hasClaim) "|" (stringFromInt64 (+ baseUnbacked planUnmet)))

fn specCheckAction hasError: Bool met: Bool checksDone: Int64 checksMax: Int64 -> String
  (cond
    (hasError "error")
    (met "met")
    ((>= checksDone checksMax) "escalate")
    (else "retry"))
