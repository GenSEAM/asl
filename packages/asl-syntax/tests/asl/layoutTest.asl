(module asl-syntax/tests/asl/layoutTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/asl/layout :a lay)
      (asl-parser/reader :a rd)
      (asl-parser/indentParser :a ip)])

fn testParseUnterminatedStringIndented -> Bool
  (let [(s1 (str "fn f -> String\n" "  \"unterminated\n"))
        (r1 (lay/parse s1))
        (l1 (stringLength s1))
        (s2 (str "fn f -> String\n" "  \"unterminated"))
        (r2 (lay/parse s2))
        (l2 (stringLength s2))
        (s3 (str "(module m :x [g])\n" "fn g -> String\n" "  \"unterminated\n"))
        (r3 (lay/parse s3))
        (l3 (stringLength s3))]
    (do
      (assert (lay/hasErrors r1) "unterminated string with newline has errors")
      (assert (ok? (tr/checkTiling r1 l1)) "unterminated string with newline tiles cleanly")
      (assert (= (pr/print s1 r1) s1) "unterminated string with newline leaf print matches")
      (assert (lay/hasErrors r2) "unterminated string at EOF has errors")
      (assert (ok? (tr/checkTiling r2 l2)) "unterminated string at EOF tiles cleanly")
      (assert (= (pr/print s2 r2) s2) "unterminated string at EOF leaf print matches")
      (assert (lay/hasErrors r3) "module with unterminated string has errors")
      (assert (ok? (tr/checkTiling r3 l3)) "module with unterminated string tiles cleanly")
      (assert (= (pr/print s3 r3) s3) "module with unterminated string leaf print matches")
      (assert (err? (lay/lowerString s1)) "lowering unterminated string returns error")
      (assert (err? (lay/lowerString s3)) "lowering module with unterminated string returns error")
      true))

fn testBasicIndentedFn -> Bool
  (let [(s (str "fn add x: Int64 y: Int64 -> Int64\n" "  (+ x y)\n"))
        (r (lay/parse s))
        (l (stringLength s))]
    (do
      (assert (not (lay/hasErrors r)) "basic fn has no errors")
      (assert (ok? (tr/checkTiling r l)) "basic fn tiles cleanly")
      (assert (= (pr/print s r) s) "basic fn leaf print matches source")
      (assert (= (lay/topLevelFormCount r) 1) "basic fn has 1 top level form")
      (let [(forms (lay/topLevelForms r))]
        (mt (listHead forms)
          ((none) (do (assert false "missing top form") false))
          ((some elem)
           (mt elem
             ((tr/elemToken _) (do (assert false "top form is not token") false))
             ((tr/elemNode node)
              (do
                (assert (= node.kind "fn") "top form is fn node")
                (let [(kids node.children)]
                  (assert (>= (listLength kids) 2) "fn has at least header and body")
                  (mt (listHead kids)
                    ((none) (assert false "missing header"))
                    ((some hElem)
                     (mt hElem
                       ((tr/elemNode hNode)
                        (assert (= hNode.kind "header") "first child is header node"))
                       ((tr/elemToken _) (assert false "first child is not node"))))))
                (let [(lowerRes (lay/lowerTopFormText s node))]
                  (mt lowerRes
                    ((err e) (do (assert false (str "lower error: " e)) false))
                    ((ok sexpr)
                     (do
                       (assert (= (rd/renderSexpr sexpr) "(fn add [(x Int64) (y Int64)] -> Int64 (+ x y))")
                               "lowered fn rendered matches expected")
                       true))))))))))))

fn testIndentedFnWithEffectAndDoc -> Bool
  (let [(s (str "fn writeLog msg: String -> Unit\n" "  :d \"writes message to log\"\n" "  (print msg)\n"))
        (r (lay/parse s))
        (l (stringLength s))]
    (do
      (assert (not (lay/hasErrors r)) "doc fn has no errors")
      (assert (ok? (tr/checkTiling r l)) "doc fn tiles cleanly")
      (assert (= (pr/print s r) s) "doc fn leaf print matches source")
      (let [(lowerRes (lay/lowerString s))]
        (mt lowerRes
          ((err e) (do (assert false (str "lower error: " e)) false))
          ((ok sexprs)
           (do
             (assert (= (listLength sexprs) 1) "1 sexpr lowered")
             (let [(firstSexpr (optionOr (listHead sexprs) (rd/makeAtom "")))]
               (assert (= (rd/renderSexpr firstSexpr)
                          "(fn writeLog [(msg String)] -> Unit :d \"writes message to log\" (print msg))")
                       "doc lowered correctly")
               true)))))))

fn testSchemaAndEnumDeclarations -> Bool
  (let [(schemaSrc (str "schema Point\n" "  x: Int64\n" "  y: Int64\n"))
        (rSchema (lay/parse schemaSrc))
        (lSchema (stringLength schemaSrc))
        (enumSrc (str "enum Color\n" "  (red)\n" "  (green)\n" "  (blue)\n"))
        (rEnum (lay/parse enumSrc))
        (lEnum (stringLength enumSrc))
        (bracedSrc (str "schema Match {\n" "  start: Int64\n" "  end: Int64\n" "}\n"))
        (rBraced (lay/parse bracedSrc))
        (lBraced (stringLength bracedSrc))]
    (do
      (assert (not (lay/hasErrors rSchema)) "schema has no errors")
      (assert (ok? (tr/checkTiling rSchema lSchema)) "schema tiles cleanly")
      (assert (= (pr/print schemaSrc rSchema) schemaSrc) "schema print matches")
      (assert (= (lay/topLevelFormCount rSchema) 1) "schema has 1 top form")
      (let [(loweredSchema (lay/lowerString schemaSrc))]
        (mt loweredSchema
          ((err e) (do (assert false (str "schema lower err: " e)) false))
          ((ok sList)
           (let [(sx (optionOr (listHead sList) (rd/makeAtom "")))]
             (assert (= (rd/renderSexpr sx) "(schema Point (:field x Int64 \"\") (:field y Int64 \"\"))")
                     "schema lowered matches")
             true))))
      (assert (not (lay/hasErrors rEnum)) "enum has no errors")
      (assert (ok? (tr/checkTiling rEnum lEnum)) "enum tiles cleanly")
      (assert (= (pr/print enumSrc rEnum) enumSrc) "enum print matches")
      (assert (= (lay/topLevelFormCount rEnum) 1) "enum has 1 top form")
      (assert (not (lay/hasErrors rBraced)) "braced schema has no errors")
      (assert (ok? (tr/checkTiling rBraced lBraced)) "braced schema tiles cleanly")
      (assert (= (pr/print bracedSrc rBraced) bracedSrc) "braced schema print matches")
      (assert (= (lay/topLevelFormCount rBraced) 1) "braced schema has 1 top form")
      true))

fn testUnclosedAndStrayDelimitersInBody -> Bool
  (let [(s1 (str "fn f -> Int64\n" "  (+ 1 2\n"))
        (r1 (lay/parse s1))
        (l1 (stringLength s1))
        (s2 (str "fn f -> Int64\n" "  )\n"))
        (r2 (lay/parse s2))
        (l2 (stringLength s2))]
    (do
      (assert (lay/hasErrors r1) "unclosed paren in body has errors")
      (assert (ok? (tr/checkTiling r1 l1)) "unclosed paren tiles cleanly")
      (assert (= (pr/print s1 r1) s1) "unclosed paren print matches")
      (assert (lay/hasErrors r2) "stray close paren in body has errors")
      (assert (ok? (tr/checkTiling r2 l2)) "stray close paren tiles cleanly")
      (assert (= (pr/print s2 r2) s2) "stray close paren print matches")
      true))

fn testMultipleTopLevelForms -> Bool
  (let [(s (str "(module test/math :x [add])\n\n"
                "schema Point\n"
                "  x: Int64\n"
                "  y: Int64\n\n"
                "fn add p: Point q: Point -> Point\n"
                "  (Point (+ p.x q.x) (+ p.y q.y))\n"))
        (r (lay/parse s))
        (l (stringLength s))]
    (do
      (assert (not (lay/hasErrors r)) "multi-form has no errors")
      (assert (ok? (tr/checkTiling r l)) "multi-form tiles cleanly")
      (assert (= (pr/print s r) s) "multi-form print matches")
      (assert (= (lay/topLevelFormCount r) 3) "multi-form has 3 top forms")
      (let [(loweredRes (lay/lowerString s))]
        (mt loweredRes
          ((err e) (do (assert false (str "lower error: " e)) false))
          ((ok sexprs)
           (do
             (assert (= (listLength sexprs) 3) "3 lowered sexprs")
             (let [(s0 (optionOr (listGet sexprs 0) (rd/makeAtom "")))
                   (s1 (optionOr (listGet sexprs 1) (rd/makeAtom "")))
                   (s2 (optionOr (listGet sexprs 2) (rd/makeAtom "")))]
               (assert (= (rd/renderSexpr s0) "(module test/math :x (list add))") "form 0 rendered")
               (assert (= (rd/renderSexpr s1) "(schema Point (:field x Int64 \"\") (:field y Int64 \"\"))") "form 1 rendered")
               (assert (= (rd/renderSexpr s2) "(fn add [(p Point) (q Point)] -> Point (Point (+ p.x q.x) (+ p.y q.y)))") "form 2 rendered")
               true)))))))

fn parseFileList stdout: String -> (List String)
  (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit stdout "\n"))

fn isParenOrInvalidFile path: String -> Bool
  (or (stringContains? path "tests/fixtures/")
  (or (stringContains? path "asl/grammar/corpus/")
  (or (stringContains? path "closureParity/")
  (or (stringContains? path "scratch/")
  (or (stringContains? path "test_")
  (or (stringContains? path "tests/acceptance/r1Host/reader/invalid/")
  (or (stringContains? path "tests/acceptance/vtbotDataPlane/fixtures/invalid/")
  (or (= path "asl/packages/asl-agent/src/dispatch.asl")
  (or (= path "asl/packages/asl-agent/tests/dispatchTest.asl")
  (or (= path "asl/packages/asl-macro/src/macro.asl")
  (or (= path "asl/packages/asl-ui/src/main.asl")
  (or (= path "asl/packages/asl-mem/src/tasks.asl")
      (= path "tests/acceptance/d81/Task58801IntermediatePolicyTest.asl")))))))))))))

fn checkTrackedIndentedFile! acc: (Pair Int64 Int64) path: String -> (Pair Int64 Int64)
  (if (isParenOrInvalidFile path)
    acc
    (mt (fileReadBytes path)
      ((err _) acc)
      ((ok bs)
       (let [(len (bytesLength bs))
             (root (lay/parseBytes bs))
             (outBs (pr/printTreeBytes! bs root))
             (tilingOk (ok? (tr/checkTiling root len)))
             (printOk (= outBs bs))
             (noErr (not (lay/hasErrors root)))
             (okAll (and tilingOk (and printOk noErr)))]
         (if okAll
           (pair (+ (pairFirst acc) 1) (pairSecond acc))
           (pair (+ (pairFirst acc) 1) (+ (pairSecond acc) 1)))))))

fn testTrackedIndentedFilesSweep! -> Bool
  (let [(cmdRes (processRun "git ls-files '*.asl'"))]
    (assert (= cmdRes.exitCode 0) "git ls-files exited 0")
    (let [(files (parseFileList cmdRes.stdout))
          (stats (fold checkTrackedIndentedFile! (pair 0 0) files))
          (cnt (pairFirst stats))
          (fails (pairSecond stats))]
      (do
        (assert (> cnt 1750) "checked >1750 indented files")
        (assert (= fails 0) "zero tiling, print or syntax error failures on indented files")
        true)))

fn checkLoweringAgainstIndentParser! path: String -> Bool
  (mt (fileRead path)
    ((err _) false)
    ((ok src)
     (let [(loweredRes (lay/lowerString src))
           (ipRes (ip/parseIndentedForms src))]
       (mt loweredRes
         ((err e1) (do (assert false (str path " lower error: " e1)) false))
         ((ok lowForms)
          (mt ipRes
            ((err e2) (do (assert false (str path " ip error: " e2)) false))
            ((ok ipForms)
             (do
               (assert (= (listLength lowForms) (listLength ipForms)) (str path " form counts match"))
               (let [(allMatch (fold (fn [(mAcc Bool) (pair (Pair rd/SExpr rd/SExpr))] -> Bool
                                       (and mAcc (= (rd/renderSexpr (pairFirst pair))
                                                    (rd/renderSexpr (pairSecond pair)))))
                                     true (zip lowForms ipForms)))]
                 (do
                   (assert allMatch (str path " rendered forms match"))
                   true))))))))))

fn testLoweringParitySample! -> Bool
  (do
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-syntax/src/core/tree.asl") "tree")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-syntax/src/core/print.asl") "print")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-syntax/src/asl/lex.asl") "lex")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-syntax/src/asl/paren.asl") "paren")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-syntax/src/asl/layout.asl") "layout")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-cli/src/main.asl") "main")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-compiler/src/compiler.asl") "compiler")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-checker/src/check.asl") "check")
    (assert (checkLoweringAgainstIndentParser! "asl/packages/asl-zip/src/inflate.asl") "inflate")
    true)

fn hostTopLevelFormCount! path: String -> Int64
  (let [(res0 (processRun (str "asl/host/out/asl-host parse " path)))
        (res (if (= res0.exitCode 0) res0 (processRun (str "asl-host parse " path))))
        (out (stringTrim res.stdout))
        (parts (stringSplit out " "))
        (first (optionOr (listHead parts) "0"))]
    (optionOr (stringToInt64 first) 0))

fn checkTopCount! path: String -> Bool
  (mt (fileRead path)
    ((err _) false)
    ((ok src)
     (let [(root (lay/parse src))
           (cnt (lay/topLevelFormCount root))
           (expected (hostTopLevelFormCount! path))]
       (do
         (assert (> expected 0) (str path " host count must be positive"))
         (assert (= cnt expected) (str path " top forms match host count " (stringFromInt64 expected)))
         true))))

fn testTopLevelCountParitySample! -> Bool
  (do
    (assert (checkTopCount! "asl/packages/asl-syntax/src/core/tree.asl") "tree")
    (assert (checkTopCount! "asl/packages/asl-syntax/src/core/print.asl") "print")
    (assert (checkTopCount! "asl/packages/asl-syntax/src/asl/lex.asl") "lex")
    (assert (checkTopCount! "asl/packages/asl-syntax/src/asl/paren.asl") "paren")
    (assert (checkTopCount! "asl/packages/asl-syntax/src/asl/layout.asl") "layout")
    (assert (checkTopCount! "asl/packages/asl-regex/src/regex.asl") "regex")
    (assert (checkTopCount! "asl/packages/asl-zip/src/inflate.asl") "inflate")
    (assert (checkTopCount! "asl/packages/asl-cli/src/main.asl") "main")
    (assert (checkTopCount! "asl/packages/asl-compiler/src/compiler.asl") "compiler")
    (assert (checkTopCount! "asl/packages/asl-checker/src/check.asl") "check")
    true)

fn testMultilineStringAndCorpusFixtures! -> Bool
  (let [(s1 (str "fn fixtureSleepContent -> String\n" "  \"#!/bin/sh\n" ": cmd\n" "\"\n"))
        (r1 (lay/lowerString s1))
        (s2 (str "fn formatPresenceRoster room: SwarmRoom -> Str\n"
                 "  (let [(hdr (str \"### Room: \"\n"
                 "\"| Agent ID |\n"
                 "\"))] hdr)\n"))
        (r2 (lay/lowerString s2))
        (s3 (str "(module grammar/corpusTest :x [runTests])\n\n"
                 "schema Scan\n"
                 "  depth: Int64\n"
                 "  low: Int64\n\n"
                 "fn scanChar st: Scan c: String -> Scan\n"
                 "  (cond\n"
                 "    ((= c \"\\\"\") st)\n"
                 "    (else st))\n"))
        (r3 (lay/lowerString s3))
        (rPres (lay/lowerString (resultOr (fileRead "asl/packages/asl-agent-bus/src/presence.asl") "")))
        (rRunner (lay/lowerString (resultOr (fileRead "asl/packages/asl-gates/tests/runnerMainTest.asl") "")))
        (rCorpus (lay/lowerString (resultOr (fileRead "asl/grammar/tests/corpusTest.asl") "")))]
    (do
      (assert (ok? r1) "multiline string in body lowers successfully")
      (mt r1
        ((ok f1)
         (let [(first1 (optionOr (listHead f1) (rd/makeAtom "")))]
           (assert (= (rd/renderSexpr first1) "(fn fixtureSleepContent [] -> String \"#!/bin/sh\\n: cmd\\n\")")
                   "multiline string lowered render matches expected")))
        ((err _) (assert false "r1 failed")))
      (assert (ok? r2) "multiline string in let expression lowers successfully")
      (assert (ok? r3) "schema followed by fn with escaped quote lowers successfully")
      (mt r3
        ((ok f3)
         (do
           (assert (= (listLength f3) 3) "corpusTest fixture has 3 forms")
           (let [(sx0 (optionOr (listGet f3 0) (rd/makeAtom "")))
                 (sx1 (optionOr (listGet f3 1) (rd/makeAtom "")))
                 (sx2 (optionOr (listGet f3 2) (rd/makeAtom "")))]
             (do
               (assert (= (rd/renderSexpr sx0) "(module grammar/corpusTest :x (list runTests))") "sx0 matches")
               (assert (= (rd/renderSexpr sx1) "(schema Scan (:field depth Int64 \"\") (:field low Int64 \"\"))") "sx1 matches")
               (assert (= (rd/renderSexpr sx2) "(fn scanChar [(st Scan) (c String)] -> Scan (cond ((= c \"\\\"\") st) (else st)))") "sx2 matches")
               true))))
        ((err _) (do (assert false "r3 failed") false)))
      (assert (ok? rPres) "presence.asl lowers successfully")
      (assert (ok? rRunner) "runnerMainTest.asl lowers successfully")
      (assert (ok? rCorpus) "corpusTest.asl lowers successfully")
      true))

fn testNoArrowFnLowersWithoutSentinel -> Bool
  (let [(s (str "(module t/sample :x [f] :i [])\n\n" "fn f x: Int64\n" "  (+ x 1)\n"))
        (r (lay/lowerString s))]
    (mt r
      ((err e) (do (assert false (str "lowering no-arrow fn header failed: " e)) false))
      ((ok forms)
       (let [(rendered (stringJoin (map rd/renderSexpr forms) "\n"))]
         (do
           (assert (not (stringContains? rendered ":inferredUnit"))
                   (str "lowered no-arrow fn header must not leak the :inferredUnit sentinel: " rendered))
           (assert (= (listLength forms) 2) "module plus one fn form")
           (assert (= (optionOr (optionMap rd/renderSexpr (listGet forms 1)) "") "(fn f [(x Int64)] (+ x 1))")
                   (str "no-arrow fn header round-trips with no arrow at all: " rendered))
           true)))))

fn testArrowedFnBodyNotCorruptedByFalseMatch -> Bool
  (let [(s (str "(module t/sample :x [f] :i [])\n\n" "fn f x: Int64 -> Int64\n" "  (-> x)\n" "  (:inferredUnit 1)\n"))
        (r (lay/lowerString s))]
    (mt r
      ((err e) (do (assert false (str "lowering an arrowed fn with a false-match-shaped body failed: " e)) false))
      ((ok forms)
       (let [(rendered (stringJoin (map rd/renderSexpr forms) "\n"))]
         (do
           (assert (= (listLength forms) 2) "module plus one fn form")
           (assert (= (optionOr (optionMap rd/renderSexpr (listGet forms 1)) "") "(fn f [(x Int64)] -> Int64 (-> x) (:inferredUnit 1))")
                   (str "both body forms, shaped like the sentinel pair, survive untouched: " rendered))
           true)))))

fn testParenFnWithNoArrowKeepsListShapedBody -> Bool
  (let [(s (str "(module t/sample :x [f] :i [])\n\n" "(fn f [(x Int64)] (-> x) (:inferredUnit 1))\n"))
        (r (lay/lowerString s))]
    (mt r
      ((err e) (do (assert false (str "lowering a paren-style no-arrow fn with a list-shaped body failed: " e)) false))
      ((ok forms)
       (let [(rendered (stringJoin (map rd/renderSexpr forms) "\n"))]
         (do
           (assert (= (listLength forms) 2) "module plus one fn form")
           (assert (= (optionOr (optionMap rd/renderSexpr (listGet forms 1)) "") "(fn f (list (x Int64)) (-> x) (:inferredUnit 1))")
                   (str "both body forms, list-shaped like the sentinel pair, survive untouched: " rendered))
           true)))))

fn testArrowedFnBareSentinelAtomsInBodySurvive -> Bool
  (let [(s (str "(module t/sample :x [f] :i [])\n\n" "fn f x: Int64 -> Int64\n" "  (+ x 1)\n" "  ->\n" "  :inferredUnit\n"))
        (r (lay/lowerString s))]
    (mt r
      ((err e) (do (assert false (str "lowering an arrowed fn with bare sentinel-shaped atoms in its body failed: " e)) false))
      ((ok forms)
       (let [(rendered (stringJoin (map rd/renderSexpr forms) "\n"))]
         (do
           (assert (= (listLength forms) 2) "module plus one fn form")
           (assert (= (optionOr (optionMap rd/renderSexpr (listGet forms 1)) "") "(fn f [(x Int64)] -> Int64 (+ x 1) -> :inferredUnit)")
                   (str "the real header and both bare body atoms survive untouched: " rendered))
           true)))))

fn ! runTests -> Bool
  (do
    (assert (testParseUnterminatedStringIndented) "testParseUnterminatedStringIndented")
    (assert (testBasicIndentedFn) "testBasicIndentedFn")
    (assert (testIndentedFnWithEffectAndDoc) "testIndentedFnWithEffectAndDoc")
    (assert (testSchemaAndEnumDeclarations) "testSchemaAndEnumDeclarations")
    (assert (testUnclosedAndStrayDelimitersInBody) "testUnclosedAndStrayDelimitersInBody")
    (assert (testMultipleTopLevelForms) "testMultipleTopLevelForms")
    (assert (testTrackedIndentedFilesSweep!) "testTrackedIndentedFilesSweep")
    (assert (testLoweringParitySample!) "testLoweringParitySample")
    (assert (testTopLevelCountParitySample!) "testTopLevelCountParitySample")
    (assert (testMultilineStringAndCorpusFixtures!) "testMultilineStringAndCorpusFixtures")
    (assert (testNoArrowFnLowersWithoutSentinel) "testNoArrowFnLowersWithoutSentinel")
    (assert (testArrowedFnBodyNotCorruptedByFalseMatch) "testArrowedFnBodyNotCorruptedByFalseMatch")
    (assert (testParenFnWithNoArrowKeepsListShapedBody) "testParenFnWithNoArrowKeepsListShapedBody")
    (assert (testArrowedFnBareSentinelAtomsInBodySurvive) "testArrowedFnBareSentinelAtomsInBodySurvive")
    true)
