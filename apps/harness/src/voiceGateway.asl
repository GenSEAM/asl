(module aslHarness/voiceGateway :x [VoicePcmFrame RawAsrTranscript VoiceRouteDecision makePcmFrame ingestPcmFrame isSearchIntent? isActionIntent? classifyVoiceIntent getGatewayVersion] :i [])

(schema VoicePcmFrame (:f frameId Str) (:f sampleRate I64) (:f durationMs I64) (:f isSpeech Bool))

(schema RawAsrTranscript (:f frameId Str) (:f text Str) (:f language Str) (:f isFinal Bool) (:f confidence F64) (:f latencyMs I64))

(schema VoiceRouteDecision (:f routeTag Str) (:f targetPreset Str) (:f normalizedQuery Str) (:f groundingRequired Bool))

fn getGatewayVersion -> Str
  "1.0.0"

fn makePcmFrame id: Str isSpeech: Bool -> VoicePcmFrame
  (VoicePcmFrame :frameId id :sampleRate 16000 :durationMs 160 :isSpeech isSpeech)

fn ingestPcmFrame frame: VoicePcmFrame text: Str lang: Str isFinal: Bool -> RawAsrTranscript
  (RawAsrTranscript :frameId frame.frameId :text text :language lang :isFinal isFinal :confidence 0.96 :latencyMs 22)

fn isSearchIntent? text: Str -> Bool
  (let [(t (stringLower text))] (or (stringContains? t "что такое") (or (stringContains? t "какой") (or (stringContains? t "найди") (or (stringContains? t "сравни") (or (stringContains? t "what is") (or (stringContains? t "find") (or (stringContains? t "search") (stringContains? t "how to")))))))))

fn isActionIntent? text: Str -> Bool
  (let [(t (stringLower text))] (or (stringContains? t "кликни") (or (stringContains? t "открой") (or (stringContains? t "заполни") (or (stringContains? t "перейди") (or (stringContains? t "click") (or (stringContains? t "open") (or (stringContains? t "fill") (stringContains? t "scroll")))))))))

fn classifyVoiceIntent transcript: RawAsrTranscript -> VoiceRouteDecision
  (let [(text transcript.text)] (if (isActionIntent? text) (VoiceRouteDecision :routeTag ":agent-action" :targetPreset "preset-agent-action" :normalizedQuery text :groundingRequired false) (if (isSearchIntent? text) (VoiceRouteDecision :routeTag ":fast-search" :targetPreset "preset-fast-search" :normalizedQuery text :groundingRequired true) (VoiceRouteDecision :routeTag ":fast-search" :targetPreset "preset-fast-search" :normalizedQuery text :groundingRequired false))))
