(module aslVoice/fastPath :x [isValidAsnInput? buildSymbolLexicon transpileFastPath] :i [])

fn isValidAsnInput? input: String -> Bool
  (let [(trimmed (stringTrim input))] (if (stringEmpty? trimmed) false (if (and (stringStartsWith? trimmed "(") (stringEndsWith? trimmed ")")) (let [(bal (fold (fn [(acc I64) (ch String)] (if (< acc 0) -999 (if (= ch "(") (+ acc 1) (if (= ch ")") (- acc 1) acc)))) 0 (stringChars trimmed)))] (= bal 0)) false)))

fn buildSymbolLexicon -> (List String)
  (list "stringStartsWith?" "stringEndsWith?" "stringContains?" "stringLength" "stringTrim" "stringReplace" "asl-mem" "asl-voice" "asl-intel" "task-claim" "task-settle" "task-recover" "task-spawn" "VadConfig" "VoiceFrame" "VoiceIntent" "compute-energy" "step-vad" "is-speech-frame" "run-tests" "transpile-fast-path" "is-valid-asn-input?" "build-symbol-lexicon" "disambiguate-homophones" "emit-asn-intent" "transliterate-voice-prompt")

fn transpileFastPath input: String -> String
  (let [(trimmed (stringTrim input))] (if (isValidAsnInput? trimmed) trimmed (if (and (stringStartsWith? trimmed "{") (stringEndsWith? trimmed "}")) (str "(:json " (stringReplace (stringReplace trimmed "{" "") "}" "") ")") (if (stringStartsWith? trimmed "---") (str "(:yaml " (stringTrim (stringReplace trimmed "---" "")) ")") ""))))
