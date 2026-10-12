(module aslMem/notes :x [NoteRecord makeNote noteIsActive? noteHasTag? noteScopeMatches? noteMatchesQuery? formatNoteAsn projectNoteMd notePromoteToTask notePromoteToAdr noteCloseScope notePruneBounded] :i [(asl-text/escape :a esc)])

; (:m :ref NOTESTEST-TYPE :do "scope was Any and did double duty as both a (List Str) of code paths a note's finding applies to (notesTest.asl, read by noteScopeMatches?) and a Str lifecycle level 'step'|'task'|'epic' (notesScopeTest.asl, read by noteCloseScope); comparing the List form against a Str path in noteScopeMatches? raised ERR_TYPE: = compares List with String. Split into scope: (List Str), always the path list, and a new scopeLevel: Str for the lifecycle level; makeNote gains the scopeLevel positional parameter")
(schema NoteRecord (:f id Str) (:f topic Str) (:f author Str) (:f session Str) (:f date Str) (:f status Str) (:f scope (List Str)) (:f scopeLevel Str) (:f tags (List Str)) (:f fact Str) (:f evidence Str) (:f consequence Str))

fn makeNote p1: Any p2: Any p3: Any p4: Any p5: Any p6: Any p7: Any p8: Any p9: Any p10: Any p11: Any p12: Any -> NoteRecord
  (let [(factStr p10) (evStr p11) (isBloat (or (> (listLength (stringSplit factStr "\n")) 3) (> (listLength (stringSplit evStr "\n")) 3)))] (if isBloat (NoteRecord :id "REJECTED" :topic "D81_RECONSTRUCTIBILITY_VIOLATION" :author "system" :session "sess-current" :date "2026-09-14" :status "rejected" :scope (list) :scopeLevel "" :tags (list "bloat") :fact "Rule D81: Reconstructible records are refused. Extract the abstract consequence instead of raw command dumps." :evidence "Multi-line code/command dump detected." :consequence "Note rejected to prevent token bloat.") (NoteRecord :id p1 :topic p2 :author p3 :session p4 :date p5 :status p6 :scope p7 :scopeLevel p8 :tags p9 :fact p10 :evidence p11 :consequence p12)))

fn noteIsActive? note: NoteRecord -> Bool
  (= note.status "active")

fn noteHasTag? note: NoteRecord tag: Str -> Bool
  (let [(matches (filter (fn [(t Str)] -> Bool (= t tag)) note.tags))] (> (listLength matches) 0))

fn noteScopeMatches? note: NoteRecord path: Str -> Bool
  (> (listLength (filter (fn [(s Str)] -> Bool (or (= s path) (or (stringContains? s path) (stringContains? path s)))) note.scope)) 0)

fn noteMatchesQuery? note: NoteRecord query: Str -> Bool
  (let [(inId (stringContains? note.id query)) (inTopic (stringContains? note.topic query)) (inFact (stringContains? note.fact query)) (inTag (noteHasTag? note query))] (or inId (or inTopic (or inFact inTag))))

fn formatNoteAsn note: NoteRecord -> Str
  (let [(scopeQuoted (map (fn [(s Str)] -> Str (str "\"" (esc/escapeAsnStr s) "\"")) note.scope)) (scopeStr (str "[" (stringJoin scopeQuoted " ") "]")) (tagsQuoted (map (fn [(t Str)] -> Str (str ":" t)) note.tags)) (tagsStr (str "[" (stringJoin tagsQuoted " ") "]"))] (str "(:note\n" "  :id \"" (esc/escapeAsnStr note.id) "\"\n" "  :topic \"" (esc/escapeAsnStr note.topic) "\"\n" "  :author \"" (esc/escapeAsnStr note.author) "\"\n" "  :session \"" (esc/escapeAsnStr note.session) "\"\n" "  :date \"" (esc/escapeAsnStr note.date) "\"\n" "  :status :" note.status "\n" "  :scope " scopeStr "\n" "  :tags " tagsStr "\n" "  :fact \"" (esc/escapeAsnStr note.fact) "\"\n" "  :evidence \"" (esc/escapeAsnStr note.evidence) "\"\n" "  :consequence \"" (esc/escapeAsnStr note.consequence) "\")"))

fn projectNoteMd note: NoteRecord -> Str
  (let [(scopeLines (map (fn [(s Str)] -> Str (str "- `" s "`\n")) note.scope)) (scopeBody (if (= (listLength scopeLines) 0) "- None\n" (stringJoin scopeLines ""))) (tagBadges (map (fn [(t Str)] -> Str (str "`#" t "`")) note.tags)) (tagHeader (stringJoin tagBadges " "))] (str "# Note [" note.id "]: " note.topic "\n\n" "- **Author**: " note.author "\n" "- **Session**: `" note.session "`\n" "- **Date**: " note.date "\n" "- **Status**: " note.status "\n" "- **Tags**: " tagHeader "\n\n" "## Scope\n" scopeBody "\n" "## Empirical Fact\n" note.fact "\n\n" "## Grounded Evidence\n" note.evidence "\n\n" "## Architectural Consequence\n" note.consequence))

fn notePromoteToTask note: NoteRecord taskId: Str -> NoteRecord
  (with note :status "promoted-to-task" :consequence (str note.consequence " (Promoted to task: " taskId ")"))

fn notePromoteToAdr note: NoteRecord adrId: Str -> NoteRecord
  (with note :status "promoted-to-adr" :consequence (str note.consequence " (Promoted to ADR: " adrId ")"))

fn noteCloseScope notes: (List NoteRecord) closingScope: Str -> (List NoteRecord)
  (filter (fn [(n NoteRecord)] -> Bool (let [(sc n.scopeLevel) (st n.status)] (if (or (= st "promoted-to-task") (= st "promoted-to-adr")) true (if (= closingScope "step") (not (= sc "step")) (if (= closingScope "task") (and (not (= sc "step")) (not (= sc "task"))) true))))) notes)

fn notePruneBounded notes: (List NoteRecord) maxActive: Int -> (List NoteRecord)
  (let [(len (listLength notes))] (if (<= len maxActive) notes (let [(excess (- len maxActive)) (rem (optionOr (listSlice notes excess len) (list)))] rem)))
