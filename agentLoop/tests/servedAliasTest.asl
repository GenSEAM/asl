(module asl/agentLoop/tests/servedAliasTest
  :x [runTests]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/providers :a pv)])

; (:m :ref SERVED-ALIAS :do "node2 2026-11-02: most write rows journalled :model unknown; the receipt now carries :servedAlias and :servedModel from the served fields of the last gateway reply, through the journal's served row")

fn metaOf fields: (List (Pair String String)) -> pv/TurnMeta
  (pv/TurnMeta :timing none :usage none :served (some fields) :finish none :truncated false)

fn result alias: (Option String) model: (Option String) -> m/LoopResult
  (m/LoopResult :status "ok" :modeHint none :deliver none :phases (list) :session none :journal none :unbacked 0
                :unbackedClaims (list) :contextTokens none :turns none :gates (list) :escalate none :patch none
                :restored (list) :written (list) :needsConfirm (list) :ownsRejected (list) :error none :gatePreflight (list)
                :parseDefect false :parseDefectTurn none :findings none :queueWaitSec none :execSec none :usage none
                :batching none :plan none :vacuousGates (list) :specCheck none :stop none :lastStep none :servedAlias alias :servedModel model)

fn ! runTests -> Bool
  (let [both (metaOf (list (pair "alias" "freeFlash") (pair "model" "vendor/m-1")))
        modelOnly (metaOf (list (pair "model" "vendor/m-1")))
        line (m/servedLine 3 both)
        journal (str "(:session :id \"s\")\n(:served :turn 1 :model \"old/m\" :alias \"oldAlias\")\n" (optionOr line "") "(:served :turn 4 :model \"vendor/m-2\")\n")
        served (m/servedIn journal)
        receipt (m/formatReceipt (result (some "freeFlash") (some "vendor/m-1")))
        bare (m/formatReceipt (result none none))]
    (do
      (assert (= (m/servedAlias both) (some "freeFlash")) "the alias of the served fields is read")
      (assert (= (m/servedAlias modelOnly) none) "no alias field reads as none")
      (assert (= line (some "(:served :turn 3 :model \"vendor/m-1\" :alias \"freeFlash\")\n")) "the journal row carries model and alias")
      (assert (= (m/servedLine 2 (pv/emptyMeta)) none) "a reply that names neither writes no row")
      (assert (= (pairFirst served) (some "freeFlash")) "the last served row that names an alias gives the alias")
      (assert (= (pairSecond served) (some "vendor/m-2")) "the last served row that names a model gives the model")
      (assert (stringContains? receipt ":servedAlias \"freeFlash\" :servedModel \"vendor/m-1\"") "the receipt carries both fields")
      (assert (not (stringContains? bare ":servedAlias")) "a receipt without a served reply has no served fields")
      true))
