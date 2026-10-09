(module aslAgentBus/mvccBus :x [CausalMessage IntentConflict MergedIntent MvccBus mvccBusCreate mvccBusPublish mvccBusGetMessage mvccBusFindHeads mvccBusMergeIntents formatMergedIntent extractPayloadFacts mergeFactLists detectIntentContradiction])

(schema CausalMessage (:f id Str) (:f parents (List Str)) (:f sender Str) (:f topic Str) (:f payloadForm Str) (:f clock I64) (:f epoch I64))

(schema IntentConflict (:f topic Str) (:f parentId Str) (:f msgAId Str) (:f msgBId Str) (:f reason Str))

(schema MergedIntent (:f topic Str) (:f sourceMsgIds (List Str)) (:f mergedPayload Str) (:f conflicts (List IntentConflict)) (:f clean Bool))

(schema MvccBus (:f messages (List CausalMessage)) (:f headIds (List Str)) (:f conflicts (List IntentConflict)))

fn mvccBusCreate -> MvccBus
  (MvccBus :messages (list) :headIds (list) :conflicts (list))

fn mvccBusGetMessage bus: MvccBus msgId: Str -> (Option CausalMessage)
  (fold (fn [(acc (Option CausalMessage)) (m CausalMessage)] -> (Option CausalMessage) (mt acc ((some found) (some found)) ((none) (if (= m.id msgId) (some m) (none))))) (none) bus.messages)

fn mvccBusPublish bus: MvccBus sender: Str topic: Str payload: Str parents: (List Str) clock: I64 epoch: I64 -> MvccBus
  (let [(nextId (str topic "-" sender "-" clock)) (msg (CausalMessage :id nextId :parents parents :sender sender :topic topic :payloadForm payload :clock clock :epoch epoch)) (nextMsgs (listAppend bus.messages (list msg))) (remainingHeads (fold (fn [(acc (List Str)) (h Str)] -> (List Str) (if (listContains? parents h) acc (listAppend acc (list h)))) (list) bus.headIds)) (nextHeads (listAppend remainingHeads (list nextId)))] (with bus :messages nextMsgs :headIds nextHeads))

fn mvccBusFindHeads bus: MvccBus targetTopic: Str -> (List CausalMessage)
  (let [(heads bus.headIds)] (fold (fn [(acc (List CausalMessage)) (m CausalMessage)] -> (List CausalMessage) (if (and (= m.topic targetTopic) (listContains? heads m.id)) (listAppend acc (list m)) acc)) (list) bus.messages))

fn extractPayloadFacts payload: Str -> (List Str)
  (let [(lines (stringSplit payload "\n"))] (fold (fn [(acc (List Str)) (l Str)] -> (List Str) (let [(trimmed (stringTrim l))] (if (or (stringEmpty? trimmed) (stringStartsWith? trimmed ";")) acc (listAppend acc (list trimmed))))) (list) lines))

fn mergeFactLists baseFacts: (List Str) aFacts: (List Str) bFacts: (List Str) -> (List Str)
  (let [(added-a (fold (fn [(acc (List Str)) (f Str)] -> (List Str) (if (listContains? baseFacts f) acc (if (listContains? acc f) acc (listAppend acc (list f))))) (list) aFacts)) (added-b (fold (fn [(acc (List Str)) (f Str)] -> (List Str) (if (listContains? baseFacts f) acc (if (or (listContains? added-a f) (listContains? acc f)) acc (listAppend acc (list f))))) (list) bFacts)) (retainedBase (fold (fn [(acc (List Str)) (f Str)] -> (List Str) (if (and (listContains? aFacts f) (listContains? bFacts f)) (listAppend acc (list f)) acc)) (list) baseFacts))] (listAppend retainedBase (listAppend added-a added-b)))

fn detectIntentContradiction aPayload: Str bPayload: Str -> Bool
  (or (or (and (stringContains? aPayload ":status :ok") (stringContains? bPayload ":status :failed")) (and (stringContains? aPayload ":status :failed") (stringContains? bPayload ":status :ok"))) (or (and (stringContains? aPayload ":verdict :approve") (stringContains? bPayload ":verdict :reject")) (and (stringContains? aPayload ":verdict :reject") (stringContains? bPayload ":verdict :approve"))))

fn mvccBusMergeIntents bus: MvccBus topic: Str baseMsgId: Str branchAId: Str branchBId: Str -> MergedIntent
  (let [(baseOpt (mvccBusGetMessage bus baseMsgId)) (aOpt (mvccBusGetMessage bus branchAId)) (bOpt (mvccBusGetMessage bus branchBId))] (mt aOpt ((none) (MergedIntent :topic topic :sourceMsgIds (list) :mergedPayload "" :conflicts (list (IntentConflict :topic topic :parentId baseMsgId :msgAId branchAId :msgBId branchBId :reason "Missing branch A message")) :clean false)) ((some ma) (mt bOpt ((none) (MergedIntent :topic topic :sourceMsgIds (list branchAId) :mergedPayload ma.payloadForm :conflicts (list (IntentConflict :topic topic :parentId baseMsgId :msgAId branchAId :msgBId branchBId :reason "Missing branch B message")) :clean false)) ((some mb) (let [(aRaw ma.payloadForm) (bRaw mb.payloadForm) (baseRaw (mt baseOpt ((none) "") ((some mbase) mbase.payloadForm))) (hasConflict (detectIntentContradiction aRaw bRaw))] (if hasConflict (let [(c (IntentConflict :topic topic :parentId baseMsgId :msgAId branchAId :msgBId branchBId :reason "Contradictory status/verdict between agent proposals"))] (MergedIntent :topic topic :sourceMsgIds (list branchAId branchBId) :mergedPayload (str "(:intentConflict\n  :branchA " aRaw "\n  :branchB " bRaw ")") :conflicts (list c) :clean false)) (let [(baseFacts (extractPayloadFacts baseRaw)) (aFacts (extractPayloadFacts aRaw)) (bFacts (extractPayloadFacts bRaw)) (mergedFacts (mergeFactLists baseFacts aFacts bFacts)) (mergedText (stringJoin mergedFacts "\n"))] (MergedIntent :topic topic :sourceMsgIds (list branchAId branchBId) :mergedPayload mergedText :conflicts (list) :clean true)))))))))

fn formatMergedIntent intent: MergedIntent -> Str
  (str "(:mergedIntent\n" "  :topic \"" intent.topic "\"\n" "  :clean " (if intent.clean "true" "false") "\n" "  :sources [" (stringJoin intent.sourceMsgIds " ") "]\n" "  :payload \n" intent.mergedPayload ")")
