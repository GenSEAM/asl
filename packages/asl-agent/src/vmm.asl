(module aslAgent/vmm :x [ContextSlot VmmSlot VmmState slotInvariants slotReceipts slotPinned slotWorking makeVmmSlot makeVmmState vmmLoadKnowledge vmmOffloadKnowledge vmmCompact vmmRenderPrompt] :i [])

(enum ContextSlot (:c slotInvariants [] "Slot 1: Immutable Invariants (zero eviction priority)") (:c slotReceipts [] "Slot 2: Semantic Receipts Ledger (compact 1-line stubs)") (:c slotPinned [] "Slot 3: Pinned Domain Slot (Paged ephemeral JIT types)") (:c slotWorking [] "Slot 4: Working Frame (Active task and local AST slices)"))

(schema VmmSlot (:f slotId ContextSlot) (:f payload Str) (:f tokens I64) (:f isPinned Bool))

(schema VmmState (:f slots (List VmmSlot)) (:f maxTokens I64) (:f usedTokens I64))

fn makeVmmSlot id: ContextSlot payload: Str tokens: I64 pinned: Bool -> VmmSlot
  (VmmSlot :slotId id :payload payload :tokens tokens :isPinned pinned)

fn makeVmmState invariantsText: Str maxTokens: I64 -> VmmState
  (let [(toksInv (/ (stringLength invariantsText) 4)) (s1 (VmmSlot :slotId (slotInvariants) :payload invariantsText :tokens toksInv :isPinned true)) (s2 (VmmSlot :slotId (slotReceipts) :payload "" :tokens 0 :isPinned false)) (s3 (VmmSlot :slotId (slotPinned) :payload "" :tokens 0 :isPinned false)) (s4 (VmmSlot :slotId (slotWorking) :payload "" :tokens 0 :isPinned false))] (VmmState :slots (list s1 s2 s3 s4) :maxTokens maxTokens :usedTokens toksInv))

fn vmmLoadKnowledge state: VmmState target: Str spec: Str -> VmmState
  (let [(slots state.slots) (s1 (mt (listGet slots 0) ((some s) s))) (s2 (mt (listGet slots 1) ((some s) s))) (s4 (mt (listGet slots 3) ((some s) s))) (toks (/ (stringLength spec) 4)) (s3Updated (VmmSlot :slotId (slotPinned) :payload spec :tokens toks :isPinned false)) (totalToks (+ (+ s1.tokens s2.tokens) (+ toks s4.tokens)))] (with state :slots (list s1 s2 s3Updated s4) :usedTokens totalToks))

fn vmmOffloadKnowledge state: VmmState target: Str anchor: Str -> VmmState
  (let [(slots state.slots) (s1 (mt (listGet slots 0) ((some s) s))) (s2 (mt (listGet slots 1) ((some s) s))) (s4 (mt (listGet slots 3) ((some s) s))) (receipt (str "(:receipt :target \"" target "\" :action \"validated-schema\" :anchor \"" anchor "\")")) (s2Payload (if (= (stringLength s2.payload) 0) receipt (str s2.payload "\n" receipt))) (s2Toks (/ (stringLength s2Payload) 4)) (s2Updated (VmmSlot :slotId (slotReceipts) :payload s2Payload :tokens s2Toks :isPinned false)) (s3Cleared (VmmSlot :slotId (slotPinned) :payload "" :tokens 0 :isPinned false)) (totalToks (+ (+ s1.tokens s2Toks) s4.tokens))] (with state :slots (list s1 s2Updated s3Cleared s4) :usedTokens totalToks))

fn vmmCompact state: VmmState -> VmmState
  (let [(slots state.slots) (s1 (mt (listGet slots 0) ((some s) s))) (s2 (mt (listGet slots 1) ((some s) s))) (s4 (mt (listGet slots 3) ((some s) s))) (s3Cleared (VmmSlot :slotId (slotPinned) :payload "" :tokens 0 :isPinned false)) (totalToks (+ (+ s1.tokens s2.tokens) s4.tokens))] (with state :slots (list s1 s2 s3Cleared s4) :usedTokens totalToks))

fn vmmRenderPrompt state: VmmState -> Str
  (let [(slots state.slots) (s1 (mt (listGet slots 0) ((some s) s))) (s2 (mt (listGet slots 1) ((some s) s))) (s3 (mt (listGet slots 2) ((some s) s))) (s4 (mt (listGet slots 3) ((some s) s)))] (str "=== INVARIANTS ===\n" s1.payload "\n" "=== RECEIPTS ===\n" s2.payload "\n" "=== DOMAIN KNOWLEDGE ===\n" s3.payload "\n" "=== WORKING FRAME ===\n" s4.payload))
