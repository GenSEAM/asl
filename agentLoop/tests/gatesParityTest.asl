(module asl/agentLoop/tests/gatesParityTest
  :x [runTests]
  :i [(asl/agentLoop/gates :a g) (asl/agentLoop/core :a c) (asl/agentLoop/diff :a d)])

fn checkExceptCase line: String want: Bool -> Bool
  (let [got (g/isSwallowedExceptLine line)]
    (do
      (assert (= got want) (str "isSwallowedExceptLine on: " line))
      true))

fn checkPassCase line: String want: Bool -> Bool
  (let [got (g/isPassLine line)]
    (do
      (assert (= got want) (str "isPassLine on: " line))
      true))

fn checkSingleCase line: String want: Bool -> Bool
  (let [got (g/isSingleLineSwallow line)]
    (do
      (assert (= got want) (str "isSingleLineSwallow on: " line))
      true))

fn testSwallowedExceptLines -> Bool
  (do
    (assert (checkExceptCase "except:" true) "except: is swallowed")
    (assert (checkExceptCase "except   :" true) "except with spaces is swallowed")
    (assert (checkExceptCase "except Exception:" true) "except Exception is swallowed")
    (assert (checkExceptCase "except BaseException:" true) "except BaseException is swallowed")
    (assert (checkExceptCase "except Exception as e:" true) "except Exception as e is swallowed")
    (assert (checkExceptCase "except BaseException as err:" true) "except BaseException as err is swallowed")
    (assert (checkExceptCase "except (Exception):" true) "except (Exception) is swallowed")
    (assert (checkExceptCase "except (Exception,):" true) "except (Exception,) is swallowed")
    (assert (checkExceptCase "except (BaseException,):" true) "except (BaseException,) is swallowed")
    (assert (checkExceptCase "except: # catch all" true) "except with comment is swallowed")
    (assert (checkExceptCase "except Exception as e: # swallow" true) "except with inline comment is swallowed")
    (assert (checkExceptCase "except Exception, e:" true) "except old comma is swallowed")
    (assert (checkExceptCase "except ValueError:" false) "except ValueError is not swallowed")
    (assert (checkExceptCase "except (ValueError, TypeError):" false) "except tuple other is not swallowed")
    (assert (checkExceptCase "except Exception" false) "except without colon is not swallowed")
    (assert (checkExceptCase "except" false) "except bare without colon is not swallowed")
    (assert (checkExceptCase "finally:" false) "finally is not swallowed")
    (assert (checkExceptCase "try:" false) "try is not swallowed")
    (assert (checkExceptCase "pass" false) "pass is not swallowed except")
    true)

fn testPassLines -> Bool
  (do
    (assert (checkPassCase "pass" true) "pass is pass")
    (assert (checkPassCase "pass;" true) "pass; is pass")
    (assert (checkPassCase "pass; something" true) "pass; something is pass")
    (assert (checkPassCase "pass " true) "pass space is pass")
    (assert (checkPassCase "pass # comment" true) "pass with comment is pass")
    (assert (checkPassCase "    pass" true) "indented pass is pass")
    (assert (checkPassCase "password = 1" false) "password is not pass")
    (assert (checkPassCase "return 1" false) "return is not pass")
    (assert (checkPassCase "continue" false) "continue is not pass")
    (assert (checkPassCase "# pass" false) "comment is not pass")
    (assert (checkPassCase "" false) "empty line is not pass")
    true)

fn testSingleLineSwallow -> Bool
  (do
    (assert (checkSingleCase "except: pass" true) "single bare pass")
    (assert (checkSingleCase "except Exception: pass" true) "single exc pass")
    (assert (checkSingleCase "except Exception as e: pass" true) "single exc as pass")
    (assert (checkSingleCase "except BaseException: pass; return" true) "single base exc pass")
    (assert (checkSingleCase "except (Exception,): pass" true) "single paren comma pass")
    (assert (checkSingleCase "except ValueError: pass" false) "single val err not swallow")
    (assert (checkSingleCase "except Exception: print(1)" false) "single exc print not swallow")
    (assert (checkSingleCase "pass" false) "pass without colon not swallow")
    (assert (checkSingleCase "# except: pass" false) "comment not swallow")
    true)

fn testFindSwallowedInAdded -> Bool
  (let [hunk1 (list (pair 1 "except Exception: pass\n"))
        res1 (g/findSwallowedInAdded hunk1)
        hunk2 (list (pair 1 "except:\n") (pair 2 "    pass\n"))
        res2 (g/findSwallowedInAdded hunk2)
        hunk3 (list (pair 1 "except Exception:\n") (pair 2 "    # note\n") (pair 3 "   \n") (pair 4 "    pass\n"))
        res3 (g/findSwallowedInAdded hunk3)
        hunk4 (list (pair 1 "except Exception:\n") (pair 2 "    print(e)\n") (pair 3 "    pass\n"))
        res4 (g/findSwallowedInAdded hunk4)
        hunk5 (list (pair 1 "except Exception:\n") (pair 2 "    # todo\n"))
        res5 (g/findSwallowedInAdded hunk5)
        hunk6 (list (pair 1 "except ValueError:\n") (pair 2 "    pass\n"))
        res6 (g/findSwallowedInAdded hunk6)
        hunk7 (list (pair 5 "x = 1\n") (pair 6 "except: pass\n") (pair 7 "y = 2\n") (pair 8 "except (BaseException,):\n") (pair 9 "    pass\n"))
        res7 (g/findSwallowedInAdded hunk7)
        hunk8 (list (pair 1 "def foo():\n") (pair 2 "    return 1\n"))
        res8 (g/findSwallowedInAdded hunk8)]
    (do
      (assert (= (listLength res1) 1) "hunk1 length 1")
      (assert (= (c/firstOf res1) 1) "hunk1 line 1")
      (assert (= (listLength res2) 1) "hunk2 length 1")
      (assert (= (c/firstOf res2) 1) "hunk2 line 1")
      (assert (= (listLength res3) 1) "hunk3 length 1")
      (assert (= (c/firstOf res3) 1) "hunk3 line 1")
      (assert (listEmpty? res4) "hunk4 empty")
      (assert (listEmpty? res5) "hunk5 empty")
      (assert (listEmpty? res6) "hunk6 empty")
      (assert (= (listLength res7) 2) "hunk7 length 2")
      (assert (= (c/firstOf res7) 6) "hunk7 line 6")
      (assert (= (c/firstOf (c/restOf res7)) 8) "hunk7 line 8")
      (assert (listEmpty? res8) "hunk8 empty")
      true))

fn testScanHunkSwallowed! -> Bool
  (let [lines1 (d/splitLinesKeepEnds "try:\n    x = 1\nexcept:\n    pass\n")
        res1 (g/scanHunkSwallowed! (list) lines1)
        old2 (d/splitLinesKeepEnds "def foo():\n    return 1\n")
        new2 (d/splitLinesKeepEnds "def foo():\n    try:\n        return 1\n    except Exception:\n        pass\n")
        res2 (g/scanHunkSwallowed! old2 new2)
        old3 (d/splitLinesKeepEnds "def foo():\n    return 1\n")
        new3 (d/splitLinesKeepEnds "def foo():\n    return 1\nexcept: pass\n")
        res3 (g/scanHunkSwallowed! old3 new3)
        old4 (d/splitLinesKeepEnds "def foo():\n    return 1\n")
        new4 (d/splitLinesKeepEnds "def foo():\n    return 1\n")
        res4 (g/scanHunkSwallowed! old4 new4)
        old5 (d/splitLinesKeepEnds "def foo():\n    return 1\n")
        new5 (d/splitLinesKeepEnds "def foo():\n    try:\n        return 1\n    except ValueError:\n        pass\n")
        res5 (g/scanHunkSwallowed! old5 new5)]
    (do
      (assert (= (listLength res1) 1) "scan1 length 1")
      (assert (= (c/firstOf res1) 3) "scan1 line 3")
      (assert (= (listLength res2) 1) "scan2 length 1")
      (assert (= (c/firstOf res2) 4) "scan2 line 4")
      (assert (= (listLength res3) 1) "scan3 length 1")
      (assert (= (c/firstOf res3) 3) "scan3 line 3")
      (assert (listEmpty? res4) "scan4 empty")
      (assert (listEmpty? res5) "scan5 empty")
      true))

fn testPlaceholderHit -> Bool
  (let [g1 (list (g/makeGateResult "sh t.sh" 1 "AssertionError: placeholder\nassert False, 'test'" "" false 0))
        f1 (list (pair "a.py" "x = 1\nassert False, 'test'\ny = 2\n"))
        res1 (g/placeholderHit g1 f1)
        g2 (list (g/makeGateResult "sh t.sh" 0 "assert False, 'test'" "" false 0))
        res2 (g/placeholderHit g2 f1)
        g3 (list (g/makeGateResult "sh t.sh" 1 "other failure" "" false 0))
        res3 (g/placeholderHit g3 f1)
        g4 (list (g/makeGateResult "sh t.sh" 1 "assert False, 'hit in b'" "" false 0))
        f4 (list (pair "a.py" "x = 1\n") (pair "b.py" "assert False, 'hit in b'\n"))
        res4 (g/placeholderHit g4 f4)
        g5 (list (g/makeGateResult "sh t.sh" 1 "x = 1" "" false 0))
        f5 (list (pair "a.py" "x = 1\n"))
        res5 (g/placeholderHit g5 f5)]
    (do
      (mt res1
        ((some h1)
          (do
            (assert (= (g/hitFile h1) "a.py") "ph1 file")
            (assert (= (g/hitLine h1) 2) "ph1 line")
            (assert (= (g/hitText h1) "assert False, 'test'") "ph1 text")))
        ((none) (assert false "ph1 should match")))
      (assert (none? res2) "ph2 exit 0 is none")
      (assert (none? res3) "ph3 mismatch is none")
      (mt res4
        ((some h4)
          (do
            (assert (= (g/hitFile h4) "b.py") "ph4 file")
            (assert (= (g/hitLine h4) 1) "ph4 line")
            (assert (= (g/hitText h4) "assert False, 'hit in b'") "ph4 text")))
        ((none) (assert false "ph4 should match")))
      (assert (none? res5) "ph5 ignores echoed non-assert line")
      true))

fn testPathNormalization! -> Bool
  (let [scripts (g/gateRunScripts (list "sh ././/./scripts/test.py"))
        expectedScripts (list "sh" "scripts/test.py")
        partition (g/gatePartitionFiles (list "././scripts/test.py" "src/app.py") scripts)
        absTool (str (resultOr (realPath "bin/asl") "bin/asl"))
        absCandidates (g/candidateGatePaths! (str "sh " absTool) ".")]
    (do
      (assert (= scripts expectedScripts) "path normalization strips all leading dot and slash chars")
      (assert (= (pairFirst partition) (list "././scripts/test.py")) "partition normalizes changed path")
      (assert (= (pairSecond partition) (list "src/app.py")) "partition keeps unrelated changed path")
      (assert (= absCandidates (list "bin/asl")) "absolute token resolves against relative root")
      true))

fn testMissingGatePaths! -> Bool
  (let [res1 (g/missingGatePaths! "sh tests/nonexistent_test.sh" ".")
        res2 (g/missingGatePaths! "sh bin/asl" ".")
        res3 (g/missingGatePaths! "python3 -u -v tests/nonexistent_test.sh" ".")
        res4 (g/missingGatePaths! "sh \"unclosed" ".")
        res5 (g/missingGatePaths! "python3 -c 'print(1)'" ".")
        res6 (g/missingGatePaths! "python3 tests/nonexistent_1.sh tests/nonexistent_1.sh" ".")
        res7 (g/missingGatePaths! "python3 --log-output-test.yaml tests/nonexistent_test.sh" ".")]
    (do
      (assert (= (listLength res1) 1) "mgp1 length 1")
      (assert (= (c/firstOf res1) "tests/nonexistent_test.sh") "mgp1 path")
      (assert (listEmpty? res2) "mgp2 existing file empty")
      (assert (= (listLength res3) 1) "mgp3 flag skipped")
      (assert (= (c/firstOf res3) "tests/nonexistent_test.sh") "mgp3 path")
      (assert (listEmpty? res4) "mgp4 unclosed quote empty")
      (assert (listEmpty? res5) "mgp5 non pathlike empty")
      (assert (= (listLength res6) 1) "mgp6 dedup length 1")
      (assert (= (c/firstOf res6) "tests/nonexistent_1.sh") "mgp6 path")
      (assert (= res7 (list "tests/nonexistent_test.sh")) "path-like CLI option token is not treated as a file")
      true))

fn testMissingGateFiles! -> Bool
  (let [g1 (list (g/makeGateResult "sh tests/nonexistent_test.sh" 1 "" "" false 0))
        res1 (g/missingGateFiles! g1 ".")
        g2 (list (g/makeGateResult "sh tests/nonexistent_test.sh" 0 "" "" false 0))
        res2 (g/missingGateFiles! g2 ".")
        g3 (list (g/makeGateResult "sh tests/nonexistent_test.sh" 1 "" "" true 5))
        res3 (g/missingGateFiles! g3 ".")
        g4 (list (g/makeGateResult "sh bin/asl" 1 "" "" false 0))
        res4 (g/missingGateFiles! g4 ".")
        g5 (list (g/makeGateResult "sh tests/nonexistent_test.sh" -1 "" "" false 0))
        res5 (g/missingGateFiles! g5 ".")]
    (do
      (assert (= (listLength res1) 1) "mgf1 length 1")
      (assert (= (pairFirst (c/firstOf res1)) 1) "mgf1 idx")
      (assert (= (pairSecond (c/firstOf res1)) "tests/nonexistent_test.sh") "mgf1 path")
      (assert (listEmpty? res2) "mgf2 passing empty")
      (assert (listEmpty? res3) "mgf3 timeout empty")
      (assert (listEmpty? res4) "mgf4 existing empty")
      (assert (listEmpty? res5) "mgf5 exit -1 empty")
      true))

fn testGateVerdicts -> Bool
  (let [g1 (list (g/makeGateResult "sh t.sh" 0 "" "" false 0))
        v1 (g/gateVerdicts g1 false)
        g2 (list (g/makeGateResult "sh t.sh" 1 "" "" false 0))
        v2 (g/gateVerdicts g2 false)
        g3 (list (g/makeGateResult "sh t.sh" 0 "(:gate :asserts 2 :failed 0)" "" false 0))
        v3 (g/gateVerdicts g3 false)
        g4 (list (g/makeGateResult "sh t.sh" 1 "(:gate :asserts 2 :failed 1)" "" false 0))
        v4 (g/gateVerdicts g4 false)
        g5 (list (g/makeGateResult "sh t.sh" 1 "(:gate :asserts 2 :failed 1)" "" false 0))
        v5 (g/gateVerdicts g5 true)
        g6 (list (g/makeGateResult "sh t.sh" 0 "(:gate :asserts 2 :failed 0)" "" false 0))
        v6 (g/gateVerdicts g6 true)
        g7 (list (g/makeGateResult "sh t.sh" 127 "" "" false 0))
        v7 (g/gateVerdicts g7 true)
        g8 (list (g/makeGateResult "sh t.sh" 1 "No such file" "" false 0))
        v8 (g/gateVerdicts g8 true)]
    (do
      (assert (= (c/firstOf v1) "asserted") "gv1 asserted")
      (assert (= (c/firstOf v2) "vacuous") "gv2 vacuous")
      (assert (= (c/firstOf v3) "asserted") "gv3 asserted")
      (assert (= (c/firstOf v4) "vacuous") "gv4 vacuous")
      (assert (= (c/firstOf v5) "failsOnRevert") "gv5 failsOnRevert")
      (assert (= (c/firstOf v6) "passesOnRevert") "gv6 passesOnRevert")
      (assert (= (c/firstOf v7) "missingOnRevert") "gv7 missingOnRevert 127")
      (assert (= (c/firstOf v8) "missingOnRevert") "gv8 missingOnRevert text")
      true))

fn testVacuousOutsideOwns! -> Bool
  (let [g1 (list (g/makeGateResult "sh bin/asl" 1 "" "" false 0))
        res1 (g/vacuousOutsideOwns! g1 (list "asl/agentLoop/") ".")
        g2 (list (g/makeGateResult "sh bin/asl" 1 "" "" false 0))
        res2 (g/vacuousOutsideOwns! g2 (list "bin/asl") ".")
        g3 (list (g/makeGateResult "sh nonexistent_file_xyz.sh" 1 "" "" false 0))
        res3 (g/vacuousOutsideOwns! g3 (list) ".")
        g4 (list (g/makeGateResult "sh bin/asl" 0 "" "" false 0))
        res4 (g/vacuousOutsideOwns! g4 (list) ".")]
    (do
      (mt res1
        ((some p1)
          (do
            (assert (= (pairFirst p1) "sh bin/asl") "voo1 cmd")
            (assert (= (pairSecond p1) "bin/asl") "voo1 file")))
        ((none) (assert false "voo1 should be outside owns")))
      (assert (none? res2) "voo2 inside owns is none")
      (assert (none? res3) "voo3 nonexistent file is none")
      (assert (none? res4) "voo4 asserted is none")
      true))

fn testGateIntegrityPure -> Bool
  (let [gates1 (list "sh tests/t.sh" "python3 ./run.py" "bash 'tests/g.sh'")
        scripts1 (g/gateRunScripts gates1)
        quotedScripts (g/gateRunScripts (list "sh -c 'bash tests/x.sh'"))
        quotedPartition (g/gatePartitionFiles (list "tests/x.sh" "src/app.py") quotedScripts)
        changed2 (list "tests/t.sh" "src/app.py" "./run.py")
        part2 (g/gatePartitionFiles changed2 (list "tests/t.sh" "run.py"))
        gateFiles2 (pairFirst part2)
        implFiles2 (pairSecond part2)
        gVac (list (g/makeGateResult "sh t.sh" 1 "" "" false 0))
        resVac (g/gateVacuousMessage gVac (list "vacuous"))
        resNoVac (g/gateVacuousMessage gVac (list "asserted"))
        revG (list (g/makeGateResult "sh t.sh" 1 "" "" false 0))
        revRes1 (g/gateRevertVerdict revG (list "failsOnRevert") (list "src/app.py") (list))
        revRes2 (g/gateRevertVerdict revG (list "failsOnRevert") (list "src/app.py") (list "src/new.py"))
        revRes3 (g/gateRevertVerdict revG (list "passesOnRevert") (list "src/app.py") (list))]
    (do
      (assert (= (listLength scripts1) 6) "scripts length 6")
      (assert (= quotedScripts (list "sh" "-c" "bash" "tests/x.sh")) "nested shell gate tokens strip quote edges")
      (assert (= (pairFirst quotedPartition) (list "tests/x.sh")) "nested shell test is classified as gate")
      (assert (= (pairSecond quotedPartition) (list "src/app.py")) "nested shell leaves implementation file")
      (assert (listContains? scripts1 "tests/t.sh") "scripts contains t.sh")
      (assert (listContains? scripts1 "run.py") "scripts contains run.py")
      (assert (listContains? scripts1 "tests/g.sh") "scripts contains g.sh")
      (assert (= (listLength gateFiles2) 2) "gateFiles length 2")
      (assert (= (listLength implFiles2) 1) "implFiles length 1")
      (assert (= (c/firstOf implFiles2) "src/app.py") "impl file is app.py")
      (assert (some? resVac) "vacuous message is some")
      (assert (none? resNoVac) "no vacuous message is none")
      (assert (pairFirst revRes1) "revRes1 ok true")
      (assert (= (pairSecond revRes1) "revertCheck: sh t.sh :failsOnRevert :exit 1") "revRes1 msg")
      (assert (pairFirst revRes2) "revRes2 ok true with new files")
      (assert (= (pairSecond revRes2) "revertCheck (kept src/new.py): sh t.sh :failsOnRevert :exit 1") "revRes2 msg kept")
      (assert (not (pairFirst revRes3)) "revRes3 ok false")
      (assert (= (pairSecond revRes3) "no gate reports a failed assertion with src/app.py reverted to HEAD: sh t.sh :passesOnRevert :exit 1") "revRes3 msg")
      true))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        content (resultOr (fileReadString (str root "/asl/agentLoop/tests/gatesParityFixture.asn")) "")
        lines (filter (fn [l] (stringStartsWith? l "(:case ")) (stringLines content))
        n (listLength lines)]
    (do
      (assert (>= n 50) "fixture holds at least 50 cases")
      (assert (testSwallowedExceptLines) "testSwallowedExceptLines passed")
      (assert (testPassLines) "testPassLines passed")
      (assert (testSingleLineSwallow) "testSingleLineSwallow passed")
      (assert (testFindSwallowedInAdded) "testFindSwallowedInAdded passed")
      (assert (testScanHunkSwallowed!) "testScanHunkSwallowed passed")
      (assert (testPlaceholderHit) "testPlaceholderHit passed")
      (assert (testPathNormalization!) "testPathNormalization passed")
      (assert (testMissingGatePaths!) "testMissingGatePaths passed")
      (assert (testMissingGateFiles!) "testMissingGateFiles passed")
      (assert (testGateVerdicts) "testGateVerdicts passed")
      (assert (testVacuousOutsideOwns!) "testVacuousOutsideOwns passed")
      (assert (testGateIntegrityPure) "testGateIntegrityPure passed")
      true))
