(module aslMem/projector :x [DualProjection formatPhaseStatusRow formatPlanItem projectStatusMd projectPlanMd projectDualManifest AdrConsequence AdrRecord makeAdr formatConsequenceAsn formatAdrAsn projectAdrMd] :i [(asl-text/escape :a esc)])

(schema DualProjection (:f statusMd Str) (:f planMd Str) (:f targetPlanPath Str))

fn formatPhaseStatusRow id: Str status: Str gate: Str -> Str
  (str "| `" id "` | " status " | `" gate "` | PASS |")

fn formatPlanItem id: Str name: Str status: Str gate: Str -> Str
  (str "### Item " id ": " name "\n" "- **Status**: " status "\n" "- **Gate**: `" gate "`\n")

fn projectStatusMd iteration: Str phasesTable: Str -> Str
  (str "# Current Status: `" iteration "`\n\n" "## Active Roadmap Waves\n\n" "| Phase ID | State | Gate Command | Result |\n" "|---|---|---|---|\n" phasesTable "\n")

fn projectPlanMd phaseId: Str phaseName: Str goal: Str gate: Str itemsContent: Str -> Str
  (str "# Plan: " phaseName "\n\n" "## Goal\n" goal "\n\n" "## Work Items\n\n" itemsContent "\n" "## Acceptance Gate\n" "```bash\n" gate "\n" "```\n\n" "## Invariants\n" "- 100% pure AgentSlang (.asl) in code packages.\n" "- Zero comments (C0001). Docstrings :d only.\n" "- Strict falsification assertions.\n")

fn projectDualManifest iteration: Str phaseId: Str phaseName: Str status: Str wave: Str gate: Str -> DualProjection
  (let [(row (formatPhaseStatusRow phaseId status gate)) (sMd (projectStatusMd iteration row)) (pItem (formatPlanItem (str phaseId ".1") "Initial Implementation" status gate)) (pMd (projectPlanMd phaseId phaseName (str "Execute " phaseName " in " wave) gate pItem)) (path (str ".plans/" phaseId "/PLAN.md"))] (DualProjection :statusMd sMd :planMd pMd :targetPlanPath path))

(schema AdrConsequence (:f kind Str) (:f text Str))

(schema AdrRecord (:f id Str) (:f shortcode Str) (:f title Str) (:f status Str) (:f date Str) (:f cluster Str) (:f deciders (List Str)) (:f problem Str) (:f drivers (List Str)) (:f decision Str) (:f invariants (List Str)) (:f consequences (List AdrConsequence)))

fn makeAdr id: Str shortcode: Str title: Str status: Str date: Str cluster: Str deciders: (List Str) problem: Str drivers: (List Str) decision: Str invariants: (List Str) consequences: (List AdrConsequence) -> AdrRecord
  (AdrRecord :id id :shortcode shortcode :title title :status status :date date :cluster cluster :deciders deciders :problem problem :drivers drivers :decision decision :invariants invariants :consequences consequences)

fn formatConsequenceAsn c: AdrConsequence -> Str
  (str "(:" c.kind " \"" (esc/escapeAsnStr c.text) "\")")

fn formatAdrAsn adr: AdrRecord -> Str
  (let [(decQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) adr.deciders)) (decStr (str "[" (stringJoin decQuoted " ") "]")) (drvQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) adr.drivers)) (drvStr (str "[" (stringJoin drvQuoted " ") "]")) (invQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) adr.invariants)) (invStr (str "[" (stringJoin invQuoted " ") "]")) (cStrs (map (fn [(c AdrConsequence)] -> Str (formatConsequenceAsn c)) adr.consequences)) (cStr (str "[" (stringJoin cStrs " ") "]"))] (str "(:adr\n" "  :id \"" (esc/escapeAsnStr adr.id) "\"\n" "  :shortcode \"" (esc/escapeAsnStr adr.shortcode) "\"\n" "  :title \"" (esc/escapeAsnStr adr.title) "\"\n" "  :status :" adr.status "\n" "  :date \"" (esc/escapeAsnStr adr.date) "\"\n" "  :cluster \"" (esc/escapeAsnStr adr.cluster) "\"\n" "  :deciders " decStr "\n" "  :problem \"" (esc/escapeAsnStr adr.problem) "\"\n" "  :drivers " drvStr "\n" "  :decision \"" (esc/escapeAsnStr adr.decision) "\"\n" "  :invariants " invStr "\n" "  :consequences " cStr ")"))

fn projectAdrMd adr: AdrRecord -> Str
  (let [(decList (stringJoin adr.deciders ", ")) (drvLines (map (fn [(d Str)] -> Str (str "- " d "\n")) adr.drivers)) (drvBody (stringJoin drvLines "")) (invLines (map (fn [(i Str)] -> Str (str "- `" i "`\n")) adr.invariants)) (invBody (stringJoin invLines "")) (posC (filter (fn [(c AdrConsequence)] -> Bool (= c.kind "pos")) adr.consequences)) (posLines (map (fn [(c AdrConsequence)] -> Str (str "- " c.text "\n")) posC)) (posBody (if (= (listLength posLines) 0) "- None\n" (stringJoin posLines ""))) (negC (filter (fn [(c AdrConsequence)] -> Bool (= c.kind "neg")) adr.consequences)) (negLines (map (fn [(c AdrConsequence)] -> Str (str "- " c.text "\n")) negC)) (negBody (if (= (listLength negLines) 0) "- None\n" (stringJoin negLines "")))] (str "# " adr.id ": " adr.title "\n\n" "- **Shortcode**: `" adr.shortcode "`\n" "- **Status**: " adr.status "\n" "- **Date**: " adr.date "\n" "- **Cluster**: `" adr.cluster "`\n" "- **Deciders**: " decList "\n\n" "## Problem Statement\n" adr.problem "\n\n" "## Decision Drivers\n" drvBody "\n" "## Decision\n" adr.decision "\n\n" "## Invariants\n" invBody "\n" "## Consequences\n\n" "### Positive\n" posBody "\n" "### Negative\n" negBody))
