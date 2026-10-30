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

fn ! runTests -> Bool
  (do (assert (testImport) "plan import on a fixture ledger")
      (assert (testSideLedgerKeepsParked) "side-ledger import keeps parked rows")
      true)
