(module aslVoice/transliterator :x [PhoneticRule makePhoneticRules disambiguateHomophones applyCanonicalLexicon emitAsnIntent transliterateVoicePrompt] :i [(fastPath :a fp)])

(schema PhoneticRule (:f pattern Str) (:f target Str))

fn makePhoneticRules -> (List PhoneticRule)
  (list (PhoneticRule :pattern "string starts swiss" :target "stringStartsWith?") (PhoneticRule :pattern "string start swiss" :target "stringStartsWith?") (PhoneticRule :pattern "string starts with" :target "stringStartsWith?") (PhoneticRule :pattern "string start with" :target "stringStartsWith?") (PhoneticRule :pattern "string ends swiss" :target "stringEndsWith?") (PhoneticRule :pattern "string end swiss" :target "stringEndsWith?") (PhoneticRule :pattern "string ends with" :target "stringEndsWith?") (PhoneticRule :pattern "string end with" :target "stringEndsWith?") (PhoneticRule :pattern "string contains" :target "stringContains?") (PhoneticRule :pattern "string contain" :target "stringContains?") (PhoneticRule :pattern "asl man" :target "asl-mem") (PhoneticRule :pattern "asl men" :target "asl-mem") (PhoneticRule :pattern "asl voice" :target "asl-voice") (PhoneticRule :pattern "asl boys" :target "asl-voice") (PhoneticRule :pattern "asl intel" :target "asl-intel") (PhoneticRule :pattern "task claim" :target "task-claim") (PhoneticRule :pattern "claim task" :target "task-claim") (PhoneticRule :pattern "task settle" :target "task-settle") (PhoneticRule :pattern "settle task" :target "task-settle") (PhoneticRule :pattern "task recover" :target "task-recover") (PhoneticRule :pattern "recover task" :target "task-recover") (PhoneticRule :pattern "task spawn" :target "task-spawn") (PhoneticRule :pattern "spawn task" :target "task-spawn") (PhoneticRule :pattern "vad config" :target "VadConfig") (PhoneticRule :pattern "bad config" :target "VadConfig") (PhoneticRule :pattern "voice frame" :target "VoiceFrame") (PhoneticRule :pattern "voice intent" :target "VoiceIntent") (PhoneticRule :pattern "compute energy" :target "compute-energy") (PhoneticRule :pattern "step vad" :target "step-vad") (PhoneticRule :pattern "step bad" :target "step-vad") (PhoneticRule :pattern "is speech frame" :target "is-speech-frame") (PhoneticRule :pattern "run tests" :target "run-tests") (PhoneticRule :pattern "run test" :target "run-tests") (PhoneticRule :pattern "fast path" :target "fast-path"))

fn disambiguateHomophones text: Str -> Str
  (let [(rules (makePhoneticRules))] (fold (fn [(acc Str) (r PhoneticRule)] (stringReplace acc r.pattern r.target)) text rules))

fn applyCanonicalLexicon text: Str -> Str
  (let [(t1 (stringReplace text "хайнесс" "harness")) (t2 (stringReplace t1 "ханес" "harness")) (t3 (stringReplace t2 "асекс" "genseam")) (t4 (stringReplace t3 "шроуди" "shrody")) (t5 (stringReplace t4 "пцп" "pcp"))] t5)

fn emitAsnIntent goal: Str actions: (List Str) -> Str
  (let [(cleanActions (if (listEmpty? actions) (list (str "\"" goal "\"")) (map (fn [(a Str)] (if (stringStartsWith? a "\"") a (str "\"" a "\""))) actions))) (actionsStr (stringJoin cleanActions " "))] (str "(:intent :goal \"" goal "\" :action-dag [" actionsStr "])"))

fn transliterateVoicePrompt rawPrompt: Str -> Str
  (let [(trimmed (stringTrim rawPrompt))] (if (fp/isValidAsnInput? trimmed) (fp/transpileFastPath trimmed) (let [(repaired (disambiguateHomophones trimmed)) (lex (fp/buildSymbolLexicon)) (matchedActions (filter (fn [(sym Str)] (stringContains? repaired sym)) lex)) (actions (if (listEmpty? matchedActions) (list repaired) matchedActions))] (emitAsnIntent repaired actions))))
