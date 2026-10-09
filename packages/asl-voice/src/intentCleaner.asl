(module aslVoice/intentCleaner :x [CleanedIntentResult stripDisfluencies deduplicateConsecutiveTokens repairAsrSlips stripConversationalPreamble cleanVoiceIntent] :i [(asl-text/string :a s)])

(schema CleanedIntentResult (:f rawInput Str) (:f cleanedIntent Str) (:f strippedFillers (List Str)) (:f hadRepetitions Bool) (:f repairedTokens (List Str)))

fn stripDisfluencies text: Str -> Str
  (let [(t1 (stringReplace text "ну " "")) (t2 (stringReplace t1 "эээ " "")) (t3 (stringReplace t2 "ээ " "")) (t4 (stringReplace t3 "ммм " "")) (t5 (stringReplace t4 "типа " "")) (t6 (stringReplace t5 "короче " "")) (t7 (stringReplace t6 "в общем " "")) (t8 (stringReplace t7 "как бы " "")) (t9 (stringReplace t8 "значит " "")) (t10 (stringReplace t9 "слушай " "")) (t11 (stringReplace t10 "смотри " "")) (t12 (stringReplace t11 "um " "")) (t13 (stringReplace t12 "uh " "")) (t14 (stringReplace t13 "hmm " "")) (t15 (stringReplace t14 "like " "")) (t16 (stringReplace t15 "you know " "")) (t17 (stringReplace t16 "basically " "")) (t18 (stringReplace t17 "actually " ""))] (stringTrim t18))

fn deduplicateConsecutiveTokens text: Str -> Str
  (let [(words (stringSplit (stringTrim text) " "))] (if (<= (listLength words) 1) text (let [(folded (fold (fn [(acc (List Str)) (w Str)] -> (List Str) (if (listEmpty? acc) (list w) (let [(lastW (optionOr (listGet acc (- (listLength acc) 1)) ""))] (if (= lastW w) acc (listAppend acc (list w)))))) (list) words))] (stringJoin folded " "))))

fn repairAsrSlips text: Str -> Str
  (let [(t1 (stringReplace text "шроуди" "shrody")) (t2 (stringReplace t1 "шроди" "shrody")) (t3 (stringReplace t2 "датахаб" "datahub")) (t4 (stringReplace t3 "дата хаб" "datahub")) (t5 (stringReplace t4 "пцп" "pcp")) (t6 (stringReplace t5 "асекс" "genseam")) (t7 (stringReplace t6 "асл" "asl")) (t8 (stringReplace t7 "гет" "git")) (t9 (stringReplace t8 "пуш" "push")) (t10 (stringReplace t9 "коммит" "commit")) (t11 (stringReplace t10 "мердж " "merge ")) (t12 (stringReplace t11 "билд " "build ")) (t13 (stringReplace t12 "чекер " "checker ")) (t14 (stringReplace t13 "тесты " "tests ")) (t15 (stringReplace t14 "воркспейс " "workspace "))] t15)

fn stripConversationalPreamble text: Str -> Str
  (let [(trimmed (stringTrim text)) (low (stringLower trimmed))] (cond ((stringStartsWith? low "можешь пожалуйста ") (stringTrim (stringReplace trimmed "можешь пожалуйста " ""))) ((stringStartsWith? low "пожалуйста ") (stringTrim (stringReplace trimmed "пожалуйста " ""))) ((stringStartsWith? low "я хочу чтобы ты ") (stringTrim (stringReplace trimmed "я хочу чтобы ты " ""))) ((stringStartsWith? low "сделай так чтобы ") (stringTrim (stringReplace trimmed "сделай так чтобы " ""))) ((stringStartsWith? low "could you please ") (stringTrim (stringReplace trimmed "could you please " ""))) ((stringStartsWith? low "please ") (stringTrim (stringReplace trimmed "please " ""))) ((stringStartsWith? low "i would like you to ") (stringTrim (stringReplace trimmed "i would like you to " ""))) ((stringStartsWith? low "i want you to ") (stringTrim (stringReplace trimmed "i want you to " ""))) (else trimmed)))

fn cleanVoiceIntent rawTranscript: Str -> CleanedIntentResult
  (let [(noFillers (stripDisfluencies rawTranscript)) (noStutters (deduplicateConsecutiveTokens noFillers)) (repaired (repairAsrSlips noStutters)) (core (stripConversationalPreamble repaired))] (CleanedIntentResult :rawInput rawTranscript :cleanedIntent (stringTrim core) :strippedFillers (list) :hadRepetitions (not (= noFillers noStutters)) :repairedTokens (list)))
