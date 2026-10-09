(module asl-gates/tests/vacuityTest :x [testParseArgv testParseAssertionsTap testParseAssertionsMvp testParseAssertionsUnrecognized testClassification testEscapeStr runTests] :i [(asl-gates/vacuity :a vac)])

fn testParseArgv -> Bool
  (let [(a1 (list "--test" "python foo.py"))
        (r1 (vac/parseArgv a1))
        (a2 (list "--test" "foo" "--base" "HEAD~1" "--fail-on-vacuous"))
        (r2 (vac/parseArgv a2))
        (a3 (list "unexpected" "--test" "foo"))
        (r3 (vac/parseArgv a3))
        (a4 (list "--base"))
        (r4 (vac/parseArgv a4))]
    (do
      (assert (ok? r1) "parseArgv simple ok")
      (mt r1
        ((ok cfg)
          (do
            (assert (= cfg.testCmd "python foo.py") "cmd matches")
            (assert (= cfg.baseRef "HEAD") "default base HEAD")
            (assert (not cfg.failOnVacuous) "default failOnVacuous false")))
        ((err _) (assert false "expected ok r1")))
      (assert (ok? r2) "parseArgv all flags ok")
      (mt r2
        ((ok cfg)
          (do
            (assert (= cfg.testCmd "foo") "cmd matches r2")
            (assert (= cfg.baseRef "HEAD~1") "custom base matches")
            (assert cfg.failOnVacuous "failOnVacuous true")))
        ((err _) (assert false "expected ok r2")))
      (assert (err? r3) "unexpected arg before test rejected")
      (assert (err? r4) "missing base arg rejected")
      true))

fn testParseAssertionsTap -> Bool
  (let [(out (str "TAP version 13\n" "1..3\n" "# Starting suite\n" "ok 1 - tapVacuousAdd\n" "not ok 2 - tapRealAdd # TODO\n" "ok - tapHyphen\n"))
        (res (vac/parseAssertions out ""))]
    (do
      (assert (ok? res) "parseAssertions TAP ok")
      (mt res
        ((ok m)
          (do
            (assert (= (mapSize m) 3) "parsed 3 assertions")
            (assert (= (optionOr (mapGet m "tapVacuousAdd") false) true) "tapVacuousAdd is true")
            (assert (= (optionOr (mapGet m "tapRealAdd") true) false) "tapRealAdd is false")
            (assert (= (optionOr (mapGet m "tapHyphen") false) true) "tapHyphen is true")))
        ((err _) (assert false "expected ok res")))
      true))

fn testParseAssertionsMvp -> Bool
  (let [(out (str "ok calc vacuousAdd\n" "FAIL calc realAdd: 2 != 5\n" "ok standalone\n" "FAIL failureOnly\n" "(:gate :name \"vac\" :asserts 4 :failed 2)\n"))
        (res (vac/parseAssertions out ""))]
    (do
      (assert (ok? res) "parseAssertions MVP ok")
      (mt res
        ((ok m)
          (do
            (assert (= (mapSize m) 4) "parsed 4 assertions")
            (assert (= (optionOr (mapGet m "calc vacuousAdd") false) true) "vacuousAdd is true")
            (assert (= (optionOr (mapGet m "calc realAdd") true) false) "realAdd is false")
            (assert (= (optionOr (mapGet m "standalone") false) true) "standalone is true")
            (assert (= (optionOr (mapGet m "failureOnly") true) false) "failureOnly is false")))
        ((err _) (assert false "expected ok res")))
      true))

fn testParseAssertionsUnrecognized -> Bool
  (let [(out "Random unparseable test line\n")
        (res (vac/parseAssertions out ""))]
    (do
      (assert (err? res) "unrecognized line gives error")
      (mt res
        ((ok _) (assert false "expected err"))
        ((err e) (assert (stringContains? e "unrecognized output line") "error hint matches")))
      true))

fn testClassification -> Bool
  (let [(base (mapSet (mapSet (mapEmpty) "vac" true) "baseOnly" true))
        (work (mapSet (mapSet (mapEmpty) "vac" true) "real" true))
        (tally (vac/classify base work))]
    (do
      (assert (= (listLength tally.vacuous) 1) "1 vacuous")
      (assert (= tally.realGreen 1) "1 realGreen")
      (assert (= tally.stillRed 0) "0 stillRed")
      (assert (= tally.baseOnly 1) "1 baseOnly")
      true))

fn testEscapeStr -> Bool
  (do
    (assert (= (vac/escapeStr "hello") "hello") "plain escape")
    (assert (= (vac/escapeStr "foo\\bar") "foo\\\\bar") "backslash escape")
    (assert (= (vac/escapeStr "foo\"bar") "foo\\\"bar") "quote escape")
    (assert (= (vac/escapeStr "foo\nbar") "foo\\nbar") "newline escape")
    true)

fn runTests -> Bool
  (do
    (assert (testParseArgv) "testParseArgv")
    (assert (testParseAssertionsTap) "testParseAssertionsTap")
    (assert (testParseAssertionsMvp) "testParseAssertionsMvp")
    (assert (testParseAssertionsUnrecognized) "testParseAssertionsUnrecognized")
    (assert (testClassification) "testClassification")
    (assert (testEscapeStr) "testEscapeStr")
    true)
