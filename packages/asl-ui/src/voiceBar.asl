(module asl-ui/voiceBar :x [VoiceBarState makeVoiceBarState formatDbfsMeter formatVerificationBadge renderAttentionRailDrawer renderVoiceBarTile] :i [(asl-ui/vnode :a ui) (asl-ui/theme :a theme)])

(schema VoiceBarState
  (:f currentDbfs Float64)
  (:f noiseFloorDb Float64)
  (:f isSpeechActive Bool)
  (:f isSpeakerVerified Bool)
  (:f speakerConfidence Float64)
  (:f isAttentionRailOpen Bool)
  (:f pendingAction String)
  (:f pendingSymbol String))

fn makeVoiceBarState currentDbfs: Float64 noiseFloorDb: Float64 isSpeechActive: Bool isSpeakerVerified: Bool speakerConfidence: Float64 isAttentionRailOpen: Bool pendingAction: String pendingSymbol: String -> VoiceBarState
  (VoiceBarState
    :currentDbfs currentDbfs
    :noiseFloorDb noiseFloorDb
    :isSpeechActive isSpeechActive
    :isSpeakerVerified isSpeakerVerified
    :speakerConfidence speakerConfidence
    :isAttentionRailOpen isAttentionRailOpen
    :pendingAction pendingAction
    :pendingSymbol pendingSymbol)

fn formatDbfsMeter dbfs: Float64 isSpeech: Bool -> String
  (if (>= dbfs -20.0)
    (if isSpeech "[==========] -18.0 dBFS [SPEECH]" "[==========] -18.0 dBFS [HOT]")
    (if (>= dbfs -35.0)
      (if isSpeech "[======....] -30.0 dBFS [SPEECH]" "[======....] -30.0 dBFS [VOICE]")
      (if (>= dbfs -50.0)
        "[===.......] -45.0 dBFS [AMBIENT]"
        "[..........] -65.0 dBFS [QUIET]")))

fn formatVerificationBadge isVerified: Bool confidence: Float64 -> String
  (if isVerified
    "[BIOMETRICS: VERIFIED]"
    "[BIOMETRICS: UNVERIFIED]")

fn renderAttentionRailDrawer isOpen: Bool action: String symbol: String -> ui/VNode
  (if isOpen
    (let [(prompt (str "Внимание: Подтвердите действие '" action "' для " symbol "? (Скажите 'применить' или 'отмена')"))
          (attrs (mapSet (mapSet (mapEmpty) "class" "sds1-attention-rail-open") "data-action" action))]
      (ui/makeContainer "attention-rail-drawer" attrs (list (ui/makeText prompt "attention-prompt"))))
    (let [(attrs (mapSet (mapEmpty) "class" "sds1-attention-rail-closed"))]
      (ui/makeContainer "attention-rail-drawer" attrs (list))))

fn renderVoiceBarTile state: VoiceBarState -> ui/VNode
  (let [(meterText (formatDbfsMeter state.currentDbfs state.isSpeechActive))
        (badgeText (formatVerificationBadge state.isSpeakerVerified state.speakerConfidence))
        (drawerNode (renderAttentionRailDrawer state.isAttentionRailOpen state.pendingAction state.pendingSymbol))
        (meterNode (ui/makeText meterText "voice-meter-label"))
        (badgeNode (ui/makeText badgeText "voice-badge-label"))
        (attrs (mapSet (mapSet (mapEmpty) "class" "sds1-voice-bar-tile") "data-status" (if state.isSpeechActive "speech" "idle")))]
    (ui/makeContainer "voice-bar-root" attrs (list meterNode badgeNode drawerNode)))
