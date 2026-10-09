(module aslVoice/conversationalContext
  :x [SpeakerTurn ConversationalContext conversationalContextCreate recordTurn checkBargeInInterrupt]
  :i [])

(schema SpeakerTurn
  (:f turnId Str)
  (:f speakerId Str)
  (:f transcript Str)
  (:f resolvedDomain Str)
  (:f executedReceipt Str)
  (:f timestamp I64))

(schema ConversationalContext
  (:f turns (List SpeakerTurn))
  (:f activeSpeaker Str)
  (:f isSpeaking Bool)
  (:f bargeInDetected Bool))

fn conversationalContextCreate activeSpeaker: Str -> ConversationalContext
  (ConversationalContext
    :turns (list)
    :activeSpeaker activeSpeaker
    :isSpeaking false
    :bargeInDetected false)

fn recordTurn ctx: ConversationalContext turn: SpeakerTurn -> ConversationalContext
  (let [(updatedTurns (listAppend ctx.turns (list turn)))]
    (with ctx :turns updatedTurns :isSpeaking false :bargeInDetected false))

fn checkBargeInInterrupt ctx: ConversationalContext isSystemAudioPlaying: Bool isUserVoicing: Bool -> (Pair ConversationalContext Bool)
  (if (and isSystemAudioPlaying isUserVoicing)
    (pair
      (with ctx :isSpeaking true :bargeInDetected true)
      true)
    (pair
      (with ctx :isSpeaking isUserVoicing :bargeInDetected false)
      false))
