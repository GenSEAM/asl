(module aslVoice/endturn :x [TurnVerdict TurnAnalysis makeTurnAnalysis isDanglingCoordinator? isHesitationParticle? isHangingSubjectPronoun? isDanglingAuxVerb? extractTrailingToken analyzeTurnCompletion] :i [(asl-text/string :a s)])

(enum TurnVerdict (:c complete [] "Utterance is grammatically complete") (:c dangling [] "Trailing preposition, subordinator or coordinator") (:c hesitation [] "Trailing filler or hesitation particle") (:c hangingSubject [] "Trailing subject pronoun without predicate") (:c danglingAux [] "Trailing auxiliary verb waiting for main verb") (:c emptyUtterance [] "Empty or whitespace utterance"))

(schema TurnAnalysis (:f verdict TurnVerdict) (:f isComplete Bool) (:f trailingToken Str) (:f reason Str) (:f recommendedWaitMs I64))

fn makeTurnAnalysis verdict: TurnVerdict isComplete: Bool trailing: Str reason: Str waitMs: I64 -> TurnAnalysis
  (TurnAnalysis :verdict verdict :isComplete isComplete :trailingToken trailing :reason reason :recommendedWaitMs waitMs)

fn isDanglingCoordinator? w: Str -> Bool
  (let [(low (stringLower (stringTrim w)))] (cond ((= low "и") true) ((= low "а") true) ((= low "но") true) ((= low "или") true) ((= low "либо") true) ((= low "что") true) ((= low "чтобы") true) ((= low "чтоб") true) ((= low "если") true) ((= low "когда") true) ((= low "пока") true) ((= low "потому") true) ((= low "поэтому") true) ((= low "как") true) ((= low "для") true) ((= low "на") true) ((= low "в") true) ((= low "во") true) ((= low "с") true) ((= low "со") true) ((= low "к") true) ((= low "ко") true) ((= low "о") true) ((= low "об") true) ((= low "от") true) ((= low "до") true) ((= low "по") true) ((= low "за") true) ((= low "из") true) ((= low "при") true) ((= low "про") true) ((= low "без") true) ((= low "у") true) ((= low "and") true) ((= low "or") true) ((= low "but") true) ((= low "so") true) ((= low "that") true) ((= low "if") true) ((= low "when") true) ((= low "while") true) ((= low "because") true) ((= low "since") true) ((= low "to") true) ((= low "for") true) ((= low "with") true) ((= low "of") true) ((= low "in") true) ((= low "on") true) ((= low "at") true) ((= low "by") true) ((= low "from") true) ((= low "about") true) (else false)))

fn isHesitationParticle? w: Str -> Bool
  (let [(low (stringLower (stringTrim w)))] (cond ((= low "ну") true) ((= low "вот") true) ((= low "это") true) ((= low "типа") true) ((= low "короче") true) ((= low "значит") true) ((= low "эээ") true) ((= low "ээ") true) ((= low "э") true) ((= low "ммм") true) ((= low "мм") true) ((= low "um") true) ((= low "uh") true) ((= low "erm") true) ((= low "hmm") true) ((= low "like") true) ((= low "well") true) (else false)))

fn isHangingSubjectPronoun? w: Str -> Bool
  (let [(low (stringLower (stringTrim w)))] (cond ((= low "я") true) ((= low "ты") true) ((= low "он") true) ((= low "она") true) ((= low "оно") true) ((= low "мы") true) ((= low "вы") true) ((= low "они") true) ((= low "i") true) ((= low "he") true) ((= low "she") true) ((= low "we") true) ((= low "they") true) (else false)))

fn isDanglingAuxVerb? w: Str -> Bool
  (let [(low (stringLower (stringTrim w)))] (cond ((= low "should") true) ((= low "would") true) ((= low "could") true) ((= low "can") true) ((= low "will") true) ((= low "shall") true) ((= low "must") true) ((= low "might") true) ((= low "may") true) ((= low "gonna") true) ((= low "wanna") true) ((= low "want") true) ((= low "need") true) (else false)))

fn extractTrailingToken text: Str -> Str
  (let [(trimmed (stringTrim text))] (if (= trimmed "") "" (let [(clean (stringReplace trimmed "." "")) (clean2 (stringReplace clean "," "")) (clean3 (stringReplace clean2 "!" "")) (clean4 (stringReplace clean3 "?" "")) (clean5 (stringReplace clean4 ";" "")) (clean6 (stringReplace clean5 ":" "")) (words (stringSplit clean6 " "))] (if (listEmpty? words) "" (let [(lastWord (optionOr (listGet words (- (listLength words) 1)) ""))] (stringLower (stringTrim lastWord)))))))

fn analyzeTurnCompletion utterance: Str -> TurnAnalysis
  (let [(token (extractTrailingToken utterance))] (cond ((= token "") (makeTurnAnalysis (emptyUtterance) false "" "Empty utterance" 0)) ((isDanglingCoordinator? token) (makeTurnAnalysis (dangling) false token "Trailing coordinator or preposition" 3000)) ((isHesitationParticle? token) (makeTurnAnalysis (hesitation) false token "Trailing hesitation filler" 3000)) ((isHangingSubjectPronoun? token) (makeTurnAnalysis (hangingSubject) false token "Trailing subject pronoun without predicate" 3000)) ((isDanglingAuxVerb? token) (makeTurnAnalysis (danglingAux) false token "Trailing auxiliary verb" 3000)) (else (makeTurnAnalysis (complete) true token "Utterance is grammatically complete" 0))))
