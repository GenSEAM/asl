(module ws/mergeRows/mergeRowsTest :x [runTests] :i [(ws/mergeRows/mergeRows :a m)])
fn ! runTests -> Bool
  (do
    (assert (testHistoryReplay!) "five historical conflicts and three Git merges replay cleanly")
    (assert (testAttributes!) "knownRed, hostValidity and camelLexicon merge with the asnRows driver")
    (assert (testLedger! ".asl/mem/knownRed.asn" "  (:suite \"rowsOurs.asl\" :cause \"E\")" "  (:suite \"rowsTheirs.asl\" :cause \"E\")") "knownRed rows added on both branches merge in place")
    (assert (testLedger! "tools/camelLexicon.asn" "    (\"rows-ours\" \"rowsOurs\")" "    (\"rows-theirs\" \"rowsTheirs\")") "camelLexicon rows added on both branches merge in place")
    (assert (testLedger! "scripts/audit/foreignBaseline.asn" "  (:raise :path \"rowsOurs.sh\" :lang :shell :lines 1 :py 0)" "  (:raise :path \"rowsTheirs.sh\" :lang :shell :lines 1 :py 0)") "foreignBaseline raises added on both branches merge in place")
    (assert (testHostValidityLedger!) "hostValidity rows added on both branches merge and recount (:total)")
    (assert (testDelete) "delete versus unchanged removes row")
    (assert (testConflict) "same key divergent update marks only that row")
    (assert (testLarger) "baseline rows changed on both sides take the larger line count")
    (assert (testMetaBaseline) "meta baseline rows merge by the larger :plain value")
    (assert (testLangMismatch) "language mismatch conflicts")
    (assert (testTie) "same line count divergent baseline rows conflict")
    (assert (testRaiseThreeWay) "raises merge three-way: a raise ours retired stays retired")
    (assert (testIdentity) "identity preserves original bytes")
    (assert (testKnownRed) "knownRed rows added on both sides land before the closing line without blank lines")
    (assert (testHostValidity) "hostValidity rows added on both sides recount (:total)")
    (assert (testSections) "camelLexicon additions stay in their section and the closing suffix moves to the last row")
    (assert (testDeleteLast) "deleting the last row of a section moves its closers to the row before")
    (assert (testDeleteVersusChange) "a row theirs changed and ours deleted conflicts")
    true)
fn testHistoryReplay! -> Bool
  (let [(r (processRun "perl -e \"alarm 900; exec @ARGV\" sh scripts/audit/mergeRowsHistoryTest.sh"))]
    (and (= r.exitCode 0)
         (stringContains? r.stdout "mergeRowsHistoryTest: 5 historical pairs and 3 Git-dispatched replays passed")))
fn testAttributes! -> Bool
  (mt (fileReadString ".gitattributes")
    ((err _) false)
    ((ok text) (let [(lines (stringLines text))]
      (and (listContains? lines ".asl/mem/knownRed.asn merge=asnRows")
           (listContains? lines "tests/audit/hostValidity.asn merge=asnRows")
           (listContains? lines "tools/camelLexicon.asn merge=asnRows")))))
fn insertBeforeLast text: String row: String -> String
  (let [(lines (stringSplit text "\n")) (n (listLength lines))
        (cut (if (stringEmpty? (optionOr (listGet lines (- n 1)) "x")) (- n 2) (- n 1)))]
    (stringJoin (listAppend (listTake lines cut) (cons row (listDrop lines cut))) "\n"))
fn testLedger! path: String oursRow: String theirsRow: String -> Bool
  (mt (fileReadString path)
    ((err _) false)
    ((ok base)
      (let [(ours (insertBeforeLast base oursRow))
            (r (m/mergeRows base ours (insertBeforeLast base theirsRow) "rows"))]
        (and (not r.conflict) (= r.text (insertBeforeLast ours theirsRow))))))
fn bumpTotal text: String by: Int64 -> String
  (stringJoin (map (fn [(l String)] -> String
    (if (stringStartsWith? l "(:total ")
      (str "(:total " (stringFromInt64 (+ by (optionOr (stringToInt64 (optionOr (stringSlice l 8 (- (stringLength l) 1)) "")) 0))) ")")
      l)) (stringSplit text "\n")) "\n")
fn testHostValidityLedger! -> Bool
  (mt (fileReadString "tests/audit/hostValidity.asn")
    ((err _) false)
    ((ok base)
      (let [(o "(:f :path \"rowsOurs.asl\" :code ERR_X :class staleName)\n")
            (t "(:f :path \"rowsTheirs.asl\" :code ERR_X :class staleName)\n")
            (r (m/mergeRows base (bumpTotal (str base o) 1) (bumpTotal (str base t) 1) "hostValidity"))]
        (and (stringStartsWith? base "(:total ") (stringEndsWith? base "\n") (not r.conflict)
             (= r.text (bumpTotal (str base o t) 2))))))
fn testDelete -> Bool
  (let [(b "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c)\n(:path \"b.c\" :kind :c)\n)")
        (o "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c)\n)")
        (r (m/mergeRows b o b "allowlist"))]
    (and (not r.conflict) (not (stringContains? r.text "b.c"))))
fn testConflict -> Bool
  (let [(b "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c :rationale \"old\")\n(:path \"b.c\" :kind :c)\n)")
        (o "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c :rationale \"ours\")\n(:path \"b.c\" :kind :c)\n)")
        (t "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c :rationale \"theirs\")\n(:path \"b.c\" :kind :c)\n)")
        (r (m/mergeRows b o t "allowlist"))]
    (and r.conflict
         (stringContains? r.text "<<<<<<< ours\n(:path \"a.c\"")
         (stringContains? r.text ">>>>>>> theirs\n(:path \"b.c\"")
         (= (listLength (stringSplit r.text "=======")) 2)))
fn testLarger -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.c\" :lang :c :lines 1007 :py 0)\n)"))
        (o (str h "(:file :path \"a.c\" :lang :c :lines 1067 :py 0)\n)"))
        (t (str h "(:file :path \"a.c\" :lang :c :lines 1026 :py 0)\n)"))
        (oursLarger (m/mergeRows b o t "baseline"))
        (theirsLarger (m/mergeRows b t o "baseline"))]
    (and (not oursLarger.conflict) (stringContains? oursLarger.text ":lines 1067") (not (stringContains? oursLarger.text ":lines 1026"))
         (not theirsLarger.conflict) (stringContains? theirsLarger.text ":lines 1067") (not (stringContains? theirsLarger.text ":lines 1026"))))
fn testMetaBaseline -> Bool
  (let [(h "(:metaBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.asl\" :plain 7)\n)"))
        (o (str h "(:file :path \"a.asl\" :plain 9)\n)"))
        (t (str h "(:file :path \"a.asl\" :plain 8)\n)"))
        (oursLarger (m/mergeRows b o t "metaBaseline"))
        (theirsLarger (m/mergeRows b t o "metaBaseline"))]
    (and (not oursLarger.conflict) (stringContains? oursLarger.text ":plain 9") (not (stringContains? oursLarger.text ":plain 8"))
         (not theirsLarger.conflict) (stringContains? theirsLarger.text ":plain 9") (not (stringContains? theirsLarger.text ":plain 8"))))
fn testLangMismatch -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.asl\" :lang :c :lines 5 :py 0)\n)"))
        (o (str h "(:file :path \"a.asl\" :lang :c :lines 7 :py 0)\n)"))
        (t (str h "(:file :path \"a.asl\" :lang :py :lines 99 :py 0)\n)"))
        (r (m/mergeRows b o t "baseline"))]
    (and r.conflict
         (stringContains? r.text ":lang :c :lines 7")
         (stringContains? r.text ":lang :py :lines 99")))
fn testRaiseThreeWay -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\")\n")
        (a "(:raise :path \"a.c\" :lang :c :lines 2 :py 0 :reason \"a\" :date \"d\")")
        (b "(:raise :path \"b.c\" :lang :c :lines 3 :py 0 :reason \"b\" :date \"d\")")
        (c "(:raise :path \"c.c\" :lang :c :lines 4 :py 0 :reason \"c\" :date \"d\")")
        (d "(:raise :path \"d.c\" :lang :c :lines 5 :py 0 :reason \"d\" :date \"d\")")
        (r (m/mergeRows (str h a "\n" b "\n") (str h b "\n" c "\n") (str h a "\n" b "\n" d "\n") "baseline"))]
    (and (not r.conflict)
         (= r.text (str h b "\n" c "\n" d "\n"))))
fn testKnownRed -> Bool
  (let [(h "(:knownRed :v 1 :date \"d\"\n")
        (x "  (:suite \"x.asl\" :cause \"E\")\n")
        (y "  (:suite \"y.asl\" :cause \"E\")\n")
        (z "  (:suite \"z.asl\" :cause \"E\")\n")
        (r (m/mergeRows (str h x ")\n") (str h x y ")\n") (str h x z ")\n") "rows"))]
    (and (not r.conflict) (= r.text (str h x y z ")\n"))))
fn testHostValidity -> Bool
  (let [(row (fn [(p String) (c String)] -> String (str "(:f :path \"" p "\" :code ERR_X :class " c ")\n")))
        (b (str "(:total 1)\n" (row "a.asl" "staleName")))
        (o (str "(:total 2)\n" (row "a.asl" "staleName") (row "b.asl" "staleName") (row "n.asl" "negativeFixture")))
        (t (str "(:total 2)\n" (row "a.asl" "staleName") (row "c.asl" "staleName")))
        (r (m/mergeRows b o t "hostValidity"))]
    (and (not r.conflict)
         (= r.text (str "(:total 3)\n" (row "a.asl" "staleName") (row "b.asl" "staleName") (row "n.asl" "negativeFixture") (row "c.asl" "staleName")))))
fn testSections -> Bool
  (let [(b "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\"))\n  :renames (\n    (\"c-d\" \"cD\")))\n")
        (o "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\"))\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")))\n")
        (t "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\")\n    (:old \"g-h\" :new \"gH\"))\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"i-j\" \"iJ\")))\n")
        (r (m/mergeRows b o t "rows"))]
    (and (not r.conflict)
         (= r.text "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\")\n    (:old \"g-h\" :new \"gH\"))\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")\n    (\"i-j\" \"iJ\")))\n")))
fn testDeleteLast -> Bool
  (let [(b "(:lexicon :id \"x\"\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")))\n")
        (o "(:lexicon :id \"y\"\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")))\n")
        (t "(:lexicon :id \"x\"\n  :renames (\n    (\"c-d\" \"cD\")))\n")
        (r (m/mergeRows b o t "rows"))]
    (and (not r.conflict) (= r.text "(:lexicon :id \"y\"\n  :renames (\n    (\"c-d\" \"cD\")))\n")))
fn testDeleteVersusChange -> Bool
  (let [(h "(:knownRed :v 1\n")
        (b (str h "  (:suite \"x.asl\" :cause \"E\")\n  (:suite \"y.asl\" :cause \"E\")\n)\n"))
        (o (str h "  (:suite \"y.asl\" :cause \"E\")\n)\n"))
        (t (str h "  (:suite \"x.asl\" :cause \"F\")\n  (:suite \"y.asl\" :cause \"E\")\n)\n"))
        (r (m/mergeRows b o t "rows"))]
    (and r.conflict (stringContains? r.text "=======\n  (:suite \"x.asl\" :cause \"F\")\n>>>>>>> theirs")))
fn testTie -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.c\" :lang :c :lines 9 :py 0)\n)"))
        (o (str h "(:file :path \"a.c\" :lang :c :lines 8 :py 0)\n)"))
        (t (str h "(:file :path \"a.c\" :lang :c :lines 8 :py 1)\n)"))
        (r (m/mergeRows b o t "baseline"))]
    (and r.conflict (stringContains? r.text "<<<<<<< ours") (stringContains? r.text "=======") (stringContains? r.text ">>>>>>> theirs")))
fn testIdentity -> Bool
  (let [(s "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c)\n\n)")
        (r (m/mergeRows s s s "allowlist"))]
    (and (not r.conflict) (= r.text s)))
