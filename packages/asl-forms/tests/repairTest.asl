(module asl-forms/tests/repairTest
  :x [runTests]
  :i [(asl-forms/repair :a rep)])

fn checkHostValid! content: String tmpPath: String -> Bool
  (mt (fileWrite tmpPath content)
    ((err e) (do (assert false (str "failed to write " tmpPath ": " e)) false))
    ((ok _)
     (let [(res (processRun (str "asl/host/out/asl-host check " tmpPath)))
           (exitCode res.exitCode)]
       (do
         (processRun (str "rm -f " tmpPath))
         (= exitCode 0)))))

fn testCleanInputs -> Bool
  (let [(aslClean "(module foo/bar\n  :x [runTests]\n  :i [])\nfn runTests -> Bool\n  true\n")
        (asnClean "(:data :a 1 :b [2 3])")
        (resAsl (rep/repair aslClean "asl"))
        (resAsn (rep/repair asnClean "asn"))]
    (do
      (assert (= (rep/repairResultReceipt resAsl) "(:repaired () :left ())") "clean ASL receipt must be empty repaired and left")
      (assert (= (rep/repairResultReceipt resAsn) "(:repaired () :left ())") "clean ASN receipt must be empty repaired and left")
      true))

fn testAsnUnclosedRepairs -> Bool
  (let [(r1 (rep/repair "(:data 1 2" "asn"))
        (r2 (rep/repair "[:a :b :c" "asn"))
        (r3 (rep/repair "{:a 1 :b 2" "asn"))
        (r4 (rep/repair "(" "asn"))
        (r5 (rep/repair "[" "asn"))
        (r6 (rep/repair "{" "asn"))
        (r7 (rep/repair "(a (b)" "asn"))]
    (do
      (assert (= (rep/repairResultReceipt r1) "(:repaired () :left ((:line 1 :col 11 :expected \")\" :near \"(:data 1 2\" :options ((:insert :tok \")\" :line 1 :col 11) (:insert :tok \")\" :line 1 :col 9) (:insert :tok \")\" :line 1 :col 7)))))") "asn unclosed list with four closing positions is left")
      (assert (= (rep/repairAlternatives "(:data 1 2" "asn") (list "():data 1 2" "(:data) 1 2" "(:data 1) 2" "(:data 1 2)")) "asn unclosed list alternatives are exactly the four closing positions")
      (assert (= (rep/repairResultText r1) "(:data 1 2") "asn unclosed list text unchanged")
      (assert (= (rep/repairResultReceipt r2) "(:repaired () :left ((:line 1 :col 10 :expected \"]\" :near \"[:a :b :c\" :options ((:insert :tok \"]\" :line 1 :col 10) (:insert :tok \"]\" :line 1 :col 7) (:insert :tok \"]\" :line 1 :col 4)))))") "asn unclosed vector is left")
      (assert (= (rep/repairResultReceipt r3) "(:repaired () :left ((:line 1 :col 11 :expected \"}\" :near \"{:a 1 :b 2\" :options ((:insert :tok \"}\" :line 1 :col 11) (:insert :tok \"}\" :line 1 :col 9) (:insert :tok \"}\" :line 1 :col 6)))))") "asn unclosed map is left")
      (assert (= (rep/repairResultReceipt r4) "(:repaired ((:kind insert :tok \")\" :line 1 :col 2)) :left ())") "asn lone open paren repaired receipt")
      (assert (= (rep/repairResultReceipt r5) "(:repaired ((:kind insert :tok \"]\" :line 1 :col 2)) :left ())") "asn lone open bracket repaired receipt")
      (assert (= (rep/repairResultReceipt r6) "(:repaired ((:kind insert :tok \"}\" :line 1 :col 2)) :left ())") "asn lone open brace repaired receipt")
      (assert (= (rep/repairResultText r4) "()") "asn lone open paren repaired text")
      (assert (= (rep/repairResultReceipt r7) "(:repaired () :left ((:line 1 :col 7 :expected \")\" :near \"(a (b)\" :options ((:insert :tok \")\" :line 1 :col 7) (:insert :tok \")\" :line 1 :col 3) (:insert :tok \")\" :line 1 :col 2)))))") "asn nested unclosed paren is left")
      true))

fn testAsnMismatchedRepairs -> Bool
  (let [(r1 (rep/repair "(a [b c)" "asn"))
        (r2 (rep/repair "[a (b c]" "asn"))
        (r3 (rep/repair "{a [b c}" "asn"))
        (r4 (rep/repair "(a {b c)" "asn"))
        (r5 (rep/repair "[a {b c]" "asn"))
        (r6 (rep/repair "{a (b c}" "asn"))]
    (do
      (assert (= (rep/repairResultReceipt r1) "(:repaired () :left ((:line 1 :col 8 :expected \"]\" :near \"(a [b c)\" :options ((:insert :tok \"]\" :line 1 :col 8) (:insert :tok \"]\" :line 1 :col 6) (:insert :tok \"]\" :line 1 :col 5)))))") "asn mismatched bracket in list is left")
      (assert (= (rep/repairAlternatives "(a [b c)" "asn") (list "(a []b c)" "(a [b] c)" "(a [b c])")) "asn mismatched bracket in list has three alternatives")
      (assert (= (rep/repairResultReceipt r2) "(:repaired () :left ((:line 1 :col 8 :expected \")\" :near \"[a (b c]\" :options ((:insert :tok \")\" :line 1 :col 8) (:insert :tok \")\" :line 1 :col 6) (:insert :tok \")\" :line 1 :col 5)))))") "asn mismatched paren in vector is left")
      (assert (= (rep/repairResultReceipt r3) "(:repaired () :left ((:line 1 :col 8 :expected \"]\" :near \"{a [b c}\" :options ((:insert :tok \"]\" :line 1 :col 8) (:insert :tok \"]\" :line 1 :col 6) (:insert :tok \"]\" :line 1 :col 5)))))") "asn mismatched bracket in map is left")
      (assert (= (rep/repairResultReceipt r4) "(:repaired () :left ((:line 1 :col 8 :expected \"}\" :near \"(a {b c)\" :options ((:insert :tok \"}\" :line 1 :col 8) (:insert :tok \"}\" :line 1 :col 6) (:insert :tok \"}\" :line 1 :col 5)))))") "asn mismatched brace in list is left")
      (assert (= (rep/repairResultReceipt r5) "(:repaired () :left ((:line 1 :col 8 :expected \"}\" :near \"[a {b c]\" :options ((:insert :tok \"}\" :line 1 :col 8) (:insert :tok \"}\" :line 1 :col 6) (:insert :tok \"}\" :line 1 :col 5)))))") "asn mismatched brace in vector is left")
      (assert (= (rep/repairResultReceipt r6) "(:repaired () :left ((:line 1 :col 8 :expected \")\" :near \"{a (b c}\" :options ((:insert :tok \")\" :line 1 :col 8) (:insert :tok \")\" :line 1 :col 6) (:insert :tok \")\" :line 1 :col 5)))))") "asn mismatched paren in map is left")
      (assert (= (rep/repairResultText r6) "{a (b c}") "asn mismatched paren in map text unchanged")
      true))

fn testImmediateMismatchedRepairs -> Bool
  (let [(r1 (rep/repair "(]" "asn"))
        (r2 (rep/repair "[)" "asn"))
        (r3 (rep/repair "{)" "asn"))
        (r4 (rep/repair "((])" "asn"))]
    (do
      (assert (= (rep/repairResultText r1) "()") "immediate mismatched (] repaired text")
      (assert (= (rep/repairResultReceipt r1) "(:repaired ((:kind delete :tok \"]\" :line 1 :col 2) (:kind insert :tok \")\" :line 1 :col 2)) :left ())") "immediate mismatched (] receipt")
      (assert (= (rep/repairResultText r2) "[]") "immediate mismatched [) repaired text")
      (assert (= (rep/repairResultReceipt r2) "(:repaired ((:kind delete :tok \")\" :line 1 :col 2) (:kind insert :tok \"]\" :line 1 :col 2)) :left ())") "immediate mismatched [) receipt")
      (assert (= (rep/repairResultText r3) "{}") "immediate mismatched {) repaired text")
      (assert (= (rep/repairResultReceipt r3) "(:repaired ((:kind delete :tok \")\" :line 1 :col 2) (:kind insert :tok \"}\" :line 1 :col 2)) :left ())") "immediate mismatched {) receipt")
      (assert (= (rep/repairResultText r4) "(())") "nested immediate mismatched ((]) repaired text")
      (assert (= (rep/repairResultReceipt r4) "(:repaired ((:kind delete :tok \"]\" :line 1 :col 3) (:kind insert :tok \")\" :line 1 :col 3)) :left ())") "nested immediate mismatched ((]) receipt")
      true))

fn testAslLayoutRepairs -> Bool
  (let [(r1 (rep/repair "fn broken a: Int64 -> Int64\n  (+ a 1" "asl"))
        (r2 (rep/repair "(module test :x [runTests]" "asl"))
        (r3 (rep/repair "(module test :x [runTests)" "asl"))
        (r4 (rep/repair "fn foo -> Int64\n  (let [(a 1]\n    a)" "asl"))]
    (do
      (assert (= (rep/repairResultReceipt r1) "(:repaired () :left ((:line 2 :col 9 :expected \")\" :near \"  (+ a 1\" :options ((:insert :tok \")\" :line 2 :col 9) (:insert :tok \")\" :line 2 :col 7) (:insert :tok \")\" :line 2 :col 5)))))") "asl broken fn body is left")
      (assert (= (rep/repairAlternatives "fn broken a: Int64 -> Int64\n  (+ a 1" "asl") (list "fn broken a: Int64 -> Int64\n  ()+ a 1" "fn broken a: Int64 -> Int64\n  (+) a 1" "fn broken a: Int64 -> Int64\n  (+ a) 1" "fn broken a: Int64 -> Int64\n  (+ a 1)")) "asl broken fn body alternatives are exactly the four closing positions")
      (assert (= (rep/repairResultReceipt r2) "(:repaired () :left ((:line 1 :col 27 :expected \")\" :near \"(module test :x [runTests]\" :options ((:insert :tok \")\" :line 1 :col 27) (:insert :tok \")\" :line 1 :col 16) (:insert :tok \")\" :line 1 :col 13)))))") "asl unclosed module header is left")
      (assert (= (rep/repairResultReceipt r3) "(:repaired () :left ((:line 1 :col 26 :expected \"]\" :near \"(module test :x [runTests)\" :options ((:insert :tok \"]\" :line 1 :col 26)))))") "asl mismatched header vector is left")
      (assert (= (rep/repairResultReceipt r4) "(:repaired () :left ((:line 2 :col 13 :expected \")\" :near \"  (let [(a 1]\" :options ((:insert :tok \")\" :line 2 :col 13) (:insert :tok \")\" :line 2 :col 11)))))") "asl nested mismatched let is left")
      true))

fn checkFixtureRepair! path: String isAsl: Bool tmpPath: String -> Bool
  (mt (fileReadString path)
    ((err e) (do (assert false (str "read error for " path ": " e)) false))
    ((ok content)
     (let [(lang (if isAsl "asl" "asn"))
           (res (rep/repair content lang))
           (repaired (rep/repairResultText res))]
       (do
         (assert (listEmpty? (rep/repairResultLeft res)) (str path " repair must have empty left"))
         (assert (not (listEmpty? (rep/repairResultRepaired res))) (str path " repair must have non-empty repaired"))
         (if isAsl
           (do (assert (checkHostValid! repaired tmpPath) (str path " repaired must pass asl-host check")) true)
           true)
         true))))

fn checkFixtureLeft! path: String lang: String firstLeft: String -> Bool
  (mt (fileReadString path)
    ((err e) (do (assert false (str "read error for " path ": " e)) false))
    ((ok content)
     (let [(res (rep/repair content lang))]
       (do
         (assert (listEmpty? (rep/repairResultRepaired res)) (str path " must not be repaired"))
         (assert (stringStartsWith? (rep/repairResultReceipt res) (str "(:repaired () :left (" firstLeft)) (str path " first left item: " (rep/repairResultReceipt res)))
         (assert (= (rep/repairResultText res) content) (str path " text unchanged"))
         true))))

fn testFixtureSetRepairs! -> Bool
  (do
    (assert (checkFixtureRepair! "tests/acceptance/r1Host/reader/invalid/unclosedEofTest.asl" true "/tmp/test_unclosedEof_repaired.asl") "unclosedEofTest.asl passes check")
    (assert (checkFixtureLeft! "tests/acceptance/r1Host/reader/invalid/strayParenEofTest.asl" "asl" "(:line 9 :col 1 :expected \"\"") "strayParenEofTest.asl left")
    (assert (checkFixtureLeft! "asl/grammar/corpus/invalid/unbalanced.asl" "asl" "(:line 2 :col 9 :expected \")\"") "unbalanced.asl left")
    (assert (checkFixtureLeft! "asl/grammar/corpus/asn/invalid/syntaxError.asn" "asn" "(:line 2 :col 31 :expected \"))\"") "syntaxError.asn left")
    (assert (checkFixtureLeft! "tests/fixtures/dyck/invalid/unclosedBracket.asn" "asn" "(:line 1 :col 8 :expected \"]\"") "unclosedBracket.asn left")
    (assert (checkFixtureLeft! "tests/fixtures/dyck/invalid/extraOpen.asn" "asn" "(:line 1 :col 7 :expected \")\"") "extraOpen.asn left")
    (assert (checkFixtureLeft! "asl/grammar/corpus/asn/invalid/unbalanced.asn" "asn" "(:line 4 :col 33 :expected \"])\"") "unbalanced.asn left")
    (assert (checkFixtureLeft! "tests/fixtures/dyck/invalid/extraClose.asn" "asn" "(:line 1 :col 6 :expected \"\"") "extraClose.asn left")
    (assert (checkFixtureLeft! "tests/fixtures/dyck/invalid/strayBracket.asn" "asn" "(:line 1 :col 5 :expected \")\"") "strayBracket.asn left")
    (assert (checkFixtureLeft! "tests/fixtures/dyck/invalid/stringHidesOpen.asn" "asn" "(:line 1 :col 10 :expected \"\"") "stringHidesOpen.asn left")
    (assert (checkFixtureLeft! "tests/fixtures/dyck/invalid/commentHidesClose.asn" "asn" "(:line 1 :col 3 :expected \")\"") "commentHidesClose.asn left")
    (assert (checkFixtureLeft! "tests/fixtures/dyck/invalid/closeBeforeOpen.asn" "asn" "(:line 1 :col 1 :expected \"\"") "closeBeforeOpen.asn left")
    (assert (= (rep/repairAlternatives "(a b))" "asn") (list "((a b))" "(a (b))" "(a b())" "(a b)")) "an extra closer has lost-opener alternatives besides its deletion")
    true)

fn testUnrepairedDiagnostics! -> Bool
  (let [(path "tests/fixtures/dyck/invalid/unterminatedString.asn")
        (content (resultOr (fileReadString path) ""))
        (res (rep/repair content "asn"))
        (leftList (rep/repairResultLeft res))]
    (do
      (assert (not (listEmpty? leftList)) "unterminatedString must have unrepaired left items")
      (let [(firstLeft (optionOr (listHead leftList) (rep/makeLeftItem 0 0 "" "")))]
        (do
          (assert (> (rep/leftItemLine firstLeft) 0) "left item line must be positive")
          (assert (> (rep/leftItemCol firstLeft) 0) "left item col must be positive")
          (assert (<= (stringLength (rep/leftItemNear firstLeft)) 60) "left item near max 60 chars")
          (assert (stringContains? (rep/repairResultReceipt res) ":left (") "receipt contains left list")
          true))))

fn testListCapping -> Bool
  (let [(items (map (fn [(c Int64)] -> rep/RepairedItem (rep/makeRepairedItem "insert" ")" 1 c)) (list 1 2 3 4 5 6)))
        (receipt (rep/formatReceipt items (list)))
        (left (rep/repairResultLeft (rep/repair "((((((" "asn")))]
    (do
      (assert (= receipt "(:repaired ((:kind insert :tok \")\" :line 1 :col 1) (:kind insert :tok \")\" :line 1 :col 2) (:kind insert :tok \")\" :line 1 :col 3) (:kind insert :tok \")\" :line 1 :col 4) (:kind insert :tok \")\" :line 1 :col 5) (:kind insert :tok \")\" :line 1 :col 6)) :left ())") "an applied receipt lists every edit, never :more")
      (assert (= (listLength left) 1) "six closers missing at one end are one fault item")
      (assert (stringContains? (rep/repairResultReceipt (rep/repair "((((((" "asn")) ":options ((:insert :tok \"))))))\" :line 1 :col 7))") "its option appends all six closers")
      (assert (stringContains? (rep/formatReceipt (list) (map (fn [(c Int64)] -> rep/LeftItem (rep/makeLeftItem 1 c ")" "")) (list 1 2 3 4 5 6))) ":more 1)") "left list caps at five with :more 1")
      true))

fn testUnterminatedStringRejected -> Bool
  (let [(res (rep/repair "(:a 1)\n(:b \"oops\n" "asn"))]
    (do
      (assert (listEmpty? (rep/repairResultRepaired res)) "unterminated string must not be repaired")
      (assert (not (listEmpty? (rep/repairResultLeft res))) "unterminated string must leave left items")
      (assert (= (rep/leftItemExpected (optionOr (listHead (rep/repairResultLeft res)) (rep/makeLeftItem 0 0 "" ""))) "\"") "unterminated string left item expects a quote")
      true))

fn testLayoutTieBreakSiblingFn -> Bool
  (let [(src "fn siblingA -> Int64
  (do
    (g 1)
    x

fn siblingB -> Int64
  3
")
        (res (rep/repair src "asl"))]
    (do
      (assert (= (rep/repairResultReceipt res) "(:repaired ((:kind insert :tok \")\" :line 4 :col 6)) :left ())") "sibling fn closer lands after x")
      (assert (= (rep/repairResultText res) "fn siblingA -> Int64
  (do
    (g 1)
    x)

fn siblingB -> Int64
  3
") "sibling fn repaired before siblingB")
      (assert (= (listLength (rep/repairAlternatives src "asl")) 1) "exactly one candidate survives layout")
      true))

fn testLayoutTieBreakAsn -> Bool
  (let [(src "(:a\n  (:b 1)\n  :c\n(:e 4)\n")
        (res (rep/repair src "asn"))]
    (do
      (assert (= (rep/repairResultText res) "(:a\n  (:b 1)\n  :c)\n(:e 4)\n") "asn closer lands after :c, not after (:e 4)")
      (assert (= (rep/repairResultReceipt res) "(:repaired ((:kind insert :tok \")\" :line 3 :col 5)) :left ())") "asn layout receipt")
      true))

fn testLayoutTieBreakLetSibling -> Bool
  (let [(src "fn foo -> Int64
  (let [(a 1)
        (b (+ 2 3)
        (c 4)]
    (+ a (+ b c)))
")
        (res (rep/repair src "asl"))]
    (do
      (assert (listEmpty? (rep/repairResultRepaired res)) "let sibling is not repaired")
      (assert (stringStartsWith? (rep/repairResultReceipt res) "(:repaired () :left ((:line 4 :col 14 :expected \")\"") "let sibling left at the mismatched ]")
      (assert (= (rep/repairResultText res) src) "let sibling text unchanged")
      true))

fn testLayoutTieBreakMtIfArm -> Bool
  (let [(src "fn testArm v: Int64 -> String
  (mt v
    (0 (if (> v 0) (str \"pos\"
           (str \"nonpos\")))
    (_ \"other\"))
")
        (res (rep/repair src "asl"))]
    (do
      (assert (listEmpty? (rep/repairResultRepaired res)) "mt if arm is not repaired")
      (assert (stringStartsWith? (rep/repairResultReceipt res) "(:repaired () :left ((:line 5 :col 17 :expected \")\"") "mt if arm left at the end of the unclosed form")
      (assert (= (rep/repairResultText res) src) "mt if arm text unchanged")
      true))

fn testOrphanCloserRefused -> Bool
  (let [(src "fn foo x: Int64 -> Int64
  + x 1)
")
        (res (rep/repair src "asl"))]
    (do
      (assert (listEmpty? (rep/repairResultRepaired res)) "orphan closer must not be repaired")
      (assert (not (listEmpty? (rep/repairResultLeft res))) "orphan closer must leave left items")
      (assert (= (rep/repairResultText res) src) "orphan closer text unchanged")
      true))

fn testKindMismatchAndStrays -> Bool
  (let [(srcLet "(module ws/m :x [f])\n\nfn f x: Int64 -> Int64\n  (let [(x (+ x 1))]\n    x)\n")
        (badLet "(module ws/m :x [f])\n\nfn f x: Int64 -> Int64\n  (let [(x (+ x 1)))\n    x)\n")
        (rLet (rep/repair badLet "asl"))
        (badMirror "(module ws/m :x [f])\n\nfn f x: Int64 -> Int64\n  (let [(x (+ x 1)]]\n    x)\n")
        (rMirror (rep/repair badMirror "asl"))
        (badStray1 "fn f x: Int64 -> Int64\n  (+ x 1))\n")
        (rStray1 (rep/repair badStray1 "asl"))
        (badStray2 "fn f x: Int64 -> Int64\n  (+ (* x 2)) 1)\n")
        (rStray2 (rep/repair badStray2 "asl"))
        (badNest "fn f x: Int64 -> Int64\n  (+ 1)\n     (* x 2))\n")
        (rNest (rep/repair badNest "asl"))]
    (do
      (assert (= (rep/repairResultText rLet) srcLet) "let kind mismatch repaired to original")
      (assert (= (rep/repairResultReceipt rLet) "(:repaired ((:kind delete :tok \")\" :line 4 :col 20) (:kind insert :tok \"]\" :line 4 :col 20)) :left ())") "let kind mismatch receipt")
      (assert (= (rep/repairResultText rMirror) srcLet) "mirror kind mismatch repaired to original")
      (assert (listEmpty? (rep/repairResultLeft rMirror)) "mirror kind mismatch left empty")
      (assert (= (rep/repairResultText rStray1) "fn f x: Int64 -> Int64\n  (+ x 1)\n") "surplus closer after a bare fn body is deleted")
      (assert (= (rep/repairResultReceipt rStray1) "(:repaired ((:kind delete :tok \")\" :line 2 :col 10)) :left ())") "surplus closer deletion receipt")
      (assert (listContains? (rep/repairAlternatives badStray1 "asl") "fn f x: Int64 -> Int64\n  (+ x (1))\n") "stray single closer has the lost-opener alternative (+ x (1))")
      (assert (= (rep/repairResultText rStray2) badStray2) "stray nested closer text unchanged")
      (assert (listContains? (rep/repairAlternatives badStray2 "asl") "fn f x: Int64 -> Int64\n  (+ (* x 2) 1)\n") "stray nested closer has the (+ (* x 2) 1) alternative")
      (assert (listContains? (rep/repairAlternatives badStray2 "asl") "fn f x: Int64 -> Int64\n  (+ (* x 2)) 1\n") "stray nested closer has the (+ (* x 2)) 1 alternative")
      (assert (not (listEmpty? (rep/repairResultLeft rNest))) "stray nesting change refused with left")
      (assert (= (rep/repairResultText rNest) badNest) "stray nesting text unchanged")
      true))

fn testSpanLayoutEvidence -> Bool
  (let [(text "fn f x: Int64 -> Int64\n  (+ 1)\n     (* x 2))\n")
        (inSpan (rep/repairTextInSpan text "asl" 25 30))
        (whole (rep/repair "fn f x: Int64 -> Int64\n  (do\n    (g 1)\n    x\n" "asl"))
        (spanned (rep/repairTextInSpan "fn f x: Int64 -> Int64\n  (do\n    (g 1)\n    x\n" "asl" 25 29))]
    (do
      (assert (listEmpty? (rep/repairResultRepaired inSpan)) "edited (+ 1) with an old indented sibling below is left")
      (assert (= (rep/repairResultText whole) "fn f x: Int64 -> Int64\n  (do\n    (g 1)\n    x)\n") "whole-text layout places the closer after x")
      (assert (listEmpty? (rep/repairResultRepaired spanned)) "with only the (do line as evidence the closer position is left")
      true))

fn testSegmentLayoutScope -> Bool
  (let [(src "(module ws/m :x [a b])\n\nfn a -> Int64\n  (let [(y 1)]\n  y)\n\nfn b -> (List Int64)\n  [1 2 3)\n")
        (res (rep/repair src "asl"))]
    (do
      (assert (= (rep/repairResultText res) "(module ws/m :x [a b])\n\nfn a -> Int64\n  (let [(y 1)]\n  y)\n\nfn b -> (List Int64)\n  [1 2 3]\n") "the swap in fn b applies despite fn a's indentation")
      (assert (= (rep/repairResultReceipt res) "(:repaired ((:kind delete :tok \")\" :line 8 :col 9) (:kind insert :tok \"]\" :line 8 :col 9)) :left ())") "fn b swap receipt")
      true))

fn testOptionsAndPicks -> Bool
  (let [(one "fn f x: Int64 -> Int64\n  (+ x 1))\n")
        (multi "fn f -> Bool\n  (do\n    true)))\n\nfn g -> Bool\n  (do\n    (let [(a 1] a)))\n")
        (r1 (rep/repairTextPick one "asl" -1 -1 "1.1"))
        (r2 (rep/repairTextPick one "asl" -1 -1 "1.2"))
        (r3 (rep/repairTextPick one "asl" -1 -1 "2.1"))
        (r4 (rep/repairTextPick one "asl" -1 -1 "x"))
        (m0 (rep/repair multi "asl"))
        (m1 (rep/repairTextPick multi "asl" -1 -1 "1.1 2.1 3.1 4.1"))
        (m2 (rep/repairTextPick multi "asl" -1 -1 "1.1 3.1"))]
    (do
      (assert (= (rep/repairResultText r1) "fn f x: Int64 -> Int64\n  (+ x 1)\n") "pick 1.1 deletes the extra closer")
      (assert (= (rep/repairResultReceipt r1) "(:repaired ((:kind delete :tok \")\" :line 2 :col 10)) :left () :pick \"1.1\")") "pick 1.1 receipt names the pick")
      (assert (= (rep/repairResultText r2) "fn f x: Int64 -> Int64\n  ((+ x 1))\n") "pick 1.2 applies the second option, the nearest lost opener that keeps (+ x 1) whole")
      (assert (= (rep/repairResultText r3) one) "pick of a missing item leaves the text")
      (assert (stringEndsWith? (rep/repairResultReceipt r3) " :pick \"2.1\" :pickParses false)") "pick of a missing item is reported")
      (assert (listEmpty? (rep/repairResultRepaired r4)) "malformed pick applies nothing")
      (assert (= (listLength (rep/repairResultLeft m0)) 4) "four fault sites across two forms")
      (assert (stringContains? (rep/repairResultReceipt m0) "(:line 7 :col 15 :expected \")\" :near \"    (let [(a 1] a)))\" :options ((:insert :tok \")\" :line 7 :col 15)") "mismatch item offers the expected closer at the flagged place first")
      (assert (= (rep/repairResultText m1) "fn f -> Bool\n  (do\n    true)\n\nfn g -> Bool\n  (do\n    (let [(a 1)] a))\n") "picking every first option repairs all four sites")
      (assert (= (rep/repairResultText m2) multi) "picking two of four sites leaves the text")
      (assert (stringEndsWith? (rep/repairResultReceipt m2) ":pickParses false)") "partial pick is reported as not parsing")
      true))

fn editCase orig: String old: String new: String lang: String pick: String -> RepairResult
  (let [(at (optionOr (stringIndexOf orig old) 0))
        (text (str (optionOr (stringSlice orig 0 at) "") new (optionOr (stringSlice orig (+ at (stringLength old)) (stringLength orig)) "")))]
    (rep/repairEdit text lang at (+ at (stringLength new)) old pick))

fn checkEditOptions orig: String old: String new: String lang: String options: String label: String -> Bool
  (do
    (assert (stringContains? (rep/repairResultReceipt (editCase orig old new lang "")) (str ":options (" options ")")) (str label " options"))
    (assert (= (rep/repairResultText (editCase orig old new lang "1.1")) orig) (str label " pick 1.1 is the true fix"))
    true)

fn testReparentingRanksLast -> Bool
  (let [(h "(module ws/m :x [f])\n\nfn f x: Int64 -> Int64\n  ")
        (ifFixed "(module ws/m :x [f])\n\nfn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (if (> y 0)\n      (+ y 1)\n      (- y 1)))\n")]
    (do
      (assert (checkEditOptions (str h "(+ (* x 2) (- x 1))\n") "(* x 2)" "(* x 2" "asl" "(:insert :tok \")\" :line 4 :col 12) (:insert :tok \")\" :line 4 :col 10) (:insert :tok \")\" :line 4 :col 21 :reparents true)" "absorb (- x 1)") "absorb (- x 1)")
      (assert (checkEditOptions (str h "(if (> x 0) (g x) (h x))\n") "(g x)" "(g x" "asl" "(:insert :tok \")\" :line 4 :col 19) (:insert :tok \")\" :line 4 :col 17) (:insert :tok \")\" :line 4 :col 26 :reparents true)" "absorb (h x)") "absorb (h x)")
      (assert (checkEditOptions (str h "(+ (* x 2) x)\n") "(* x 2)" "(* x 2))" "asl" "(:delete :tok \")\" :line 4 :col 13) (:insert :tok \"(\" :line 4 :col 11) (:delete :tok \")\" :line 4 :col 16 :reparents true)" "orphan x") "orphan x")
      (assert (checkEditOptions "  (:b (:x 2))\n  (:c 3)\n" "(:x 2))" "(:x 2)" "asn" "(:insert :tok \")\" :line 1 :col 13) (:insert :tok \")\" :line 1 :col 10) (:insert :tok \")\" :line 2 :col 9 :reparents true)" "sibling (:c 3)") "sibling (:c 3)")
      (assert (checkEditOptions "(module ws/m :x [f])\n\nfn f -> Int64\n  (g [1 2] 3)\n" "[1 2]" "[1 2" "asl" "(:insert :tok \"]\" :line 4 :col 10) (:insert :tok \"]\" :line 4 :col 8) (:insert :tok \"]\" :line 4 :col 12 :reparents true)" "arity of g") "arity of g")
      (assert (checkEditOptions ifFixed "(+ y 1)" "(+ y 1))" "asl" "(:delete :tok \")\" :line 6 :col 14) (:insert :tok \"(\" :line 6 :col 12) (:delete :tok \")\" :line 7 :col 15 :reparents true)" "if keeps its else") "if keeps its else")
      true))

fn testWriteModeOneLine -> Bool
  (let [(h "(module ws/m :x [f])\n\nfn f x: Int64 -> Int64\n  ")
        (r1 (rep/repairReceipt (str h "(+ (* x 2 (- x 1))\n") "asl"))
        (r2 (rep/repairReceipt (str h "(if (> x 0) (g x (h x))\n") "asl"))
        (r3 (rep/repairReceipt (str h "(+ (* x 2)) x)\n") "asl"))]
    (do
      (assert (stringContains? r1 ":options ((:insert :tok \")\" :line 4 :col 21) (:insert :tok \")\" :line 4 :col 12) (:insert :tok \")\" :line 4 :col 10))") "absorb case shows the true fix at col 12 unmarked")
      (assert (stringContains? r2 ":options ((:insert :tok \")\" :line 4 :col 26) (:insert :tok \")\" :line 4 :col 19) (:insert :tok \")\" :line 4 :col 17))") "if case shows the true fix at col 19 unmarked")
      (assert (stringContains? r3 ":options ((:delete :tok \")\" :line 4 :col 16) (:insert :tok \"(\" :line 4 :col 15) (:delete :tok \")\" :line 4 :col 13))") "orphan case shows the true fix at col 13 unmarked")
      (assert (not (stringContains? (str r1 r2 r3) ":reparents")) "no misleading :reparents flag in these writes")
      (assert (= (rep/repairResultReceipt (rep/repairTextPick "fn f -> Int64\n  (a b))\n" "asl" -1 -1 "0.0")) "(:repaired () :left ((:line 2 :col 8 :expected \"\" :near \"  (a b))\" :options ((:delete :tok \")\" :line 2 :col 8) (:insert :tok \"(\" :line 2 :col 3) (:insert :tok \"(\" :line 1 :col 1)))) :pick \"0.0\" :pickParses false)") "ASL options never create an empty form such as (a b())")
      (assert (stringContains? (rep/repairReceipt "(a b))" "asn") "(:insert :tok \"(\" :line 1 :col 5)") "ASN keeps the empty-form option, since () is a value")
      true))

fn testFlushLeftSegments -> Bool
  (let [(e1 (rep/repair "(:e\n:id 1\n:score 42\n" "asn"))
        (e2 (rep/repair "(:note \"first\nsecond\" :x 1\n" "asn"))
        (e3 (rep/repair "fn f -> Int64\n  (+ x\n1\n" "asl"))
        (e4 (rep/repair "(:list [1 2\n3 4\n" "asn"))
        (e5 (rep/repair "(:doc\n\"text\"\n:x 1\n" "asn"))]
    (do
      (assert (= (rep/repairResultReceipt e1) "(:repaired () :left ((:line 3 :col 10 :expected \")\" :near \":score 42\" :options ((:insert :tok \")\" :line 3 :col 10) (:insert :tok \")\" :line 3 :col 7) (:insert :tok \")\" :line 2 :col 6)))))") "flush-left ASN is one form with the closer at its end first")
      (assert (= (rep/repairResultReceipt e2) "(:repaired () :left ((:line 2 :col 13 :expected \")\" :near \"second\\\" :x 1\" :options ((:insert :tok \")\" :line 2 :col 13) (:insert :tok \")\" :line 2 :col 11) (:insert :tok \")\" :line 2 :col 8)))))") "a string continuing at column 1 does not split the form")
      (assert (= (rep/repairResultReceipt e3) "(:repaired () :left ((:line 3 :col 2 :expected \")\" :near \"1\" :options ((:insert :tok \")\" :line 3 :col 2) (:insert :tok \")\" :line 2 :col 7) (:insert :tok \")\" :line 2 :col 5)))))") "a column-1 atom continues (+ x")
      (assert (= (rep/repairResultReceipt e4) "(:repaired () :left ((:line 2 :col 4 :expected \"])\" :near \"3 4\" :options ((:insert :tok \"])\" :line 2 :col 4)))))") "two closers missing at one end are one item")
      (assert (= (rep/repairResultText (rep/repairTextPick "(:list [1 2\n3 4\n" "asn" -1 -1 "1.1")) "(:list [1 2\n3 4])\n") "the merged option appends both closers")
      (assert (stringStartsWith? (rep/repairResultReceipt e5) "(:repaired () :left ((:line 3 :col 5 :expected \")\" :near \":x 1\" :options ((:insert :tok \")\" :line 3 :col 5)") "a column-1 string stays in its form")
      true))

fn replayFixture! name: String -> String
  (mt (fileReadString (str "asl/packages/asl-forms/tests/fixtures/unbalanced/g3real/" name ".txt"))
    ((ok t) t)
    ((err e) (do (assert false (str "missing fixture " name ": " e)) "")))

fn hostRunText! content: String tmpPath: String cmd: String -> (Pair Int64 String)
  (mt (fileWrite tmpPath content)
    ((err e) (do (assert false (str "failed to write " tmpPath ": " e)) (pair -1 e)))
    ((ok _)
     (let [(res (processRun (str "asl/host/out/asl-host " cmd " " tmpPath " 2>&1")))]
       (do
         (processRun (str "rm -f " tmpPath))
         (pair res.exitCode (str res.stdout res.stderr))))))

fn hostAccepts! content: String tmpPath: String cmd: String -> Bool
  (= (pairFirst (hostRunText! content tmpPath cmd)) 0)

fn checkSurplusReplay! name: String base: String at: Int64 oldLen: Int64 receipt: String checkError: String -> Bool
  (let [(edit (>= at 0))
        (b (if edit (replayFixture! base) ""))
        (n (if edit (replayFixture! (str name ".new")) ""))
        (text (if edit (str (optionOr (stringSlice b 0 at) "") n (optionOr (stringSlice b (+ at oldLen) (stringLength b)) "")) (replayFixture! name)))
        (res (if edit
               (rep/repairEdit text "asl" at (+ at (stringLength n)) (optionOr (stringSlice b at (+ at oldLen)) "") "")
               (rep/repairTextPick text "asl" -1 -1 "")))
        (fixed (rep/repairResultText res))]
    (do
      (assert (= (rep/repairResultReceipt res) receipt) (str name " receipt: " (rep/repairResultReceipt res)))
      (assert (= (stringLength fixed) (- (stringLength text) (listLength (rep/repairResultRepaired res)))) (str name " only the surplus closers are removed"))
      (assert (not (hostAccepts! text (str "asl/packages/asl-forms/tests/.surplus_" name "_before.asl") "parse")) (str name " payload is rejected before the repair"))
      (if (= checkError "")
        (do (assert (hostAccepts! fixed (str "asl/packages/asl-forms/tests/.surplus_" name ".asl") "check") (str name " repaired text passes asl-host check")) true)
        (let [(chk (hostRunText! fixed (str "asl/packages/asl-forms/tests/.surplus_" name ".asl") "check"))]
          (do
            (assert (hostAccepts! fixed (str "asl/packages/asl-forms/tests/.surplus_" name ".asl") "parse") (str name " repaired text passes asl-host parse"))
            (assert (and (!= (pairFirst chk) 0) (stringContains? (pairSecond chk) checkError)) (str name " asl-host check fails only on the payload's own " checkError ", not syntax: " (pairSecond chk)))
            (assert (not (stringContains? (pairSecond chk) "ERR_READ")) (str name " asl-host check reports no reader error"))
            true)))
      true))

fn testFnSurplusReplays! -> Bool
  (do
      (assert (checkSurplusReplay! "case01" "case01" -1 0 "(:repaired ((:kind delete :tok \")\" :line 41 :col 9)) :left ())" "ERR_UNKNOWN_SYMBOL") "case01 fn-end surplus replay")
      (assert (checkSurplusReplay! "case02" "case02" -1 0 "(:repaired ((:kind delete :tok \")\" :line 80 :col 28)) :left ())" "") "case02 fn-end surplus replay")
      (assert (checkSurplusReplay! "case04" "case04" -1 0 "(:repaired ((:kind delete :tok \")\" :line 62 :col 73) (:kind delete :tok \")\" :line 95 :col 13)) :left ())" "ERR_EFFECT_UNMARKED") "case04 fn-end surplus replay")
      (assert (checkSurplusReplay! "case05" "case05" -1 0 "(:repaired ((:kind delete :tok \")\" :line 52 :col 63) (:kind delete :tok \")\" :line 100 :col 13)) :left ())" "ERR_ARITY") "case05 fn-end surplus replay")
      (assert (checkSurplusReplay! "case17" "case17" -1 0 "(:repaired ((:kind delete :tok \")\" :line 23 :col 13) (:kind delete :tok \")\" :line 33 :col 13) (:kind delete :tok \")\" :line 43 :col 13) (:kind delete :tok \")\" :line 55 :col 13) (:kind delete :tok \")\" :line 65 :col 13) (:kind delete :tok \")\" :line 73 :col 13) (:kind delete :tok \")\" :line 80 :col 13) (:kind delete :tok \")\" :line 91 :col 13) (:kind delete :tok \")\" :line 104 :col 10) (:kind delete :tok \")\" :line 116 :col 10)) :left ())" "ERR_UNKNOWN_SYMBOL") "case17 fn-end surplus replay")
      (assert (checkSurplusReplay! "case20" "case20" -1 0 "(:repaired ((:kind delete :tok \")\" :line 27 :col 85)) :left ())" "ERR_EFFECT_UNMARKED") "case20 fn-end surplus replay")
      (assert (checkSurplusReplay! "case22" "case22" -1 0 "(:repaired ((:kind delete :tok \")\" :line 202 :col 64) (:kind delete :tok \")\" :line 213 :col 13) (:kind delete :tok \")\" :line 228 :col 21) (:kind delete :tok \")\" :line 274 :col 19)) :left ())" "ERR_CONSTANT_ASSERT") "case22 fn-end surplus replay")
      (assert (checkSurplusReplay! "case25" "baseb1b9331b" 12020 72 "(:repaired ((:kind delete :tok \")\" :line 314 :col 72)) :left ())" "") "case25 fn-end surplus replay")
      (assert (checkSurplusReplay! "case27" "base6341fd35" 1321 115 "(:repaired ((:kind delete :tok \")\" :line 54 :col 59)) :left ())" "") "case27 fn-end surplus replay")
      (assert (checkSurplusReplay! "case31" "case31" -1 0 "(:repaired ((:kind delete :tok \")\" :line 142 :col 18) (:kind delete :tok \")\" :line 175 :col 81)) :left ())" "ERR_UNKNOWN_SYMBOL") "case31 fn-end surplus replay")
      true)

fn testFnSurplusGuards -> Bool
  (let [(multi (rep/repair "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (* y 2))))\n" "asl"))
        (quoted (rep/repair "fn f -> String\n  (str \"a)\" \"(b\")) ; (:m (x)))\n" "asl"))
        (needLet "fn f x: Int64 -> Int64\n  let [(a 1)]\n    (+ a x))\n")
        (rLet (rep/repair needLet "asl"))
        (premature "fn f x: Int64 -> Int64\n  (let [(a 1)]\n    (+ a x))\n    (g a))\n")
        (rPremature (rep/repair premature "asl"))
        (unindented "fn f x: Int64 -> Int64\n  (let [(a 1)]\n  (+ a x)))\n")
        (rUnindented (rep/repair unindented "asl"))
        (missing "fn f x: Int64 -> Int64\n  (let [(a 1)\n    (+ a x)))\n")
        (rMissing (rep/repair missing "asl"))
        (twoFaults "fn f x: Int64 -> Int64\n  (+ x 1))\n\nfn g x: Int64 -> Int64\n  (h [x)\n")
        (rTwo (rep/repair twoFaults "asl"))
        (h "(module ws/m :x [f])\n\nfn f x: Int64 -> Int64\n  ")
        (at (stringLength h))
        (lostOpener (str h "(+ x * x 2))\n"))
        (rLost (rep/repairEdit lostOpener "asl" (+ at 5) (+ at 11) "(* x 2)" ""))
        (rAdded (rep/repairEdit (str h "(+ x 1))\n") "asl" at (+ at 8) "(+ x 1)" ""))]
    (do
      (assert (= (rep/repairResultText multi) "fn f x: Int64 -> Int64\n  (let [(y (+ x 1))]\n    (* y 2))\n") "several surplus closers are all removed")
      (assert (= (rep/repairResultReceipt multi) "(:repaired ((:kind delete :tok \")\" :line 3 :col 13) (:kind delete :tok \")\" :line 3 :col 14)) :left ())") "exactly the two surplus closers are deleted")
      (assert (= (rep/repairResultText quoted) "fn f -> String\n  (str \"a)\" \"(b\") ; (:m (x)))\n") "closers in strings and comments are untouched")
      (assert (= (rep/repairResultText rLet) needLet) "a closer needed by a lost opener stays")
      (assert (listEmpty? (rep/repairResultRepaired rLet)) "lost-opener case is not applied")
      (assert (= (rep/repairResultText rPremature) premature) "a premature closer mid-body is not answered by deleting the last")
      (assert (listEmpty? (rep/repairResultRepaired rPremature)) "premature case is not applied")
      (assert (= (rep/repairResultText rUnindented) unindented) "nesting that disagrees with indentation stays")
      (assert (stringStartsWith? (rep/repairResultReceipt rUnindented) "(:repaired () :left ((:line 3 :col 11 :expected \"\" :near \"  (+ a x)))\" :options ((:delete :tok \")\" :line 3 :col 11)") "the unapplied deletion is the first option")
      (assert (= (rep/repairResultText rMissing) missing) "a body missing a closer is not trimmed")
      (assert (= (rep/repairResultText rTwo) twoFaults) "another fault elsewhere blocks auto-apply")
      (assert (stringStartsWith? (rep/repairResultReceipt rTwo) "(:repaired () :left ((:line 2 :col 10 :expected \"\" :near \"  (+ x 1))\" :options ((:delete :tok \")\" :line 2 :col 10)") "the fn-end deletion leads its item when blocked")
      (assert (= (rep/repairResultText (rep/repair "fn f\n  (:a 1))\n" "asn")) "fn f\n  (:a 1))\n") "ASN is outside the bare fn rule")
      (assert (= (rep/repairResultText rLost) lostOpener) "an edit that lost an opener keeps the closer")
      (assert (stringStartsWith? (rep/repairResultReceipt rLost) "(:repaired () :left ((:line 4 :col 14 :expected \"\"") "the lost-opener edit is left with options")
      (assert (= (rep/repairResultText rAdded) (str h "(+ x 1)\n")) "an edit that added a surplus closer is trimmed")
      true))

fn ! runTests -> Bool
  (do
    (assert (testCleanInputs) "testCleanInputs")
    (assert (testAsnUnclosedRepairs) "testAsnUnclosedRepairs")
    (assert (testAsnMismatchedRepairs) "testAsnMismatchedRepairs")
    (assert (testImmediateMismatchedRepairs) "testImmediateMismatchedRepairs")
    (assert (testAslLayoutRepairs) "testAslLayoutRepairs")
    (assert (testFixtureSetRepairs!) "testFixtureSetRepairs")
    (assert (testUnrepairedDiagnostics!) "testUnrepairedDiagnostics")
    (assert (testListCapping) "testListCapping")
    (assert (testUnterminatedStringRejected) "testUnterminatedStringRejected")
    (assert (testLayoutTieBreakSiblingFn) "testLayoutTieBreakSiblingFn")
    (assert (testLayoutTieBreakAsn) "testLayoutTieBreakAsn")
    (assert (testLayoutTieBreakLetSibling) "testLayoutTieBreakLetSibling")
    (assert (testLayoutTieBreakMtIfArm) "testLayoutTieBreakMtIfArm")
    (assert (testOrphanCloserRefused) "testOrphanCloserRefused")
    (assert (testKindMismatchAndStrays) "testKindMismatchAndStrays")
    (assert (testSpanLayoutEvidence) "testSpanLayoutEvidence")
    (assert (testSegmentLayoutScope) "testSegmentLayoutScope")
    (assert (testOptionsAndPicks) "testOptionsAndPicks")
    (assert (testReparentingRanksLast) "testReparentingRanksLast")
    (assert (testWriteModeOneLine) "testWriteModeOneLine")
    (assert (testFlushLeftSegments) "testFlushLeftSegments")
    (assert (testFnSurplusReplays!) "testFnSurplusReplays")
    (assert (testFnSurplusGuards) "testFnSurplusGuards")
    true)
