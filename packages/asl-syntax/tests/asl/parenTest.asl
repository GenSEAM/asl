(module asl-syntax/tests/asl/parenTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/asl/paren :a prn)
      (tools/fleet/run :a run)])

fn testParseUnclosedParen -> Bool
  (let [(s1 "(foo (bar 1 2)")
        (r1 (prn/parse s1))
        (l1 (stringLength s1))
        (s2 "(")
        (r2 (prn/parse s2))
        (l2 (stringLength s2))
        (s3 "(a [b {c")
        (r3 (prn/parse s3))
        (l3 (stringLength s3))]
    (assert (prn/hasErrors r1) "unclosed paren has errors")
    (assert (ok? (tr/checkTiling r1 l1)) "unclosed paren tiles cleanly")
    (assert (= (pr/print s1 r1) s1) "unclosed paren leaf print matches source")
    (assert (prn/hasErrors r2) "lone open paren has errors")
    (assert (ok? (tr/checkTiling r2 l2)) "lone open paren tiles cleanly")
    (assert (= (pr/print s2 r2) s2) "lone open paren print matches")
    (assert (prn/hasErrors r3) "multiple unclosed delimiters have errors")
    (assert (ok? (tr/checkTiling r3 l3)) "multiple unclosed delimiters tile cleanly")
    (assert (= (pr/print s3 r3) s3) "multiple unclosed delimiters print matches")
    true)

fn testParseStrayClose -> Bool
  (let [(s1 "foo ) bar")
        (r1 (prn/parse s1))
        (l1 (stringLength s1))
        (s2 ")")
        (r2 (prn/parse s2))
        (l2 (stringLength s2))
        (s3 "[1 2 3)")
        (r3 (prn/parse s3))
        (l3 (stringLength s3))
        (s4 "( [ 1 ) 2 ]")
        (r4 (prn/parse s4))
        (l4 (stringLength s4))]
    (assert (prn/hasErrors r1) "stray close paren has errors")
    (assert (ok? (tr/checkTiling r1 l1)) "stray close paren tiles cleanly")
    (assert (= (pr/print s1 r1) s1) "stray close paren print matches")
    (let [(c1 r1.children)]
      (assert (= (listLength c1) 5) "r1 has 5 children")
      (mt (listGet c1 2)
        ((some elem1)
         (mt elem1
           ((tr/elemNode e1)
            (do
              (assert (= e1.kind "error") "r1 stray paren is error node")
              (assert (= e1.start 4) "r1 stray paren start is 4")
              (assert (= e1.end 5) "r1 stray paren end is 5")))
           ((tr/elemToken _) (assert false "r1 child 2 is not elemNode"))))
        ((none) (assert false "r1 missing child 2"))))
    (assert (prn/hasErrors r2) "lone close paren has errors")
    (assert (ok? (tr/checkTiling r2 l2)) "lone close paren tiles cleanly")
    (assert (= (pr/print s2 r2) s2) "lone close paren print matches")
    (let [(c2 r2.children)]
      (assert (= (listLength c2) 1) "r2 has 1 child")
      (mt (listHead c2)
        ((some elem2)
         (mt elem2
           ((tr/elemNode e2)
            (do
              (assert (= e2.kind "error") "r2 stray paren is error node")
              (assert (= e2.start 0) "r2 stray paren start is 0")
              (assert (= e2.end 1) "r2 stray paren end is 1")))
           ((tr/elemToken _) (assert false "r2 child 0 is not elemNode"))))
        ((none) (assert false "r2 missing child 0"))))
    (assert (prn/hasErrors r3) "mismatched close delimiter has errors")
    (assert (ok? (tr/checkTiling r3 l3)) "mismatched close delimiter tiles cleanly")
    (assert (= (pr/print s3 r3) s3) "mismatched close delimiter print matches")
    (let [(c3 r3.children)]
      (assert (= (listLength c3) 1) "r3 has 1 child")
      (mt (listHead c3)
        ((some elem3)
         (mt elem3
           ((tr/elemNode e3)
            (do
              (assert (= e3.kind "error") "r3 unclosed bracket is error node")
              (assert (= e3.start 0) "r3 error node start is 0")
              (assert (= e3.end 7) "r3 error node end is 7")
              (let [(e3Kids e3.children)]
                (assert (= (listLength e3Kids) 7) "r3 error node has 7 kids")
                (mt (listGet e3Kids 6)
                  ((some elem3Close)
                   (mt elem3Close
                     ((tr/elemNode strayClose3)
                      (do
                        (assert (= strayClose3.kind "error") "r3 stray close paren is error node")
                        (assert (= strayClose3.start 6) "r3 stray close paren start is 6")
                        (assert (= strayClose3.end 7) "r3 stray close paren end is 7")))
                     ((tr/elemToken _) (assert false "r3 child 6 is not elemNode"))))
                  ((none) (assert false "r3 missing child 6"))))))
           ((tr/elemToken _) (assert false "r3 child 0 is not elemNode"))))
        ((none) (assert false "r3 missing child 0"))))
    (assert (prn/hasErrors r4) "nested mismatched close has errors")
    (assert (ok? (tr/checkTiling r4 l4)) "nested mismatched close tiles cleanly")
    (assert (= (pr/print s4 r4) s4) "nested mismatched close print matches")
    (let [(c4 r4.children)]
      (assert (= (listLength c4) 5) "r4 has 5 children")
      (mt (listHead c4)
        ((some elem4Head)
         (mt elem4Head
           ((tr/elemNode listNode)
            (do
              (assert (= listNode.kind "list") "r4 parent structure around error is list")
              (assert (= listNode.start 0) "r4 list start is 0")
              (assert (= listNode.end 7) "r4 list end is 7")
              (let [(lKids listNode.children)]
                (assert (= (listLength lKids) 4) "r4 list has 4 elements")
                (mt (listGet lKids 2)
                  ((some errElem)
                   (mt errElem
                     ((tr/elemNode errNode)
                      (do
                        (assert (= errNode.kind "error") "r4 nested unclosed [ is error node")
                        (assert (= errNode.start 2) "r4 nested error node start is 2")
                        (assert (= errNode.end 6) "r4 nested error node end is 6")))
                     ((tr/elemToken _) (assert false "r4 child 2 of list is not elemNode"))))
                  ((none) (assert false "r4 missing child 2 of list"))))))
           ((tr/elemToken _) (assert false "r4 child 0 is not elemNode"))))
        ((none) (assert false "r4 missing child 0")))
      (mt (listGet c4 4)
        ((some elem4Tail)
         (mt elem4Tail
           ((tr/elemNode strayNode)
            (do
              (assert (= strayNode.kind "error") "r4 stray close ] is error node")
              (assert (= strayNode.start 10) "r4 stray ] start is 10")
              (assert (= strayNode.end 11) "r4 stray ] end is 11")))
           ((tr/elemToken _) (assert false "r4 child 4 is not elemNode"))))
        ((none) (assert false "r4 missing child 4"))))
    true)

fn testParseUnterminatedStringParen -> Bool
  (let [(s1 "(foo \"bar)")
        (r1 (prn/parse s1))
        (l1 (stringLength s1))
        (s2 "\"unterminated")
        (r2 (prn/parse s2))
        (l2 (stringLength s2))
        (s3 "(x \"bad \\x1z hex\")")
        (r3 (prn/parse s3))
        (l3 (stringLength s3))]
    (assert (prn/hasErrors r1) "unterminated string inside paren has errors")
    (assert (ok? (tr/checkTiling r1 l1)) "unterminated string inside paren tiles cleanly")
    (assert (= (pr/print s1 r1) s1) "unterminated string inside paren print matches")
    (assert (prn/hasErrors r2) "unterminated string at top level has errors")
    (assert (ok? (tr/checkTiling r2 l2)) "unterminated string at top level tiles cleanly")
    (assert (= (pr/print s2 r2) s2) "unterminated string at top level print matches")
    (assert (prn/hasErrors r3) "bad hex escape has errors")
    (assert (ok? (tr/checkTiling r3 l3)) "bad hex escape tiles cleanly")
    (assert (= (pr/print s3 r3) s3) "bad hex escape print matches")
    true)

fn testValidParenStructures -> Bool
  (let [(sEmpty "")
        (rEmpty (prn/parse sEmpty))
        (sList "(a b c)")
        (rList (prn/parse sList))
        (sVec "[1 2 3]")
        (rVec (prn/parse sVec))
        (sMap "{:a 1 :b 2}")
        (rMap (prn/parse sMap))
        (sNested "(defn foo [x] {:val (+ x 1)})")
        (rNested (prn/parse sNested))
        (sMulti "(form1)\n(form2)\n(form3)\n")
        (srcMulti (src/sourceFromString "multi.asl" sMulti))
        (rMulti (prn/parseSource srcMulti))]
    (assert (not (prn/hasErrors rEmpty)) "empty string has no errors")
    (assert (= (prn/topLevelFormCount rEmpty) 0) "empty string has 0 top forms")
    (assert (ok? (tr/checkTiling rEmpty 0)) "empty string tiles cleanly")
    (assert (= (pr/print sEmpty rEmpty) sEmpty) "empty print matches")
    (assert (not (prn/hasErrors rList)) "valid list has no errors")
    (assert (= (prn/topLevelFormCount rList) 1) "valid list has 1 top form")
    (assert (ok? (tr/checkTiling rList (stringLength sList))) "valid list tiles cleanly")
    (assert (= (pr/print sList rList) sList) "valid list print matches")
    (assert (not (prn/hasErrors rVec)) "valid vec has no errors")
    (assert (= (prn/topLevelFormCount rVec) 1) "valid vec has 1 top form")
    (assert (ok? (tr/checkTiling rVec (stringLength sVec))) "valid vec tiles cleanly")
    (assert (= (pr/print sVec rVec) sVec) "valid vec print matches")
    (assert (not (prn/hasErrors rMap)) "valid map has no errors")
    (assert (= (prn/topLevelFormCount rMap) 1) "valid map has 1 top form")
    (assert (ok? (tr/checkTiling rMap (stringLength sMap))) "valid map tiles cleanly")
    (assert (= (pr/print sMap rMap) sMap) "valid map print matches")
    (assert (not (prn/hasErrors rNested)) "valid nested structure has no errors")
    (assert (= (prn/topLevelFormCount rNested) 1) "valid nested structure has 1 top form")
    (assert (ok? (tr/checkTiling rNested (stringLength sNested))) "valid nested structure tiles cleanly")
    (assert (= (pr/print sNested rNested) sNested) "valid nested structure print matches")
    (assert (not (prn/hasErrors rMulti)) "multi form has no errors")
    (assert (= (prn/countTopLevelForms srcMulti rMulti) 3) "multi form has 3 col0 forms")
    (assert (= (prn/topLevelFormCount rMulti) 3) "multi form has 3 top forms")
    (assert (ok? (tr/checkTiling rMulti (stringLength sMulti))) "multi form tiles cleanly")
    (assert (= (pr/print sMulti rMulti) sMulti) "multi form print matches")
    true)

fn verifyFixtureFile! path: String expectedValid: Bool expectedTopForms: Int64 -> Bool
  (mt (fileReadBytes path)
    ((err ioErr)
     (do
       (assert false (str "cannot read fixture: " path " (" ioErr ")"))
       false))
    ((ok bs)
     (let [(len (bytesLength bs))
           (src (src/sourceFromBytes path bs))
           (root (prn/parseBytes bs))
           (hasErr (prn/hasErrors root))
           (tilingRes (tr/checkTiling root len))
           (outBs (pr/printTreeBytes! bs root))]
       (assert (ok? tilingRes) (str "fixture tiles: " path))
       (assert (= outBs bs) (str "fixture leaf print exact: " path))
       (if expectedValid
         (do
           (assert (not hasErr) (str "expected valid fixture: " path))
           (if (>= expectedTopForms 0)
             (assert (= (prn/countTopLevelForms src root) expectedTopForms)
                     (str "top level count matches for: " path))
             ())
           true)
         (do
           (assert hasErr (str "expected invalid fixture: " path))
           true)))))

(schema CheckDirStats
  (:f agree Int64)
  (:f disagree Int64)
  (:f total Int64))

fn checkOneCorpusFile! acc: CheckDirStats path: String -> CheckDirStats
  (mt (fileReadBytes path)
    ((err e)
     (do
       (assert false (str "read error for " path ": " e))
       (with acc :disagree (+ acc.disagree 1) :total (+ acc.total 1))))
    ((ok bs)
     (let [(len (bytesLength bs))
           (root (prn/parseBytes bs))
           (hasErr (prn/hasErrors root))
           (tilingRes (tr/checkTiling root len))
           (outBs (pr/printTreeBytes! bs root))
           (cmd (str (run/legacyHost!) " check " path " >/dev/null 2>&1"))
           (cmdRes (processRun cmd))
           (hostReject (!= cmdRes.exitCode 0))
           (agree (= hasErr hostReject))]
       (do
         (assert (ok? tilingRes) (str "tiling check for " path))
         (assert (= outBs bs) (str "lossless print for " path))
         (if agree
           (with acc :agree (+ acc.agree 1) :total (+ acc.total 1))
           (with acc :disagree (+ acc.disagree 1) :total (+ acc.total 1)))))))

fn checkDirectoryAtRuntime! dir: String -> CheckDirStats
  (let [(cmd (str "find " dir " -type f | sort"))
        (res (processRun cmd))]
    (assert (= res.exitCode 0) (str "find succeeded for " dir))
    (let [(files (parseFileList res.stdout))]
      (fold checkOneCorpusFile! (CheckDirStats :agree 0 :disagree 0 :total 0) files)))

fn testDyckFixtures! -> Bool
  (let [(stats (checkDirectoryAtRuntime! "tests/fixtures/dyck"))]
    (assert (= stats.total 16) "dyck checked 16 files")
    (assert (= stats.agree 14) "dyck agree count is 14")
    (assert (= stats.disagree 2) "dyck disagree count is 2")
    (and (verifyFixtureFile! "tests/fixtures/dyck/valid/empty.asn" true 0)
    (and (verifyFixtureFile! "tests/fixtures/dyck/valid/escapedQuoteInString.asn" true 1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/valid/nested.asn" true 1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/valid/parenInComment.asn" true 1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/valid/parenInString.asn" true 1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/valid/semicolonInString.asn" true 1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/closeBeforeOpen.asn" false -1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/commentHidesClose.asn" false -1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/extraClose.asn" false -1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/extraOpen.asn" false -1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/semicolonIsRetired.asl" false -1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/strayBracket.asn" false -1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/stringHidesOpen.asn" false -1)
    (and (verifyFixtureFile! "tests/fixtures/dyck/invalid/unclosedBracket.asn" false -1)
         (verifyFixtureFile! "tests/fixtures/dyck/invalid/unterminatedString.asn" false -1))))))))))))))))

fn testAcceptanceAndGrammarInvalidFixtures! -> Bool
  (let [(sGrammar (checkDirectoryAtRuntime! "asl/grammar/corpus/invalid"))
        (sAsn (checkDirectoryAtRuntime! "asl/grammar/corpus/asn/invalid"))
        (sAccept (checkDirectoryAtRuntime! "tests/acceptance/r1Host/reader/invalid"))]
    (assert (= sGrammar.total 7) "corpus invalid checked 7 files")
    (assert (= sGrammar.agree 4) "corpus invalid agree count is 4")
    (assert (= sGrammar.disagree 3) "corpus invalid disagree count is 3")
    (assert (= sAsn.total 17) "corpus asn invalid checked 17 files")
    (assert (= sAsn.agree 7) "corpus asn invalid agree count is 7")
    (assert (= sAsn.disagree 10) "corpus asn invalid disagree count is 10")
    (assert (= sAccept.total 2) "reader invalid checked 2 files")
    (assert (= sAccept.agree 2) "reader invalid agree count is 2")
    (assert (= sAccept.disagree 0) "reader invalid disagree count is 0")
    true)

fn isInvalidFixturePath path: String -> Bool
  (or (stringContains? path "tests/fixtures/dyck/invalid/")
  (or (stringContains? path "tests/acceptance/r1Host/reader/invalid/")
  (or (= path "asl/grammar/corpus/asn/invalid/syntaxError.asn")
  (or (= path "asl/grammar/corpus/asn/invalid/unbalanced.asn")
  (or (= path "asl/grammar/corpus/invalid/unbalanced.asl")
      (= path "asl/grammar/corpus/invalid/defunListParams.asl"))))))

fn parseFileList stdout: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit stdout "\n"))

fn checkOneAsnFile! acc: (Pair Int64 Int64) path: String -> (Pair Int64 Int64)
  (let [(checked (pairFirst acc))
        (mismatches (pairSecond acc))]
    (mt (fileReadBytes path)
      ((err e)
       (do
         (assert false (str "read error for " path ": " e))
         (pair (+ checked 1) (+ mismatches 1))))
      ((ok bs)
       (let [(len (bytesLength bs))
             (src (src/sourceFromBytes path bs))
             (root (prn/parseBytes bs))
             (hasErr (prn/hasErrors root))
             (tilingRes (tr/checkTiling root len))
             (outBs (pr/printTreeBytes! bs root))
             (isInvalid (isInvalidFixturePath path))]
         (if (or (err? tilingRes)
             (or (!= outBs bs)
                 (if isInvalid (not hasErr) hasErr)))
           (pair (+ checked 1) (+ mismatches 1))
           (pair (+ checked 1) mismatches))))))

fn testTrackedAsnSweep! -> Bool
  (let [(cmdRes (processRun "git ls-files '*.asn'"))]
    (assert (= cmdRes.exitCode 0) "git ls-files asn exited 0")
    (let [(files (parseFileList cmdRes.stdout))
          (stats (fold checkOneAsnFile! (pair 0 0) files))
          (totalChecked (pairFirst stats))
          (mismatches (pairSecond stats))]
      (assert (> totalChecked 1350) "checked >1350 tracked asn files")
      (assert (= mismatches 0) "zero tiling, print or accept/reject mismatches across all tracked asn files")
      true))

fn checkParenAslFile! acc: (Pair Int64 Int64) path: String -> (Pair Int64 Int64)
  (let [(checked (pairFirst acc))
        (mismatches (pairSecond acc))]
    (mt (fileReadBytes path)
      ((err e)
       (do
         (assert false (str "read error for " path ": " e))
         (pair (+ checked 1) (+ mismatches 1))))
      ((ok bs)
       (let [(len (bytesLength bs))
             (src (src/sourceFromBytes path bs))
             (root (prn/parseBytes bs))
             (hasErr (prn/hasErrors root))
             (tilingRes (tr/checkTiling root len))
             (outBs (pr/printTreeBytes! bs root))
             (isInvalid (isInvalidFixturePath path))]
         (if (or (err? tilingRes)
             (or (!= outBs bs)
                 (if isInvalid (not hasErr) hasErr)))
           (pair (+ checked 1) (+ mismatches 1))
           (pair (+ checked 1) mismatches))))))

fn testTrackedParenAslFiles! -> Bool
  (let [(parenFiles (list "asl/packages/asl-agent/src/dispatch.asl"
                          "asl/packages/asl-agent/src/onion.asl"
                          "asl/packages/asl-agent/tests/fixtures/test-app/src/snake.asl"
                          "asl/packages/asl-agent/tests/fixtures/test-app/tests/snake-test.asl"
                          "asl/packages/asl-agent/tests/fixtures/test-app/tests/snakeTest.asl"
                          "asl/grammar/corpus/semantic/exportBareCase.asl"
                          "asl/packages/asl-checker/tests/fixtures/closureParity/ambiguousImporter.asl"
                          "asl/packages/asl-checker/tests/fixtures/closureParity/one/parityDup.asl"
                          "asl/packages/asl-checker/tests/fixtures/closureParity/symlinkImporter.asl"
                          "asl/packages/asl-checker/tests/fixtures/closureParity/two/parityDup.asl"
                          "asl/packages/asl-mesh/package.asl"
                          "asl/packages/asl-mesh/src/main.asl"
                          "asl/packages/asl-mesh/target.asl"
                          "asl/packages/asl-pack/tests/intermediatePolicyTest.asl"
                          "asl/packages/asl-plugin/src/types.asl"
                          "asl/packages/asl-replay/src/main.asl"
                          "asl/packages/asl-target-py/tests/fixtures/pointClass.asl"
                          "asl/packages/asl-ui/src/main.asl"
                          "asl/packages/asl-mem/src/tasks.asl"
                          "tests/acceptance/d81/Task58801IntermediatePolicyTest.asl"
                          "tests/fixtures/attractor_bench/clean_eval.asl"
                          "tests/fixtures/attractor_bench/clean_vector.asl"
                          "tests/fixtures/attractor_bench/defect_concurrency.asl"
                          "tests/fixtures/attractor_bench/defect_reversibility.asl"
                          "tests/fixtures/crossModuleImport.asl"
                          "tests/fixtures/failingAssert.asl"
                          "tests/fixtures/hmTypeError.asl"
                          "tests/fixtures/hmValidTypes.asl"
                          "tests/fixtures/pilotMigrationFixture.asl"
                          "tests/fixtures/runTestsFalse.asl"
                          "tests/fixtures/typeError.asl"
                          "tests/fixtures/unknownSymbol.asl"
                          "tests/fixtures/wat/add.asl"))
        (stats (fold checkParenAslFile! (pair 0 0) parenFiles))
        (totalChecked (pairFirst stats))
        (mismatches (pairSecond stats))]
    (assert (= totalChecked 33) "checked all 33 valid paren asl files")
    (assert (= mismatches 0) "zero mismatches on valid paren asl files")
    (assert (verifyFixtureFile! "asl/packages/asl-agent/src/dispatch.asl" true 15) "dispatch.asl has 15 top-level forms")
    (assert (verifyFixtureFile! "asl/grammar/corpus/semantic/exportBareCase.asl" true 2) "exportBareCase.asl has 2 top-level forms")
    (assert (verifyFixtureFile! "tests/acceptance/d81/Task58801IntermediatePolicyTest.asl" true 6) "Task58801 has 6 top-level forms")
    (assert (verifyFixtureFile! "asl/packages/asl-syntax/manifest.asn" true 1) "manifest.asn has 1 top-level form")
    (assert (verifyFixtureFile! ".asl.config.asn" true 1) ".asl.config.asn has 1 top-level form")
    (assert (verifyFixtureFile! "asl/packages/asl-forms/tests/fixtures/formsCorpus.asn" true 179) "formsCorpus.asn has 179 top-level forms")
    (assert (verifyFixtureFile! "asl/packages/asl-forms/tests/fixtures/ws/symbols.asn" true 8) "symbols.asn has 8 top-level forms")
    (assert (verifyFixtureFile! ".asl/mem/tasks/asl_language_and_runtime_audit_dossier.asn" true 23) "dossier.asn has 23 top-level forms")
    true)

fn testBenchmarkPerformance! -> Bool
  (let [(path ".asl/mem/notes.asn")]
    (mt (fileReadBytes path)
      ((err e) (assert false (str "benchmark file missing: " e)))
      ((ok bs)
       (let [(len (bytesLength bs))]
         (assert (> len 100000) "benchmark file is >100 KB")
         (let [(t0 (nowNs))
               (root (prn/parseBytes bs))
               (outBs (pr/printTreeBytes! bs root))
               (t1 (nowNs))
               (elapsedNs (- t1 t0))
               (elapsedMs (/ elapsedNs 1000000))
               (msPer100Kb (/ (* elapsedMs 102400) len))]
           (assert (= outBs bs) "benchmark output matches input bytes")
           (assert (not (prn/hasErrors root)) "benchmark file parses without errors")
           (assert (<= msPer100Kb 200) (str "tokenize+CST <= 200 ms per 100 KB, took: " (stringFromInt64 msPer100Kb) " ms"))
           true)))))

fn ! runTests -> Bool
  (and (testParseUnclosedParen)
  (and (testParseStrayClose)
  (and (testParseUnterminatedStringParen)
  (and (testValidParenStructures)
  (and (testDyckFixtures!)
  (and (testAcceptanceAndGrammarInvalidFixtures!)
  (and (testTrackedParenAslFiles!)
  (and (testTrackedAsnSweep!)
       (testBenchmarkPerformance!)))))))))
