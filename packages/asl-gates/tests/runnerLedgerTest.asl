(module asl-gates/tests/runnerLedgerTest
  :x [runTests]
  :i [(asl-gates/runnerLedger :a rl) (asl-gates/suiteRunner :a sr)])

fn testParseLedgerEmpty -> Bool
  (let [(entries (rl/parseLedger ""))]
    (do
      (assert (= (listLength entries) 0) "parseLedger empty string yields empty list")
      true))

fn testParseLedgerValid -> Bool
  (let [(text "  (:suite \"foo/barTest.asl\" :cause \"ERR_LOAD\" :failedAssertDigest \"abc123\" :since \"def456\")\n")
        (entries (rl/parseLedger text))]
    (do
      (assert (= (listLength entries) 1) "parseLedger parses one entry")
      (let [(e (optionOr (listHead entries) (rl/makeLedgerEntry "" "" "" "")))]
        (do
          (assert (= e.suite "foo/barTest.asl") "suite parsed")
          (assert (= e.cause "ERR_LOAD") "cause parsed")
          (assert (= e.digest "abc123") "digest parsed")
          (assert (= e.since "def456") "since parsed")
          true))))

fn testParseLedgerIgnoresNonSuites -> Bool
  (let [(text "(:knownRed :v 1 :scope \"full\")\n  ; comment line\n  (:flaky \"fooTest.asl\")\n  (:suite \"realTest.asl\" :cause \"OK\" :failedAssertDigest \"\" :since \"sha1\")\n")
        (entries (rl/parseLedger text))]
    (do
      (assert (= (listLength entries) 1) "parseLedger ignores non-suite lines")
      (let [(e (optionOr (listHead entries) (rl/makeLedgerEntry "" "" "" "")))]
        (do
          (assert (= e.suite "realTest.asl") "suite is realTest.asl")
          (assert (= e.digest "") "empty digest parsed")
          true))))

fn testParseLedgerPrefixMatch -> Bool
  (let [(text "  (:suite \"closingTest.asl\" :cause \"ERR_LOAD\" :failedAssertDigest \"d1\" :since \"s1\"))\n  (:suite \"notedTest.asl\" :cause \"ERR_RUNTIME\" :failedAssertDigest \"d2\" :since \"s2\") ; note\n  (:suite \"\" :cause \"ERR_LOAD\" :failedAssertDigest \"d3\" :since \"s3\")\n  (:suite \"brokenTest.asl\" :cause \"ERR_LOAD\" :failedAssertDigest \"d4\" :since \"s4\"\n")
        (entries (rl/parseLedger text))
        (first (optionOr (listHead entries) (rl/makeLedgerEntry "" "" "" "")))
        (second (optionOr (listLast entries) (rl/makeLedgerEntry "" "" "" "")))]
    (do
      (assert (= (listLength entries) 2) "entry ending )) and entry with trailing ; note both parse, empty suite and unclosed do not")
      (assert (= first.suite "closingTest.asl") "entry ending )) keeps its suite")
      (assert (= first.since "s1") "entry ending )) keeps its since")
      (assert (= second.suite "notedTest.asl") "entry with ; note keeps its suite")
      (assert (= second.digest "d2") "entry with ; note keeps its digest")
      true))

fn testDeltaEmpty -> Bool
  (let [(d (rl/delta (list) (list)))]
    (do
      (assert (= d "(:knownRedDelta)") "empty delta is (:knownRedDelta)")
      true))

fn testDeltaAdded -> Bool
  (let [(e1 (rl/makeLedgerEntry "suiteA.asl" "ERR_LOAD" "d1" "sha1"))
        (d (rl/delta (list) (list e1)))]
    (do
      (assert (= d "(:knownRedDelta (:added (:suite \"suiteA.asl\" :cause \"ERR_LOAD\" :confirmation :unverified)))") "delta added formatted correctly")
      true))

fn testDeltaRemoved -> Bool
  (let [(e1 (rl/makeLedgerEntry "suiteB.asl" "ERR_RUNTIME" "d2" "sha1"))
        (d (rl/delta (list e1) (list)))]
    (do
      (assert (= d "(:knownRedDelta (:removed (:suite \"suiteB.asl\" :cause \"ERR_RUNTIME\")))") "delta removed formatted correctly")
      true))

fn testDeltaBoth -> Bool
  (let [(e1 (rl/makeLedgerEntry "suiteOld.asl" "ERR_RUNTIME" "d1" "sha1"))
        (e2 (rl/makeLedgerEntry "suiteNew.asl" "ERR_LOAD" "d2" "sha2"))
        (d (rl/delta (list e1) (list e2)))]
    (do
      (assert (= d "(:knownRedDelta (:added (:suite \"suiteNew.asl\" :cause \"ERR_LOAD\" :confirmation :unverified)) (:removed (:suite \"suiteOld.asl\" :cause \"ERR_RUNTIME\")))") "delta both added and removed")
      true))

fn testReconcileStalePassed! -> Bool
  (let [(entry (rl/makeLedgerEntry "passTest.asl" "ERR_LOAD" "d1" "sha1"))
        (res (sr/makeSuiteResult "passTest.asl" "OK" "" "" 5 0 5 0))
        (rec (rl/reconcile! (list res) (list entry) ""))]
    (do
      (assert (= rec.held 0) "held is 0")
      (assert (= (listLength rec.checks) 1) "one check produced")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_STALE_KNOWN_RED") "err is ERR_STALE_KNOWN_RED")
          (assert (= c.suite "passTest.asl") "suite is passTest.asl")
          (assert (= c.ev "listed in knownRed but passed") "ev matches")
          true))))

fn testReconcileHeld! -> Bool
  (let [(entry (rl/makeLedgerEntry "failTest.asl" "ERR_LOAD" "d1" "sha1"))
        (res (sr/makeSuiteResult "failTest.asl" "ERR_LOAD" "d1" "err line" 0 0 0 1))
        (rec (rl/reconcile! (list res) (list entry) ""))]
    (do
      (assert (= rec.held 1) "held is 1")
      (assert (= (listLength rec.checks) 0) "no check produced when held")
      true))

fn testReconcileNewRed! -> Bool
  (let [(res (sr/makeSuiteResult "newFailTest.asl" "ASSERTION_FAILURE" "d9" "assert 1 == 2" 1 0 2 1))
        (rec (rl/reconcile! (list res) (list) ""))]
    (do
      (assert (= rec.held 0) "held is 0")
      (assert (= (listLength rec.checks) 1) "one check produced for new red")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_NEW_RED_SUITE") "err is ERR_NEW_RED_SUITE")
          (assert (= c.suite "newFailTest.asl") "suite is newFailTest.asl")
          (assert (= c.ev "ASSERTION_FAILURE d9 assert 1 == 2") "ev is signature")
          true))))

fn testReconcileDrift! -> Bool
  (let [(entry (rl/makeLedgerEntry "driftTest.asl" "ERR_UNKNOWN_SYMBOL" "oldDigest" "sha1"))
        (res (sr/makeSuiteResult "driftTest.asl" "ASSERTION_FAILURE" "newDigest" "assert fail" 2 0 3 1))
        (rec (rl/reconcile! (list res) (list entry) ""))]
    (do
      (assert (= rec.held 0) "held is 0")
      (assert (= (listLength rec.checks) 1) "one check produced for drift")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_KNOWN_RED_DRIFT") "err is ERR_KNOWN_RED_DRIFT")
          (assert (= c.suite "driftTest.asl") "suite is driftTest.asl")
          (assert (= c.ev "ASSERTION_FAILURE newDigest assert fail (knownRed signature differs)") "ev has signature differs")
          true))))

fn testReconcileDeclaredGap! -> Bool
  (let [(res (sr/makeSuiteResult "gapTest.asl" "ERR_DECLARED_GAP" "digGap" "gap=3" 2 0 5 1))
        (rec (rl/reconcile! (list res) (list) ""))]
    (do
      (assert (= (listLength rec.checks) 1) "one check for declared gap")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_DECLARED_GAP") "err is ERR_DECLARED_GAP")
          (assert (= c.ev "ERR_DECLARED_GAP digGap gap=3") "ev for declared gap")
          true))))

fn testReconcileVacuous! -> Bool
  (let [(res (sr/makeSuiteResult "vacTest.asl" "ERR_VACUOUS_SUITE" "digVac" "no gate line" 0 0 0 1))
        (rec (rl/reconcile! (list res) (list) ""))]
    (do
      (assert (= (listLength rec.checks) 1) "one check for vacuous suite")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_VACUOUS_SUITE") "err is ERR_VACUOUS_SUITE")
          (assert (= c.ev "ERR_VACUOUS_SUITE digVac no gate line") "ev for vacuous suite")
          true))))

fn testReconcileTimeout! -> Bool
  (let [(res (sr/makeSuiteResult "timeTest.asl" "ERR_TIMEOUT" "digTime" "timeout" 0 0 0 1))
        (rec (rl/reconcile! (list res) (list) ""))]
    (do
      (assert (= (listLength rec.checks) 1) "one check for timeout suite")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_TIMEOUT") "err is ERR_TIMEOUT")
          (assert (= c.ev "ERR_TIMEOUT digTime timeout") "ev for timeout suite")
          true))))

fn testReconcileMissingFile! -> Bool
  (let [(entry (rl/makeLedgerEntry "nonexistent/missingTest.asl" "ERR_LOAD" "d1" "sha1"))
        (rec (rl/reconcile! (list) (list entry) ""))]
    (do
      (assert (= rec.notEvaluated 0) "notEvaluated is 0 when missing")
      (assert (= (listLength rec.checks) 1) "one check for missing file")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_STALE_KNOWN_RED") "err is ERR_STALE_KNOWN_RED")
          (assert (= c.ev "knownRed entry names no suite file") "ev names missing suite file")
          true))))

fn testReconcileTreeDirtied! -> Bool
  (let [(res (sr/makeSuiteResult "dirtyTest.asl" "ERR_TREE_DIRTIED" "" "suite wrote foo" 0 0 0 1))
        (rec (rl/reconcile! (list res) (list) ""))]
    (do
      (assert (= (listLength rec.checks) 1) "one check for tree dirtied")
      (let [(c (optionOr (listHead rec.checks) (rl/makeReconcileCheck "" "" "")))]
        (do
          (assert (= c.err "ERR_NEW_RED_SUITE") "reconcile has no tree-dirtied class; runner.py reports dirt per snapshot")
          (assert (= c.suite "dirtyTest.asl") "suite matches")
          (assert (= c.ev "ERR_TREE_DIRTIED  suite wrote foo") "ev is the plain signature")
          true))))

fn excludedHere! -> String
  (mt (sr/getExcludedForm ".") ((ok x) x) ((err e) (do (assert false (str "excluded form: " e)) "")))

fn testReceiptFormatting! -> Bool
  (let [(r1 (sr/makeSuiteResult "suite1.asl" "OK" "" "" 10 0 10 0))
        (chk (rl/makeReconcileCheck "ERR_NEW_RED_SUITE" "suite2.asl" "bad \"test\""))
        (res (rl/receipt (list r1) (list chk) 0 0 "(:knownRedDelta)" (excludedHere!) ":affected" 0))
        (text (pairFirst res))
        (passed (pairSecond res))]
    (do
      (assert (not passed) "receipt passed is false when checks present")
      (assert (stringStartsWith? text "(:runner :status :failed :scope :affected :suites 1 :passedSuites 1 :knownRedHeld 0 :notEvaluated 0 :executedAsserts 10 :executedRefutes 0 :declaredAsserts 10") "receipt header matches")
      (assert (stringContains? text "(:check :id suite :status :failed :err ERR_NEW_RED_SUITE :suite \"suite2.asl\" :ev \"bad \\\"test\\\"\")") "escaped check line matches")
      (assert (stringContains? text "(:knownRedDelta)") "knownRedDelta included")
      (assert (stringEndsWith? text ")") "closes with parenthesis")
      true))

fn indexIn text: String needle: String -> Int64
  (optionOr (stringIndexOf text needle) -1)

fn testReceiptOrderAndExcluded! -> Bool
  (let [(r1 (sr/makeSuiteResult "zeta.asl" "ASSERTION_FAILURE" "d1" "f1" 1 0 1 1))
        (chkA (rl/makeReconcileCheck "ERR_NEW_RED_SUITE" "zeta.asl" "first"))
        (chkB (rl/makeReconcileCheck "ERR_STALE_KNOWN_RED" "alpha.asl" "second"))
        (text (pairFirst (rl/receipt (list r1) (list chkA chkB) 0 0 "(:knownRedDelta)" (excludedHere!) ":affected" 0)))
        (iA (indexIn text ":suite \"zeta.asl\" :ev \"first\""))
        (iB (indexIn text ":suite \"alpha.asl\" :ev \"second\""))
        (iDelta (indexIn text "(:knownRedDelta)"))
        (iExcluded (indexIn text "(:excluded (:class drivers :n "))
        (iNonHermetic (indexIn text "(:class nonHermetic :n "))
        (iTrust (indexIn text "(:trust (:asl :evaluator \"asl/host/out/asl-host\""))]
    (do
      (assert (>= iA 0) "first check present")
      (assert (> iB iA) "checks keep their given order, not sorted by suite")
      (assert (> iDelta iB) "delta follows the checks")
      (assert (> iExcluded iDelta) "excluded form follows the delta")
      (assert (> iNonHermetic iExcluded) "excluded form carries the nonHermetic class")
      (assert (> iTrust iNonHermetic) "trust form closes the excluded part")
      (assert (stringEndsWith? text "zero executed assertions is red\")))") "receipt ends with the trust form and its closing paren")
      true))

fn testReconcileCheckOrder! -> Bool
  (let [(rNew (sr/makeSuiteResult "zNewTest.asl" "ASSERTION_FAILURE" "d9" "boom" 1 0 1 1))
        (rStale (sr/makeSuiteResult "aStaleTest.asl" "OK" "" "" 3 0 3 0))
        (eStale (rl/makeLedgerEntry "aStaleTest.asl" "ERR_LOAD" "d1" "s"))
        (eGone (rl/makeLedgerEntry "gone/missingTest.asl" "ERR_LOAD" "d2" "s"))
        (eGone2 (rl/makeLedgerEntry "gone/absentTest.asl" "ERR_LOAD" "d3" "s"))
        (rec (rl/reconcile! (list rNew rStale) (list eGone eStale eGone2) ""))
        (suites (map (fn [(c rl/ReconcileCheck)] -> String c.suite) rec.checks))]
    (do
      (assert (= suites (list "zNewTest.asl" "aStaleTest.asl" "gone/missingTest.asl" "gone/absentTest.asl"))
              "result checks in result order, then ledger checks in ledger order")
      true))

fn ! runTests -> Bool
  (do
    (assert (testParseLedgerEmpty) "parseLedger empty")
    (assert (testParseLedgerValid) "parseLedger valid")
    (assert (testParseLedgerIgnoresNonSuites) "parseLedger ignores non-suites")
    (assert (testParseLedgerPrefixMatch) "parseLedger matches by prefix")
    (assert (testDeltaEmpty) "delta empty")
    (assert (testDeltaAdded) "delta added")
    (assert (testDeltaRemoved) "delta removed")
    (assert (testDeltaBoth) "delta both")
    (assert (testReconcileStalePassed!) "reconcile stale passed")
    (assert (testReconcileHeld!) "reconcile held")
    (assert (testReconcileNewRed!) "reconcile new red")
    (assert (testReconcileDrift!) "reconcile drift")
    (assert (testReconcileDeclaredGap!) "reconcile declared gap")
    (assert (testReconcileVacuous!) "reconcile vacuous")
    (assert (testReconcileTimeout!) "reconcile timeout")
    (assert (testReconcileMissingFile!) "reconcile missing file")
    (assert (testReconcileTreeDirtied!) "reconcile tree dirtied")
    (assert (testReceiptFormatting!) "receipt formatting")
    (assert (testReceiptOrderAndExcluded!) "receipt order and excluded form")
    (assert (testReconcileCheckOrder!) "reconcile check order")
    true)
