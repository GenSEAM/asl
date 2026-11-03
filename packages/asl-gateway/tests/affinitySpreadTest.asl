(module aslGateway/tests/affinitySpreadTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (wire :a w)])

; (:m :ref GW-AFFINITY-SPREAD :do "a session sticks to its member across a spread profile, but never at the cost of progress: the stuck member goes first past the spread order, by default yields at once to the chain when its rpm bucket is dry (an opt-in :affinityWaitSec waits for it), a switch is recorded as a skippedSwitch usage note and named in the reply as switchedFrom; node2 2026-11-03 showed 27 of 38 Leon sessions served by 2-6 models because a throttled stuck member was dropped after 5 s")
(schema Seen
  (:f labels String)
  (:f body String)
  (:f status Int64))

fn okBody -> String
  "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"

fn ok200 -> ch/HttpReply
  (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (okBody))

fn tooMany -> ch/HttpReply
  (ch/httpError 429 "Too Many Requests" (list) "{\"error\":{\"message\":\"rate limited\"}}")

fn effLabel eff: ch/ChatEffect -> String
  (match eff
    ((ch/effBucket m _ t) (str "bucket:" m ":" (stringFromInt64 (truncate t))))
    ((ch/effHttp _ m _ _ _ _ _ _) (str "http:" m))
    ((ch/effUsageNote _ a o _) (str "note:" a ":" o))
    ((ch/effAffinityNote s a) (str "stick:" s ":" a))
    (_ ""))

fn truncate f: Float64 -> Int64
  (optionOr (float64ToInt64 f) 0)

fn push labels: String l: String -> String
  (if (stringEmpty? l) labels (if (stringEmpty? labels) l (str labels "|" l)))

fn statusOf resp: ch/ChatResponse -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus s) s) (_ acc))) 0 resp.head)

; (:m :do "the affinity ask answers stuck; the spread order is m1 then m2; a bucket is granted only to a wait of at least 20 s (a shared bucket some other session drained); replies feed effHttp in order and the last repeats")
fn ! drive! step: ch/ChatStep labels: String stuck: (List String) replies: (List ch/HttpReply) fuel: Int64 -> Seen
  (if (<= fuel 0)
    (Seen :labels labels :body "out of fuel" :status 0)
    (match step
      ((ch/stepDone resp) (Seen :labels labels :body resp.body :status (statusOf resp)))
      ((ch/stepRaised kind msg) (Seen :labels labels :body (str "raised " kind ": " msg) :status 0))
      ((ch/stepEffect eff k)
       (let [(labels2 (push labels (effLabel eff)))]
         (match eff
           ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels2 stuck replies (- fuel 1)))
           ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels2 stuck replies (- fuel 1)))
           ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels2 stuck replies (- fuel 1)))
           ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels2 stuck replies (- fuel 1)))
           ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels2 stuck replies (- fuel 1)))
           ((ch/effAffinity _) (drive! (k (ch/outStrings stuck)) labels2 stuck replies (- fuel 1)))
           ((ch/effSpreadOrder _ _ _ _ _) (drive! (k (ch/outStrings (list "m1" "m2"))) labels2 stuck replies (- fuel 1)))
           ((ch/effBucket _ _ t) (drive! (k (ch/outBool (>= t 20.0))) labels2 stuck replies (- fuel 1)))
           ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels2 stuck replies (- fuel 1)))
           ((ch/effHttp _ _ _ _ _ _ _ _) (drive! (k (ch/outHttp (optionOr (listHead replies) (ok200)))) labels2 stuck (if (> (listLength replies) 1) (optionOr (listTail replies) (list)) replies) (- fuel 1)))
           (_ (drive! (k ch/outDone) labels2 stuck replies (- fuel 1))))))))

; (:m :do "two members with their own rpm in a spread profile, plus a third without rpm as the plain last member")
fn cfg -> String
  "(:gateway :v 2 :bucketWaitSec 5 :providers ((:provider :id af :kind openai :base \"http://127.0.0.1:1\" :keyEnv AF_KEY)) :models ((:model :id m1 :provider af :name \"n1\" :rpm 10) (:model :id m2 :provider af :name \"n2\" :rpm 10) (:model :id m3 :provider af :name \"n3\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2 m3) :spread ((m1 1) (m2 1)))))) :uses ((:use :for default :profile default)))"

fn body -> String
  "{\"model\":\"default\",\"queue_timeout\":120,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn ! run! session: String stuck: (List String) replies: (List ch/HttpReply) -> Seen
  (match (c/gatewayConfigParse! (cfg) "affinitySpread" ".asl/mem/calibration/index.asn")
    ((err e) (Seen :labels "" :body (str "no table: " e) :status 0))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) (Seen :labels "" :body "no settings" :status 0))
        ((ok st)
          (let [(w (ch/ChatWorld :env (mapFromPairs (list (pair "AF_KEY" "k-AFFINITY-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))
                (hs (if (stringEmpty? session) (list) (list (pair "X-ASL-Session" session))))]
            (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers hs :body (body)) w) "" stuck replies 300))))))

fn ! runTests -> Bool
  (let [(sticky (run! "s1" (list "m2" "1" "1" "30") (list)))
        (switched (run! "s1" (list "m2" "1" "1" "30") (list (tooMany) (ok200))))
        (noWait (run! "s1" (list "m2" "1" "1" "0") (list)))
        (loose (run! "s1" (list "m2" "0" "1" "30") (list)))
        (noSession (run! "" (list "m2" "1" "1" "30") (list)))]
    (do
      (assert (stringStartsWith? sticky.labels "bucket:n2:30") (str "the stuck member goes first past the spread order and waits :affinityWaitSec for its token: " sticky.labels))
      (assert (and (= sticky.status 200) (stringContains? sticky.labels "http:n2")) (str "the stuck member answers once its shared bucket refills: " sticky.labels))
      (assert (not (stringContains? sticky.labels "http:n1")) (str "a sticking session is not moved to the spread's first member: " sticky.labels))
      (assert (not (stringContains? sticky.labels "skippedSwitch")) (str "no switch is recorded when the stuck member answers: " sticky.labels))
      (assert (and (= switched.status 200) (stringContains? switched.labels "http:n3")) (str "a stuck member that answers 429 is left for the next: " switched.labels))
      (assert (stringContains? switched.labels "note:m2:skippedSwitch:m3") (str "the switch is recorded as a skippedSwitch note on the member it left: " switched.labels))
      (assert (stringContains? switched.labels "stick:s1:m3") (str "the session then sticks to the member that answered: " switched.labels))
      (assert (stringStartsWith? noWait.labels "bucket:n2:5") (str ":affinityWaitSec 0 (the default) gives the stuck member the plain bucket wait: " noWait.labels))
      (assert (and (= noWait.status 200) (stringContains? noWait.labels "http:n3")) (str "a paced stuck member yields and the chain moves on as for any request: " noWait.labels))
      (assert (stringContains? noWait.labels "note:m2:skippedSwitch:m3") (str "the yield is recorded as a skippedSwitch note: " noWait.labels))
      (assert (stringContains? noWait.body "\"switchedFrom\": \"m2\"") (str "the reply names the member the session left: " noWait.body))
      (assert (stringContains? switched.body "\"switchedFrom\": \"m2\"") (str "a switch after a 429 is named in the reply: " switched.body))
      (assert (not (stringContains? sticky.body "switchedFrom")) (str "a reply by the session's own member names no switch: " sticky.body))
      (assert (stringContains? loose.body "\"switchedFrom\": \"m2\"") (str "any change of member is named, also past the stick window: " loose.body))
      (assert (not (stringContains? noSession.body "switchedFrom")) (str "a request without a session names no switch: " noSession.body))
      (assert (stringContains? (w/chatReplyAsnStr "{\"model\":\"n3\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"ok\"},\"finish_reason\":\"stop\"}],\"asl\":{\"alias\":\"m3\",\"switchedFrom\":\"m2\"}}") ":switchedFrom \"m2\"") "the ASN reply carries switchedFrom")
      (assert (stringStartsWith? loose.labels "bucket:n1:5") (str "past the stick window the spread order stands and no member waits longer: " loose.labels))
      (assert (not (stringContains? loose.labels "skippedSwitch")) (str "a session past its stick window records no switch: " loose.labels))
      (assert (stringStartsWith? noSession.labels "bucket:n1:5") (str "a request without a session key keeps the spread order and the plain wait: " noSession.labels))
      true))
