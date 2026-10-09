(module asl-audio/voiceIntent :x [VoiceIntent TwoPhaseCommitState classifyIntentTeleologyTier extractActionFromUtterance parseVoiceIntent makeInitial2PcState initiateTwoPhaseCommit evaluateTwoPhaseCommit isConfirmationUtterance? isCancellationUtterance?] :i [(asl-audio/heardname :a hn)])

(schema VoiceIntent
  (:f rawUtterance String)
  (:f action String)
  (:f targetSymbol String)
  (:f targetPath String)
  (:f tier String)
  (:f requires2Pc Bool))

(schema TwoPhaseCommitState
  (:f pendingAction String)
  (:f pendingSymbol String)
  (:f isPending Bool)
  (:f timeoutSeconds Int64)
  (:f confirmedByUser Bool)
  (:f isCancelled Bool))

fn classifyIntentTeleologyTier action: String -> String
  (if (or (= action "flush") (or (= action "reset") (or (= action "kill") (or (= action "delete") (= action "rm")))))
    "tier2"
    "tier1")

fn extractActionFromUtterance utterance: String -> String
  (let [(low (stringLower utterance))]
    (if (or (stringContains? low "тест") (or (stringContains? low "test") (stringContains? low "запусти тесты")))
      "test"
      (if (or (stringContains? low "проверь") (stringContains? low "check"))
        "check"
        (if (or (stringContains? low "прочитай") (stringContains? low "read"))
          "read"
          (if (or (stringContains? low "примени") (or (stringContains? low "сохрани") (stringContains? low "flush")))
            "flush"
            (if (or (stringContains? low "сбрось") (stringContains? low "reset"))
              "reset"
              (if (or (stringContains? low "убей") (or (stringContains? low "останови") (stringContains? low "kill")))
                "kill"
                (if (or (stringContains? low "измени") (stringContains? low "edit"))
                  "edit"
                  "query"))))))))

fn parseVoiceIntent utterance: String candidates: (List hn/AstSymbolCandidate) -> VoiceIntent
  (let [(act (extractActionFromUtterance utterance))]
    (let [(tier (classifyIntentTeleologyTier act))]
      (let [(req2Pc (= tier "tier2"))]
        (let [(matchRes (hn/matchVoiceQueryToAstSymbol utterance candidates 0.60))]
          (let [(targetSym (if matchRes.isMatched matchRes.matchedSymbol ""))
                (targetP (if matchRes.isMatched matchRes.matchedPath ""))]
            (VoiceIntent
              :rawUtterance utterance
              :action act
              :targetSymbol targetSym
              :targetPath targetP
              :tier tier
              :requires2Pc req2Pc))))))

fn makeInitial2PcState -> TwoPhaseCommitState
  (TwoPhaseCommitState
    :pendingAction ""
    :pendingSymbol ""
    :isPending false
    :timeoutSeconds 15
    :confirmedByUser false
    :isCancelled false)

fn initiateTwoPhaseCommit intent: VoiceIntent -> TwoPhaseCommitState
  (TwoPhaseCommitState
    :pendingAction intent.action
    :pendingSymbol intent.targetSymbol
    :isPending true
    :timeoutSeconds 15
    :confirmedByUser false
    :isCancelled false)

fn isConfirmationUtterance? feedback: String -> Bool
  (let [(low (stringLower (stringTrim feedback)))]
    (or (= low "применить") (or (= low "да") (or (= low "подтверждаю") (or (= low "apply") (or (= low "confirm") (= low "yes")))))))

fn isCancellationUtterance? feedback: String -> Bool
  (let [(low (stringLower (stringTrim feedback)))]
    (or (= low "отмена") (or (= low "нет") (or (= low "отменить") (or (= low "cancel") (or (= low "abort") (= low "no")))))))

fn evaluateTwoPhaseCommit st: TwoPhaseCommitState spokenFeedback: String isTimeout: Bool -> TwoPhaseCommitState
  (if (= isTimeout true)
    (with st :isPending false :confirmedByUser false :isCancelled true)
    (if (isConfirmationUtterance? spokenFeedback)
      (with st :isPending false :confirmedByUser true :isCancelled false)
      (if (isCancellationUtterance? spokenFeedback)
        (with st :isPending false :confirmedByUser false :isCancelled true)
        st)))
