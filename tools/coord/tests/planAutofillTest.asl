(module asl-tools/coord/tests/planAutofillTest
  :x [runTests]
  :i [(asl-tools/coord/planImport :a pi)])

; (:m :do "seven rows: mixed pri spellings, one already queued, one non-importable, two overlapping owns")
fn ledger -> String
  (str "(:u :id A1 :queue conductor :pri p1 :do \"a\" :owns (\"docs/a.md\") :gate \"true\")\n"
       "(:u :id B2 :queue conductor :prio med :do \"b\" :owns (\"docs/b.md\") :gate \"true\")\n"
       "(:u :id C3 :queue conductor :pri low :do \"c\" :owns (\"docs/c.md\") :gate \"true\")\n"
       "(:u :id D4 :queue conductor :pri p0 :do \"d\" :owns (\"docs/d.md\") :gate \"true\")\n"
       "(:u :id E5 :queue conductor :do \"e\" :owns (\"docs/e.md\") :gate \"true\")\n"
       "(:u :id F6 :queue conductor :pri p1 :do \"f\" :owns (\"docs/a.md\") :gate \"true\")\n"
       "(:u :id G7 :queue conductor :pri p0 :do \"g\" :gate \"true\")\n")

fn pickedIds rows: (List pi/PlanRow) -> (List String)
  (map (fn [(r pi/PlanRow)] -> String r.id) rows)

fn ! testPick -> Bool
  (let [(rows (pi/rowsOf (ledger)))
        (picked (pi/autofillPick rows (list "B2") 3))
        (none (pi/autofillPick rows (list "B2") 0))]
    (do (assert (= (listLength rows) 7) (str "seven rows: " (stringFromInt64 (listLength rows))))
        (assert (= (pickedIds picked) (list "A1" "D4" "E5")) (str "picked: " (stringJoin (pickedIds picked) ",")))
        (assert (listEmpty? none) "capacity 0 picks nothing")
        true))

fn ! runTests -> Bool
  (do (assert (testPick) "autofill picks by pri, skips queued, non-importable and overlapping owns")
      true)
