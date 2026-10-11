(module aslAgent/vmmTest :x [testVmmInitialization testVmmKnowledgeLifecycle testVmmCompactPreservesInvariants testVmmPromptRendering runTests] :i [(vmm :a vmm)])

fn testVmmInitialization -> Bool
  (let [(st (vmm/makeVmmState "Never delete assertions" 4096)) (slots st.slots) (s1 (mt (listGet slots 0) ((some s) s)))] (assert (= st.usedTokens 5) "used tokens matches initial count") (assert s1.isPinned "slot 0 is pinned") true)

fn testVmmKnowledgeLifecycle -> Bool
  (let [(st0 (vmm/makeVmmState "Root rules" 4096)) (st1 (vmm/vmmLoadKnowledge st0 "zod@3.22" "interface ZodSchema { parse: (x: any) => any }")) (slots1 st1.slots) (s3Loaded (mt (listGet slots1 2) ((some s) s))) (st2 (vmm/vmmOffloadKnowledge st1 "zod@3.22" "src/schema.asl:12")) (slots2 st2.slots) (s3Cleared (mt (listGet slots2 2) ((some s) s))) (s2Receipt (mt (listGet slots2 1) ((some s) s)))] (assert (> s3Loaded.tokens 0) "loaded tokens > 0") (assert (= s3Cleared.tokens 0) "cleared tokens == 0") (assert (> (stringLength s2Receipt.payload) 0) "receipt payload non-empty") true)

fn testVmmCompactPreservesInvariants -> Bool
  (let [(st0 (vmm/makeVmmState "Root rules" 4096)) (st1 (vmm/vmmLoadKnowledge st0 "react@19" "export function useState()")) (st2 (vmm/vmmCompact st1)) (slots st2.slots) (s1 (mt (listGet slots 0) ((some s) s))) (s3 (mt (listGet slots 2) ((some s) s)))] (assert (= s1.payload "Root rules") "slot 1 payload preserved") (assert (= s3.tokens 0) "slot 3 tokens cleared after compact") true)

fn testVmmPromptRendering -> Bool
  (let [(st (vmm/makeVmmState "No foreign code" 4096)) (prompt (vmm/vmmRenderPrompt st))] (assert (>= (stringLength prompt) 50) "rendered prompt length >= 50") (assert (stringContains? prompt "No foreign code") "rendered prompt contains base rules") true)

fn runTests -> Bool
  (do (testVmmInitialization) (testVmmKnowledgeLifecycle) (testVmmCompactPreservesInvariants) (testVmmPromptRendering) true)
