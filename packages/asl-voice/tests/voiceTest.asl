(module aslVoice/test :x [runTests] :i [(voice/vad :a vad) (voice/voice :a v)])

fn testVadConfig -> Bool
  (let [(cfg (vad/makeVadConfig 16000))] (assert (= cfg.sampleRate 16000) "Sample rate must equal 16000") (assert (= cfg.frameSize 160) "Frame size must equal 160") true)

fn testVadState -> Bool
  (let [(st (vad/makeInitialVadState))] (assert (not st.isSpeech) "Initial VAD state must not be speech") (assert (= st.consecutiveSpeech 0) "Consecutive speech must equal 0") true)

fn testAudioChunk -> Bool
  (let [(chk (v/AudioChunk :id "chk-1" :format (pcm16k) :sampleRate 16000 :byteLength 320 :timestamp 1000)) (frame (v/processAudioChunk chk))] (assert (= frame.chunkId "chk-1") "Chunk id must equal chk-1") (assert frame.isFinal "Audio frame must be final") true)

fn testSpeechSynth -> Bool
  (let [(res (v/synthesizeSpeechEvent "Hello world" "eddie-v1"))] (assert (> (stringLength res) 0) "Synthesized speech event must be non-empty") (assert (not (stringContains? res "error")) "Speech event must not contain error") true)

fn testComputeEnergy -> Bool
  (let [(e0 (vad/computeEnergy (list))) (e1 (vad/computeEnergy (list 0.1 0.2 0.3)))] (assert (<= e0 0.001) "Empty samples energy must be 0") (assert (> e1 0.0) "Non-empty samples energy must be greater than 0") true)

fn runTests -> Bool
  (do (assert (testVadConfig) "test-vad-config must pass") (assert (testVadState) "test-vad-state must pass") (assert (testComputeEnergy) "test-compute-energy must pass") (assert (testAudioChunk) "test-audio-chunk must pass") (assert (testSpeechSynth) "test-speech-synth must pass") true)
