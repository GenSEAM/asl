(module asl-forms/tests/repairAdversarialTest
  :x [runTests]
  :i [(asl-forms/repair :a rep)])

fn fixtureDir -> String
  "asl/packages/asl-forms/tests/fixtures/unbalanced/g3real/"

fn readFixture! name: String -> String
  (mt (fileReadString (str (fixtureDir) name ".txt"))
    ((ok t) t)
    ((err e) (do (assert false (str "missing fixture " name ": " e)) "")))

fn caseText! name: String base: String at: Int64 oldLen: Int64 -> String
  (if (< at 0)
    (readFixture! name)
    (let [(b (readFixture! base))
          (n (readFixture! (str name ".new")))]
      (str (optionOr (stringSlice b 0 at) "") n (optionOr (stringSlice b (+ at oldLen) (stringLength b)) ""))))

fn caseOld! base: String at: Int64 oldLen: Int64 -> String
  (if (< at 0) "" (optionOr (stringSlice (readFixture! base) at (+ at oldLen)) ""))

fn runCase! text: String base: String at: Int64 oldLen: Int64 newLen: Int64 pick: String -> RepairResult
  (if (< at 0)
    (rep/repairTextPick text "asl" -1 -1 pick)
    (rep/repairEdit text "asl" at (+ at newLen) (caseOld! base at oldLen) pick))

fn itemProperty name: String it: rep/LeftItem -> Bool
  (let [(os (optionOr (rep/leftItemOptions it) (list)))
        (atSite (filter (fn [(o rep/RepairOption)] -> Bool (and (= (rep/repairOptionLine o) (rep/leftItemLine it)) (= (rep/repairOptionCol o) (rep/leftItemCol it)))) os))
        (safe (filter (fn [(o rep/RepairOption)] -> Bool (not (rep/repairOptionReparents o))) os))
        (firstSafe (mt (listHead os) ((some o) (not (rep/repairOptionReparents o))) ((none) true)))]
    (do
      (assert (or (listEmpty? os) (not (listEmpty? atSite))) (str name " item at " (stringFromInt64 (rep/leftItemLine it)) ":" (stringFromInt64 (rep/leftItemCol it)) " lists its at-site option"))
      (assert (or (listEmpty? safe) firstSafe) (str name " item at " (stringFromInt64 (rep/leftItemLine it)) " puts a non-reparenting option first"))
      true))

fn checkReal! name: String base: String at: Int64 oldLen: Int64 nItems: Int64 firstItem: String firstOption: String pick: String applied: Bool -> Bool
  (let [(text (caseText! name base at oldLen))
        (newLen (if (< at 0) 0 (stringLength (readFixture! (str name ".new")))))
        (res (runCase! text base at oldLen newLen ""))
        (left (rep/repairResultLeft res))
        (receipt (rep/repairResultReceipt res))
        (all (rep/repairResultLeft (runCase! text base at oldLen newLen "0.0")))
        (opts (mt (listHead all) ((some it) (optionOr (rep/leftItemOptions it) (list))) ((none) (list))))
        (allReceipt (rep/formatReceipt (list) all))]
    (do
      (if applied
        (do
          (assert (= (listLength (rep/repairResultRepaired res)) nItems) (str name " auto-applies one deletion per item: " receipt))
          (assert (not (stringContains? receipt ":kind insert")) (str name " auto-apply only deletes"))
          (assert (listEmpty? left) (str name " auto-apply leaves nothing"))
          (assert (= (rep/repairResultText res) (rep/repairResultText (runCase! text base at oldLen newLen pick))) (str name " auto-apply equals picking every first option"))
          (assert (= (rep/repairReceipt (rep/repairResultText res) "asl") "(:repaired () :left ())") (str name " auto-applied text parses"))
          true)
        (do
          (assert (listEmpty? (rep/repairResultRepaired res)) (str name " must not be auto-applied"))
          (assert (= (rep/repairResultText res) text) (str name " text unchanged"))
          (assert (= (listLength left) nItems) (str name " item count " (stringFromInt64 (listLength left))))
          true))
      (assert (stringStartsWith? allReceipt (str "(:repaired () :left (" firstItem)) (str name " first item: " allReceipt))
      (assert (= (mt (listHead opts) ((some o) (rep/formatOption o)) ((none) "")) firstOption) (str name " first option is the at-site fix"))
      (assert (= (listLength all) nItems) (str name " every item is analysed when a pick is given"))
      (assert (listEmpty? (filter (fn [(it rep/LeftItem)] -> Bool (not (itemProperty name it))) all)) (str name " option property"))
      (if (= pick "")
        true
        (let [(picked (runCase! text base at oldLen newLen pick))]
          (do
            (assert (not (listEmpty? (rep/repairResultRepaired picked))) (str name " pick " pick " applies"))
            (assert (listEmpty? (rep/repairResultLeft picked)) (str name " pick leaves nothing"))
            (assert (not (stringContains? (rep/repairResultReceipt picked) ":more")) (str name " applied receipt lists every edit"))
            (assert (= (rep/repairReceipt (rep/repairResultText picked) "asl") "(:repaired () :left ())") (str name " picked text parses"))
            true)))
      true))

fn ! runTests -> Bool
  (do
    (assert (checkReal! "case00" "base75fe4d97" 7047 170 1 "(:line 119 :col 52 :expected \")\"" "(:insert :tok \")\" :line 119 :col 52)" "1.1" false) "case00 replay")
    (assert (checkReal! "case01" "case01" -1 0 1 "(:line 41 :col 9 :expected \"\"" "(:delete :tok \")\" :line 41 :col 9)" "1.1" true) "case01 replay")
    (assert (checkReal! "case02" "case02" -1 0 1 "(:line 80 :col 28 :expected \"\"" "(:delete :tok \")\" :line 80 :col 28)" "1.1" true) "case02 replay")
    (assert (checkReal! "case04" "case04" -1 0 2 "(:line 62 :col 73 :expected \"\"" "(:delete :tok \")\" :line 62 :col 73)" "1.1 2.1" true) "case04 replay")
    (assert (checkReal! "case05" "case05" -1 0 2 "(:line 52 :col 63 :expected \"\"" "(:delete :tok \")\" :line 52 :col 63)" "1.1 2.1" true) "case05 replay")
    (assert (checkReal! "case06" "base6341fd35" 1321 114 2 "(:line 63 :col 120 :expected \"\"" "(:delete :tok \")\" :line 63 :col 120)" "1.1 2.1" false) "case06 replay")
    (assert (checkReal! "case08" "base6341fd35" 29763 90 1 "(:line 553 :col 92 :expected \")\"" "(:insert :tok \")\" :line 553 :col 92)" "1.1" false) "case08 replay")
    (assert (checkReal! "case09" "base6341fd35" 20563 90 1 "(:line 427 :col 92 :expected \")\"" "(:insert :tok \")\" :line 427 :col 92)" "1.1" false) "case09 replay")
    (assert (checkReal! "case10" "base6341fd35" 31757 109 1 "(:line 584 :col 111 :expected \")\"" "(:insert :tok \")\" :line 584 :col 111)" "1.1" false) "case10 replay")
    (assert (checkReal! "case11" "base6341fd35" 32673 401 1 "(:line 601 :col 108 :expected \")\"" "(:insert :tok \")\" :line 601 :col 108)" "1.1" false) "case11 replay")
    (assert (checkReal! "case12" "base6341fd35" 32069 391 1 "(:line 592 :col 105 :expected \")\"" "(:insert :tok \")\" :line 592 :col 105)" "1.1" false) "case12 replay")
    (assert (checkReal! "case13" "base6341fd35" 33383 548 1 "(:line 612 :col 100 :expected \")\"" "(:insert :tok \")\" :line 612 :col 100)" "1.1" false) "case13 replay")
    (assert (checkReal! "case15" "case15" -1 0 3 "(:line 163 :col 16 :expected \"\"" "(:delete :tok \")\" :line 163 :col 16)" "1.1 2.1 3.1" false) "case15 replay")
    (assert (checkReal! "case16" "case16" -1 0 28 "(:line 180 :col 13 :expected \"\"" "(:delete :tok \")\" :line 180 :col 13)" "1.1 2.1 3.1 4.1 5.1 6.1 7.1 8.1 9.1 10.1 11.1 12.1 13.1 14.1 15.1 16.1 17.1 18.1 19.1 20.1 21.1 22.1 23.1 24.1 25.1 26.1 27.1 28.1" false) "case16 replay")
    (assert (checkReal! "case17" "case17" -1 0 10 "(:line 23 :col 13 :expected \"\"" "(:delete :tok \")\" :line 23 :col 13)" "1.1 2.1 3.1 4.1 5.1 6.1 7.1 8.1 9.1 10.1" true) "case17 replay")
    (assert (checkReal! "case18" "case18" -1 0 1 "(:line 55 :col 13 :expected \"\"" "(:delete :tok \")\" :line 55 :col 13)" "1.1" true) "case18 replay")
    (assert (checkReal! "case19" "case19" -1 0 1 "(:line 80 :col 13 :expected \"\"" "(:delete :tok \")\" :line 80 :col 13)" "1.1" true) "case19 replay")
    (assert (checkReal! "case20" "case20" -1 0 1 "(:line 27 :col 85 :expected \"\"" "(:delete :tok \")\" :line 27 :col 85)" "1.1" true) "case20 replay")
    (assert (checkReal! "case21" "case21" -1 0 3 "(:line 215 :col 13 :expected \"\"" "(:delete :tok \")\" :line 215 :col 13)" "1.1 2.1 3.1" true) "case21 replay")
    (assert (checkReal! "case22" "case22" -1 0 4 "(:line 202 :col 64 :expected \"\"" "(:delete :tok \")\" :line 202 :col 64)" "1.1 2.1 3.1 4.1" true) "case22 replay")
    (assert (checkReal! "case25" "baseb1b9331b" 12020 72 1 "(:line 314 :col 72 :expected \"\"" "(:delete :tok \")\" :line 314 :col 72)" "1.1" true) "case25 replay")
    (assert (checkReal! "case27" "base6341fd35" 1321 115 1 "(:line 54 :col 59 :expected \"\"" "(:delete :tok \")\" :line 54 :col 59)" "1.1" true) "case27 replay")
    (assert (checkReal! "case28" "base6341fd35" 1321 115 3 "(:line 54 :col 59 :expected \"\"" "(:delete :tok \")\" :line 54 :col 59)" "1.1 2.1 3.1" false) "case28 replay")
    (assert (checkReal! "case29" "case29" -1 0 1 "(:line 22 :col 1449 :expected \"\"" "(:delete :tok \")\" :line 22 :col 1449)" "1.1" true) "case29 replay")
    (assert (checkReal! "case30" "case30" -1 0 2 "(:line 10 :col 455 :expected \"\"" "(:delete :tok \")\" :line 10 :col 455)" "1.1 2.1" true) "case30 replay")
    (assert (checkReal! "case31" "case31" -1 0 2 "(:line 142 :col 18 :expected \"\"" "(:delete :tok \")\" :line 142 :col 18)" "1.1 2.1" true) "case31 replay")
    (assert (checkReal! "case32" "base6341fd35" 35286 157 1 "(:line 672 :col 51 :expected \"\"" "(:delete :tok \")\" :line 672 :col 51)" "1.1" false) "case32 replay")
    (assert (checkReal! "case33" "base6341fd35" 35286 157 3 "(:line 672 :col 51 :expected \"\"" "(:delete :tok \")\" :line 672 :col 51)" "1.1 2.1 3.1" false) "case33 replay")
    (assert (checkReal! "altdriverBad" "altdriverBad" -1 0 2 "(:line 7 :col 104 :expected \"\"" "(:delete :tok \")\" :line 7 :col 104)" "1.1 2.1" false) "altdriverBad replay")
    (assert (checkReal! "altdriverBad2" "altdriverBad2" -1 0 1 "(:line 21 :col 26 :expected \"\"" "(:delete :tok \")\" :line 21 :col 26)" "1.1" false) "altdriverBad2 replay")
    true)
