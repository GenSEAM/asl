(module ws/asl/tools/obs/tests/attribJoinTest
  :x [runTests]
  :i [(ws/asl/tools/obs/obs :a ob)
      (ws/asl/tools/obs/classify :a cl)
      (ws/asl/tools/obs/sources :a src)
      (ws/asl/tools/obs/corpus :a co)])

fn readText p: String -> String
  (resultOr (fileReadString p) "")

fn fx name: String -> String
  (readText (str "asl/tools/obs/tests/fixtures/" name))

fn ctx -> src/Ctx
  (src/Ctx :table (cl/parseTable (readText "asl/tools/obs/failClasses.asn")) :host "node2" :mtime 1792966000000 :run "fixRun")

fn gateway i: Int64 -> ob/Obs
  (match (src/gatewayRow (ctx) (optionOr (listGet (stringLines (fx "gatewayAttrib.fixture.asn")) i) ""))
    ((some o) o)
    ((none) (ob/blankObs)))

fn journal name: String -> ob/Obs
  (match (src/journalObs (ctx) 1792966000000 (fx name))
    ((some o) o)
    ((none) (ob/blankObs)))

; (:m LEON-ATTRIB / OBS-GATEERR-ROW: a ledger row with :session joins the Leon session row on :run and keeps its turn; a row without keeps the profile run; a failed session takes its class from the first receipt error line, a :gateErr row first, and with no error line is still sessionFailed)
fn ! runTests -> Bool
  (let [(g1 (gateway 0))
        (g2 (gateway 1))
        (noReply (journal "journalNoReply.fixture.asn"))
        (gateErr (journal "journalGateErr.fixture.asn"))
        (plain (journal "journalPlainFail.fixture.asn"))
        (timed (journal "journalTurnTime.fixture.asn"))]
    (do
      (assert (= timed.turn 2) (str "(:turnTime rows are not counted as turns: " timed.turn))
      (assert (= g1.run "abc1230000000000") (str "the ledger row joins by session: " g1.run))
      (assert (= g1.turn 2) "the ledger row keeps its turn")
      (assert (= g2.run "work") "a row without :session keeps the profile as its run")
      (assert (= g2.turn 0) "a row without :turn has turn 0")
      (assert (= noReply.run g1.run) "the Leon session row and the ledger row share :run")
      (assert (= noReply.failClass "emptyReply") (str "first receipt error ERR_NO_REPLY classifies: " noReply.failClass))
      (assert (= gateErr.failClass "unknownSymbol") (str "a :gateErr row wins over later turn errors: " gateErr.failClass))
      (assert (= plain.failClass "sessionFailed") (str "no error line keeps the sessionFailed class: " plain.failClass))
      (assert (= (co/pickOldest (list (pair "/src/.asl/run/agentLoop/a.journal" 900) (pair "/wt/u/.asl/run/agentLoop/a.journal" 500) (pair "/wt/u/.asl/run/agentLoop/b.journal" 700)))
                 (list "/wt/u/.asl/run/agentLoop/a.journal" "/wt/u/.asl/run/agentLoop/b.journal")) "one journal per session id, the oldest copy wins")
      (assert (= (co/pickOldest (list (pair "/x/a.journal" 5) (pair "/y/a.journal" 5))) (list "/x/a.journal")) "a tie keeps the first listed")
      true))
