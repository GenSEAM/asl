(module asl/agentLoop/tests/mainReceiptTest
  :x [runTests]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/plan :a pl) (asl/agentLoop/gitOps :a go) (asl-json/json :a j)])

fn ! write path: String content: String -> Bool
  (mt (fileWrite path content)
    ((err _) false)
    ((ok _) true))

fn jsonOf text: String -> j/Json
  (resultOr (j/jsonParse text) (j/jnull))

fn jsonItems v: j/Json -> (List j/Json)
  (mt v ((j/jarr xs) xs) (_ (list)))

fn optText o: (Option String) -> j/Json
  (mt o ((some s) (j/jstr s)) ((none) (j/jnull)))

fn optInt o: (Option Int64) -> j/Json
  (mt o ((some n) (j/jint n)) ((none) (j/jnull)))

fn strings xs: (List String) -> j/Json
  (j/jarr (map (fn [x] (j/jstr x)) xs))

fn resumeLine r: (Result m/ResumeState String) -> String
  (mt r
    ((err e) e)
    ((ok st)
      (j/jsonEmit
        (j/jarr (list (j/jstr st.journal) (j/jstr st.task) (optText st.modeHint) (optText st.intent)
                      (strings st.owns) (strings st.gates) (j/jstr st.base) (optInt st.contextTokens)
                      (j/jstr st.note) (optText st.result)
                      (j/jarr (map (fn [h] (j/jarr (list (j/jint h.turn) (j/jstr h.sent) (j/jstr h.got)))) st.history))
                      (j/jint st.turn) (j/jstr st.reply)
                      (j/jbool (mt st.plan ((some _) true) ((none) false))))))))

fn minimalResult -> m/LoopResult
  (m/LoopResult :status "ok" :modeHint none :deliver none :phases (list) :session none :journal none :unbacked 0
                :unbackedClaims (list) :contextTokens none :turns none :gates (list) :escalate none :patch none
                :restored (list) :written (list) :needsConfirm (list) :ownsRejected (list) :error none :gatePreflight (list)
                :parseDefect false :parseDefectTurn none :findings none :queueWaitSec none :execSec none :usage none
                :batching none :plan none)

fn fullGates -> String
  "[{\"cmd\":\"echo \\\"a\\\"\",\"exit\":0},{\"cmd\":\"sleep 9\",\"timeout\":true,\"seconds\":5}]"

fn fullResult -> m/LoopResult
  (m/LoopResult :status "partial" :modeHint (some "sco\"ut") :deliver (some "patch") :phases (list "scout" "plan")
                :session (some "abc123") :journal (some ".asl/run/agentLoop/abc123.journal") :unbacked 2
                :unbackedClaims (list "claim one" "c\"2") :contextTokens (some 64000) :turns (some 3)
                :gates (jsonItems (jsonOf (fullGates)))
                :escalate (some ":reason \"stuck\"") :patch (some "diff text") :restored (list "a.txt")
                :written (list "b.txt" "c d")
                :needsConfirm (list (m/NeedsConfirm :op "push" :error "") (m/NeedsConfirm :op "deploy" :error "ERR_X"))
                :ownsRejected (list (m/OwnsRejection :turn 2 :op "write" :file "x\"y"))
                :error (some "ERR_Z")
                :gatePreflight (list (list (pair "n" (go/rInt 1)) (pair "cmd" (go/rStr "a\"b")) (pair "message" (go/rStr "bad"))))
                :parseDefect true :parseDefectTurn (some 4) :findings (some (list " f1 " "" "  " "(:f 2)"))
                :queueWaitSec (some 0.1) :execSec (some 2.0) :usage (some (m/Usage :input 10 :cached 3 :output 5))
                :batching (some (m/Batching :turns 4 :ops 6 :single 2)) :plan (some (pl/summaryOf 3 1 1 0)))

fn edgeResult -> m/LoopResult
  (m/LoopResult :status "failed" :modeHint (some "") :deliver (some "") :phases (list) :session (some "") :journal (some "")
                :unbacked 0 :unbackedClaims (list) :contextTokens (some 0) :turns (some 0) :gates (list) :escalate (some "")
                :patch (some "") :restored (list) :written (list) :needsConfirm (list) :ownsRejected (list) :error (some "")
                :gatePreflight (list) :parseDefect true :parseDefectTurn none :findings (some (list)) :queueWaitSec (some 0.0)
                :execSec none :usage (some (m/Usage :input 0 :cached 0 :output 0))
                :batching (some (m/Batching :turns 0 :ops 0 :single 0)) :plan (some (pl/summaryOf 0 0 0 0)))

fn sessions -> (List String)
  (list "full" "legacy" "hints" "noTurn" "endedOk" "a..b" "missing" "bad id")

fn headers -> (List String)
  (list "(:session :id \"s\" :task \"t\" :modeHint \"re\\\"view\" :mode :scout)"
        "(:session :id \"s\" :task \"t\" :mode :auto)"
        "(:session :id \"s\" :task \"t\" :mode :scout)"
        "(:session :id \"s\" :task \"has :modeHint \\\"x\\\" and :mode :fix\")"
        "(:session :id \"s\" :task \"t\" :modeHint  \"spaced\")"
        "(:session :id \"s\" :task \"t\")")

fn misspelt -> (List String)
  (list "aa" "badKey" "z" "x" "gatesTimeout" "mode2" "plans" "owner" "rot" "tsk" "gate")

fn journals -> (List (Pair String String))
  (list (pair "full" (str "(:session :id \"full\" :task \"fix \\\"it\\\"\" :modeHint \"patch\" :intent \"review\" :root \"/r\" :owns (\"a.txt\" \"b c\") :gates (\"echo \\\"x\\\"\") :base \"main\" :model \"m\" :contextTokens 64000 :plan true)\n"
                          "(:turn 1 :reply \"(:read \\\"a\\\")\")\n"
                          "(:turn 1 :observation \"got a\")\n"
                          "(:turn 1 :note \"first\")\n"
                          "(:turn 2 :reply \"(:write)\")\n"
                          "(:turn 2 :note \"second \\\"q\\\"\")\n"
                          "(:result :status :partial :session \"full\")\n"))
        (pair "legacy" (str "(:session :id \"legacy\" :task \"old\" :mode :auto :intent \"auto\" :owns () :gates ())\n"
                            "(:turn 3 :reply \"three\")\n"
                            "(:turn 1 :reply \"one\")\n"
                            "(:turn 1 :retryBrief \"brief\")\n"
                            "(:turn 2 :answer \"no reply\")\n"))
        (pair "hints" (str "(:session :id \"hints\" :task \"say :modeHint \\\"x\\\" :intent \\\"y\\\"\" :mode :scout)\n"
                           "(:turn 1 :reply \"r\") \n"
                           "(:turn 4 :reply \"four\")\n"))
        (pair "a..b" "(:session :id \"a..b\" :task \"dots\")\n(:turn 1 :reply \"r\")\n")
        (pair "noTurn" "(:session :id \"noTurn\" :task \"t\")\n(:turn 1 :observation \"only\")\n")
        (pair "endedOk" "(:session :id \"endedOk\" :task \"t\")\n(:turn 1 :reply \"r\")\n(:result :status :ok)\n"))

fn ! aslLines root: String -> (List String)
  (listAppend
    (map m/formatReceipt (list (minimalResult) (fullResult) (edgeResult)))
    (listAppend
      (list (mt (m/receiptFieldNames ".") ((ok fs) (stringJoin fs " ")) ((err e) e)))
      (listAppend
        (map (fn [s] (resumeLine (m/journalResume s root))) (sessions))
        (listAppend
          (map (fn [h] (j/jsonEmit (optText (m/journalModeHint h)))) (headers))
          (map m/nearestKey! (misspelt))))))

fn ! runTests -> Bool
  (let [root (stringTrim (processRun "mktemp -d /tmp/asl-main-receipt.XXXXXX").stdout)
        dirMade (ok? (dirCreate (str root "/.asl/run/agentLoop")))
        written (fold (fn [acc jp] (and acc (write (str root "/.asl/run/agentLoop/" (pairFirst jp) ".journal") (pairSecond jp)))) true (journals))
        asl (map (fn [line] (stringReplace line root "{ROOT}")) (aslLines root))
        expected (stringLines (stringTrim (resultOr (fileReadString "asl/agentLoop/tests/mainReceiptExpected.txt") "")))
        synthetic (m/receiptFieldsIn "fn other -> String\n  \"(:x :no)\"\n\nfn formatReceipt r: R -> String\n  (str \"(:agentReceipt :status :\" s \" :alpha \" a \" :gates ((:cmd \\\"\" c \"\\\" :exit 0)) :beta (\" b \")\" \" :alpha 1\")\n\nfn after -> String\n  \" :omega \"\n")
        noFn (m/receiptFieldsIn "fn formatDryRun -> String\n  \"(:agentReceipt :status :ok)\"\n")
        noHead (m/receiptFieldsIn "fn formatReceipt -> String\n  \"(:dryRunReceipt :vendor \"\n")
        removed (pathRemove root)]
    (do
      (assert (and dirMade written) "journal fixtures written")
      (assert (and (= (listLength asl) 29) (= (listLength expected) 29)) "all 29 direct receipt and journal outputs produced")
      (assert (= asl expected) "all direct receipt and journal outputs match recorded expected values")
      (assert (stringContains? (optionOr (listGet asl 1) "") ":status :partial") "full receipt preserves its recorded status")
      (assert (= (optionOr (listGet asl 0) "") "(:agentReceipt :status :ok :phases () :unbacked 0)") "minimal receipt holds status, phases and unbacked only")
      (assert (stringContains? (optionOr (listGet asl 1) "") " :needsConfirm ((:op \"push\" :blocked true) (:op \"deploy\" :error ERR_X))") "needsConfirm keeps blocked and failed ops")
      (assert (mt synthetic ((ok fs) (= fs (list "status" "alpha" "gates" "beta"))) ((err _) false)) "receipt fields follow a changed formatReceipt source, once each, nested cmd and exit dropped")
      (assert (mt noFn ((ok _) false) ((err e) (stringContains? e "no fn formatReceipt"))) "a source without fn formatReceipt is an error")
      (assert (mt noHead ((ok _) false) ((err e) (stringContains? e "(:agentReceipt"))) "a formatReceipt without (:agentReceipt is an error")
      (assert (ok? removed) "fixture root removed")
      true))
