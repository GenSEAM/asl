(module aslVoice/tests/vadTest :x [runTests testEnergyThresholds testZcrCalculation testVadHysteresis testSliceUtteranceFrames] :i [(voice/vad :a vad)])

fn testEnergyThresholds -> Bool
  (let [(cfg (vad/makeVadConfig 16000)) (e0 (vad/computeEnergy (list))) (eSilence (vad/computeEnergy (list 0.001 0.002 0.001))) (eSpeech (vad/computeEnergy (list 0.2 0.3 0.25)))] (assert (<= e0 0.0001) "Empty samples energy must be 0") (assert (not (vad/isSpeechFrame? eSilence cfg.energyThreshold)) "Silence frame must not trigger is-speech-frame?") (assert (vad/isSpeechFrame? eSpeech cfg.energyThreshold) "Speech frame must trigger is-speech-frame?") (assert (not (vad/detectVoiceActivity (list 0.001 0.002 0.001) cfg)) "Silence samples must not trigger detect-voice-activity") (assert (vad/detectVoiceActivity (list 0.2 0.3 0.25) cfg) "Speech samples must trigger detect-voice-activity") true)

fn testZcrCalculation -> Bool
  (let [(zFlat (vad/computeZcr (list 0.5 0.5 0.5 0.5))) (zCross (vad/computeZcr (list 0.5 -0.5 0.5 -0.5))) (zEmpty (vad/computeZcr (list)))] (assert (<= zFlat 0.001) "Flat positive waveform must have 0 zero-crossings") (assert (> zCross 0.99) "Alternating waveform must reach maximum zero-crossing rate") (assert (<= zEmpty 0.001) "Empty waveform ZCR must be 0") true)

fn testVadHysteresis -> Bool
  (let [(cfg (vad/VadConfig :sampleRate 16000 :frameSize 160 :energyThreshold 0.02 :zcrThreshold 0.08 :hangoverFrames 2)) (st0 (vad/makeInitialVadState)) (st1 (vad/stepVad cfg st0 0.001)) (st2 (vad/stepVad cfg st1 0.08)) (st3 (vad/stepVad cfg st2 0.005)) (st4 (vad/stepVad cfg st3 0.005)) (st5 (vad/stepVad cfg st4 0.005))] (assert (not st1.isSpeech) "Silence step on initial state must remain silent") (assert (= st1.consecutiveSilence 1) "Silence counter must increment to 1") (assert st2.isSpeech "Speech step must transition is-speech to true") (assert (= st2.consecutiveSpeech 1) "Speech counter must equal 1") (assert st3.isSpeech "Silence step within hangover 1 must retain speech state") (assert st4.isSpeech "Silence step within hangover 2 must retain speech state") (assert (not st5.isSpeech) "Silence step exceeding hangover 2 must transition to false") (assert (= st5.consecutiveSilence 3) "Consecutive silence must equal 3") true)

fn testSliceUtteranceFrames -> Bool
  (let [(cfg (vad/VadConfig :sampleRate 16000 :frameSize 160 :energyThreshold 0.02 :zcrThreshold 0.08 :hangoverFrames 1)) (fSilence (list 0.001 0.001 0.001)) (fSpeech1 (list 0.2 0.3 0.25)) (fSpeech2 (list 0.15 0.25 0.2)) (frames (list fSilence fSilence fSpeech1 fSpeech2 fSilence fSilence fSilence)) (sliced (vad/sliceUtteranceFrames frames cfg)) (emptySliced (vad/sliceUtteranceFrames (list) cfg))] (assert (= (listLength sliced) 3) "Sliced utterance frames must retain speech frames plus hangover frame") (assert (= (listLength emptySliced) 0) "Empty frames slice must return empty list") true)

fn runTests -> Bool
  (do (assert (testEnergyThresholds) "test-energy-thresholds must pass") (assert (testZcrCalculation) "test-zcr-calculation must pass") (assert (testVadHysteresis) "test-vad-hysteresis must pass") (assert (testSliceUtteranceFrames) "test-slice-utterance-frames must pass") true)
