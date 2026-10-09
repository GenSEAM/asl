(module aslAgentCore/promptpool :x [PromptEntry PromptPool MultiLanePool promptPoolCreate promptPoolPush promptPoolPrune renderPromptPool multiPoolCreate multiPoolPush multiPoolGet multiPoolPruneAll poolCapDefault ttlMsDefault] :i [])

fn poolCapDefault -> I64
  3

fn ttlMsDefault -> I64
  180000

(schema PromptEntry (:f id Str) (:f lane Str) (:f prompt Str) (:f timestamp I64) (:f turnIndex I64))

(schema PromptPool (:f lane Str) (:f cap I64) (:f ttlMs I64) (:f entries (List PromptEntry)))

(schema MultiLanePool (:f cap I64) (:f ttlMs I64) (:f pools (Map Str PromptPool)))

fn promptPoolCreate lane: Str cap: I64 ttlMs: I64 -> PromptPool
  (PromptPool :lane lane :cap cap :ttlMs ttlMs :entries (list))

fn promptPoolPrune pool: PromptPool nowMs: I64 -> PromptPool
  (let [(valid (filter (fn [(entry PromptEntry)] -> Bool (<= (- nowMs entry.timestamp) pool.ttlMs)) pool.entries))] (with pool :entries valid))

fn promptPoolPush pool: PromptPool prompt: Str nowMs: I64 -> PromptPool
  (let [(pruned (promptPoolPrune pool nowMs)) (lastOpt (listHead (listReverse pool.entries))) (nextIdx (mt lastOpt ((some lastE) (+ lastE.turnIndex 1)) ((none) 1))) (newEntry (PromptEntry :id (str pool.lane "-turn-" (stringFromInt64 nextIdx)) :lane pool.lane :prompt prompt :timestamp nowMs :turnIndex nextIdx)) (appended (listAppend pruned.entries (list newEntry))) (totalCnt (listLength appended)) (cap pool.cap) (clamped (if (> totalCnt cap) (optionOr (listSlice appended (- totalCnt cap) totalCnt) appended) appended))] (with pool :cap cap :entries clamped))

fn renderPromptPool pool: PromptPool currentPrompt: Str nowMs: I64 -> Str
  (let [(pruned (promptPoolPrune pool nowMs)) (entries pruned.entries)] (if (listEmpty? entries) (str "<current-instruction>\n" currentPrompt "\n</current-instruction>") (let [(priorText (fold (fn [(acc Str) (entry PromptEntry)] -> Str (let [(line (str "<turn index=\"" (stringFromInt64 entry.turnIndex) "\">\n" entry.prompt "\n</turn>"))] (if (stringEmpty? acc) line (str acc "\n" line)))) "" entries))] (str "<prior-context>\n" priorText "\n</prior-context>\n<current-instruction>\n" currentPrompt "\n</current-instruction>"))))

fn multiPoolCreate cap: I64 ttlMs: I64 -> MultiLanePool
  (MultiLanePool :cap cap :ttlMs ttlMs :pools (mapEmpty))

fn multiPoolGet mp: MultiLanePool lane: Str -> PromptPool
  (optionOr (mapGet mp.pools lane) (promptPoolCreate lane mp.cap mp.ttlMs))

fn multiPoolPush mp: MultiLanePool lane: Str prompt: Str nowMs: I64 -> MultiLanePool
  (let [(pool (multiPoolGet mp lane)) (updated (promptPoolPush pool prompt nowMs))] (with mp :pools (mapSet mp.pools lane updated)))

fn multiPoolPruneAll mp: MultiLanePool nowMs: I64 -> MultiLanePool
  (let [(lanes (mapKeys mp.pools)) (prunedMap (fold (fn [(acc (Map Str PromptPool)) (lane Str)] -> (Map Str PromptPool) (let [(p (optionOr (mapGet acc lane) (promptPoolCreate lane mp.cap mp.ttlMs))) (prunedP (promptPoolPrune p nowMs))] (mapSet acc lane prunedP))) mp.pools lanes))] (with mp :pools prunedMap))
