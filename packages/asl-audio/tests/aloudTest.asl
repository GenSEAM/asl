(module asl-audio/tests/aloudTest :x [runAloudTests runTests] :i [(asl-audio/aloud :a aloud) (asl-audio/voiceIntent :a vi) (asl-audio/heardname :a hn)])

fn runTests -> Bool
  (runAloudTests)

fn runAloudTests -> Bool
  (let [(shortText "Короткий дайджест")
        (longText "Это очень длинный текст системного отчета, который заведомо превышает предел внимания слушателя в восемь секунд или сто двенадцать печатных символов на естественном языке.")
        (formattedShort (aloud/formatAloudDigest shortText 112))
        (formattedLong (aloud/formatAloudDigest longText 112))
        (lenLong (stringLength formattedLong))]
    (assert (= formattedShort shortText) "Short text must not be truncated")
    (assert (<= lenLong 112) "Formatted digest must strictly fit within 112 characters")
    (assert (stringContains? formattedLong "...") "Truncated digest must end with ellipsis")
    (assert (= (aloud/isWithinEarBudget? shortText 112) true) "Short text is within budget")
    (assert (= (aloud/isWithinEarBudget? longText 112) false) "Long text exceeds budget"))

  (let [(greenDigest (aloud/formatAuditDigestAloud 7 0 14))
        (redDigest (aloud/formatAuditDigestAloud 6 1 12))]
    (assert (stringContains? greenDigest "Аудит пройден: 7 гейтов зеленые, 14 мутантов убито.") "Green audit digest format")
    (assert (stringContains? redDigest "Аудит провален: 1 гейтов красные, 6 зеленые.") "Red audit digest format")
    (assert (<= (stringLength greenDigest) 112) "Green audit must be <= 112 chars")
    (assert (<= (stringLength redDigest) 112) "Red audit must be <= 112 chars"))

  (let [(attDigest (aloud/formatAttentionDigestAloud "flush" "asl/target/swift"))
        (lenAtt (stringLength attDigest))]
    (assert (<= lenAtt 48) "Attention rail digest must be <= 48 chars")
    (assert (stringContains? attDigest "Применить") "Attention digest must prompt user"))

  (let [(tTest (vi/classifyIntentTeleologyTier "test"))
        (tRead (vi/classifyIntentTeleologyTier "read"))
        (tCheck (vi/classifyIntentTeleologyTier "check"))
        (tFlush (vi/classifyIntentTeleologyTier "flush"))
        (tReset (vi/classifyIntentTeleologyTier "reset"))
        (tKill (vi/classifyIntentTeleologyTier "kill"))]
    (assert (= tTest "tier1") "test must be tier1 (non-destructive)")
    (assert (= tRead "tier1") "read must be tier1 (non-destructive)")
    (assert (= tCheck "tier1") "check must be tier1 (non-destructive)")
    (assert (= tFlush "tier2") "flush must be tier2 (destructive)")
    (assert (= tReset "tier2") "reset must be tier2 (destructive)")
    (assert (= tKill "tier2") "kill must be tier2 (destructive)"))

  (let [(c1 (hn/makeAstSymbolCandidate "emitSwift" "asl/packages/asl-target-swift/src/emitSwift.asl" "fn"))
        (c2 (hn/makeAstSymbolCandidate "terminalCanvas" "asl/packages/asl-ui/src/terminalCanvas.asl" "fn"))
        (candidates (list c1 c2))]
    (let [(intentTest (vi/parseVoiceIntent "запусти тесты на эмит свифт" candidates))
          (intentFlush (vi/parseVoiceIntent "примени изменения в коде" candidates))]
      (assert (= intentTest.action "test") "Action must be test")
      (assert (= intentTest.tier "tier1") "Tier must be tier1")
      (assert (= intentTest.requires2Pc false) "Tier 1 does not require 2PC")
      (assert (= intentTest.targetSymbol "emitSwift") "Target symbol must resolve to emitSwift")

      (assert (= intentFlush.action "flush") "Action must be flush")
      (assert (= intentFlush.tier "tier2") "Tier must be tier2")
      (assert (= intentFlush.requires2Pc true) "Tier 2 strictly requires 2PC confirmation")))

  (assert (= (vi/isConfirmationUtterance? "применить") true) "isConfirmationUtterance? must be true for применить")
  (assert (= (vi/isCancellationUtterance? "отмена") true) "isCancellationUtterance? must be true for отмена")
  (let [(c1 (hn/makeAstSymbolCandidate "emitSwift" "path" "fn"))
        (cand (list c1))]
    (let [(intentFlush (vi/parseVoiceIntent "примени изменения" cand))]
      (let [(s0 (vi/initiateTwoPhaseCommit intentFlush))]
        (assert (= s0.isPending true) "2PC must be pending initially")
        (assert (= s0.confirmedByUser false) "2PC must not be confirmed initially")
        (assert (= s0.isCancelled false) "2PC must not be cancelled initially")
        (assert (= s0.timeoutSeconds 15) "Initial timeout must be 15s")
        (assert (= s0.pendingAction "flush") "Pending action must be flush")

        (let [(sConfirmed (vi/evaluateTwoPhaseCommit s0 "применить" false))]
          (assert (= sConfirmed.isPending false) "Pending cleared upon confirmation")
          (assert (= sConfirmed.confirmedByUser true) "Confirmed set to true")
          (assert (= sConfirmed.isCancelled false) "Cancelled remains false"))

        (let [(sCancelled (vi/evaluateTwoPhaseCommit s0 "отмена" false))]
          (assert (= sCancelled.isPending false) "Pending cleared upon cancellation")
          (assert (= sCancelled.confirmedByUser false) "Confirmed remains false")
          (assert (= sCancelled.isCancelled true) "Cancelled set to true"))

        (let [(sTimeout (vi/evaluateTwoPhaseCommit s0 "" true))]
          (assert (= sTimeout.isPending false) "Pending cleared upon timeout")
          (assert (= sTimeout.confirmedByUser false) "Confirmed remains false")
          (assert (= sTimeout.isCancelled true) "Cancelled set to true on timeout")))))

  true

fn main -> Int64
  (if (runAloudTests) 0 1)
