(module asl-audio/tests/vadTest :x [runVadTests] :i [(asl-audio/vad :a vad) (asl-audio/dictation :a dict)])

fn runVadTests -> Bool
  (do
    (let [(quietDbfs (vad/calculateDbfs 0.0001))
          (loudDbfs (vad/calculateDbfs 0.1))
          (maxDbfs (vad/calculateDbfs 1.0))]
      (assert (<= quietDbfs -65.0) "Quiet signal must be near floor -70 dBFS")
      (assert (and (> loudDbfs -25.0) (< loudDbfs -15.0)) "0.1 amplitude should be near -20 dBFS")
      (assert (= maxDbfs 0.0) "Full scale amplitude must be 0 dBFS"))

    (let [(zcrLow (vad/computeZcr 10 160))
          (zcrHigh (vad/computeZcr 90 160))]
      (assert (< zcrLow 0.10) "10 sign changes in 160 samples must be < 0.10 ZCR")
      (assert (> zcrHigh 0.50) "90 sign changes in 160 samples must be > 0.50 ZCR"))

  (let [(floor1 (vad/updateNoiseFloorDb -55.0 -60.0 -70.0 -25.0 false))
        (floorFrozen (vad/updateNoiseFloorDb -55.0 -30.0 -70.0 -25.0 true))]
    (assert (< floor1 -55.0) "Noise floor should adapt downward toward -60 dBFS in quiet")
    (assert (= floorFrozen -55.0) "Noise floor must NOT adapt during active speech"))

  (let [(cfg (vad/VadConfig
               :minFloorDb -70.0
               :maxFloorDb -25.0
               :speechTriggerMarginDb 12.0
               :speechReleaseMarginDb 6.0
               :minZcr 0.08
               :maxZcr 0.45
               :transientClickZcr 0.50
               :minDwellFrames 3
               :hangoverFrames 14))
        (st0 (vad/makeInitialVadState))
        (stAfterClick (vad/stepVadWithZcr cfg st0 -35.0 0.65 false))]
    (assert (= st0.isSpeechActive false) "Check isSpeechActive on st0")
    (assert (= stAfterClick.isSpeechActive false) "Click must not trigger speech"))

  (let [(cfg (vad/VadConfig
               :minFloorDb -70.0
               :maxFloorDb -25.0
               :speechTriggerMarginDb 12.0
               :speechReleaseMarginDb 6.0
               :minZcr 0.08
               :maxZcr 0.45
               :transientClickZcr 0.50
               :minDwellFrames 3
               :hangoverFrames 14))
        (st0 (vad/makeInitialVadState))
        (st1 (vad/stepVadWithZcr cfg st0 -38.0 0.22 false))
        (st2 (vad/stepVadWithZcr cfg st1 -37.0 0.24 false))
        (st3 (vad/stepVadWithZcr cfg st2 -36.0 0.21 false))]
    (assert (= st1.consecutiveSpeechFrames 1) "st1 speech count must be 1")
    (assert (= st2.consecutiveSpeechFrames 2) "st2 speech count must be 2")
    (assert (= st3.consecutiveSpeechFrames 3) "st3 speech count must be 3")
    (assert (= st1.isSpeechActive false) "st1 must not be active")
    (assert (= st2.isSpeechActive false) "st2 must not be active")
    (assert (= st3.isSpeechActive true) "st3 must be active"))

  (let [(cfg (vad/VadConfig
               :minFloorDb -70.0
               :maxFloorDb -25.0
               :speechTriggerMarginDb 12.0
               :speechReleaseMarginDb 6.0
               :minZcr 0.08
               :maxZcr 0.45
               :transientClickZcr 0.50
               :minDwellFrames 1
               :hangoverFrames 14))
        (st0 (vad/makeInitialVadState))
        (stBargeIn (vad/stepVadWithZcr cfg st0 -35.0 0.20 true))]
    (assert (= stBargeIn.isBargeInTriggered true) "Speech during active TTS must trigger barge-in event"))

  (let [(cont1 (dict/isContinuationWord "для"))
        (cont2 (dict/isContinuationWord "запусти"))
        (cont3 (dict/isContinuationWord "for"))
        (fast1 (dict/isFastPathWord "стоп"))
        (fast2 (dict/isFastPathWord "применить"))
        (regular (dict/isContinuationWord "тест"))]
    (assert (= cont1 true) "Russian preposition 'для' must be recognized as continuation")
    (assert (= cont2 true) "Russian transitive verb 'запусти' must be continuation")
    (assert (= cont3 true) "English preposition 'for' must be continuation")
    (assert (= fast1 true) "Command 'стоп' must be fast-path")
    (assert (= fast2 true) "Command 'применить' must be fast-path")
    (assert (= regular false) "Noun 'тест' is not a continuation token"))

  (let [(hCont (dict/calculateDynamicHangoverMs "для"))
        (hFast (dict/calculateDynamicHangoverMs "стоп"))
        (hNorm (dict/calculateDynamicHangoverMs "коммит"))]
    (assert (= hCont 1400) "Continuation word hangover must be 1400 ms")
    (assert (= hFast 150) "Fast-path word hangover must be 150 ms")
    (assert (= hNorm 550) "Normal sentence hangover must be 550 ms"))

  (let [(b0 (dict/makeInitialDictationBuffer))
        (b1 (dict/accumulateUtterance b0 "запусти тесты" 1000))
        (b2 (dict/accumulateUtterance b1 "для свифта" 1400))
        (bHeld (dict/stepDictationTimer b2 1800 15000))
        (bFinal (dict/stepDictationTimer b2 2900 15000))]
    (assert (= b2.textPayload "запусти тесты для свифта") "Transcript fragments must merge cleanly")
    (assert (= bHeld.isFinalized false) "Buffer should not finalize during continuation hangover (elapsed 400ms < 1400ms)")
    (assert (= bFinal.isFinalized true) "Buffer must finalize when elapsed > dynamic hangover (elapsed 1500ms > 1400ms)"))

    true)

fn main -> Int64
  (if (runVadTests) 0 1)
