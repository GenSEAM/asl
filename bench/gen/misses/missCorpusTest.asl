(module aslBench/gen/misses/missCorpusTest
  :x [runTests fixtureRows wrap healed missDir]
  :i [(aslBench/gen/core :a gc)
      (asl-forms/heal :a h)
      (asl-cli/verify :a v)
      (asl-checker/types :a ty)])

; (:m :ref MISS-ABSORB :do "gate over the miss corpus of the 2026-11-13 generation bench: every fixture is a model reply as written; an accept fixture checks raw, a heal fixture fails raw, both come out of heal as the stored canonical form with nothing left and the pipeline without the fixture's rule does not get there; a turn fixture stays diagnosed and its diagnostic carries the stated fix; the 30 reference solutions come back byte-identical")

fn missDir -> String
  "asl/bench/gen/misses"

fn hdr -> String
  "(module cand :x [])\n\n"

fn wrap body: String -> String
  (str (hdr) body)

fn ! readOr path: String -> String
  (match (fileReadString path) ((ok t) t) ((err _) ""))

fn ! fixtureRows -> (List (List gc/Sx))
  (match (gc/readForms (readOr (str (missDir) "/catalogue.asn")))
    ((err _) (list))
    ((ok forms) (map gc/sxItems (filter (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":fixture")) forms))))

fn healed vocab: (List String) text: String -> h/HealResult
  (h/healSourceWith text "cand.asl" (mapEmpty) vocab)

fn said ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (v/formatDiag d)) ds) "\n")

fn ! turnOk vocab: (List String) id: String row: (List gc/Sx) text: String -> Bool
  (let [(before (h/healDiags text (mapEmpty) "cand.asl"))
        (res (healed vocab text))]
    (assert (not (listEmpty? before)) (str id ": a turn fixture fails its raw check"))
    (assert (not (listEmpty? res.left)) (str id ": no mechanical repair exists, the receipt keeps a diagnostic, got " res.receipt))
    (assert (stringContains? (said res.left) (gc/kwText row ":says")) (str id ": the diagnostic names the fix " (gc/kwText row ":says") ", got " (said res.left)))
    true)

fn ! absorbOk vocab: (List String) id: String row: (List gc/Sx) text: String -> Bool
  (let [(decision (gc/kwText row ":decision"))
        (rule (gc/kwText row ":rule"))
        (want (wrap (readOr (str (missDir) "/" id ".asl"))))
        (before (h/healDiags text (mapEmpty) "cand.asl"))
        (res (healed vocab text))
        (again (healed vocab want))
        (alt (gc/kwText row ":alt"))
        (mutant (h/healSourceRules text "cand.asl" (mapEmpty) vocab (filter (fn [(r String)] -> Bool (and (!= r rule) (!= r alt))) (h/healRuleNames))))]
    (assert (> (stringLength want) (stringLength (hdr))) (str id ": the expected canonical form is stored"))
    (assert (= (listEmpty? before) (= decision "accept")) (str id ": the raw reply checks only when the decision is accept, got " (said before)))
    (assert (= res.text want) (str id ": absorbs to the expected canonical form, got " res.text " receipt " res.receipt))
    (assert (listEmpty? res.left) (str id ": nothing is left, got " res.receipt))
    (assert (listContains? res.repaired rule) (str id ": the receipt names " rule ", got " res.receipt))
    (assert (listEmpty? (h/healDiags want (mapEmpty) "cand.asl")) (str id ": the expected form checks"))
    (assert (and (not again.changed) (= again.text want)) (str id ": the canonical form is a fixed point"))
    (assert (not (and (= mutant.text want) (listEmpty? mutant.left))) (str id ": the pipeline without " rule " does not absorb the fixture"))
    true)

fn parseLeft? ds: (List ty/Diagnostic) -> Bool
  (listAny? (fn [(d ty/Diagnostic)] -> Bool (= d.code "parse")) ds)

; (:m :ref MISS-ABSORB :do "a parse fixture is a whole module as a model wrote it, imports included, so only its parse level is asserted: the two delimiter rules make it parse by deleting exactly the stated stray closers, and delimiterBalance alone leaves it unparsed")
fn ! parseOk vocab: (List String) id: String row: (List gc/Sx) text: String -> Bool
  (let [(res (h/healSourceRules text "cand.asl" (mapEmpty) vocab (list "delimiterBalance" "indentBalance")))
        (mutant (h/healSourceRules text "cand.asl" (mapEmpty) vocab (list "delimiterBalance")))]
    (assert (parseLeft? (h/healDiags text (mapEmpty) "cand.asl")) (str id ": the raw module does not parse"))
    (assert (listContains? res.repaired "indentBalance") (str id ": the receipt names indentBalance, got " res.receipt))
    (assert (not (parseLeft? res.left)) (str id ": the healed module parses, got " res.receipt))
    (assert (= (stringLength res.text) (- (stringLength text) (gc/kwInt row ":strays"))) (str id ": exactly the stray closers are deleted"))
    (assert (parseLeft? mutant.left) (str id ": delimiterBalance alone leaves the module unparsed"))
    true)

fn ! fixtureOk vocab: (List String) row: (List gc/Sx) -> Bool
  (let [(id (gc/kwText row ":id"))
        (decision (gc/kwText row ":decision"))
        (raw (readOr (str (missDir) "/" id ".raw.txt")))]
    (assert (not (stringEmpty? raw)) (str id ": the raw reply is stored"))
    (cond
      ((= decision "turn") (turnOk vocab id row (wrap raw)))
      ((= decision "parse") (parseOk vocab id row raw))
      (else (absorbOk vocab id row (wrap raw)))))

fn ! refOk vocab: (List String) name: String -> Bool
  (let [(text (wrap (readOr (str "asl/bench/gen/ref/" name))))
        (res (healed vocab text))]
    (assert (listEmpty? (h/healDiags text (mapEmpty) "cand.asl")) (str name ": the reference checks, got " (said (h/healDiags text (mapEmpty) "cand.asl"))))
    (assert (and (= res.text text) (not res.changed)) (str name ": heal leaves a correct program byte-identical, receipt " res.receipt))
    true)

fn ! runTests -> Bool
  (let [(vocab (h/preludeVocab! "asl/prelude/prelude.asl"))
        (rows (fixtureRows))
        (refs (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asl")) (match (dirList "asl/bench/gen/ref") ((ok ns) ns) ((err _) (list)))))
        (decisions (map (fn [(r (List gc/Sx))] -> String (gc/kwText r ":decision")) rows))]
    (assert (listContains? vocab "listSum") "the prelude vocabulary loads")
    (assert (and (>= (listLength rows) 20) (<= (listLength rows) 60)) (str "the corpus holds 20 to 60 fixtures, found " (stringFromInt64 (listLength rows))))
    (assert (and (listContains? decisions "accept") (and (listContains? decisions "heal") (listContains? decisions "turn"))) "every decision has a fixture")
    (assert (= (listLength refs) 30) (str "30 reference solutions, found " (stringFromInt64 (listLength refs))))
    (and (fold (fn [(ok Bool) (r (List gc/Sx))] -> Bool (and (fixtureOk vocab r) ok)) true rows)
         (fold (fn [(ok Bool) (n String)] -> Bool (and (refOk vocab n) ok)) true refs)))
