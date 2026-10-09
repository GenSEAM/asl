(module aslAgent/promptPool :x [PromptEntry PromptPool makePromptEntry makePromptPool recordPrompt getActivePrompts renderPromptPoolAsn] :i [(asl-text/string :a s)])

(schema PromptEntry (:f text Str) (:f timestampMs Int64))

(schema PromptPool (:f chatId Str) (:f entries (List PromptEntry)) (:f capacity Int64) (:f ttlMs Int64))

fn makePromptEntry text: Str timestampMs: Int64 -> PromptEntry
  (PromptEntry :text text :timestampMs timestampMs)

fn makePromptPool chatId: Str capacity: Int64 ttlMs: Int64 -> PromptPool
  (PromptPool :chatId chatId :entries (list) :capacity (if (> capacity 0) capacity 3) :ttlMs (if (> ttlMs 0) ttlMs 180000))

fn recordPrompt pool: PromptPool text: Str nowMs: Int64 -> PromptPool
  (let [(cutoff (- nowMs pool.ttlMs)) (alive (filter (fn [(e PromptEntry)] (> e.timestampMs cutoff)) pool.entries)) (newEntry (makePromptEntry (stringTrim text) nowMs)) (appended (listAppend alive (list newEntry))) (len (listLength appended)) (cap pool.capacity) (trimmed (if (> len cap) (listDrop appended (- len cap)) appended))] (with pool :entries trimmed))

fn getActivePrompts pool: PromptPool nowMs: Int64 -> (List PromptEntry)
  (let [(cutoff (- nowMs pool.ttlMs))] (filter (fn [(e PromptEntry)] (> e.timestampMs cutoff)) pool.entries))

fn renderPromptPoolAsn pool: PromptPool nowMs: Int64 -> Str
  (let [(active (getActivePrompts pool nowMs))] (if (listEmpty? active) "" (let [(count (listLength active))] (str "(:recent-context :chat-id \"" pool.chatId "\" :count " (stringFromInt64 count) ")"))))
