(module asl-tools/coord/tests/planImportTest
  :x [runTests]
  :i [(asl-tools/coord/planImport :a pi) (asl-tools/coord/store :a st)])

; (:m :ref COND4 :do "fixture ledger only (never the real SH/plan.asn): :auto true and :queue conductor rows become store tasks with owns, gate and deps; a row without :owns is parked with :need owns and never guessed; a row after a parked row is parked too; an :auto list row, a done row and an unmarked row are ignored; a second import changes nothing; a row that gains :owns leaves parked.asn at the next import")
fn ledgerText owns2: String -> String
  (str "; comment line\n"
       "(:u :id A1 :auto true :do \"add doc a\" :owns (\"docs/a.md\") :gate \"grep -q a docs/a.md\")\n"
       "(:u :id B2 :queue conductor :do \"add doc b\" :owns (\"docs/b.md\" \"docs/b2.md\") :gate \"true\" :after A1 :channel leon)\n"
       "(:u :id C3 :auto true :do \"needs owns\" :gate \"true\")\n"
       "(:u :id D4 :auto true :do \"after parked\" :owns (\"docs/d.md\") :gate \"true\" :after (C3))\n"
       "(:u :id E5 :auto (\"survey list\") :do \"ignored\" :owns (\"x\") :gate \"true\")\n"
       "(:u :id F6 :auto true :status :done :do \"done\" :owns (\"x\") :gate \"true\")\n"
       "(:u :id G7 :do \"unmarked\" :owns (\"x\") :gate \"true\")\n"
       "(:u :id H8 :auto true :do \"unknown dep\" :owns (\"docs/h.md\") :gate \"true\" :after ZZ9)\n"
       "(:u :id I9 :auto true :do \"gains owns\" " owns2 " :gate \"true\")\n")

fn ! scratchStore name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/planImportTest-" name)

fn ! ids store: String -> (List String)
  (match (st/readUnits! store) ((ok us) (listSort (map (fn [(u st/Task)] -> String u.id) us))) ((err _) (list)))

fn ! unitOf store: String id: String -> st/Task
  (optionOr (match (st/readUnits! store) ((ok us) (listFind (fn [(u st/Task)] -> Bool (= u.id id)) us)) ((err _) (none)))
            (st/Task :id "" :owns (list) :reads (list) :gate "" :channel "" :model "" :base "" :after (list) :st "absent" :epoch 0 :receipt ""))

fn ! testImport -> Bool
  (let [(store (scratchStore "main"))
        (_ (dirCreate store))
        (_ (fileWrite (str store "/.keep") ""))
        (text (ledgerText ""))
        (dry (pi/plan! text store "dev" true))
        (afterDry (ids store))
        (first (pi/plan! text store "dev" false))
        (b (unitOf store "B2"))
        (a (unitOf store "A1"))
        (doc (resultOr (fileReadString (str store "/tasks/A1.txt")) ""))
        (parked (resultOr (fileReadString (str store "/parked.asn")) ""))
        (idsOnce (ids store))
        (second (pi/plan! text store "dev" false))
        (idsTwice (ids store))
        (text2 (ledgerText ":owns (\"docs/i.md\")"))
        (third (pi/plan! text2 store "dev" false))
        (idsThree (ids store))
        (parked3 (resultOr (fileReadString (str store "/parked.asn")) ""))
        (_ (pathRemove store))]
    (do (assert (and (ok? dry) (listEmpty? afterDry)) "a dry import writes nothing")
        (assert (ok? first) (str "import: " first))
        (assert (= idsOnce (list "A1" "B2")) (str "only complete rows with resolvable deps became tasks: " (stringJoin idsOnce ",")))
        (assert (and (= b.owns (list "docs/b.md" "docs/b2.md")) (= b.after (list "A1")) (= b.channel "leon") (= b.base "dev") (= b.st "queued")) "owns, after, channel and base carried")
        (assert (and (= a.gate "grep -q a docs/a.md") (= a.channel "free") (= doc "add doc a")) "gate, default channel and task text")
        (assert (and (stringContains? parked ":id \"C3\" :need owns") (stringContains? parked ":id \"D4\" :need after") (stringContains? parked ":id \"H8\" :need after") (stringContains? parked ":id \"I9\" :need owns")) (str "parked with their need: " parked))
        (assert (not (or (stringContains? parked "E5") (or (stringContains? parked "F6") (stringContains? parked "G7")))) "list-marked, done and unmarked rows are not even parked")
        (assert (and (ok? second) (= idsTwice idsOnce)) "a second import changes nothing")
        (assert (and (ok? third) (listContains? idsThree "I9")) (str "a row that gained :owns is imported: " third " " (stringJoin idsThree ",")))
        (assert (not (stringContains? parked3 "I9")) (str "and leaves parked.asn: " parked3))
        true))

; (:m :ref PLANIMPORT-PARKED-WIPE :do "an import from a second (side) ledger keeps the parked rows of ids it does not carry; it still replaces the rows of its own ids")
fn ! testSideLedgerKeepsParked -> Bool
  (let [(store (scratchStore "side"))
        (_ (dirCreate store))
        (main (pi/plan! "(:u :id P1 :auto true :do \"main parked\" :gate \"true\")\n" store "dev" false))
        (side (pi/plan! "(:u :id S1 :queue conductor :do \"side row\" :owns (\"docs/s.md\") :gate \"true\")\n(:u :id S2 :queue conductor :do \"side parked\" :gate \"true\")\n" store "dev" false))
        (parked (resultOr (fileReadString (str store "/parked.asn")) ""))
        (sideAgain (pi/plan! "(:u :id S2 :queue conductor :do \"side parked\" :owns (\"docs/s2.md\") :gate \"true\")\n" store "dev" false))
        (parked2 (resultOr (fileReadString (str store "/parked.asn")) ""))
        (_ (pathRemove store))]
    (do (assert (and (ok? main) (ok? side)) "both imports run")
        (assert (stringContains? parked ":id \"P1\" :need owns") (str "the main ledger's parked row survives a side import: " parked))
        (assert (stringContains? parked ":id \"S2\" :need owns") (str "the side ledger's own parked row is written: " parked))
        (assert (and (ok? sideAgain) (not (stringContains? parked2 "S2"))) (str "a side row that gained :owns leaves parked.asn: " parked2))
        (assert (stringContains? parked2 ":id \"P1\"") (str "and P1 still stays: " parked2))
        true))

; (:m :ref CONDUCTOR-TASK-REFRESH :do "a changed ledger row refreshes tasks/ID.txt and the store row's owns and gate of a unit that is not in a stage and journals one (:refresh ...) row; the same ledger again changes nothing; a writing unit is left alone; a dry import only reports")
fn ledgerOne doc: String gate: String -> String
  (str "(:u :id R1 :queue conductor :do \"" doc "\" :owns (\"docs/r.md\") :gate \"" gate "\")\n")

fn refreshedOf r: (Result pi/Report String) -> (List String)
  (match r ((ok rep) rep.refreshed) ((err _) (list "ERR")))

fn ! journalRows store: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:refresh ")) (stringLines (resultOr (fileReadString (str store "/journal.asn")) ""))))

fn ! testRefresh -> Bool
  (let [(store (scratchStore "refresh"))
        (_ (dirCreate store))
        (first (pi/plan! (ledgerOne "d1" "g1") store "dev" false))
        (r0 (refreshedOf first))
        (changed (pi/plan! (ledgerOne "d2" "g2") store "dev" false))
        (r1 (refreshedOf changed))
        (u1 (unitOf store "R1"))
        (doc1 (resultOr (fileReadString (str store "/tasks/R1.txt")) ""))
        (rows1 (journalRows store))
        (again (refreshedOf (pi/plan! (ledgerOne "d2" "g2") store "dev" false)))
        (rows2 (journalRows store))
        (_ (dirCreate (str store "/cond")))
        (_ (fileWrite (str store "/cond/R1.asn") "(:cu :id \"R1\" :st writing)\n"))
        (busy (refreshedOf (pi/plan! (ledgerOne "d3" "g3") store "dev" false)))
        (doc2 (resultOr (fileReadString (str store "/tasks/R1.txt")) ""))
        (_ (fileWrite (str store "/cond/R1.asn") "(:cu :id \"R1\" :st blocked :await \"lead\")\n"))
        (leadHeld (refreshedOf (pi/plan! (ledgerOne "d3" "g3") store "dev" false)))
        (_ (fileWrite (str store "/cond/R1.asn") "(:cu :id \"R1\" :st blocked :await \"rebase\")\n"))
        (rebaseHeld (refreshedOf (pi/plan! (ledgerOne "d3" "g3") store "dev" false)))
        (docHeld (resultOr (fileReadString (str store "/tasks/R1.txt")) ""))
        (_ (fileWrite (str store "/cond/R1.asn") "(:cu :id \"R1\" :st blocked :await \"\")\n"))
        (dry (refreshedOf (pi/plan! (ledgerOne "d3" "g3") store "dev" true)))
        (doc3 (resultOr (fileReadString (str store "/tasks/R1.txt")) ""))
        (_ (pathRemove store))]
    (do (assert (listEmpty? r0) (str "the first import refreshes nothing: " (stringJoin r0 ",")))
        (assert (= r1 (list "R1")) (str "a changed row is refreshed: " (stringJoin r1 ",")))
        (assert (and (= u1.gate "g2") (= doc1 "d2")) (str "gate and task text follow the row: " u1.gate " " doc1))
        (assert (= rows1 1) "one refresh row in the journal")
        (assert (and (listEmpty? again) (= rows2 1)) "the same ledger again refreshes nothing and journals nothing")
        (assert (and (listEmpty? busy) (= doc2 "d2")) "a writing unit keeps its task text")
        (assert (and (listEmpty? leadHeld) (and (listEmpty? rebaseHeld) (= docHeld "d2"))) "a unit blocked awaiting the lead or a rebase keeps its task text")
        (assert (and (= dry (list "R1")) (= doc3 "d2")) "a dry import reports the refresh and writes nothing")
        true))

; (:m :ref ORG-GAP-20261102 :do "staleOwns: one (:staleOwns :id :paths) line per row whose :owns has a path with neither the path nor its directory in the tree; an existing file, a new file in an existing directory and a glob over an existing directory are live; a moved package's old paths are stale")
fn ! testStaleOwns -> Bool
  (let [(root (scratchStore "stale"))
        (_ (dirCreate root))
        (_ (dirCreate (str root "/asl")))
        (_ (dirCreate (str root "/asl/live")))
        (_ (fileWrite (str root "/asl/live/a.asl") "x"))
        (text (str "(:u :id S1 :queue conductor :do \"live\" :owns (\"asl/live/a.asl\") :gate \"true\")\n"
                   "(:u :id S2 :queue conductor :do \"new file\" :owns (\"asl/live/new.asl\" \"asl/live/\") :gate \"true\")\n"
                   "(:u :id S3 :queue conductor :do \"moved\" :owns (\"asl/agentLoop/x.asl\") :gate \"true\")\n"
                   "(:u :id S4 :queue conductor :do \"mixed\" :owns (\"asl/live/a.asl\" \"asl/agentLoop/**\" \"asl/live/*.asl\" \"old/y/z.asl\") :gate \"true\")\n"))
        (rows (pi/staleOwns text root))
        (none (pi/staleOwns "" root))
        (_ (pathRemove root))]
    (do (assert (= (listLength rows) 2) (str "two rows are stale: " (stringJoin rows " | ")))
        (assert (= (optionOr (listGet rows 0) "") "(:staleOwns :id \"S3\" :paths (\"asl/agentLoop/x.asl\"))") (str "S3 names its moved path: " (stringJoin rows " | ")))
        (assert (= (optionOr (listGet rows 1) "") "(:staleOwns :id \"S4\" :paths (\"asl/agentLoop/**\" \"old/y/z.asl\"))") (str "S4 names only the missing paths: " (stringJoin rows " | ")))
        (assert (listEmpty? none) "an empty ledger has nothing stale")
        true))

fn ! runTests -> Bool
  (do (assert (testImport) "plan import on a fixture ledger")
      (assert (testRefresh) "a changed row refreshes an idle unit")
      (assert (testStaleOwns) "rows owning paths absent from the tree are reported")
      (assert (testSideLedgerKeepsParked) "side-ledger import keeps parked rows")
      true)
