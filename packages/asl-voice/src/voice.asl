(module aslVoice/voice :x [AudioFormat AudioChunk VoiceFrame VoiceIntent processAudioChunk synthesizeSpeechEvent VoicePipelineConfig VoicePipelineState VoicePipelineResult makeVoicePipelineConfig makeInitialVoicePipelineState pipelineStepFrame pipelineParaphraseIntent pipelineFormatSpokenTts renderTerminalSparkline] :i [(asl-text/string :a s) (voice/voicePipeline :a vp) (voice/speakerMatch :a sm) (voice/audioFrame :a af)])

(enum AudioFormat (:c pcm16k [] "16kHz linear PCM") (:c pcm24k [] "24kHz linear PCM") (:c opus [] "compressed opus"))

(schema AudioChunk (:f id String) (:f format AudioFormat) (:f sampleRate I64) (:f byteLength I64) (:f timestamp I64))

(schema VoiceFrame (:f chunkId String) (:f transcript String) (:f isFinal Bool) (:f confidence F64) (:f latencyMs F64))

(schema VoiceIntent (:f intentName String) (:f rawSpeech String) (:f synthesizedAction String) (:f targetAgent String))

fn processAudioChunk chunk: AudioChunk -> VoiceFrame
  (let [(len chunk.byteLength) (conf (if (> len 1000) 0.95 0.60)) (lat (if (> len 5000) 0.050 0.010))] (VoiceFrame :chunkId chunk.id :transcript (str "Parsed chunk of length " (stringFromInt64 len)) :isFinal true :confidence conf :latencyMs lat))

fn synthesizeSpeechEvent text: String voiceId: String -> String
  (str "Synthesizing audio reply for voice " voiceId ": " text)

fn makeVoicePipelineConfig speaker: sm/SpeakerProfile deliveryMode: Str -> vp/VoicePipelineConfig
  (vp/makeVoicePipelineConfig speaker deliveryMode)

fn makeInitialVoicePipelineState -> vp/VoicePipelineState
  (vp/makeInitialVoicePipelineState)

fn pipelineStepFrame cfg: vp/VoicePipelineConfig st: vp/VoicePipelineState frame: af/AudioFrame frameSamples: (List F64) -> vp/VoicePipelineResult
  (vp/pipelineStepFrame cfg st frame frameSamples)

fn pipelineParaphraseIntent rawText: Str -> Str
  (vp/pipelineParaphraseIntent rawText)

fn pipelineFormatSpokenTts technicalText: Str -> Str
  (vp/pipelineFormatSpokenTts technicalText)

fn renderTerminalSparkline db: F64 isSpeech: Bool -> Str
  (vp/renderTerminalSparkline db isSpeech)
