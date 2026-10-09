(module aslMem/consistencyAudit :x [ConsistencyDimension ConsistencyReport canonicalShortcode verifyShortcodeBidirectional? checkD52Completeness? verifyRoadmapGate? makeCleanReport auditConsistencyState] :i [(records :a r) (tasks :a t)])

(enum ConsistencyDimension (:c dimAdrTask [] "ADR <-> Task bidirectional linkage") (:c dimIntent [] "Intent ledger & decision coherence") (:c dimTaskContext [] "Task context completeness (D52)") (:c dimRoadmap [] "Roadmap ledger & phase graph integrity") (:c dimDelimiters [] "Orphan references, delimiters, and emoji invariants"))

(schema ConsistencyReport (:f adrsScanned I64) (:f tasksIndexed I64) (:f adrTaskLinks I64) (:f taskAdrLinks I64) (:f brokenLinks I64) (:f intentRecords I64) (:f desyncIntents I64) (:f contextVoids I64) (:f wavesCount I64) (:f phasesCount I64) (:f roadmapDiscrepancies I64) (:f delimiterErrors I64) (:f emojiViolations I64) (:f allPassed Bool))

fn canonicalShortcode code: Str -> Str
  (let [(c (stringLower (stringTrim code))) (c1 (stringReplace c "adr-" "d")) (c2 (stringReplace c "adr" "d")) (c3 (stringReplace c2 "-" ""))] (if (and (stringStartsWith? c3 "d") (stringStartsWith? (optionOr (stringSlice c3 1 (stringLength c3)) "") "0")) (canonicalShortcode (str "d" (optionOr (stringSlice c3 2 (stringLength c3)) ""))) c3))

fn verifyShortcodeBidirectional? adrCode: Str taskTarget: Str -> Bool
  (= (canonicalShortcode adrCode) (canonicalShortcode taskTarget))

fn checkD52Completeness? presentFields: (List Str) -> Bool
  (let [(req (list ":motivation" ":purpose" ":context" ":outcomes" ":owns" ":invariants" ":variations" ":failureModes" ":adr" ":decision" ":gate" ":actionDag"))] (listAll? (fn [(rf Str)] -> Bool (listContains? presentFields rf)) req))

fn verifyRoadmapGate? gateCmd: Str -> Bool
  (and (not (stringEmpty? (stringTrim gateCmd))) (or (stringContains? gateCmd "asl") (or (stringContains? gateCmd "test") (stringContains? gateCmd "bin/"))))

fn makeCleanReport adrs: I64 tasks: I64 links: I64 intents: I64 waves: I64 phases: I64 -> ConsistencyReport
  (ConsistencyReport :adrsScanned adrs :tasksIndexed tasks :adrTaskLinks links :taskAdrLinks links :brokenLinks 0 :intentRecords intents :desyncIntents 0 :contextVoids 0 :wavesCount waves :phasesCount phases :roadmapDiscrepancies 0 :delimiterErrors 0 :emojiViolations 0 :allPassed true)

fn auditConsistencyState adrs: I64 tasks: I64 broken: I64 desync: I64 voids: I64 disc: I64 delim: I64 emoji: I64 -> ConsistencyReport
  (let [(clean (and (= broken 0) (and (= desync 0) (and (= voids 0) (and (= disc 0) (and (= delim 0) (= emoji 0)))))))] (ConsistencyReport :adrsScanned adrs :tasksIndexed tasks :adrTaskLinks (- tasks broken) :taskAdrLinks (- tasks broken) :brokenLinks broken :intentRecords adrs :desyncIntents desync :contextVoids voids :wavesCount 89 :phasesCount 39 :roadmapDiscrepancies disc :delimiterErrors delim :emojiViolations emoji :allPassed clean))
