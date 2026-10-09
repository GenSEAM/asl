(module asl/agentLoop/tests/retryParityTest
  :x [runTests]
  :i [(asl/agentLoop/retry :a r) (asl/agentLoop/core :a c)])

fn getKvStr kv: (List (Pair String c/KvVal)) k: String -> String
  (mt (c/dictGet kv k)
    ((some v) (mt v ((c/kvStr s) s) ((c/kvInt s) s)))
    (none ""))

fn fixtureFloat cid: String s: String -> Float64
  (mt (stringToFloat64 s)
    ((some f) f)
    ((none) (do (assert false (str cid " invalid float fixture: " s)) 0.0)))

fn getKvInt kv: (List (Pair String c/KvVal)) k: String -> Int64
  (mt (c/dictGet kv k)
    ((some v) (mt v ((c/kvInt s) (optionOr (stringToInt64 s) 0)) ((c/kvStr s) (optionOr (stringToInt64 s) 0))))
    (none 0))

fn getKvBool kv: (List (Pair String c/KvVal)) k: String -> Bool
  (= (getKvStr kv k) "true")


fn checkCase line: String -> Bool
  (let [kv (c/parseKv line)
        cid (getKvStr kv "id")
        fnName (getKvStr kv "fn")
        want (getKvStr kv "want")]
    (cond
      ((= fnName "batchingRates")
        (let [rates (r/batchingRates (getKvInt kv "turns") (getKvInt kv "ops") (getKvInt kv "single"))
              got (str (stringFromFloat64 (pairFirst rates)) " " (stringFromFloat64 (pairSecond rates)))]
          (do (assert (= got want) (str cid " batchingRates should match")) true)))

      ((= fnName "costForm")
        (let [got (r/costForm (getKvInt kv "turns") (getKvInt kv "ops") (getKvInt kv "single") (getKvInt kv "tokens")
                               (fixtureFloat cid (getKvStr kv "wallSec")) (getKvInt kv "turnsDone"))]
          (do (assert (= got want) (str cid " costForm should match")) true)))

      ((= fnName "gateNow")
        (let [g (r/makeGateRec (getKvStr kv "gCmd") (getKvInt kv "gExit") (getKvBool kv "gTimeout")
                                (getKvInt kv "gSeconds") (getKvStr kv "gStdout") (getKvStr kv "gStderr"))
              got (r/gateNow (getKvInt kv "turn") g)]
          (do (assert (= got want) (str cid " gateNow should match")) true)))

      ((= fnName "digestLine")
        (let [rec (r/makeReceiptRec (getKvStr kv "recId") (getKvStr kv "recOp") (getKvStr kv "recKind") (getKvStr kv "recCmd")
                                     (getKvStr kv "recStdout") (getKvStr kv "recFile") (getKvStr kv "recPath") (getKvStr kv "recSymbol")
                                     (getKvStr kv "recQuery") (getKvStr kv "recTopic") (getKvStr kv "recUrl") (getKvInt kv "recExit")
                                     (getKvStr kv "recStatus") (getKvStr kv "recError") (getKvStr kv "recContent"))
              got (r/digestLine rec)]
          (do (assert (= got want) (str cid " digestLine should match")) true)))

      ((= fnName "advisorOpLine")
        (let [rec (r/makeReceiptRec (getKvStr kv "recId") (getKvStr kv "recOp") (getKvStr kv "recKind") (getKvStr kv "recCmd")
                                     (getKvStr kv "recStdout") (getKvStr kv "recFile") (getKvStr kv "recPath") (getKvStr kv "recSymbol")
                                     (getKvStr kv "recQuery") (getKvStr kv "recTopic") (getKvStr kv "recUrl") (getKvInt kv "recExit")
                                     (getKvStr kv "recStatus") (getKvStr kv "recError") (getKvStr kv "recContent"))
              got (r/advisorOpLine rec)]
          (do (assert (= got want) (str cid " advisorOpLine should match")) true)))

      ((= fnName "advisorGateOutput")
        (let [g (r/makeGateRec (getKvStr kv "gCmd") (getKvInt kv "gExit") (getKvBool kv "gTimeout")
                                (getKvInt kv "gSeconds") (getKvStr kv "gStdout") (getKvStr kv "gStderr"))
              got (r/advisorGateOutput g)]
          (do (assert (= got want) (str cid " advisorGateOutput should match")) true)))

      ((= fnName "advisorSkip")
        (let [retries (list (pair (getKvStr kv "retryKind") (getKvInt kv "retryCount")))
              got (r/advisorSkip (getKvStr kv "why") retries (getKvInt kv "parseDefectCount"))]
          (do (assert (= got want) (str cid " advisorSkip should match")) true)))

      ((= fnName "parseAdvice")
        (let [got (mt (r/parseAdvice (getKvStr kv "text"))
                    ((none) "(none)")
                    ((some a) (str "(some \"" (r/escapeAsn (r/adviceNext a)) "\" "
                                    (mt (r/adviceWhy a) ((some w) (str "(some \"" (r/escapeAsn w) "\")")) ((none) "(none)"))
                                    " "
                                    (mt (r/adviceAvoid a) ((some w) (str "(some \"" (r/escapeAsn w) "\")")) ((none) "(none)"))
                                    ")")))]
          (do (assert (= got want) (str cid " parseAdvice should match")) true)))

      ((= fnName "parseSpecVerdict")
        (let [got (mt (r/parseSpecVerdict (getKvStr kv "text"))
                    ((none) "(none)")
                    ((some v) (str "(some " (if (r/verdictMet v) "true" "false") " ( "
                                    (stringJoin (map (fn [m] (str "\"" (r/escapeAsn m) "\"")) (r/verdictMissing v)) " ") "))")))]
          (do (assert (= got want) (str cid " parseSpecVerdict should match")) true)))

      ((= fnName "noWriteNudge")
        (let [filesStr (getKvStr kv "files")
              files (if (stringEmpty? filesStr) (list) (stringSplit filesStr " "))
              winStr (getKvStr kv "winWhole")
              winWhole (if (stringEmpty? winStr) (list) (map (fn [s] (optionOr (stringToInt64 s) 0)) (stringSplit winStr " ")))
              redGateStr (getKvStr kv "redGate")
              redGateOpt (if (stringEmpty? redGateStr) none (some redGateStr))
              got (r/noWriteNudge (getKvStr kv "deliver") (getKvBool kv "wrote") (getKvInt kv "done")
                                  files winWhole (getKvInt kv "readStreak") redGateOpt)]
          (do (assert (= got want) (str cid " noWriteNudge should match")) true)))

      ((= fnName "advisorSummary")
        (let [got (cond
                    ((= cid "adv_all_green")
                      (let [lintG (r/makeGateRec "lint.sh" 0 false -1 "" "")
                            testG (r/makeGateRec "test.sh" 0 false -1 "" "")
                            lg (list (pair "lint.sh" (pair 1 lintG)) (pair "test.sh" (pair 2 testG)))]
                        (r/advisorSummary "fix the bug" "patch" "6 turns without a write while gate g1 is red"
                                          (list "lint.sh" "test.sh") lg (list "a.py") (evdReceipts) "")))
                    (else ""))]
          (do (assert (= got want) (str cid " advisorSummary should match")) true)))

      ((= fnName "buildRetryBrief")
        (let [got (cond
                    ((= cid "brb_gate_timeout")
                      (let [g (r/makeGateRec (getKvStr kv "gCmd") (getKvInt kv "gExit") (getKvBool kv "gTimeout")
                                             (getKvInt kv "gSeconds") "" "")]
                        (r/buildRetryBrief 1 false none none none 0 none (list g) none 0 none (list) (list) 0 (list) (list) "")))
                    ((= cid "brb_all_gates_green")
                      (let [g (r/makeGateRec (getKvStr kv "gCmd") (getKvInt kv "gExit") (getKvBool kv "gTimeout")
                                             (getKvInt kv "gSeconds") "" "")]
                        (r/buildRetryBrief 1 false none none none 0 none (list g) none 0 none (list) (list) 0 (list) (list) "")))
                    ((= cid "brb_undeclared_ops")
                      (r/buildRetryBrief 1 false none none none 0 none (list) none 0 none (list) (list) 0 (list)
                                         (list (getKvStr kv "undLine")) (getKvStr kv "shapes")))
                    (else ""))]
          (do (assert (= got want) (str cid " buildRetryBrief should match")) true)))

      (else true)))


fn checkEscalation -> Bool
  (do
    (assert (= (r/escalationNear 1 20 (list (pair "steps" 0)) 3 (list) 0 0 false 0 false) "")
      "esc_turn1")
    (assert (= (r/escalationNear 5 20 (list (pair "steps" 3) (pair "gate" 0)) 3 (list) 0 0 false 0 false) "one more steps miss escalates")
      "esc_retry_spent")
    (assert (= (r/escalationNear 5 20 (list (pair "steps" 0)) 3 (list (pair "sig1" 2)) 0 0 false 0 false) "one more repeat of the same failure escalates")
      "esc_failure_cap")
    (assert (= (r/escalationNear 5 20 (list (pair "steps" 0)) 3 (list) 2 0 false 0 false) "one more turn without new evidence escalates")
      "esc_stalled")
    (assert (= (r/escalationNear 5 20 (list (pair "steps" 0)) 3 (list) 0 3 false 0 false) "one more parse defect escalates")
      "esc_parsedefects")
    (assert (= (r/escalationNear 5 20 (list (pair "steps" 0)) 3 (list) 0 0 false 11 true) "one more turn without a write while a gate is red escalates")
      "esc_redgate")
    (assert (= (r/escalationNear 10 20 (list (pair "steps" 0)) 3 (list) 0 0 true 0 false) "the run stops without a write after this turn")
      "esc_nowrite_stop")
    true)

fn checkReinforce -> Bool
  (do
    (assert (= (r/reinforceWhyFor false (list (list "a" "b") (list "b" "c")) "patch" true 0 5 20 (list (pair "steps" 0)) 3 (list) 0 0 none)
                "same gate failure twice in a row: b")
      "rf_twice")
    (assert (= (r/reinforceWhyFor true (list) "patch" true 0 5 20 (list (pair "steps" 0)) 3 (list) 0 0 none)
                "the last reply was a parse defect")
      "rf_parsedefect")
    (assert (= (r/reinforceWhyFor false (list) "patch" true 0 5 20 (list (pair "steps" 0)) 3 (list) 0 6 (some "g1"))
                "6 turns without a write while gate g1 is red")
      "rf_redgate")
    (assert (= (r/reinforceWhyFor false (list) "patch" false 2 5 20 (list (pair "steps" 0)) 3 (list) 0 0 none)
                "patch deliverable and nothing written after 4 turns")
      "rf_patch_nowrite")
    (assert (= (r/reinforceWhyFor false (list) "patch" true 0 10 20 (list (pair "steps" 0)) 3 (list) 0 0 none) "")
      "rf_fallback")
    true)

fn checkNowForm -> Bool
  (let [gTest (r/makeGateRec "test.sh" 0 false -1 "(:gate x :asserts 2 :failed 0)\n" "")
        fullGot (r/nowForm 5 8000 (some (pair 1234 "(:receipt :id 1)")) (list "a.py" "b.py")
                           (list (pair 3 gTest)) (list (pair "steps" 2) (pair "gate" 1))
                           "write something" "(:turns 5)" "(:plan (:step :id s1 :do d1))")
        minimalGot (r/nowForm 1 8000 none (list) (list) (list) "" "" "")]
    (do
      (assert (= fullGot "(:now :turn 5 :context (:tokens 8000 :usedBytes 1234) :cost (:turns 5) :plan (:plan (:step :id s1 :do d1)) :noWrite \"write something\" :written (\"a.py\" \"b.py\") :gates ((:cmd \"test.sh\" :turn 3 :exit 0 :asserts 2 :failed 0)) :retriesLeft (:steps 2 :gate 1) :last (:receipt :id 1))")
        "now_full")
      (assert (= minimalGot "(:now :turn 1 :context (:tokens 8000 :usedBytes 0) :retriesLeft ())")
        "now_minimal")
      true))

fn checkNoWriteNudge -> Bool
  (do
    (assert (= (r/noWriteNudge "patch" false 5 (list "a.py") (list 1 2 3) 6 (some "g1"))
                "6 turns without a write while gate g1 is red: write the fix you have, or escalate naming what is missing")
      "nwn_redgate")
    (assert (= (r/noWriteNudge "plan" false 15 (list) (list) 0 none) "") "nwn_not_patch")
    (assert (= (r/noWriteNudge "patch" true 15 (list) (list) 0 none) "") "nwn_wrote")
    (assert (= (r/noWriteNudge "patch" false 12 (list "a.py" "b.py") (list 1 3 5) 0 none)
                "12 turns and nothing written; files read: a.py, b.py; receipts still whole: turns 1 3 5; the run stops at turn 20 without a write")
      "nwn_full")
    (assert (= (r/noWriteNudge "patch" false 5 (list "a.py") (list 1 2) 0 none) "")
      "nwn_done_under_nudge")
    true)

fn checkBuildRetryBrief -> Bool
  (let [lintGate (r/makeGateRec "lint.sh" 0 false -1 "(:gate x :asserts 1 :failed 0)\n" "")
        testGate (r/makeGateRec "test.sh" 1 false -1 "(:gate x :asserts 3 :failed 1)\nFAIL: something broke\n" "")
        line1 "(:receipt :id \"abc123\" :op \"note\" :status :ok :chars 10)"
        brb1 (r/buildRetryBrief 2 false none none none 0 none
               (list lintGate testGate)
               (some "src/x.py") 42 (some "assert false")
               (list (pair 2 "test.sh"))
               (list line1)
               1 (list "\"caching layer untested\"")
               (list) "")
        brb1Want (str "Retry 2:\n\ngate 2 of 2: \"test.sh\", exit code: 1\n\n"
                      "gate 2 output (last 20 lines, at most 2000 chars):\n(:gate x :asserts 3 :failed 1)\nFAIL: something broke\n\n"
                      "the failing assert is one this run wrote in src/x.py line 42: assert false; if it is a placeholder, replace it with a real check of the behaviour\n\n"
                      "gate 2 runs test.sh, which does not exist: create it (a real test first, red on the missing behaviour)\n\n"
                      "turn op receipts:\n(:receipt :id \"abc123\" :op \"note\" :status :ok :chars 10)\n\n"
                      "unbacked claims (1): \"caching layer untested\"")
        brb2 (r/buildRetryBrief 1 true none none none 0 none (list) none 0 none (list) (list) 0 (list) (list) "")
        brb3 (r/buildRetryBrief 3 false (some "not valid asn (((") (some "form opened at char 14 and never closes: \"not valid asn (((\"")
               none 0 none (list) none 0 none (list) (list) 0 (list) (list) "")
        brb3Want (str "Retry 3:\n\nreply was not parseable ASN: \"not valid asn (((\"\n\n"
                      "form opened at char 14 and never closes: \"not valid asn (((\"\n\n"
                      "accepted op forms:\n  \nfor code with quotes, backslashes or many lines, use :raw and a fenced block; nothing inside the block is escaped.")
        brb4 (r/buildRetryBrief 1 false none none (some "a.py") 7 (some "catch specific errors")
               (list) none 0 none (list) (list) 0 (list) (list) "")
        timeoutGate (r/makeGateRec "slow.sh" 1 true 30 "" "")
        brbTimeout (r/buildRetryBrief 1 false none none none 0 none (list timeoutGate) none 0 none (list) (list) 0 (list) (list) "")
        brbTimeoutWant "Retry 1:\n\ngate 1 of 1: \"slow.sh\", timed out after 30 s (:timeout true :seconds 30): killed by the run's :gateTimeout, not a failing exit"
        greenGate (r/makeGateRec "test.sh" 0 false -1 "ok" "")
        brbAllGreen (r/buildRetryBrief 1 false none none none 0 none (list greenGate) none 0 none (list) (list) 0 (list) (list) "")
        brbAllGreenWant "Retry 1:\n\ngate 1 of 1: \"test.sh\", exit code: 0"
        undLine "unknown op 'foobar': no declared op is near; a :implement run ends with (:done) or (:escalate :reason s)"
        brbUnd (r/buildRetryBrief 1 false none none none 0 none (list) none 0 none (list) (list) 0 (list) (list undLine) "")
        brbUndWant (str "Retry 1:\n\n" undLine "\n\naccepted op forms:\n  \nfor code with quotes, backslashes or many lines, use :raw and a fenced block; nothing inside the block is escaped.")]
    (do
      (assert (= brb1 brb1Want) "brb1")
      (assert (= brb2 "Retry 1:\n\nyour reply was cut at the output token ceiling: send fewer steps and less prose") "brb2")
      (assert (= brb3 brb3Want) "brb3")
      (assert (= brb4 "Retry 1:\n\nswallowed error in a.py line 7: catch specific errors") "brb4")
      (assert (= brbTimeout brbTimeoutWant) "brb_gate_timeout")
      (assert (= brbAllGreen brbAllGreenWant) "brb_all_gates_green")
      (assert (= brbUnd brbUndWant) "brb_undeclared_ops")
      true))

fn evdReceipts -> (List r/ReceiptRec)
  (list
    (r/makeReceiptRec "r1" "read" "" "" "" "a.py" "" "" "" "" "" 0 "" "" "")
    (r/makeReceiptRec "r2" "edit" "" "" "" "b.py" "" "" "" "" "" 0 "" "" "")
    (r/makeReceiptRec "r3" "observe" "" "" "(:observe :dim callers :count (:calls 2 :possible 0 :excluded 0))" "" "" "" "" "" "" -1 "" "" ""))

fn checkEvidenceDigest -> Bool
  (let [receipts (evdReceipts)
        normalGot (r/evidenceDigest receipts 12000)
        smallGot (r/evidenceDigest receipts 90)]
    (do
      (assert (= normalGot (str "(:receipt :id \"r1\" :op \"read\" :target \"a.py\" :exit 0)\n"
                                 "(:receipt :id \"r2\" :op \"edit\" :target \"b.py\" :exit 0)\n"
                                 "(:receipt :id \"r3\" :op \"observe\" :target \"callers\" :ok :count (:calls 2 :possible 0 :excluded 0))"))
        "evd_normal")
      (assert (= smallGot "[3 older receipt lines cut]\n") "evd_small_cap")
      true))

fn checkAdvisorSummary -> Bool
  (let [lintGate (r/makeGateRec "lint.sh" 0 false -1 "" "")
        testGate (r/makeGateRec "test.sh" 1 false -1 "FAIL something\nmore output\n" "")
        lastGates (list (pair "lint.sh" (pair 2 lintGate)) (pair "test.sh" (pair 3 testGate)))
        got (r/advisorSummary "fix the bug" "patch" "patch deliverable and nothing written after 4 turns"
              (list "lint.sh" "test.sh") lastGates (list "a.py") (evdReceipts) "")
        want (str "task:\nfix the bug\n\ndeliverable: patch\nstuck because: patch deliverable and nothing written after 4 turns\n"
                  "gates:\n1 lint.sh :exit 0\n2 test.sh :exit 1\n"
                  "last red gate output (test.sh), last 2 lines:\nFAIL something\nmore output\n"
                  "files written: a.py\nlast ops, oldest first:\nread a.py :exit 0\nedit b.py :exit 0\nobserve :ok\n")
        got2 (r/advisorSummary "task text" "patch" "the last reply was a parse defect"
               (list) (list) (list) (list) "Retry 3:\n\nreply was not parseable ASN")
        want2 (str "task:\ntask text\n\ndeliverable: patch\nstuck because: the last reply was a parse defect\n"
                   "last retry brief head: Retry 3:\n\nreply was not parseable ASN\n"
                   "gates:\n(none declared)\nfiles written: (none)\nlast ops, oldest first:\n(none)\n")
        greenTestGate (r/makeGateRec "test.sh" 0 false -1 "" "")
        greenLastGates (list (pair "lint.sh" (pair 1 lintGate)) (pair "test.sh" (pair 2 greenTestGate)))
        gotGreen (r/advisorSummary "fix the bug" "patch" "6 turns without a write while gate g1 is red"
                   (list "lint.sh" "test.sh") greenLastGates (list "a.py") (evdReceipts) "")
        wantGreen (str "task:\nfix the bug\n\ndeliverable: patch\nstuck because: 6 turns without a write while gate g1 is red\n"
                       "gates:\n1 lint.sh :exit 0\n2 test.sh :exit 0\n"
                       "files written: a.py\nlast ops, oldest first:\nread a.py :exit 0\nedit b.py :exit 0\nobserve :ok\n")]
    (do
      (assert (= got want) "adv_summary")
      (assert (= got2 want2) "adv_summary_parsedefect")
      (assert (= gotGreen wantGreen) "adv_summary_allgreen")
      true))

fn checkComplexCases -> Bool
  (and (checkEscalation)
    (and (checkReinforce)
      (and (checkNowForm)
        (and (checkNoWriteNudge)
          (and (checkBuildRetryBrief)
            (and (checkEvidenceDigest) (checkAdvisorSummary)))))))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        content (resultOr (fileReadString (str root "/asl/agentLoop/tests/retryParityFixture.asn")) "")
        lines (filter (fn [l] (stringStartsWith? l "(:case ")) (stringLines content))
        n (listLength lines)]
    (do
      (assert (>= n 40) "the retry parity fixture holds at least 40 cases")
      (assert (checkComplexCases) "the hand-verified list-shaped cases passed")
      (fold (fn [acc line] (and (checkCase line) acc)) true lines)))
