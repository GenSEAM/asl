(module asl/agentLoop/tests/coreDataFindingsTest
  :x [runTests]
  :i [(asl/agentLoop/core :a c)])

; (:m :ref LEON-DATAFINDINGS-FALLBACK-20261017 :do "the all-ops-are-data fallback in core.asl#dataFindings must not turn a stray colon-headed fragment of a garbled, mostly-unparseable reply into a finding; it may only fire when every top-level balanced-paren fragment in the reply survives the colon-head filter parseReply already applies before building ops")

; (:m :do "the literal turn-9 reply text from the kept journal bbb33271f9dda82e: nine non-colon parenthetical fragments (prose, notes) plus one (:start 1 :end 300) and one hallucinated (:receipt ... :ERR_EFFECT_UNDECLARED ...) fragment; the fallback used to wrap both survivors as findings")
fn turn9Reply -> String
  (str "(previous turns read it but those receipts are gone from the window)\n"
       "(constraintsFromSpec)\n"
       "(relevant parts)\n"
       "(legacy_split is a hint for the split algorithm)\n"
       "(full, lines 1-400?)\n"
       "(parcels, Batch)\n"
       "(:start 1 :end 300)\n"
       "(for CARRIERS, ZONES etc.)\n"
       "(restating intent is allowed and good)\n"
       "(:receipt :id \"3d1014e6e630a627\" :op \"start\" :status :rejected :error :ERR_EFFECT_UNDECLARED "
       ":message \"Operation 'start' not declared in effects registry\")")

fn runTests -> Bool
  (do
    (assert (listEmpty? (c/dataFindings (turn9Reply) (list)))
      "turn 9's garbled reply (9 dropped non-colon fragments, 2 colon-headed survivors) yields no findings (LEON-DATAFINDINGS-FALLBACK-20261017)")
    (assert (listEmpty? (c/dataFindings (turn9Reply) (list "start" "receipt")))
      "declaring the survivors' names doesn't matter; the reply is still incoherent and yields no findings")
    (assert (= (listLength (c/dataFindings "(:claim \"x happens\")\n(:file \"src/a.py\")" (list))) 2)
      "a clean reply where every top-level fragment is colon-headed and undeclared still falls back to ad-hoc findings data"
    )
    (assert (listEmpty? (c/dataFindings "(:claim \"x\")\n(:myGate)" (list "myGate")))
      "a coherent reply still yields nothing when one op's name is a declared gate (pre-existing all-or-nothing behavior, unaffected by coherence)")
    (assert (listEmpty? (c/dataFindings "just a sentence with no forms at all" (list)))
      "a reply with no parseable forms yields no findings (parseReply's own raw fallback has no colon head, so it isn't a data op)")
    (assert (listEmpty? (c/dataFindings "(:ask :to 1 :body (:q \"x?\"))" (list)))
      "a reply holding only a pool (:ask) op is not ad-hoc findings data (LEON-POOL-ASK-SCOUT)")
    (assert (listEmpty? (c/dataFindings "(:answer :to 0 :body (:a 42))" (list)))
      "nor is one holding only a pool (:answer) op")
    (assert (= (listLength (c/dataFindings "(:claim \"x\")" (list))) 1)
      "while an undeclared (:claim) alone still is")
    true)
