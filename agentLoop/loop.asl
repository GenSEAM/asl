(module asl/agentLoop/loop
  :x [sessionHeader endStatus finalGatesGreen preserveFiles handBackRestore loopBoundary specCheckKind finalOutcome specCheckAction]
  :i [(asl/agentLoop/core :a c)])

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

fn endStatus status: String deliver: String hasFindings: Bool hasClaim: Bool -> String
  (if (and (= status "ok")
           (or (and hasFindings (not hasClaim))
               (and (= deliver "findings") (not hasClaim))))
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
  (and (not (= status "ok")) (not preserve))

fn noWriteLimitReached runTurns: Float64 turnLimit: Float64 wallBudget: Int64 elapsed: Float64 share: Float64 -> Bool
  (or (>= runTurns turnLimit)
    (and (> wallBudget 0)
      (>= elapsed (* (optionOr (stringToFloat64 (stringFromInt64 wallBudget)) 0.0) share))))

fn loopBoundary redGate: Bool readStreak: Int64 readLimit: Int64 deliver: String writesPersisted: Bool runTurns: Float64 noWriteTurnLimit: Float64 wallBudget: Int64 elapsed: Float64 share: Float64 nextTurn: Int64 budget: Int64 -> String
  (cond
    ((and redGate (>= readStreak readLimit)) "readStreak")
    ((and (> share 0.0) (= deliver "patch") (not writesPersisted) (> runTurns 0.0)
          (noWriteLimitReached runTurns noWriteTurnLimit wallBudget elapsed share))
      (if (>= runTurns noWriteTurnLimit) "noWriteTurns" "noWriteWall"))
    ((> nextTurn budget) "budget")
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
