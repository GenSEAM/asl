(module aslVoice/ttsEngine :x [TtsEngineKind TtsEngineConfig TtsSynthesisJob makeSileroConfig makeKokoroConfig supportsLanguage? selectOptimalEngine createSynthesisJob sileroOnnx kokoroOnnx cloudStream terminalSilent] :i [(asl-text/string :a s)])

(enum TtsEngineKind (:c sileroOnnx [] "Silero TTS v4/v5 ONNX 24kHz (native Russian and English)") (:c kokoroOnnx [] "Kokoro TTS v1.0 ONNX 24kHz (English and select languages)") (:c cloudStream [] "Cloud streaming speech synthesis fallback") (:c terminalSilent [] "Terminal text-only fallback without audio synthesis"))

(schema TtsEngineConfig (:f engine TtsEngineKind) (:f modelPath Str) (:f sampleRate I64) (:f language Str) (:f voiceId Str) (:f speed F64))

(schema TtsSynthesisJob (:f jobId Str) (:f text Str) (:f config TtsEngineConfig) (:f status Str) (:f audioSamplesCount I64) (:f durationMs I64))

fn makeSileroConfig language: Str voiceId: Str -> TtsEngineConfig
  (TtsEngineConfig :engine (sileroOnnx) :modelPath "~/.asl/models/silero_v4.onnx" :sampleRate 24000 :language language :voiceId (if (= voiceId "") (if (= language "ru") "xenia" "en_0") voiceId) :speed 1.0)

fn makeKokoroConfig voiceId: Str -> TtsEngineConfig
  (TtsEngineConfig :engine (kokoroOnnx) :modelPath "~/.asl/models/kokoro-v1.0.onnx" :sampleRate 24000 :language "en" :voiceId (if (= voiceId "") "af_heart" voiceId) :speed 1.0)

fn supportsLanguage? engine: TtsEngineKind language: Str -> Bool
  (let [(lang (stringLower (stringTrim language)))] (cond ((= engine (sileroOnnx)) (or (= lang "ru") (= lang "en"))) ((= engine (kokoroOnnx)) (= lang "en")) ((= engine (cloudStream)) true) (else false)))

fn selectOptimalEngine language: Str hasLocalSilero: Bool hasCloud: Bool -> TtsEngineConfig
  (let [(lang (stringLower (stringTrim language)))] (cond ((and (= lang "ru") hasLocalSilero) (makeSileroConfig "ru" "xenia")) ((and (= lang "en") hasLocalSilero) (makeSileroConfig "en" "en_0")) ((and (= lang "en") (not hasLocalSilero)) (makeKokoroConfig "af_heart")) (hasCloud (TtsEngineConfig :engine (cloudStream) :modelPath "https://api.openai.com/v1/audio/speech" :sampleRate 24000 :language lang :voiceId "alloy" :speed 1.0)) (else (TtsEngineConfig :engine (terminalSilent) :modelPath "" :sampleRate 16000 :language lang :voiceId "silent" :speed 1.0))))

fn createSynthesisJob jobId: Str text: Str cfg: TtsEngineConfig -> TtsSynthesisJob
  (let [(charCount (stringLength text)) (estDurationMs (/ (* charCount 1000) 14)) (samplesCount (/ (* estDurationMs cfg.sampleRate) 1000))] (TtsSynthesisJob :jobId jobId :text text :config cfg :status "completed" :audioSamplesCount samplesCount :durationMs estDurationMs))
