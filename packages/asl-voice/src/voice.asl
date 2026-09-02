(module asl-voice/voice
  :doc "Real-time Voice Stream Assistant Protocol in ASL"
  :export [AudioFormat AudioChunk VoiceFrame VoiceIntent process-audio-chunk synthesize-speech-event]
  :import [(core/strings :as s)])

(defenum AudioFormat
  (:case pcm-16k [] "16kHz linear PCM")
  (:case pcm-24k [] "24kHz linear PCM")
  (:case opus [] "compressed opus"))

(defschema AudioChunk
  (:field id String "chunk id")
  (:field format AudioFormat "audio format")
  (:field sample-rate Int64 "sample rate")
  (:field byte-length Int64 "byte length")
  (:field timestamp Int64 "timestamp"))

(defschema VoiceFrame
  (:field chunk-id String "chunk id")
  (:field transcript String "transcript")
  (:field is-final Bool "is final flag")
  (:field confidence Float "confidence score")
  (:field latency-ms Float "latency in ms"))

(defschema VoiceIntent
  (:field intent-name String "intent name")
  (:field raw-speech String "speech text")
  (:field synthesized-action String "action")
  (:field target-agent String "agent id"))

(defun process-audio-chunk [(chunk AudioChunk)] -> VoiceFrame
  :doc "Processes raw audio chunk"
  (VoiceFrame :chunk-id (.-id chunk) :transcript "Voice command parsed" :is-final true :confidence 0.98 :latency-ms 0.025))

(defun synthesize-speech-event [(text String) (voice-id String)] -> String
  :doc "Synthesizes voice event metadata"
  (s/concat (s/concat "Synthesizing audio reply for voice " voice-id) (s/concat ": " text)))
