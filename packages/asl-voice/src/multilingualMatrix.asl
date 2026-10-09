(module aslVoice/multilingualMatrix :x [LocaleDialect MultilingualConfig LanguageDetectionResult detectLanguageDialect makeMultilingualConfig resolveSpeechEngine] :i [(asl-text/string :a s)])

(enum LocaleDialect (:c localeEnPrimary [] "International English primary with standard technical vocabulary") (:c localeRuNative [] "Russian native syntax and vocabulary") (:c localeMixedCodeswitch [] "Mixed developer speech: Russian syntax with English tech tokens") (:c localeUniversal [] "Multilingual auto-detection with adaptive code-switching"))

(schema MultilingualConfig (:f dialect LocaleDialect) (:f primaryLanguage Str) (:f secondaryLanguage Str) (:f enablePhoneticFolding Bool) (:f ttsVoiceId Str) (:f fastPathEnabled Bool))

(schema LanguageDetectionResult (:f detectedDialect LocaleDialect) (:f hasCyrillic Bool) (:f hasLatinCodeTokens Bool) (:f confidence F64))

fn containsCyrillic? text: Str -> Bool
  (let [(chars (stringChars (stringLower text)))] (listAny? (fn [(c Str)] (or (stringContains? "абвгдеёжзийклмнопрстуфхцчшщъыьэюя" c) (stringContains? "ієїґў" c))) chars))

fn containsLatin? text: Str -> Bool
  (let [(chars (stringChars (stringLower text)))] (listAny? (fn [(c Str)] (stringContains? "abcdefghijklmnopqrstuvwxyz" c)) chars))

fn detectLanguageDialect text: Str -> LanguageDetectionResult
  (let [(cyr (containsCyrillic? text)) (lat (containsLatin? text))] (cond ((and cyr lat) (LanguageDetectionResult :detectedDialect (localeMixedCodeswitch) :hasCyrillic true :hasLatinCodeTokens true :confidence 0.95)) (cyr (LanguageDetectionResult :detectedDialect (localeRuNative) :hasCyrillic true :hasLatinCodeTokens false :confidence 0.98)) (lat (LanguageDetectionResult :detectedDialect (localeEnPrimary) :hasCyrillic false :hasLatinCodeTokens true :confidence 0.99)) (else (LanguageDetectionResult :detectedDialect (localeEnPrimary) :hasCyrillic false :hasLatinCodeTokens false :confidence 0.50))))

fn makeMultilingualConfig dialect: LocaleDialect -> MultilingualConfig
  (cond ((= dialect (localeEnPrimary)) (MultilingualConfig :dialect dialect :primaryLanguage "en" :secondaryLanguage "ru" :enablePhoneticFolding false :ttsVoiceId "en_0" :fastPathEnabled true)) ((= dialect (localeMixedCodeswitch)) (MultilingualConfig :dialect dialect :primaryLanguage "en" :secondaryLanguage "ru" :enablePhoneticFolding true :ttsVoiceId "xenia" :fastPathEnabled true)) ((= dialect (localeRuNative)) (MultilingualConfig :dialect dialect :primaryLanguage "ru" :secondaryLanguage "en" :enablePhoneticFolding true :ttsVoiceId "xenia" :fastPathEnabled true)) (else (MultilingualConfig :dialect (localeUniversal) :primaryLanguage "en" :secondaryLanguage "ru" :enablePhoneticFolding true :ttsVoiceId "en_0" :fastPathEnabled true)))

fn resolveSpeechEngine cfg: MultilingualConfig detection: LanguageDetectionResult -> Str
  (if detection.hasCyrillic "silero-ru" (if (= cfg.primaryLanguage "en") "silero-en" "silero-ru"))
