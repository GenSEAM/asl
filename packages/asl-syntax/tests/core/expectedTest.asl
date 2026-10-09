(module asl-syntax/tests/core/expectedTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/asl/paren :a prn)
      (asl-syntax/asl/layout :a lay)])

fn insertToken text: String offset: Int64 tok: String -> String
  (let [(len (stringLength text))
        (prefix (optionOr (stringSlice text 0 offset) ""))
        (suffix (optionOr (stringSlice text offset len) ""))]
    (str prefix tok suffix))

fn applyMissingFixesLoop text: String fixes: (List tr/Missing) -> String
  (if (listEmpty? fixes)
    text
    (let [(m (optionOr (listHead fixes) (tr/makeMissing -1 "")))
          (rest (optionOr (listTail fixes) (list)))
          (off (tr/missingOffset m))
          (tok (tr/missingText m))
          (nextText (insertToken text off tok))]
      (applyMissingFixesLoop nextText rest)))

fn repairAllMissing text: String fixes: (List tr/Missing) -> String
  (applyMissingFixesLoop text (listReverse fixes))

fn deleteSpan text: String start: Int64 end: Int64 -> String
  (let [(len (stringLength text))
        (prefix (optionOr (stringSlice text 0 start) ""))
        (suffix (optionOr (stringSlice text end len) ""))]
    (str prefix suffix))

fn applyDeleteFixesLoop text: String deletes: (List tr/Delete) -> String
  (if (listEmpty? deletes)
    text
    (let [(d (optionOr (listHead deletes) (tr/makeDelete -1 -1)))
          (rest (optionOr (listTail deletes) (list)))
          (start (tr/deleteStart d))
          (end (tr/deleteEnd d))
          (nextText (if (and (>= start 0) (<= start end))
                      (deleteSpan text start end)
                      text))]
      (applyDeleteFixesLoop nextText rest)))

fn repairAll text: String fixes: (List tr/Missing) deletes: (List tr/Delete) -> String
  (let [(afterDeletes (applyDeleteFixesLoop text (listReverse deletes)))]
    (applyMissingFixesLoop afterDeletes (listReverse fixes)))

fn verifyParenMissing text: String expectedTok: String expectedOffset: Int64 label: String -> Bool
  (let [(root (prn/parse text))]
    (assert (prn/hasErrors root) (str label ": input must have errors"))
    (let [(misList (tr/treeMissing root))]
      (assert (not (listEmpty? misList)) (str label ": tree must carry at least one Missing"))
      (let [(mis (optionOr (listHead misList) (tr/makeMissing -1 "")))
            (off (tr/missingOffset mis))
            (tok (tr/missingText mis))]
        (assert (= off expectedOffset) (str label ": expected offset " (stringFromInt64 expectedOffset) " got " (stringFromInt64 off)))
        (assert (= tok expectedTok) (str label ": expected token " expectedTok " got " tok))
        (let [(repairedText (repairAllMissing text misList))
              (repairedRoot (prn/parse repairedText))]
          (assert (not (prn/hasErrors repairedRoot)) (str label ": repaired text must parse clean"))
          (assert (= (pr/print repairedText repairedRoot) repairedText) (str label ": repaired text must round-trip print"))
          true))))

fn verifyLayoutMissing text: String expectedTok: String expectedOffset: Int64 label: String -> Bool
  (let [(root (lay/parse text))]
    (assert (lay/hasErrors root) (str label ": input must have errors"))
    (let [(misList (tr/treeMissing root))]
      (assert (not (listEmpty? misList)) (str label ": tree must carry at least one Missing"))
      (let [(mis (optionOr (listHead misList) (tr/makeMissing -1 "")))
            (off (tr/missingOffset mis))
            (tok (tr/missingText mis))]
        (assert (= off expectedOffset) (str label ": expected offset " (stringFromInt64 expectedOffset) " got " (stringFromInt64 off)))
        (assert (= tok expectedTok) (str label ": expected token " expectedTok " got " tok))
        (let [(repairedText (repairAllMissing text misList))
              (repairedRoot (lay/parse repairedText))]
          (assert (not (lay/hasErrors repairedRoot)) (str label ": repaired text must parse clean"))
          (assert (= (pr/print repairedText repairedRoot) repairedText) (str label ": repaired text must round-trip print"))
          true))))

fn testAsnUnclosedDelimiters -> Bool
  (and (verifyParenMissing "(:data 1 2" ")" 10 "asn unclosed list")
  (and (verifyParenMissing "[:a :b :c" "]" 9 "asn unclosed vector")
  (and (verifyParenMissing "{:a 1 :b 2" "}" 10 "asn unclosed map")
  (and (verifyParenMissing "(" ")" 1 "asn lone open paren")
  (and (verifyParenMissing "[" "]" 1 "asn lone open bracket")
  (and (verifyParenMissing "{" "}" 1 "asn lone open brace")
  (and (verifyParenMissing "(:pool [\"a\" \"b\"] :data [(:ref 0)" "]" 32 "asn nested unclosed bracket")
  (and (verifyParenMissing "(a (b)" ")" 6 "asn nested unclosed paren")
       (verifyParenMissing "(:invalidSyntax (unclosedParen" ")" 30 "asn syntaxError unclosed")))))))))

fn testAsnMismatchedDelimiters -> Bool
  (and (verifyParenMissing "(a [b c)" "]" 7 "mismatched bracket in list")
  (and (verifyParenMissing "[a (b c]" ")" 7 "mismatched paren in vector")
  (and (verifyParenMissing "{a [b c}" "]" 7 "mismatched bracket in map")
  (and (verifyParenMissing "(a {b c)" "}" 7 "mismatched brace in list")
  (and (verifyParenMissing "[a {b c]" "}" 7 "mismatched brace in vector")
  (and (verifyParenMissing "{a (b c}" ")" 7 "mismatched paren in map")
  (and (verifyParenMissing "(:pool [1 2 3)" "]" 13 "mismatched vector in record")
       (verifyParenMissing "(a [b c)" "]" 7 "dyck unclosedBracket case"))))))))

fn verifyImmediateMismatch text: String expectedTok: String expectedOffset: Int64 label: String -> Bool
  (let [(root (prn/parse text))]
    (assert (prn/hasErrors root) (str label ": input must have errors"))
    (let [(misList (tr/treeMissing root))]
      (assert (not (listEmpty? misList)) (str label ": tree must carry at least one Missing"))
      (let [(mis (optionOr (listHead misList) (tr/makeMissing -1 "")))
            (off (tr/missingOffset mis))
            (tok (tr/missingText mis))]
        (assert (= off expectedOffset) (str label ": expected offset " (stringFromInt64 expectedOffset) " got " (stringFromInt64 off)))
        (assert (= tok expectedTok) (str label ": expected token " expectedTok " got " tok))
        (let [(delList (tr/treeDeletes root))]
          (assert (not (listEmpty? delList)) (str label ": tree must carry at least one Delete"))
          (let [(repairedText (repairAll text misList delList))
                (repairedRoot (prn/parse repairedText))]
            (assert (not (prn/hasErrors repairedRoot)) (str label ": repaired text must parse clean"))
            (assert (= (pr/print repairedText repairedRoot) repairedText) (str label ": repaired text must round-trip print"))
            true)))))

fn testImmediateMismatchedDelimiters -> Bool
  (and (verifyImmediateMismatch "(]" ")" 1 "immediate mismatched (]")
  (and (verifyImmediateMismatch "[)" "]" 1 "immediate mismatched [)")
  (and (verifyImmediateMismatch "{)" "}" 1 "immediate mismatched {)")
       (verifyImmediateMismatch "((])" ")" 2 "nested immediate mismatched ((])"))))

fn testAslParenDelimiters -> Bool
  (and (verifyParenMissing "(+ 1 (* 2 3)" ")" 12 "asl paren unclosed mult")
  (and (verifyParenMissing "(fn [(a Int64] a)" ")" 13 "asl paren mismatched lambda param")
       (verifyParenMissing "(let [(x 1]" ")" 10 "asl paren let binding unclosed")))

fn testAslLayoutDelimiters -> Bool
  (and (verifyLayoutMissing "fn broken a: Int64 -> Int64\n  (+ a 1" ")" 36 "layout unbalanced fn body")
  (and (verifyLayoutMissing "(module test :x [runTests]" ")" 26 "layout unclosed module header")
  (and (verifyLayoutMissing "(module test :x [runTests)" "]" 25 "layout mismatched header vector")
       (verifyLayoutMissing "fn foo -> Int64\n  (let [(a 1]\n    a)" ")" 28 "layout nested mismatched let"))))

fn testTreeMissingAPI -> Bool
  (let [(m (tr/makeMissing 42 ")"))]
    (assert (= (tr/missingOffset m) 42) "missingOffset must equal 42")
    (assert (= (tr/missingText m) ")") "missingText must equal paren")
    (assert (= (tr/missingTok m) ")") "missingTok must equal paren")
    (let [(misNode (tr/makeMissingNode 15 "]"))]
      (assert (tr/isMissingNode misNode) "isMissingNode on makeMissingNode must be true")
      (assert (= (tr/missingNodeOffset misNode) 15) "missingNodeOffset must equal 15")
      (assert (= (tr/missingNodeText misNode) "]") "missingNodeText must equal bracket")
      (let [(errNode (tr/makeErrorNodeWithMissing 0 10 (list) m))]
        (assert (tr/isErrorNode errNode) "errNode must be error node")
        (let [(errMisOpt (tr/nodeMissing errNode))]
          (assert (some? errMisOpt) "errNode nodeMissing must be some")
          (mt errMisOpt
            ((some em)
             (do
               (assert (= (tr/missingOffset em) 42) "errNode missing offset matches")
               (assert (= (tr/missingText em) ")") "errNode missing text matches")
               true))
            ((none) (assert false "unreachable missing none")))))))

fn checkFixtureFile! path: String isLayout: Bool -> Bool
  (mt (fileReadString path)
    ((err e) (assert false (str "read error for " path ": " e)))
    ((ok content)
     (let [(root (if isLayout (lay/parse content) (prn/parse content)))]
       (assert (if isLayout (lay/hasErrors root) (prn/hasErrors root)) (str path " has errors"))
       (let [(misList (if isLayout (tr/treeMissing root) (tr/treeMissing root)))]
         (assert (not (listEmpty? misList)) (str path " has Missing"))
         (let [(repText (repairAllMissing content misList))
               (repRoot (if isLayout (lay/parse repText) (prn/parse repText)))]
           (assert (not (if isLayout (lay/hasErrors repRoot) (prn/hasErrors repRoot))) (str path " repaired parses clean"))
           true)))))

fn testFixtureFilesMissing! -> Bool
  (and (checkFixtureFile! "asl/grammar/corpus/invalid/unbalanced.asl" true)
  (and (checkFixtureFile! "asl/grammar/corpus/asn/invalid/syntaxError.asn" false)
  (and (checkFixtureFile! "tests/fixtures/dyck/invalid/unclosedBracket.asn" false)
  (and (checkFixtureFile! "tests/fixtures/dyck/invalid/extraOpen.asn" false)
  (and (checkFixtureFile! "asl/grammar/corpus/asn/invalid/unbalanced.asn" false)
       (checkFixtureFile! "tests/acceptance/r1Host/reader/invalid/unclosedEofTest.asl" true))))))

fn ! runTests -> Bool
  (and (testTreeMissingAPI)
  (and (testAsnUnclosedDelimiters)
  (and (testAsnMismatchedDelimiters)
  (and (testImmediateMismatchedDelimiters)
  (and (testAslParenDelimiters)
  (and (testAslLayoutDelimiters)
       (testFixtureFilesMissing!)))))))
