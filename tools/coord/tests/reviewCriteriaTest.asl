(module asl-tools/coord/tests/reviewCriteriaTest
  :x [runTests]
  :i [(asl-tools/coord/reviewStage :a rs) (asl-tools/coord/ladder :a l) (asl-tools/coord/tests/fixtures/pipeFix :a pf)])

; (:m :ref REVIEW-CRITERIA-DOCDUP :do "the review stage through reviewUnit! with a fake model call that records each prompt and answers per alias, no network: 1 the writer-only part of a task text (the node's RULES AND EXEMPLAR block, and a part between the writerOnly markers) is absent from the reviewers' prompt while the requirement lines around it are present; 2 a fail that cites neither the change nor the task sends no unit back: it is a reviewNoCite row and an abstention, the next rung is asked; a fail citing a changed path, a symbol of the diff or words of the task stays a fail; a verdict with both kinds keeps only the cited defect; a diff with no file header is not judged and a pass is never touched")
fn gatewayText -> String
  (str "(:gateway :v 2 :models ("
       "(:model :id flashLow :provider agy :name \"g\") (:model :id orNemotronUltraFree :provider openrouter :name \"n\") (:model :id ocLongcat :provider okSub :name \"l\")"
       "(:model :id ocDeepseekFlash :provider midSub :name \"d\") (:model :id kmK31Pro :provider kimiCode :name \"k\")))")

fn lanesText -> String
  (str "(:reviewLanes :v 1 :familyExtra \"(:f :match km :family moonshot)\" :unknown () :lanes ("
       "(:lane :alias flashLow :tier free :quality 0 :allowance 5) (:lane :alias orNemotronUltraFree :tier free :quality 0 :allowance 3)"
       "(:lane :alias ocLongcat :tier free :quality 0 :allowance 3) (:lane :alias ocDeepseekFlash :tier paid :quality 0 :allowance 5)"
       "(:lane :alias kmK31Pro :tier strong :quality 0 :allowance 3)))")

fn receipt -> String
  "(:receipt U1 :gates ((:gate g :exit 0 :executed 3)) :redBefore ((:gate g :exit 1 :executed 0)))"

; (:m :do "the shape of a node STD task text: the requirement, a blank line, then the block appended for the writer")
fn stdTask -> String
  (str "new module asl-text/base64: encode and decode (standard and url-safe alphabets, padding optional) over Bytes and Str, with RFC 4648 vectors and malformed input as Result err\n\n"
       "RULES AND EXEMPLAR (stdExemplar; write src and test in one txn, src first):\n"
       " :rules (\"write src and test in ONE (:txn ...) with the src file first; never stage the test alone: its import then fails with ERR_UNRESOLVED_IMPORT\"\n"
       "         \"if a txn aborts, read the :message line and fix that line; do not re-read the same files more than once\"))\n"
       "--- src asl/packages/asl-text/src/exampleSum.asl ---\n"
       "(module asl-text/exampleSum :x [sumDigits firstDigit] :i [])\n")

fn markedTask -> String
  (str "the parser keeps repeated keys, last wins\n--- writerOnly ---\nstage both files in ONE txn, the source first\n--- end writerOnly ---\nmalformed input is a Result err\n")

fn diffText -> String
  (str "diff --git a/asl/packages/asl-text/src/base64.asl b/asl/packages/asl-text/src/base64.asl\nnew file mode 100644\n--- /dev/null\n+++ b/asl/packages/asl-text/src/base64.asl\n@@ -0,0 +1,5 @@\n"
       "+(module asl-text/base64 :x [encode decodeWith] :i [])\n+fn encode s: String -> String\n+  s\n+fn decodeWith s: String -> String\n+  (stripPadLen s)\n")

fn unit task: String -> l/ReviewUnit
  (l/ReviewUnit :id "U1" :task task :risk "low" :closureChanged false :writerAlias "flashHigh" :writerChannel "agy" :startRung "" :fixesUsed 0 :prior (list))

fn pass -> String
  "(:verdict :pass :defects () :model m)"

fn failWith defects: (List String) -> String
  (str "(:verdict :fail :defects (" (stringJoin (map (fn [(d String)] -> String (str "\"" d "\"")) defects) " ") ") :model m)")

fn noVote -> String
  "I could not decide"

fn txnDefect -> String
  "src and test are not wrapped in a single (:txn ...) transaction as required by the rules"

fn pathDefect -> String
  "asl/packages/asl-text/src/base64.asl: trailing = signs are removed without a length check"

fn lookup replies: (List (Pair String String)) alias: String -> String
  (optionOr (listHead (map pairSecond (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) alias)) replies))) (pass))

; (:m :do "one review: nemo and cat are the answers of the two free lanes, the paid and strong lanes pass; a free lane that answers no verdict form is an abstention, so one fail beside it outvotes zero passes and is a fix; the prompts go to a file named by tag")
fn ! run root: String tag: String task: String diff: String nemo: String cat: String -> (Result rs/RevOut String)
  (rs/reviewUnit! (gatewayText) (lanesText) (list) "." (str root "/usage-" tag ".asn") (unit task) diff (receipt)
                  (fn [(a String) (p String)] -> (Result String String)
                    (let [(_ (fileAppend (str root "/prompt-" tag ".txt") (str p "\n")))]
                      (ok (lookup (list (pair "orNemotronUltraFree" nemo) (pair "ocLongcat" cat)) a)))))

fn actionOf r: (Result rs/RevOut String) -> String
  (match r ((ok o) o.action) ((err e) (str "error " e)))

fn sigOf r: (Result rs/RevOut String) -> String
  (match r ((ok o) o.sig) ((err e) e))

fn modelsOf r: (Result rs/RevOut String) -> String
  (match r ((ok o) o.models) ((err e) e))

fn rowsOf r: (Result rs/RevOut String) -> String
  (match r ((ok o) (stringJoin o.rows "\n")) ((err e) e))

fn noCite r: (Result rs/RevOut String) -> (List String)
  (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:reviewNoCite ")) (stringLines (rowsOf r)))

fn citesOf task: String d: String -> Bool
  (rs/cites? d (rs/citeCtx task (diffText)))

; (:m :ref REVIEW-CRITERIA-DOCDUP :do "words: the narrow no-break space U+202F, no-break hyphen U+2011 and the other typographic spaces and dashes a model wraps a name in separate words, so the wrapped name still matches the diff; a lone word of the shown task cites when it is camelCase or six letters not on the generic list, a generic phrase does not")
fn wrapCases -> (List String)
  (list "for  decodeWith  contains a bug" "for ‑decodeWith‑ contains a bug" "the  decodeWith call" "a decodeWith b" "x‐decodeWith–y—z")

fn ! runTests -> Bool
  (let [(root (pf/scratch "reviewCriteria" "x"))
        (_ (pf/cleanup root))
        (made (pf/sh (str "mkdir -p " root " && echo dirOk")))
        (rStd (run root "std" (stdTask) (diffText) (pass) (pass)))
        (pStd (resultOr (fileReadString (str root "/prompt-std.txt")) ""))
        (rMark (run root "mark" (markedTask) (diffText) (pass) (pass)))
        (pMark (resultOr (fileReadString (str root "/prompt-mark.txt")) ""))
        (rTxn (run root "txn" (stdTask) (diffText) (failWith (list (txnDefect))) (noVote)))
        (rPath (run root "path" (stdTask) (diffText) (failWith (list (pathDefect))) (noVote)))
        (rSym (run root "sym" (stdTask) (diffText) (failWith (list "decodeWith accepts any input")) (noVote)))
        (rTask (run root "task" (stdTask) (diffText) (failWith (list "the url-safe alphabets are not handled at all")) (noVote)))
        (rMixed (run root "mixed" (stdTask) (diffText) (failWith (list (txnDefect) (pathDefect))) (noVote)))
        (rBare (run root "bare" (stdTask) "+ a\n- b\n" (failWith (list (txnDefect))) (noVote)))
        (rPass (run root "pass" (stdTask) (diffText) "(:verdict :pass :defects (\"looks fine overall\") :model m)" (pass)))
        (leftover (fileExists? (str root "/usage-txn.asn.noCite")))
        (_ (pf/cleanup root))]
    (do (assert (stringContains? made "dirOk") "fixture: scratch dir")
        (assert (= (actionOf rStd) "merge") (str "1: two passing reviewers merge: " (actionOf rStd) " " (sigOf rStd)))
        (assert (and (stringContains? pStd "RFC 4648 vectors") (stringContains? pStd "base64.asl")) (str "1: the requirement line and the diff reach the reviewer: " (l/clip pStd 400)))
        (assert (and (not (stringContains? pStd "(:txn")) (and (not (stringContains? pStd "RULES AND EXEMPLAR")) (and (not (stringContains? pStd "re-read the same files")) (not (stringContains? pStd "exampleSum"))))) (str "1: the writer's block of a queued STD task text (how to stage, how to recover, the exemplar) is not in the reviewers' prompt: " (l/clip pStd 700)))
        (assert (and (stringContains? pMark "repeated keys, last wins") (stringContains? pMark "malformed input is a Result err")) (str "1: requirement lines before and after a writerOnly part reach the reviewer: " (l/clip pMark 400)))
        (assert (and (not (stringContains? pMark "ONE txn")) (not (stringContains? pMark "writerOnly"))) (str "1: the part between the writerOnly markers does not: " (l/clip pMark 400)))
        (assert (= (actionOf rTxn) "merge") (str "2: a fail that cites neither the change nor the task sends no unit back to the writer (alone beside an abstention it was a fix), the next rungs are asked and pass: " (actionOf rTxn) " " (sigOf rTxn)))
        (assert (stringContains? (modelsOf rTxn) "ocDeepseekFlash") (str "2: the next rung reviewed: " (modelsOf rTxn)))
        (assert (and (= (listLength (noCite rTxn)) 1) (stringContains? (rowsOf rTxn) "(:reviewNoCite :unit U1 :reviewer orNemotronUltraFree :kept 0 :text \"src and test are not wrapped in a single (:txn ...) transaction")) (str "2: one journal row names unit, reviewer and the text: " (rowsOf rTxn)))
        (assert (stringContains? (rowsOf rTxn) ":alias orNemotronUltraFree :verdict abstain") (str "2: that reviewer's call row is an abstention: " (rowsOf rTxn)))
        (assert (not leftover) "2: the note file next to the usage file is removed once its rows are in the ruling")
        (assert (and (= (actionOf rPath) "fix") (stringContains? (sigOf rPath) "trailing = signs")) (str "2: a fail citing a changed path stays a fail with its defect: " (actionOf rPath) " " (sigOf rPath)))
        (assert (listEmpty? (noCite rPath)) "2: and writes no reviewNoCite row")
        (assert (and (= (actionOf rSym) "fix") (listEmpty? (noCite rSym))) (str "2: a fail citing a symbol the diff defines stays a fail: " (actionOf rSym) " " (rowsOf rSym)))
        (assert (and (= (actionOf rTask) "fix") (listEmpty? (noCite rTask))) (str "2: a fail citing words of the task requirement stays a fail: " (actionOf rTask) " " (rowsOf rTask)))
        (assert (and (= (actionOf rMixed) "fix") (and (stringContains? (sigOf rMixed) "trailing = signs") (not (stringContains? (sigOf rMixed) "(:txn")))) (str "2: of two defects only the cited one goes to the writer: " (actionOf rMixed) " " (sigOf rMixed)))
        (assert (and (= (listLength (noCite rMixed)) 1) (stringContains? (rowsOf rMixed) ":reviewer orNemotronUltraFree :kept 1 :text \"src and test")) (str "2: the dropped one is journalled with :kept 1: " (rowsOf rMixed)))
        (assert (and (= (actionOf rBare) "fix") (listEmpty? (noCite rBare))) (str "2: a diff with no file header gives nothing to cite, the fail is not judged: " (actionOf rBare) " " (rowsOf rBare)))
        (assert (and (= (actionOf rPass) "merge") (listEmpty? (noCite rPass))) (str "2: a pass with an uncited remark stays a pass: " (actionOf rPass) " " (rowsOf rPass)))
        (assert (listAll? (fn [(d String)] -> Bool (citesOf "x" d)) (wrapCases)) (str "1: a name wrapped in U+202F, U+2011, U+00A0, U+2009, U+2010, U+2013 or U+2014 still cites the diff: " (stringJoin (filter (fn [(d String)] -> Bool (not (citesOf "x" d))) (wrapCases)) " | ")))
        (assert (not (citesOf "x" "for decodeWithOther contains a bug")) "1: a different name does not cite")
        (assert (citesOf "add a trie with insert, member, prefix search" "member is not implemented") "2: a lone requirement word of the shown task cites")
        (assert (and (not (citesOf "add a trie with insert, member, prefix search" "the code is not good enough")) (not (citesOf "make the module function return a value that should be tested against the result" "result missing, tested value, module returns"))) "2: a generic phrase cites nothing, generic words of the task do not count")
        (assert (not (citesOf "add a trie with insert, member, prefix search" "lookup is not implemented")) "2: a word that is not in the task does not cite")
        true))
