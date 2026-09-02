(module asl-voice/voice
  :d "Real-time Voice Stream Assistant Protocol in ASL"
  :x [AudioFormat AudioChunk VoiceFrame VoiceIntent process-audio-chunk synthesize-speech-event]
  :i [(core/strings :a s)])

(dfe AudioFormat
  (:c pcm-16k [] "16kHz linear PCM")
  (:c pcm-24k [] "24kHz linear PCM")
  (:c opus [] "compressed opus"))

(dfs AudioChunk
  (:f id String "chunk id")
  (:f format AudioFormat "audio format")
  (:f sample-rate Int64 "sample rate")
  (:f byte-length Int64 "byte length")
  (:f timestamp Int64 "timestamp"))

(dfs VoiceFrame
  (:f chunk-id String "chunk id")
  (:f transcript String "transcript")
  (:f is-final Bool "is final flag")
  (:f confidence Float "confidence score")
  (:f latency-ms Float "latency in ms"))

(dfs VoiceIntent
  (:f intent-name String "intent name")
  (:f raw-speech String "speech text")
  (:f synthesized-action String "action")
  (:f target-agent String "agent id"))

(df process-audio-chunk [(chunk AudioChunk)] -> VoiceFrame
  :d "Processes raw audio chunk"
  (VoiceFrame :chunk-id (.-id chunk) :transcript "Voice command parsed" :is-final true :confidence 0.98 :latency-ms 0.025))

(df synthesize-speech-event [(text String) (voice-id String)] -> String
  :d "Synthesizes voice event metadata"
  (s/concat (s/concat "Synthesizing audio reply for voice " voice-id) (s/concat ": " text)))
