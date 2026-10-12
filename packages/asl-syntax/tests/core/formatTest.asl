(module asl-syntax/tests/core/formatTest
  :x [runTests]
  :i [(asl-syntax/core/format :a fmt)
      (asl-forms/repair :a rep)
      (asl-syntax/asl/lex :a lx)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/bytesText :a bt)
      (tools/fleet/run :a run)])

(schema HostRun
  (:f exitCode Int64)
  (:f output String))

(schema Outcome
  (:f label String)
  (:f input String)
  (:f lang String)
  (:f expected String)
  (:f actual String))

fn shown r: (Result String String) -> String
  (mt r
    ((ok s) s)
    ((err e) (str "<err " e ">")))

fn fr text: String lang: String -> String
  (shown (fmt/formatRepair text lang))

fn findRoot! dir: String depth: Int64 -> (Result String String)
  (if (<= depth 0)
    (err "no ancestor holds asl/host/build.sh")
    (if (fileExists? (str dir "/asl/host/build.sh"))
      (ok dir)
      (let [(parts (stringSplit dir "/"))]
        (if (<= (listLength parts) 1)
          (err "no ancestor holds asl/host/build.sh")
          (findRoot! (stringJoin (listTake parts (- (listLength parts) 1)) "/") (- depth 1))))))

fn repoRoot! -> (Result String String)
  (mt (pathCanonicalize ".")
    ((err _) (err "cannot canonicalize the working directory"))
    ((ok cwd) (findRoot! cwd 64)))

fn hostBinary! root: String -> String
  (run/legacyHost!)

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn createUnique! dir: String ext: String content: String attempt: Int64 -> (Result String String)
  (if (>= attempt 8)
    (err (str "could not create a unique oracle file under " dir))
    (let [(path (str dir "/out-" (stringFromInt64 (nowNs)) "-" (stringFromInt64 attempt) ext))]
      (mt (fileCreateExclusive path content)
        ((ok _) (ok path))
        ((err _) (createUnique! dir ext content (+ attempt 1))))))

fn oracleDir! root: String -> (Result String String)
  (let [(dir (str root "/scratch/formatTestOracle"))]
    (if (fileExists? dir)
      (ok dir)
      (mt (dirCreate dir)
        ((ok _) (ok dir))
        ((err e) (err (str "cannot create " dir ": " e))))))

fn hostRun! text: String lang: String -> (Result HostRun String)
  (mt (repoRoot!)
    ((err e) (err e))
    ((ok root)
     (mt (oracleDir! root)
       ((err e) (err e))
       ((ok dir)
        (mt (createUnique! dir (if (= lang "asl") ".asl" ".asn") text 0)
          ((err e) (err e))
          ((ok path)
           (let [(res (processRun (str (shellQuote (hostBinary! root)) (if (= lang "asl") " check " " parse ") (shellQuote path) " 2>&1")))]
             (mt (pathRemove path)
               ((err e) (err (str "cannot remove oracle file " path ": " e)))
               ((ok _) (ok (HostRun :exitCode res.exitCode :output (str res.stdout res.stderr))))))))))))

fn hostComplaint! text: String lang: String -> String
  (mt (hostRun! text lang)
    ((err e) (str "oracle failed to run: " e))
    ((ok r) (if (= r.exitCode 0) "" (str "exit " (stringFromInt64 r.exitCode) ": " r.output))))

fn tokenBag text: String -> (List String)
  (listSort (map (fn [(t tr/Token)] -> String (lx/tokenSliceString text t))
                 (filter (fn [(t tr/Token)] -> Bool (and (!= t.kind "whitespace") (!= t.kind "newline")))
                         (lx/tokenize text))))

fn kase input: String lang: String expected: String -> (Pair (Pair String String) String)
  (pair (pair input lang) expected)

fn inlineCases -> (List (Pair (Pair String String) String))
  (list (kase "(:data 1 2" "asn" "(:data 1 2)")
        (kase "[:a :b :c" "asn" "[:a :b :c]")
        (kase "{:a 1 :b 2" "asn" "{:a 1 :b 2}")
        (kase "#(1 2" "asn" "#(1 2)")
        (kase "#{1   2" "asn" "#{1 2}")
        (kase "(a (b (c" "asn" "(a (b (c)))")
        (kase "((1 2) (3 4" "asn" "((1 2) (3 4))")
        (kase "(:x    1   [2  3" "asn" "(:x 1 [2 3])")
        (kase "(a [b c)" "asn" "(a [b c])")
        (kase "[a (b c]" "asn" "[a (b c)]")
        (kase "{a [b c}" "asn" "{a [b c]}")
        (kase "(a {b c)" "asn" "(a {b c})")
        (kase "[a {b c]" "asn" "[a {b c}]")
        (kase "{a (b c}" "asn" "{a (b c)}")
        (kase "(]" "asn" "()")
        (kase "[)" "asn" "[]")
        (kase "{)" "asn" "{}")
        (kase "((])" "asn" "(())")
        (kase "(:a  1)   \n\n\n   (:b    2)\n\t(:t 0)\n(:c   3\n" "asn" "(:a  1)   \n\n\n   (:b    2)\n\t(:t 0)\n(:c 3)\n")
        (kase "(:a\n  1\n)\n(:b 2\n" "asn" "(:a\n  1\n)\n(:b 2)\n")
        (kase "(:a \"x\n  y   z\"\n" "asn" "(:a \"x\n  y   z\")\n")
        (kase "(:note \"fn x\" #{1 2\n" "asn" "(:note \"fn x\" #{1 2})\n")
        (kase "fn broken a: Int64 -> Int64\n  (+    a 1" "asl" "fn broken a: Int64 -> Int64\n  (+ a 1)")
        (kase "(module test :x [runTests]" "asl" "(module test :x [runTests])")
        (kase "(module test :x [runTests)" "asl" "(module test :x [runTests])")
        (kase "(:a  1)\r\n(:b   2\r\n" "asn" "(:a  1)\r\n(:b 2)\r\n")
        (kase "(a ; c\r\n(:b   2)\r\n" "asn" "(a ; c\r\n(:b 2))\r\n")
        (kase "(:x 1)\r\n(a ; c\r\n" "asn" "(:x 1)\r\n(a ; c\r\n)\r\n")
        (kase "fn broken a: Int64 -> Int64\r\n  (+    a 1\r\n" "asl" "fn broken a: Int64 -> Int64\r\n  (+ a 1)\r\n")
        (kase "fn foo -> Int64\n  (let [(a 1]\n    a)" "asl" "fn foo -> Int64\n  (let [(a 1)]\n    a)")
        (kase "fn   keep  a: Int64 -> Int64\n    (+   a  1)   \n\n\n; (:m :tags (x))   \nfn broken b: Int64 -> Int64\n  (+   b 1\n" "asl" "fn   keep  a: Int64 -> Int64\n    (+   a  1)   \n\n\n; (:m :tags (x))   \nfn broken b: Int64 -> Int64\n  (+ b 1)\n")
        (kase "fn   keep  a: Int64 -> Int64\n    (+   a  1)   \n)\n\n\nfn other -> Int64\n      7\n" "asl" "fn   keep  a: Int64 -> Int64\n    (+   a  1)   \n\n\nfn other -> Int64\n      7\n"))

fn fixtureCases -> (List (Pair String String))
  (list (pair "tests/acceptance/r1Host/reader/invalid/unclosedEofTest.asl" "(module r1Host/reader/unclosedEofTest\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  (do\n    (assert (= (listLength (list 1)) 1) \"must never execute\")\n    true)\n")
        (pair "tests/acceptance/r1Host/reader/invalid/strayParenEofTest.asl" "(module r1Host/reader/strayParenEofTest\n  :x [runTests]\n  :i [])\n\nfn runTests -> Bool\n  (do\n    (assert (= (listLength (list 1)) 1) \"must never execute\")\n    true)\n")
        (pair "asl/grammar/corpus/invalid/unbalanced.asl" "fn broken a: Int64 -> Int64\n  (+ a 1)\n")
        (pair "asl/grammar/corpus/asn/invalid/syntaxError.asn" ";; Invalid syntax ASN file with unbalanced delimiters\n(:invalidSyntax (unclosedParen))\n")
        (pair "tests/fixtures/dyck/invalid/unclosedBracket.asn" "(a [b c])\n")
        (pair "tests/fixtures/dyck/invalid/extraOpen.asn" "(a (b))\n")
        (pair "asl/grammar/corpus/asn/invalid/unbalanced.asn" "; Delimiters must balance. This is the property every streaming claim rests on:\n; a severed connection leaves the documents that already arrived readable only\n; because an unbalanced one is not a document.\n(:pool [\"a\" \"b\"] :data [(:ref 0)])\n")
        (pair "tests/fixtures/dyck/invalid/extraClose.asn" "(a b)\n")
        (pair "tests/fixtures/dyck/invalid/strayBracket.asn" "(a b)\n")
        (pair "tests/fixtures/dyck/invalid/stringHidesOpen.asn" "(:x \"(\")\n")
        (pair "tests/fixtures/dyck/invalid/commentHidesClose.asn" "(a ; )\n)\n")
        (pair "tests/fixtures/dyck/invalid/closeBeforeOpen.asn" "()\n"))

fn fixtureOutcomes! -> (List Outcome)
  (map (fn [(c (Pair String String))] -> Outcome
         (let [(path (pairFirst c))]
           (Outcome :label path
                    :input (mt (fileReadString path) ((ok s) s) ((err e) (str "<read error " e ">")))
                    :lang (mt (fmt/langForPath path) ((ok l) l) ((err e) e))
                    :expected (pairSecond c)
                    :actual (shown (fmt/formatFile! path)))))
       (fixtureCases))

fn inlineOutcomes -> (List Outcome)
  (map (fn [(c (Pair (Pair String String) String))] -> Outcome
         (let [(input (pairFirst (pairFirst c)))
               (lang (pairSecond (pairFirst c)))]
           (Outcome :label input :input input :lang lang :expected (pairSecond c) :actual (fr input lang))))
       (inlineCases))

fn failures outcomes: (List Outcome) check: (fn [Outcome] -> String) -> String
  (stringJoin (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
                      (map (fn [(o Outcome)] -> String
                             (let [(why (check o))]
                               (if (stringEmpty? why) "" (str o.label ": " why))))
                           outcomes))
              "\n")

fn textMismatch o: Outcome -> String
  (if (= o.actual o.expected) "" (str "got " o.actual))

fn tokenMismatch o: Outcome -> String
  (let [(repaired (rep/repairResultText (rep/repairAtSite o.input o.lang)))]
    (if (= (tokenBag o.actual) (tokenBag repaired)) "" (str "tokens differ from repaired input: " o.actual)))

fn hostMismatch! o: Outcome -> String
  (hostComplaint! o.actual o.lang)

fn testOutcomes! -> Bool
  (let [(all (listAppend (fixtureOutcomes!) (inlineOutcomes)))
        (badText (failures all textMismatch))
        (badTokens (failures all tokenMismatch))
        (badHost (failures all hostMismatch!))]
    (do
      (assert (stringEmpty? badText) (str "outputs equal expected canonical text:\n" badText))
      (assert (stringEmpty? badTokens) (str "outputs keep the repaired input's token multiset:\n" badTokens))
      (assert (stringEmpty? badHost) (str "outputs pass asl-host check (ASL) or parse (ASN):\n" badHost))
      (and (stringEmpty? badText) (and (stringEmpty? badTokens) (stringEmpty? badHost)))))

fn testOracleRejects! -> Bool
  (let [(astPrinterOut (hostRun! "fn foo -> Int64\n  (let (list (a 1)) a)\n" "asl"))
        (badAsn (hostRun! "(a [b c)\n" "asn"))]
    (do
      (assert (mt astPrinterOut ((ok r) (and (!= r.exitCode 0) (stringContains? r.output "ERR_UNKNOWN_SYMBOL"))) ((err _) false))
              (str "host rejects (let (list (a 1)) a): " (mt astPrinterOut ((ok r) r.output) ((err e) e))))
      (assert (mt badAsn ((ok r) (!= r.exitCode 0)) ((err _) false))
              (str "host parse rejects an unbalanced ASN frame: " (mt badAsn ((ok r) r.output) ((err e) e))))
      true))

fn testTokenBagRejects -> Bool
  (do
    (assert (!= (tokenBag "(let [(a 1)] a)") (tokenBag "(let (list (a 1)) a)")) "token bag tells [ from (list")
    true)

fn testCleanInputs -> Bool
  (let [(c1 "(+ 1 2)")
        (c2 "(let [(x 1)] (+ x 1))")
        (c3 "fn foo a: Int64 -> Int64\n  (+ a 1)")
        (c4 "fn   foo  a: Int64 -> Int64\n    (+   a  1)   \n\n\n")
        (c5 "(:a  1)   \n\n   (:b    2)\n")]
    (do
      (assert (= (fr c1 "asl") c1) "clean input (+ 1 2) is identity")
      (assert (= (fr c2 "asl") c2) "clean input let is identity")
      (assert (= (fr c3 "asl") c3) "clean input fn foo is identity")
      (assert (= (fr c4 "asl") c4) "clean non-canonical ASL is identity")
      (assert (= (fr c5 "asn") c5) "clean non-canonical ASN is identity")
      true))

fn testCallerItemsFollowed -> Bool
  (let [(given (rep/makeRepairResult "(a  (b) c)" (list (rep/makeRepairedItem "insert" ")" 1 7) (rep/makeRepairedItem "insert" ")" 1 9)) (list) ""))
        (multi (rep/makeRepairResult "(:a   1)\n(:b  2)\n" (list (rep/makeRepairedItem "insert" ")" 1 8)) (list) ""))
        (unexplained (rep/makeRepairResult "(:a   1)\n(:b  2)\n" (list (rep/makeRepairedItem "insert" ")" 2 7)) (list) ""))
        (leftOver (rep/makeRepairResult "(a" (list) (list (rep/makeLeftItem 1 1 ")" "(a")) "(:repaired () :left ((:line 1)))"))]
    (do
      (assert (= (fr "(a  (b c" "asn") "(a (b c))") "repair itself closes at the end")
      (assert (= (shown (fmt/formatText "(a  (b c" given "asn")) "(a (b) c)") "formatter follows the caller's items, not a re-run repair")
      (assert (= (shown (fmt/formatText "(:a   1\n(:b  2)\n" multi "asn")) "(:a 1)\n(:b  2)\n") "only the line the items name is re-spaced")
      (assert (err? (fmt/formatText "(:a   1\n(:b  2)\n" unexplained "asn")) "text changing a line no item names is refused")
      (assert (err? (fmt/formatText "(a" leftOver "asn")) "a result with left defects is refused")
      (assert (= (mt (fmt/formatBytes (stringToBytes "(a  (b c") given "asn")
                   ((ok bs) (bt/bytesToString bs))
                   ((err e) e))
                 "(a (b) c)")
              "formatBytes follows the caller's items")
      true))

fn testLangFromCaller! -> Bool
  (let [(asnText "(:note \"fn x\" #{1 2\n")]
    (do
      (assert (= (shown (fmt/formatText asnText (rep/repairAtSite asnText "asn") "x.asn")) "(:note \"fn x\" #{1 2})\n") "a .asn path selects asn")
      (assert (!= (rep/repairResultReceipt (rep/repair "fn f\n  (g x))\n" "asl")) (rep/repairResultReceipt (rep/repair "fn f\n  (g x))\n" "asn"))) "asl and asn repair differ on a bare fn surplus closer, so the choice is observable")
      (assert (err? (fmt/formatRepair asnText "")) "no language is an error, not a guess")
      (assert (err? (fmt/formatFile! "notes.txt")) "an unknown extension is an error")
      true))

fn ! runTests -> Bool
  (do
    (assert (testOutcomes!) "testOutcomes")
    (assert (testOracleRejects!) "testOracleRejects")
    (assert (testTokenBagRejects) "testTokenBagRejects")
    (assert (testCleanInputs) "testCleanInputs")
    (assert (testCallerItemsFollowed) "testCallerItemsFollowed")
    (assert (testLangFromCaller!) "testLangFromCaller")
    true)
