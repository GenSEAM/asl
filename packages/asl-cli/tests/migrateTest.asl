(module asl-cli/tests/migrateTest
  :d "Falsifiable test suite for Task 52610 Automated Migration CLI with In-Memory Semantic Equivalence Invariant."
  :x [runTests]
  :i [(migrate :a mig)
      (cli :a c)
      (reader :a rd)
      (ast :a a)
      (indentParser :a ip)])

(df sampleModuleSource [] -> Str
  :d "Returns canonical S-expression source module for migration testing."
  (str "(module demo/calculator\n"
       "  :d \"Arithmetic service\"\n"
       "  :x [add]\n"
       "  :i [(reader :a rd)])\n\n"
       "(df add [(x Int64) (y Int64)] -> Int64\n"
       "  (+ x y))\n"))

(df testVerifySemanticEquivalenceAtoms [] -> Bool
  :d "Verifies semantic equivalence logic on terminal atom tokens including aliases."
  (let [(aAdd1 (rd/makeAtom "add"))
        (aAdd2 (rd/makeAtom "add"))
        (aSub (rd/makeAtom "sub"))
        (aDf (rd/makeAtom "df"))
        (aDefun (rd/makeAtom "defun"))
        (aMt (rd/makeAtom "mt"))
        (aMatch (rd/makeAtom "match"))
        (aD (rd/makeAtom ":d"))
        (aDoc (rd/makeAtom ":doc"))
        (aX (rd/makeAtom ":x"))
        (aExp (rd/makeAtom ":export"))
        (aI (rd/makeAtom ":i"))
        (aImp (rd/makeAtom ":import"))
        (aA (rd/makeAtom ":a"))
        (aAs (rd/makeAtom ":as"))
        (aTrue (rd/makeAtom "true"))
        (aFalse (rd/makeAtom "false"))
        (a42 (rd/makeAtom "42"))
        (a43 (rd/makeAtom "43"))]
    (assert (mig/verifySemanticEquivalence aAdd1 aAdd2) "identical atoms must be equivalent")
    (assert (mig/verifySemanticEquivalence aDf aDefun) "df and defun must be equivalent")
    (assert (mig/verifySemanticEquivalence aDefun aDf) "defun and df must be equivalent")
    (assert (mig/verifySemanticEquivalence aMt aMatch) "mt and match must be equivalent")
    (assert (mig/verifySemanticEquivalence aMatch aMt) "match and mt must be equivalent")
    (assert (mig/verifySemanticEquivalence aD aDoc) ":d and :doc must be equivalent")
    (assert (mig/verifySemanticEquivalence aDoc aD) ":doc and :d must be equivalent")
    (assert (mig/verifySemanticEquivalence aX aExp) ":x and :export must be equivalent")
    (assert (mig/verifySemanticEquivalence aI aImp) ":i and :import must be equivalent")
    (assert (mig/verifySemanticEquivalence aA aAs) ":a and :as must be equivalent")

    (refute (mig/verifySemanticEquivalence aAdd1 aSub) "different fn names must refute equivalence")
    (refute (mig/verifySemanticEquivalence aTrue aFalse) "true vs false must refute equivalence")
    (refute (mig/verifySemanticEquivalence a42 a43) "different numbers must refute equivalence")
    (refute (mig/verifySemanticEquivalence aAdd1 (rd/makeList (list))) "atom vs list must refute equivalence")
    true))

(df testVerifySemanticEquivalenceCompound [] -> Bool
  :d "Verifies semantic equivalence logic on compound expressions and functions."
  (let [(form1 (rd/makeList (list (rd/makeAtom "df")
                                  (rd/makeAtom "add")
                                  (rd/makeVect (list (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "Int")))
                                                     (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int")))))
                                  (rd/makeAtom "->")
                                  (rd/makeAtom "Int")
                                  (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))))
        (form2 (rd/makeList (list (rd/makeAtom "defun")
                                  (rd/makeAtom "add")
                                  (rd/makeVect (list (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "Int")))
                                                     (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int")))))
                                  (rd/makeAtom "->")
                                  (rd/makeAtom "Int")
                                  (rd/makeAtom ":doc")
                                  (rd/makeAtom "\"Adds x and y\"")
                                  (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))))
        (formBodyDiv (rd/makeList (list (rd/makeAtom "df")
                                        (rd/makeAtom "add")
                                        (rd/makeVect (list (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "Int")))
                                                           (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int")))))
                                        (rd/makeAtom "->")
                                        (rd/makeAtom "Int")
                                        (rd/makeList (list (rd/makeAtom "-") (rd/makeAtom "x") (rd/makeAtom "y"))))))
        (formParamDiv (rd/makeList (list (rd/makeAtom "df")
                                         (rd/makeAtom "add")
                                         (rd/makeVect (list (rd/makeList (list (rd/makeAtom "z") (rd/makeAtom "Int")))
                                                            (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int")))))
                                         (rd/makeAtom "->")
                                         (rd/makeAtom "Int")
                                         (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))))
        (formRetDiv (rd/makeList (list (rd/makeAtom "df")
                                       (rd/makeAtom "add")
                                       (rd/makeVect (list (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "Int")))
                                                          (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int")))))
                                       (rd/makeAtom "->")
                                       (rd/makeAtom "Bool")
                                       (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))))
        (formNameDiv (rd/makeList (list (rd/makeAtom "df")
                                        (rd/makeAtom "mult")
                                        (rd/makeVect (list (rd/makeList (list (rd/makeAtom "x") (rd/makeAtom "Int")))
                                                           (rd/makeList (list (rd/makeAtom "y") (rd/makeAtom "Int")))))
                                        (rd/makeAtom "->")
                                        (rd/makeAtom "Int")
                                        (rd/makeList (list (rd/makeAtom "+") (rd/makeAtom "x") (rd/makeAtom "y"))))))]
    (assert (mig/verifySemanticEquivalence form1 form1) "identical defun forms must be equivalent")
    (assert (mig/verifySemanticEquivalence form1 form2) "defun with alias and docstring must be equivalent to df form")

    (refute (mig/verifySemanticEquivalence form1 formBodyDiv) "divergent body must refute equivalence")
    (refute (mig/verifySemanticEquivalence form1 formParamDiv) "divergent param name must refute equivalence")
    (refute (mig/verifySemanticEquivalence form1 formRetDiv) "divergent return type must refute equivalence")
    (refute (mig/verifySemanticEquivalence form1 formNameDiv) "divergent function name must refute equivalence")
    true))

(df ! testDryRunLeavesDiskUntouched [] -> Bool
  :d "Asserts that --dry-run returns migrated text while leaving disk target untouched."
  (let [(src (sampleModuleSource))
        (path "tmp/migrate_dryrun_fixture.asl")]
    (mt (file-write path src)
      ((err _) (assert false "failed to prepare dry-run test fixture"))
      ((ok _)
       (let [(res (mig/migrateSource src path true false))]
         (mt res
           ((err emsg)
            (assert false (str "dry-run should succeed, got: " emsg)))
           ((ok indented)
            (assert (string-contains? indented "fn add x: Int64 y: Int64 -> Int64") "dry-run output contains fn signature")
            (assert (string-contains? indented "module demo/calculator") "dry-run output contains module header")
            (refute (string-contains? indented "(df add") "dry-run output refutes old df syntax")
            (mt (file-read path)
              ((err _) (assert false "failed to read dry-run target file"))
              ((ok diskContent)
               (assert (= diskContent src) "disk file content remains strictly identical to original source")
               (refute (= diskContent indented) "disk file must refute mutation on dry-run"))))))))
    true))

(df ! testCheckOnlyValidatesWithoutMutation [] -> Bool
  :d "Asserts that --check validates migratable source without mutating disk."
  (let [(src (sampleModuleSource))
        (path "tmp/migrate_check_fixture.asl")]
    (mt (file-write path src)
      ((err _) (assert false "failed to prepare check test fixture"))
      ((ok _)
       (let [(res (mig/migrateSource src path false true))]
         (mt res
           ((err emsg)
            (assert false (str "check should succeed, got: " emsg)))
           ((ok msg)
            (assert (string-contains? msg "Validated migratable") "check result confirms migratable status")
            (assert (string-contains? msg path) "check result contains file path")
            (mt (file-read path)
              ((err _) (assert false "failed to read check target file"))
              ((ok diskContent)
               (assert (= diskContent src) "disk file content remains strictly unchanged on check")
               (refute (string-contains? diskContent "fn add") "disk file must refute migrated syntax on check"))))))))
    true))

(df ! testActualMigrationWritesToDisk [] -> Bool
  :d "Asserts that full migration converts source, passes equivalence, and writes to disk."
  (let [(src (sampleModuleSource))
        (path "tmp/migrate_write_fixture.asl")]
    (mt (file-write path src)
      ((err _) (assert false "failed to prepare write test fixture"))
      ((ok _)
       (let [(res (mig/migrateSource src path false false))]
         (mt res
           ((err emsg)
            (assert false (str "migration write should succeed, got: " emsg)))
           ((ok msg)
            (assert (string-contains? msg "Successfully migrated") "success message confirms migration")
            (assert (string-contains? msg path) "success message contains target file path")
            (mt (file-read path)
              ((err _) (assert false "failed to read written target file"))
              ((ok diskContent)
               (assert (string-contains? diskContent "fn add x: Int64 y: Int64 -> Int64") "disk file contains migrated fn signature")
               (assert (string-contains? diskContent "module demo/calculator") "disk file contains module header")
               (refute (string-contains? diskContent "(df add") "disk file refutes old df syntax")
               (refute (= diskContent src) "disk file refutes unmigrated source"))))))))
    true))

(df ! testMalformedSourceAndDivergenceAbortsWithoutDiskCorruption [] -> Bool
  :d "Asserts that malformed input or semantic divergence triggers immediate abort without disk corruption."
  (let [(path "tmp/migrate_abort_fixture.asl")
        (sentinel "ORIGINAL_UNTOUCHED_CONTENT_STAYS_INTACT")
        (corruptSrc "(module broken/delims (df unclosed [(x Int] (+ x 1)))")]
    (mt (file-write path sentinel)
      ((err _) (assert false "failed to prepare abort test fixture"))
      ((ok _)
       (let [(res (mig/migrateSource corruptSrc path false false))]
         (mt res
           ((ok _)
            (assert false "malformed source must not succeed"))
           ((err emsg)
            (assert (string-contains? emsg "semantic divergence detected") "error message confirms divergence detection")
            (refute (string-contains? emsg "Successfully migrated") "error message refutes success")
            (mt (file-read path)
              ((err _) (assert false "failed to read abort target file"))
              ((ok diskContent)
               (assert (= diskContent sentinel) "disk file content strictly preserved after abort")
               (refute (!= diskContent sentinel) "disk file corruption must be refuted on abort"))))))))
    true))

(df ! testCliCommandDispatchIntegration [] -> Bool
  :d "Asserts CLI command dispatching for migrate with arguments, error cases, and help manual."
  (let [(path "tmp/migrate_cli_fixture.asl")
        (src (sampleModuleSource))]
    (mt (file-write path src)
      ((err _) (assert false "failed to prepare cli fixture"))
      ((ok _)
       (mt (c/dispatchCmd "migrate" (list "--check" path))
         ((ok msg)
          (assert (string-contains? msg "Validated migratable") "cli dispatch --check succeeds")
          (refute (string-contains? msg "Successfully migrated") "cli dispatch --check refutes migration write"))
         ((err emsg)
          (assert false (str "cli dispatch --check should succeed, got: " emsg))))
       (mt (c/dispatchCmd "migrate" (list "--dry-run" path))
         ((ok msg)
          (assert (string-contains? msg "fn add x: Int64 y: Int64 -> Int64") "cli dispatch --dry-run returns fn syntax")
          (refute (string-contains? msg "(df add") "cli dispatch --dry-run refutes df syntax"))
         ((err emsg)
          (assert false (str "cli dispatch --dry-run should succeed, got: " emsg))))
       (mt (c/dispatchCmd "migrate" (list))
         ((ok _)
          (assert false "empty migrate dispatch must fail"))
         ((err msg)
          (assert (string-contains? msg "Usage: asl migrate") "empty migrate dispatch returns usage")
          (refute (string-contains? msg "Validated") "empty migrate dispatch refutes validation")))
       (mt (c/dispatchCmd "migrate" (list "nonexistent_migrate_target_xyz.asl"))
         ((ok _)
          (assert false "missing file migrate dispatch must fail"))
         ((err msg)
          (assert (string-contains? msg "Failed to read target file") "missing file dispatch reports read error")
          (refute (string-contains? msg "Validated") "missing file dispatch refutes validation")))
       (let [(hlp (c/formatHelp))]
         (assert (string-contains? hlp "migrate [--dry-run|--check]") "formatHelp documents migrate command")
         (refute (not (string-contains? hlp "migrate [--dry-run|--check]")) "formatHelp must not omit migrate command"))))
    true))

(df ! runTests [] -> Bool
  :d "Master test runner executing all falsifiable migration unit tests and D77 refutations."
  (and (testVerifySemanticEquivalenceAtoms)
       (and (testVerifySemanticEquivalenceCompound)
            (and (testDryRunLeavesDiskUntouched)
                 (and (testCheckOnlyValidatesWithoutMutation)
                      (and (testActualMigrationWritesToDisk)
                           (and (testMalformedSourceAndDivergenceAbortsWithoutDiskCorruption)
                                (testCliCommandDispatchIntegration))))))))
