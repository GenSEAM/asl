(module aslVoice/vad :x [VadConfig VadState BargeInEvent makeVadConfig makeInitialVadState computeEnergy computeZcr isSpeechFrame isSpeechFrame? stepVad triggerBargeIn detectVoiceActivity sliceUtteranceFrames] :i [(asl-text/string :a s)])

(schema VadConfig (:f sampleRate I64) (:f frameSize I64) (:f energyThreshold F64) (:f zcrThreshold F64) (:f hangoverFrames I64))

(schema VadState (:f isSpeech Bool) (:f consecutiveSpeech I64) (:f consecutiveSilence I64) (:f currentEnergy F64))

(schema BargeInEvent (:f targetAgent Str) (:f timestamp I64) (:f cutoffLatencyMs F64))

fn makeVadConfig sampleRate: I64 -> VadConfig
  (VadConfig :sampleRate sampleRate :frameSize 160 :energyThreshold 0.015 :zcrThreshold 0.08 :hangoverFrames 5)

fn makeInitialVadState -> VadState
  (VadState :isSpeech false :consecutiveSpeech 0 :consecutiveSilence 0 :currentEnergy 0.0)

fn computeEnergy samples: (List F64) -> F64
  (if (listEmpty? samples) 0.0 (let [(sum (fold (fn [(acc F64) (s F64)] -> F64 (+ acc (* s s))) 0.0 samples)) (n (listLength samples))] (if (> n 0) (/ sum (int64ToFloat64 n)) 0.0)))

fn isSpeechFrame energy: F64 threshold: F64 -> Bool
  (> energy threshold)

fn isSpeechFrame? energy: F64 threshold: F64 -> Bool
  (> energy threshold)

(schema ZcrState (:f prev F64) (:f count I64))

fn computeZcr samples: (List F64) -> F64
  (let [(n (listLength samples))] (if (<= n 1) 0.0 (let [(h (optionOr (listHead samples) 0.0)) (t (optionOr (listTail samples) (list))) (finalState (fold (fn [(acc ZcrState) (curr F64)] -> ZcrState (let [(prev acc.prev) (cross? (or (and (< prev 0.0) (> curr 0.0)) (and (> prev 0.0) (< curr 0.0)))) (newCount (if cross? (+ acc.count 1) acc.count))] (ZcrState :prev curr :count newCount))) (ZcrState :prev h :count 0) t)) (crossings finalState.count)] (/ (int64ToFloat64 crossings) (int64ToFloat64 (- n 1))))))

fn detectVoiceActivity samples: (List F64) cfg: VadConfig -> Bool
  (if (listEmpty? samples) false (let [(energy (computeEnergy samples))] (isSpeechFrame? energy cfg.energyThreshold)))

fn stepVad cfg: VadConfig st: VadState frameEnergy: F64 -> VadState
  (let [(speech? (isSpeechFrame? frameEnergy cfg.energyThreshold))] (if speech? (VadState :isSpeech true :consecutiveSpeech (+ st.consecutiveSpeech 1) :consecutiveSilence 0 :currentEnergy frameEnergy) (let [(silenceCount (+ st.consecutiveSilence 1)) (stillSpeaking? (and st.isSpeech (<= silenceCount cfg.hangoverFrames)))] (VadState :isSpeech stillSpeaking? :consecutiveSpeech 0 :consecutiveSilence silenceCount :currentEnergy frameEnergy))))

(schema SliceState (:f st VadState) (:f acc (List (List F64))))

fn sliceUtteranceFrames frames: (List (List F64)) cfg: VadConfig -> (List (List F64))
  (let [(final (fold (fn [(acc SliceState) (frame (List F64))] -> SliceState (let [(energy (computeEnergy frame)) (nextSt (stepVad cfg acc.st energy)) (nextAcc (if nextSt.isSpeech (listAppend acc.acc (list frame)) acc.acc))] (SliceState :st nextSt :acc nextAcc))) (SliceState :st (makeInitialVadState) :acc (list)) frames))] final.acc)

fn triggerBargeIn agentId: Str timestamp: I64 latencyMs: F64 -> BargeInEvent
  (BargeInEvent :targetAgent agentId :timestamp timestamp :cutoffLatencyMs latencyMs)
