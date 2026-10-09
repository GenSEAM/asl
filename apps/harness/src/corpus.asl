(module aslHarness/corpus :x [AudioSegment TranscriptUtterance PreferencePair CorpusStore makeCorpusStore recordUtterance recordAudioSegment isWithinWindow? pruneCorpusWindow extractSftDpoPairs formatPreferencePairAsn] :i [])

(schema AudioSegment (:f segmentId Str) (:f timestampMs Int64) (:f durationMs Int64) (:f speakerScore Float) (:f sampleCount Int64) (:f pcmDigest Str))

(schema TranscriptUtterance (:f utteranceId Str) (:f timestampMs Int64) (:f speakerId Str) (:f speakerScore Float) (:f verifiedSpeaker Bool) (:f text Str) (:f intent Str))

(schema PreferencePair (:f pairId Str) (:f prompt Str) (:f chosen Str) (:f rejected Str) (:f gateVerdictChosen Str) (:f gateVerdictRejected Str) (:f timestampMs Int64))

(schema CorpusStore (:f windowDays Int64) (:f utterances (List TranscriptUtterance)) (:f audioSegments (List AudioSegment)) (:f preferencePairs (List PreferencePair)))

fn makeCorpusStore windowDays: Int64 -> CorpusStore
  (CorpusStore :windowDays windowDays :utterances (list) :audioSegments (list) :preferencePairs (list))

fn recordUtterance store: CorpusStore utt: TranscriptUtterance -> CorpusStore
  (let [(isVerified (>= utt.speakerScore 0.75)) (taggedUtt (with utt :verifiedSpeaker isVerified))] (with store :utterances (listAppend store.utterances (list taggedUtt))))

fn recordAudioSegment store: CorpusStore seg: AudioSegment -> CorpusStore
  (with store :audioSegments (listAppend store.audioSegments (list seg)))

fn isWithinWindow? itemTs: Int64 currentTs: Int64 windowMs: Int64 -> Bool
  (<= (- currentTs itemTs) windowMs)

fn filterUtterancesWindow utts: (List TranscriptUtterance) nowTs: Int64 winMs: Int64 -> (List TranscriptUtterance)
  (if (listEmpty? utts) (list) (let [(head (optionOr (listHead utts) (TranscriptUtterance :utteranceId "" :timestampMs 0 :speakerId "" :speakerScore 0.0 :verifiedSpeaker false :text "" :intent ""))) (tail (optionOr (listTail utts) (list)))] (if (isWithinWindow? head.timestampMs nowTs winMs) (cons head (filterUtterancesWindow tail nowTs winMs)) (filterUtterancesWindow tail nowTs winMs))))

fn filterAudioWindow segs: (List AudioSegment) nowTs: Int64 winMs: Int64 -> (List AudioSegment)
  (if (listEmpty? segs) (list) (let [(head (optionOr (listHead segs) (AudioSegment :segmentId "" :timestampMs 0 :durationMs 0 :speakerScore 0.0 :sampleCount 0 :pcmDigest ""))) (tail (optionOr (listTail segs) (list)))] (if (isWithinWindow? head.timestampMs nowTs winMs) (cons head (filterAudioWindow tail nowTs winMs)) (filterAudioWindow tail nowTs winMs))))

fn pruneCorpusWindow store: CorpusStore nowTs: Int64 -> CorpusStore
  (let [(winMs (* store.windowDays 86400000)) (activeUtts (filterUtterancesWindow store.utterances nowTs winMs)) (activeSegs (filterAudioWindow store.audioSegments nowTs winMs))] (with store :utterances activeUtts :audioSegments activeSegs))

fn isPassVerdict? v: Str -> Bool
  (or (= v "pass") (or (= v ":pass") (stringContains? v "pass")))

fn isFailVerdict? v: Str -> Bool
  (or (= v "fail") (or (= v ":fail") (stringContains? v "fail")))

fn filterChosenCompletions receipts: (List Str) completions: (List Str) -> (List Str)
  (if (or (listEmpty? receipts) (listEmpty? completions)) (list) (let [(rec (optionOr (listHead receipts) "")) (comp (optionOr (listHead completions) "")) (recTail (optionOr (listTail receipts) (list))) (compTail (optionOr (listTail completions) (list)))] (if (isPassVerdict? rec) (cons comp (filterChosenCompletions recTail compTail)) (filterChosenCompletions recTail compTail))))

fn filterRejectedCompletions receipts: (List Str) completions: (List Str) -> (List Str)
  (if (or (listEmpty? receipts) (listEmpty? completions)) (list) (let [(rec (optionOr (listHead receipts) "")) (comp (optionOr (listHead completions) "")) (recTail (optionOr (listTail receipts) (list))) (compTail (optionOr (listTail completions) (list)))] (if (isFailVerdict? rec) (cons comp (filterRejectedCompletions recTail compTail)) (filterRejectedCompletions recTail compTail))))

fn buildPreferencePairs taskPrompt: Str chosenList: (List Str) rejectedList: (List Str) idx: Int64 -> (List PreferencePair)
  (if (or (listEmpty? chosenList) (listEmpty? rejectedList)) (list) (let [(cHead (optionOr (listHead chosenList) "")) (rHead (optionOr (listHead rejectedList) "")) (cTail (optionOr (listTail chosenList) (list))) (rTail (optionOr (listTail rejectedList) (list))) (pair (PreferencePair :pairId (str "pref-" (stringFromInt64 idx)) :prompt taskPrompt :chosen cHead :rejected rHead :gateVerdictChosen "pass" :gateVerdictRejected "fail" :timestampMs 1757300000000))] (cons pair (buildPreferencePairs taskPrompt cTail rTail (+ idx 1)))))

fn extractSftDpoPairs taskPrompt: Str receipts: (List Str) completions: (List Str) -> (List PreferencePair)
  (if (or (!= (listLength receipts) (listLength completions)) (<= (listLength receipts) 0)) (list) (let [(chosen (filterChosenCompletions receipts completions)) (rejected (filterRejectedCompletions receipts completions))] (if (or (listEmpty? chosen) (listEmpty? rejected)) (list) (buildPreferencePairs taskPrompt chosen rejected 1))))

fn formatPreferencePairAsn pair: PreferencePair -> Str
  (str "(:preference-pair :id \"" pair.pairId "\" :prompt \"" pair.prompt "\" :chosen \"" pair.chosen "\" :rejected \"" pair.rejected "\" :gate-verdict-chosen \"" pair.gateVerdictChosen "\" :gate-verdict-rejected \"" pair.gateVerdictRejected "\" :timestamp-ms " (stringFromInt64 pair.timestampMs) ")")
