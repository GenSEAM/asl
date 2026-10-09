(module asl-ui/tests/voiceBarTest :x [runVoiceBarTests runTests] :i [(asl-ui/voiceBar :a vb) (asl-ui/vnode :a ui)])

fn runVoiceBarTests -> Bool
  (do
    (let [(mHotSpeech (vb/formatDbfsMeter -15.0 true))
          (mHotNoise (vb/formatDbfsMeter -15.0 false))
          (mVoiceSpeech (vb/formatDbfsMeter -30.0 true))
          (mVoiceNoise (vb/formatDbfsMeter -30.0 false))
          (mAmbient (vb/formatDbfsMeter -45.0 false))
          (mQuiet (vb/formatDbfsMeter -65.0 false))]
      (assert (= mHotSpeech "[==========] -18.0 dBFS [SPEECH]") "Hot speech cue")
      (assert (= mHotNoise "[==========] -18.0 dBFS [HOT]") "Hot noise cue")
      (assert (= mVoiceSpeech "[======....] -30.0 dBFS [SPEECH]") "Voice speech cue")
      (assert (= mVoiceNoise "[======....] -30.0 dBFS [VOICE]") "Voice background cue")
      (assert (= mAmbient "[===.......] -45.0 dBFS [AMBIENT]") "Ambient cue")
      (assert (= mQuiet "[..........] -65.0 dBFS [QUIET]") "Quiet room floor cue"))

    (let [(bVerified (vb/formatVerificationBadge true 0.88))
          (bUnverified (vb/formatVerificationBadge false 0.42))]
      (assert (= bVerified "[BIOMETRICS: VERIFIED]") "Verified biometrics badge")
      (assert (= bUnverified "[BIOMETRICS: UNVERIFIED]") "Unverified biometrics badge"))

    (let [(drawerOpen (vb/renderAttentionRailDrawer true "flush" "mySymbol"))
          (drawerClosed (vb/renderAttentionRailDrawer false "" ""))]
      (assert (= drawerOpen.tag "container") "Drawer open is container")
      (assert (= drawerOpen.key "attention-rail-drawer") "Drawer open key matches")
      (assert (= (listLength drawerOpen.children) 1) "Drawer open contains confirmation prompt")
      (assert (= drawerClosed.tag "container") "Drawer closed is container")
      (assert (= (listLength drawerClosed.children) 0) "Drawer closed has empty children"))

    (let [(stIdle (vb/makeVoiceBarState -55.0 -60.0 false false 0.0 false "" ""))
          (stActive (vb/makeVoiceBarState -24.0 -58.0 true true 0.85 true "flush" "mySymbol"))]
      (let [(vTileIdle (vb/renderVoiceBarTile stIdle))
            (vTileActive (vb/renderVoiceBarTile stActive))]
        (assert (= vTileIdle.tag "container") "Idle voice bar is container")
        (assert (= vTileIdle.key "voice-bar-root") "Voice bar root key")
        (assert (= (listLength vTileIdle.children) 3) "Voice bar tile contains 3 elements: meter, badge, drawer")
        (assert (= vTileActive.tag "container") "Active voice bar is container")
        (assert (= (listLength vTileActive.children) 3) "Active voice bar contains 3 elements")))
    true)

fn runTests -> Bool
  (runVoiceBarTests)
