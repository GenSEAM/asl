(module asl-voice/voice
  :doc "Real-time Voice Stream Assistant Protocol in ASL Nano"
  :export [AudioFormat AudioChunk VoiceFrame VoiceIntent process-audio-chunk synthesize-speech-event]
  :import [(core/strings :as s)])

(dfe AudioFormat
  (:case pcm-16k [] "16kHz linear PCM")
  (:case pcm-24k [] "24kHz linear PCM")
  (:case opus [] "compressed opus"))

(dfs AudioChunk
  (:field id Str "chunk id")
  (:field format AudioFormat "audio format")
  (:field sample-rate I64 "sample rate")
  (:field byte-length I64 "byte length")
  (:field timestamp I64 "timestamp"))

(dfs VoiceFrame
  (:field chunk-id Str "chunk id")
  (:field transcript Str "transcript")
  (:field is-final Bool "is final flag")
  (:field confidence F64 "confidence score")
  (:field latency-ms F64 "latency in ms"))

(dfs VoiceIntent
  (:field intent-name Str "intent name")
  (:field raw-speech Str "speech text")
  (:field synthesized-action Str "action")
  (:field target-agent Str "agent id"))

(df process-audio-chunk [(chunk AudioChunk)] -> VoiceFrame
  :doc "Processes raw audio chunk"
  [(.-id chunk) "Voice command parsed" true 0.98 0.025])

(df synthesize-speech-event [(text Str) (voice-id Str)] -> Str
  :doc "Synthesizes voice event metadata"
  (s/concat "Synthesizing audio reply: " text))
