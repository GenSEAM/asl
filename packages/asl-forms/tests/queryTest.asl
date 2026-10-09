(module asl-forms/tests/queryTest
  :x [runTests]
  :i [(asl-forms/query :a q)
      (asl-forms/repair :a rep)
      (asl-syntax/core/source :a src)])

fn testQueryParse -> Bool
  (let [(q1 (q/queryCompile "(list @target (keyword \":id\") (string) @id)"))
        (q2 (q/queryCompile "(:query :kind \"list\" :as \"@target\" :children [(:pattern :kind \"keyword\" :text \":id\") (:pattern :kind \"string\" :as \"@id\")])"))]
    (do
      (assert (= (q/patternKind q1) "list") "q1 kind is list")
      (assert (= (q/patternCapture q1) "@target") "q1 capture is @target")
      (assert (= (listLength (q/patternChildren q1)) 2) "q1 has 2 children")
      (assert (= (q/patternKind q2) "list") "q2 kind is list")
      (assert (= (q/patternCapture q2) "@target") "q2 capture is @target")
      (assert (= (listLength (q/patternChildren q2)) 2) "q2 has 2 children")
      true))

fn testCapturesHandCheckedFixtures -> Bool
  (let [(asnText "(:plan :id \"testPlan\"\n  (:unit :id \"U1\" :dependsOn ())\n  (:unit :id \"U2\" :dependsOn (U1)))\n")
        (matches (q/queryExecute "(list @target (keyword \":id\") (string) @id)" asnText "asn"))]
    (do
      (assert (= (listLength matches) 3) "matches count is 3")
      (let [(m1 (optionOr (listGet matches 0) (q/makeQueryMatch (q/queryPatternKindDummy) (list))))
            (m2 (optionOr (listGet matches 1) (q/makeQueryMatch (q/queryPatternKindDummy) (list))))
            (m3 (optionOr (listGet matches 2) (q/makeQueryMatch (q/queryPatternKindDummy) (list))))
            (c1 (optionOr (q/queryCaptureGet m1 "@id") (q/makeQueryCapture "" "" "" 0 0 0 0)))
            (c2 (optionOr (q/queryCaptureGet m2 "@id") (q/makeQueryCapture "" "" "" 0 0 0 0)))
            (c3 (optionOr (q/queryCaptureGet m3 "@id") (q/makeQueryCapture "" "" "" 0 0 0 0)))]
        (do
          (assert (= (q/captureValue c1) "testPlan") "first match capture value is testPlan")
          (assert (= (q/captureLine c1) 1) "first match line is 1")
          (assert (= (q/captureValue c2) "U1") "second match capture value is U1")
          (assert (= (q/captureLine c2) 2) "second match line is 2")
          (assert (= (q/captureValue c3) "U2") "third match capture value is U2")
          (assert (= (q/captureLine c3) 3) "third match line is 3")
          true))))

fn testCapturesAslFixture -> Bool
  (let [(aslText "(module test/mod :x [foo])\n\nfn foo a: Int64 -> Int64\n  (+ a 1)\n")
        (matches (q/queryExecute "(header (keyword \"fn\") (symbol) @name)" aslText "asl"))
        (effText "(module test/mod :x [bar])\n\nfn ! bar a: Int64 -> Int64\n  (+ a 1)\n")
        (effMatches (q/queryExecute "(header (keyword \"fn\") (symbol \"!\")? (symbol) @name)" effText "asl"))]
    (do
      (assert (= (listLength matches) 1) "asl fn match count is 1")
      (let [(m1 (optionOr (listHead matches) (q/makeQueryMatch (q/queryPatternKindDummy) (list))))
            (c1 (optionOr (q/queryCaptureGet m1 "@name") (q/makeQueryCapture "" "" "" 0 0 0 0)))]
        (do
          (assert (= (q/captureValue c1) "foo") "asl capture value is foo")
          (assert (= (q/captureLine c1) 3) "asl fn line is 3")
          true))
      (assert (= (listLength effMatches) 1) "effectful fn match count is 1")
      (let [(mEff (optionOr (listHead effMatches) (q/makeQueryMatch (q/queryPatternKindDummy) (list))))
            (cEff (optionOr (q/queryCaptureGet mEff "@name") (q/makeQueryCapture "" "" "" 0 0 0 0)))]
        (do
          (assert (= (q/captureValue cEff) "bar") "effectful capture value is bar")
          (assert (= (q/captureLine cEff) 3) "effectful fn line is 3")
          true))))

fn testSemverValidation -> Bool
  (do
    (assert (q/validateSemver "1.0.0") "valid 1.0.0")
    (assert (q/validateSemver "0.1.0") "valid 0.1.0")
    (assert (q/validateSemver "2.1.3") "valid 2.1.3")
    (assert (q/validateSemver "1.0.0-alpha") "valid 1.0.0-alpha")
    (assert (q/validateSemver "1.0.0-alpha.1") "valid 1.0.0-alpha.1")
    (assert (q/validateSemver "1.0.0-0.3.7") "valid 1.0.0-0.3.7")
    (assert (q/validateSemver "1.0.0+20130313144700") "valid 1.0.0+build")
    (assert (q/validateSemver "1.0.0-beta+exp.sha.5114f85") "valid 1.0.0-beta+build")
    (assert (not (q/validateSemver "1.0")) "invalid 1.0 missing patch")
    (assert (not (q/validateSemver "1")) "invalid 1 missing minor and patch")
    (assert (not (q/validateSemver "01.1.1")) "invalid leading zero in major")
    (assert (not (q/validateSemver "1.02.1")) "invalid leading zero in minor")
    (assert (not (q/validateSemver "1.1.03")) "invalid leading zero in patch")
    (assert (not (q/validateSemver "1.2.3-")) "invalid trailing hyphen")
    (assert (not (q/validateSemver "v1.2.3")) "invalid leading v")
    (assert (not (q/validateSemver "")) "invalid empty semver")
    (assert (not (q/validateSemver "1.2.3.4")) "invalid 4-part semver")
    true)

fn testCronValidation -> Bool
  (do
    (assert (q/validateCron "* * * * *") "valid * * * * *")
    (assert (q/validateCron "*/5 * * * *") "valid */5 * * * *")
    (assert (q/validateCron "0 12 * * 1-5") "valid 0 12 * * 1-5")
    (assert (q/validateCron "0 0 1,15 * *") "valid 0 0 1,15 * *")
    (assert (q/validateCron "30 4 1,15 * 5") "valid 30 4 1,15 * 5")
    (assert (q/validateCron "0 0 * * 0") "valid 0 0 * * 0")
    (assert (q/validateCron "59 23 31 12 7") "valid 59 23 31 12 7")
    (assert (not (q/validateCron "* * * *")) "invalid only 4 fields")
    (assert (not (q/validateCron "* * * * * *")) "invalid 6 fields")
    (assert (not (q/validateCron "60 * * * *")) "invalid minute 60")
    (assert (not (q/validateCron "* 24 * * *")) "invalid hour 24")
    (assert (not (q/validateCron "* * 32 * *")) "invalid dom 32")
    (assert (not (q/validateCron "* * * 13 *")) "invalid month 13")
    (assert (not (q/validateCron "* * * * 8")) "invalid dow 8")
    (assert (not (q/validateCron "*/0 * * * *")) "invalid step 0")
    (assert (not (q/validateCron "5-2 * * * *")) "invalid inverted range")
    (assert (not (q/validateCron "bad cron")) "invalid bad cron")
    (assert (not (q/validateCron "abc * * * *")) "invalid non-numeric token in 5-part cron")
    (assert (not (q/validateCron "")) "invalid empty cron")
    true)

fn testLintUnboundReferences -> Bool
  (let [(cleanPath "inline clean plan")
        (cleanContent "(:plan :id \"cleanPlan\"\n  (:unit :id \"A\" :dependsOn ())\n  (:unit :id \"B\" :dependsOn (A))\n  (:unit :id \"C\" :dependsOn (A B)))\n")
        (cleanItems (q/lintUnboundReferences cleanContent "asn"))
        (seededText "(:plan :id \"testPlan\"\n  (:unit :id \"U1\" :dependsOn ())\n  (:unit :id \"U2\" :dependsOn (GhostUnit999)))\n")
        (seededItems (q/lintUnboundReferences seededText "asn"))]
    (do
      (assert (not (stringEmpty? cleanContent)) (str "read clean file " cleanPath))
      (assert (= (listLength cleanItems) 0) "clean inline plan has zero unbound references")
      (assert (= (listLength seededItems) 1) "seeded defect produces 1 unbound reference")
      (let [(item (optionOr (listHead seededItems) (rep/makeLeftItem 0 0 "" "")))]
        (do
          (assert (= (rep/leftItemLine item) 3) "seeded item line is 3")
          (assert (stringContains? (rep/leftItemExpected item) "unbound reference 'GhostUnit999'") "item expected mentions GhostUnit999")
          true))))

fn testLintDuplicateDefinitions -> Bool
  (let [(cleanPath "inline clean plan")
        (cleanContent "(:plan :id \"cleanPlan\"\n  (:unit :id \"A\" :dependsOn ())\n  (:unit :id \"B\" :dependsOn (A))\n  (:unit :id \"C\" :dependsOn (A B)))\n")
        (cleanItems (q/lintDuplicateDefinitions cleanContent "asn"))
        (seededAsn "(:plan :id \"testPlan\"\n  (:unit :id \"DupUnit\" :dependsOn ())\n  (:unit :id \"DupUnit\" :dependsOn ()))\n")
        (seededAsnItems (q/lintDuplicateDefinitions seededAsn "asn"))
        (seededAsl "(module test/mod :x [dupFn])\n\nfn dupFn -> Bool\n  true\n\nfn dupFn -> Bool\n  false\n")
        (seededAslItems (q/lintDuplicateDefinitions seededAsl "asl"))
        (effectfulAsl "(module test/mod :x [a b])\n\nfn ! a -> Bool\n  true\n\nfn ! b -> Bool\n  false\n")
        (effectfulItems (q/lintDuplicateDefinitions effectfulAsl "asl"))]
    (do
      (assert (= (listLength cleanItems) 0) "clean plan.asn has zero duplicate definitions")
      (assert (= (listLength seededAsnItems) 1) "seeded duplicate asn unit produces 1 item")
      (let [(item (optionOr (listHead seededAsnItems) (rep/makeLeftItem 0 0 "" "")))]
        (do
          (assert (= (rep/leftItemLine item) 3) "seeded asn dup line is 3")
          (assert (stringContains? (rep/leftItemExpected item) "duplicate definition 'DupUnit'") "asn expected mentions DupUnit")
          true))
      (assert (= (listLength seededAslItems) 1) "seeded duplicate asl fn produces 1 item")
      (let [(aslItem (optionOr (listHead seededAslItems) (rep/makeLeftItem 0 0 "" "")))]
        (do
          (assert (= (rep/leftItemLine aslItem) 6) "seeded asl dup line is 6")
          (assert (stringContains? (rep/leftItemExpected aslItem) "duplicate definition 'dupFn'") "asl expected mentions dupFn")
          true))
      (assert (= (listLength effectfulItems) 0) "two effectful fns are not flagged as duplicates")
      true))

fn testLintValueFormatSemver! -> Bool
  (let [(cleanPath "asl/packages/asl-forms/manifest.asn")
        (cleanContent (resultOr (fileReadString cleanPath) ""))
        (cleanItems (q/lintValueFormatSemver cleanContent "asn"))
        (seededText "(:pkg :id \"badPkg\" :version \"1.0\")\n")
        (seededItems (q/lintValueFormatSemver seededText "asn"))]
    (do
      (assert (not (stringEmpty? cleanContent)) (str "read clean manifest " cleanPath))
      (assert (= (listLength cleanItems) 0) "manifest.asn has zero semver errors")
      (assert (= (listLength seededItems) 1) "seeded invalid semver produces 1 item")
      (let [(item (optionOr (listHead seededItems) (rep/makeLeftItem 0 0 "" "")))]
        (do
          (assert (= (rep/leftItemLine item) 1) "seeded semver line is 1")
          (assert (stringContains? (rep/leftItemExpected item) "invalid semver format '1.0'") "item expected mentions invalid semver")
          true))))

fn testLintValueFormatCron -> Bool
  (let [(cleanText "(:job :id \"backup\" :cron \"*/15 0-23 * * 1-5\")\n")
        (cleanItems (q/lintValueFormatCron cleanText "asn"))
        (seededText "(:job :id \"backup\" :cron \"99 * * * *\")\n")
        (seededItems (q/lintValueFormatCron seededText "asn"))]
    (do
      (assert (= (listLength cleanItems) 0) "valid cron fixture has zero errors")
      (assert (= (listLength seededItems) 1) "seeded invalid cron produces 1 item")
      (let [(item (optionOr (listHead seededItems) (rep/makeLeftItem 0 0 "" "")))]
        (do
          (assert (= (rep/leftItemLine item) 1) "seeded cron line is 1")
          (assert (stringContains? (rep/leftItemExpected item) "invalid cron expression '99 * * * *'") "item expected mentions invalid cron")
          true))))

fn testLintReceiptFormat -> Bool
  (let [(cleanReceipt (q/lintReceipt "(:plan :id \"testPlan\")" "asn"))
        (seededText "(:pkg :version \"1.0\")")
        (defectReceipt (q/lintReceipt seededText "asn"))
        (multiDefects "(:pkg :version \"1\")\n(:pkg :version \"2\")\n(:pkg :version \"3\")\n(:pkg :version \"4\")\n(:pkg :version \"5\")\n(:pkg :version \"6\")\n")
        (cappedReceipt (q/lintReceipt multiDefects "asn"))]
    (do
      (assert (= cleanReceipt "(:left ())") "clean receipt is (:left ())")
      (assert (stringContains? defectReceipt "(:left ((:line 1 :col 16 :expected \"invalid semver format '1.0'\"") "defect receipt matches G2 left shape")
      (assert (stringContains? cappedReceipt ":more 1") "receipt with 6 items caps at 5 with :more 1")
      true))

fn ! runTests -> Bool
  (do
    (assert (testQueryParse) "testQueryParse")
    (assert (testCapturesHandCheckedFixtures) "testCapturesHandCheckedFixtures")
    (assert (testCapturesAslFixture) "testCapturesAslFixture")
    (assert (testSemverValidation) "testSemverValidation")
    (assert (testCronValidation) "testCronValidation")
    (assert (testLintUnboundReferences) "testLintUnboundReferences")
    (assert (testLintDuplicateDefinitions) "testLintDuplicateDefinitions")
    (assert (testLintValueFormatSemver!) "testLintValueFormatSemver")
    (assert (testLintValueFormatCron) "testLintValueFormatCron")
    (assert (testLintReceiptFormat) "testLintReceiptFormat")
    true)
