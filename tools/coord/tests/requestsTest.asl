(module asl/tools/coord/tests/requestsTest
  :x [runTests]
  :i [(asl-tools/coord/requests :a r)])

fn unit -> r/Unit
  (r/Unit :id "U1" :root "/w" :owns (list "asl/tools/coord/a.asl") :external true :requestsLeft 4 :escalationsLeft 2
          :gatesRun 1 :wallBudget 1800 :timeGranted false :writePersisted true)

fn leasesOf -> (List r/Lease)
  (list (r/Lease :unit "U2" :path "asl/tools/coord/held.asl") (r/Lease :unit "U3" :path "asl/tools/other"))

fn paced -> r/Pace
  (r/Pace :nextLaneAllowance true)

fn go u: r/Unit req: r/Request -> r/Decision
  (r/decide u (leasesOf) (paced) req)

fn esc reason: String -> r/Request
  (r/reqEscalate reason "s" "t")

fn testEscalate -> Bool
  (let [(ok1 (go (unit) (esc "other")))
        (noGate (go (r/Unit :id "U1" :root "/w" :owns (list) :external true :requestsLeft 4 :escalationsLeft 2 :gatesRun 0 :wallBudget 1800 :timeGranted false :writePersisted true) (esc "other")))
        (spec (go (r/Unit :id "U1" :root "/w" :owns (list) :external true :requestsLeft 4 :escalationsLeft 2 :gatesRun 0 :wallBudget 1800 :timeGranted false :writePersisted true) (esc "spec")))
        (none (r/decide (unit) (leasesOf) (r/Pace :nextLaneAllowance false) (esc "other")))
        (spent (go (r/Unit :id "U1" :root "/w" :owns (list) :external true :requestsLeft 4 :escalationsLeft 0 :gatesRun 1 :wallBudget 1800 :timeGranted false :writePersisted true) (esc "other")))]
    (do (assert ok1.granted "escalate with gates run, escalations and allowance is granted")
        (assert (= ok1.unit.escalationsLeft 1) "a granted escalation spends one escalation")
        (assert (= ok1.unit.requestsLeft 3) "a granted request spends one request")
        (assert (= noGate.row "(:refused :op escalate :why noGateRun)") "no gate ran and reason class not spec/owns is refused")
        (assert spec.granted "reason class spec skips the gate-ran condition")
        (assert (= none.row "(:refused :op escalate :why noAllowance)") "no allowance on the next rung is refused")
        (assert (= spent.row "(:refused :op escalate :why exhausted)") "no escalations left is refused")
        (assert (= spent.unit.requestsLeft 3) "a refused request still spends one request")
        (assert (= spent.unit.escalationsLeft 0) "a refused escalation spends no escalation")
        true))

fn testCtx -> Bool
  (let [(ok1 (go (unit) (r/reqNeedCtx "asl/tools/coord/a.asl" "f")))
        (outside (go (unit) (r/reqNeedCtx "/etc/passwd" "f")))
        (dots (go (unit) (r/reqNeedCtx "asl/../../x" "f")))
        (mem (go (unit) (r/reqNeedCtx ".asl/mem/work/x.asn" "f")))
        (secret (go (unit) (r/reqNeedCtx "config/api.env" "f")))
        (abs (go (unit) (r/reqNeedCtx "/w/asl/a.asl" "f")))
        (local (go (r/Unit :id "U1" :root "/w" :owns (list) :external false :requestsLeft 4 :escalationsLeft 2 :gatesRun 1 :wallBudget 1800 :timeGranted false :writePersisted true) (r/reqNeedCtx ".asl/mem/x.asn" "f")))]
    (do (assert ok1.granted "a path inside the root is granted")
        (assert (= outside.why "outsideRoot") "an absolute path outside the root is refused")
        (assert (= dots.why "outsideRoot") "a dotdot path is refused")
        (assert (= mem.why "memPath") "an external lane never gets .asl/mem content")
        (assert (= secret.why "secretLike") "an external lane never gets a secret-like path")
        (assert abs.granted "an absolute path under the root is granted")
        (assert local.granted "an internal lane may read .asl/mem")
        (assert (r/secretLike? "a/.env") "secretLike sees .env")
        (assert (not (r/secretLike? "asl/a.asl")) "secretLike passes a plain source path")
        true))

fn testOwns -> Bool
  (let [(ok1 (go (unit) (r/reqNeedOwns "asl/tools/coord/b.asl")))
        (held (go (unit) (r/reqNeedOwns "asl/tools/coord/held.asl")))
        (under (go (unit) (r/reqNeedOwns "asl/tools/other/deep/x.asl")))
        (pkg (go (unit) (r/reqNeedOwns "asl/tools/fleet/b.asl")))]
    (do (assert ok1.granted "a free path in the same package is granted")
        (assert (= (listLength ok1.unit.owns) 2) "a granted widen adds the path to the owns")
        (assert (= held.row "(:refused :op needOwns :heldBy U2)") "a held path names its holder")
        (assert (= under.row "(:refused :op needOwns :heldBy U3)") "a lease on a directory covers paths below it")
        (assert (= pkg.why "otherPackage") "a path in another package is refused")
        (assert (= (listLength held.unit.owns) 1) "a refused widen leaves the owns unchanged")
        true))

fn testTime -> Bool
  (let [(ok1 (go (unit) (r/reqNeedTime 900)))
        (twice (go ok1.unit (r/reqNeedTime 100)))
        (big (go (unit) (r/reqNeedTime 901)))
        (nowrite (go (r/Unit :id "U1" :root "/w" :owns (list) :external true :requestsLeft 4 :escalationsLeft 2 :gatesRun 1 :wallBudget 1800 :timeGranted false :writePersisted false) (r/reqNeedTime 60)))
        (zero (go (unit) (r/reqNeedTime 0)))]
    (do (assert ok1.granted "half the wall budget is granted")
        (assert (= ok1.unit.wallBudget 2700) "a granted time request raises the wall budget")
        (assert (= twice.why "alreadyGranted") "time is granted once per unit")
        (assert (= big.why "overHalf") "over half the wall budget is refused")
        (assert (= nowrite.why "noWrite") "no persisted write is refused")
        (assert (= zero.why "badArg") "a non-positive time is refused")
        true))

fn testSplitAndBound -> Bool
  (let [(sp (go (unit) (r/reqSplit (list "A" "B") "too big")))
        (empty (go (r/Unit :id "U1" :root "/w" :owns (list) :external true :requestsLeft 0 :escalationsLeft 2 :gatesRun 1 :wallBudget 1800 :timeGranted false :writePersisted true) (r/reqSplit (list "A") "x")))]
    (do (assert sp.granted "a split is always recorded")
        (assert (= sp.unit.requestsLeft 3) "a split spends one request")
        (assert (not empty.granted) "no requests left refuses even a split")
        (assert (= empty.why "requestsExhausted") "the refusal names the exhausted request budget")
        (assert (= (r/journalRow "U1" sp) "(:request :unit U1 :op split :granted true :why ok)") "journal row for a grant")
        (assert (= (r/journalRow "U1" (go (unit) (r/reqNeedOwns "asl/tools/coord/held.asl"))) "(:request :unit U1 :op needOwns :granted false :why heldBy:U2)") "journal row for a held refusal")
        true))

fn testDeterminismAndRepeat -> Bool
  (let [(req (r/reqNeedOwns "asl/tools/coord/held.asl"))
        (a (go (unit) req))
        (b (go (unit) req))
        (c (go a.unit req))]
    (do (assert (= a.row b.row) "the same request in the same state gets the same row")
        (assert (= (r/signature a) (r/signature b)) "the same state gives the same signature")
        (assert (= (r/repeatCount (list) a) 1) "the first refusal counts one")
        (assert (= (r/repeatCount (list (r/signature a)) b) 2) "a repeated refusal counts toward sameSig")
        (assert (= (r/repeatCount (list (r/signature a) (r/signature b)) c) 3) "the third equal refusal reaches the cap")
        (assert (= (r/repeatCount (list "x|y|z") a) 1) "an unrelated signature is not counted")
        (assert (= (r/repeatCount (list (r/signature a)) (go (unit) (r/reqSplit (list "A") "w"))) 0) "a grant never counts")
        true))

fn ! runTests -> Bool
  (do (assert (testEscalate) "escalate")
      (assert (testCtx) "needCtx")
      (assert (testOwns) "needOwns")
      (assert (testTime) "needTime")
      (assert (testSplitAndBound) "split and bound")
      (assert (testDeterminismAndRepeat) "determinism and repeat")
      true)
