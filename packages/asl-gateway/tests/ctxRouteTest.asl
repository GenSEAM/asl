(module aslGateway/tests/ctxRouteTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (wire :a w)])

; (:m :ref CTX-ROUTE :do "context routing proved on the pure chat state machine with scripted effects: a provider context overflow hops to a member with a larger window, a chain no member of which fits answers a typed contextTooLarge 413 instead of a breaker cooldown, a pin profile relays the upstream overflow unchanged, the reply names the route's largest window, and :budgetFirstAbove tries the largest window first for a large prompt")
(schema Seen
  (:f labels String)
  (:f body String)
  (:f status Int64)
  (:f head String))

fn okBody -> String
  "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"

fn ok200 -> ch/HttpReply
  (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (okBody))

fn overflow -> ch/HttpReply
  (ch/httpError 400 "Bad Request" (list) "{\"error\":{\"message\":\"This model's maximum context length is 8192 tokens. However, your messages resulted in 9000 tokens.\",\"code\":\"context_length_exceeded\"}}")

fn badRequest -> ch/HttpReply
  (ch/httpError 400 "Bad Request" (list) "{\"error\":{\"message\":\"unknown field foo\"}}")

; (:m :do "the model an effHttp went to, without the request data, so a label never matches inside a payload")
fn effLabel eff: ch/ChatEffect -> String
  (match eff
    ((ch/effHttp _ m _ _ _ _ _ _) (str "http:" m))
    ((ch/effBreakerEvent e p _) (str "bk:" e ":" p))
    ((ch/effUsageNote _ a o _) (str "note:" a ":" o))
    (_ ""))

fn push labels: String l: String -> String
  (if (stringEmpty? l) labels (if (stringEmpty? labels) l (str labels "|" l)))

fn headText resp: ch/ChatResponse -> String
  (stringJoin (map (fn [(h ch/HeadItem)] -> String (match h ((ch/headField n v) (str n "=" v)) ((ch/headStatus s) (stringFromInt64 s)))) resp.head) ";")

fn statusOf resp: ch/ChatResponse -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus s) s) (_ acc))) 0 resp.head)

; (:m :do "replies feed effHttp in order and the last repeats; the breaker is never down; a CLI call answers empty")
fn ! drive! step: ch/ChatStep labels: String replies: (List ch/HttpReply) fuel: Int64 -> Seen
  (if (<= fuel 0)
    (Seen :labels labels :body "out of fuel" :status 0 :head "")
    (match step
      ((ch/stepDone resp) (Seen :labels labels :body resp.body :status (statusOf resp) :head (headText resp)))
      ((ch/stepRaised kind msg) (Seen :labels labels :body (str "raised " kind ": " msg) :status 0 :head ""))
      ((ch/stepEffect eff k)
       (let [(labels2 (push labels (effLabel eff)))]
         (match eff
           ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels2 replies (- fuel 1)))
           ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels2 replies (- fuel 1)))
           ((ch/effClock) (drive! (k (ch/outFloat 1.0)) labels2 replies (- fuel 1)))
           ((ch/effBreakerDown _) (drive! (k (ch/outFloat 0.0)) labels2 replies (- fuel 1)))
           ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels2 replies (- fuel 1)))
           ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) labels2 replies (- fuel 1)))
           ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels2 replies (- fuel 1)))
           ((ch/effHttp _ _ _ _ _ _ _ _) (drive! (k (ch/outHttp (optionOr (listHead replies) (ok200)))) labels2 (if (> (listLength replies) 1) (optionOr (listTail replies) (list)) replies) (- fuel 1)))
           (_ (drive! (k ch/outDone) labels2 replies (- fuel 1))))))))

fn ! worldOf! text: String -> (Option ch/ChatWorld)
  (match (c/gatewayConfigParse! text "ctxRoute" ".asl/mem/calibration/index.asn")
    ((err _) none)
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) none)
        ((ok st) (some (ch/ChatWorld :env (mapFromPairs (list (pair "CR_KEY" "k-CTXROUTE-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))))))

fn ! run! text: String body: String replies: (List ch/HttpReply) -> Seen
  (match (worldOf! text)
    ((none) (Seen :labels "" :body "no world" :status 0 :head ""))
    ((some w)
      (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body body) w) "" replies 300)))

; (:m :do "three members m1 m2 m3 sent as n1 n2 n3, each with its own extra fields, one profile default with the given profile extras")
fn cfg3 profExtra: String e1: String e2: String e3: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id cr :kind openai :base \"http://127.0.0.1:1\" :keyEnv CR_KEY)) :models ((:model :id m1 :provider cr :name \"n1\"" e1
       ") (:model :id m2 :provider cr :name \"n2\"" e2 ") (:model :id m3 :provider cr :name \"n3\"" e3
       ")) :profiles ((:profile :id default" profExtra " :routes ((:intent any :chain (m1 m2 m3))))) :uses ((:use :for default :profile default)))")

fn shortBody -> String
  "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"

fn rep s: String n: Int64 -> String
  (if (<= n 0) "" (str s (rep s (- n 1))))

; (:m :do "about 190 estimated tokens")
fn longBody -> String
  (str "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"" (rep "lorem ipsum dolor " 40) "\"}]}")

fn ! runTests -> Bool
  (let [(hop (run! (cfg3 "" " :contextBudget 8000" " :contextBudget 4000" " :contextBudget 32000") (shortBody) (list (overflow) (ok200))))
        (noneFit (run! (cfg3 "" " :contextBudget 10" " :contextBudget 20" " :contextBudget 30") (longBody) (list)))
        (allOverflow (run! (cfg3 "" "" "" "") (shortBody) (list (overflow))))
        (pinned (run! (cfg3 " :mode pin" " :contextBudget 8000" "" "") (shortBody) (list (overflow))))
        (plain400 (run! (cfg3 "" "" "" "") (shortBody) (list (badRequest) (ok200))))
        (served (run! (cfg3 "" " :contextBudget 8000" " :contextBudget 64000" "") (shortBody) (list)))
        (bigFirst (run! (cfg3 " :budgetFirstAbove 50" " :contextBudget 1000" " :contextBudget 64000" " :contextBudget 64000") (longBody) (list)))
        (smallKeeps (run! (cfg3 " :budgetFirstAbove 50" " :contextBudget 1000" " :contextBudget 64000" "") (shortBody) (list)))
        (offKeeps (run! (cfg3 "" " :contextBudget 1000" " :contextBudget 64000" "") (longBody) (list)))
        (badOption (worldOf! (cfg3 " :budgetFirstAbove 0" "" "" "")))
        (asn (w/chatReplyAsnStr "{\"model\":\"n1\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"ok\"},\"finish_reason\":\"stop\"}],\"asl\":{\"alias\":\"m1\",\"contextTokens\":8000,\"maxContextTokens\":64000}}"))]
    (do
      (assert (ch/contextOverflowError? 400 "{\"error\":{\"code\":\"context_length_exceeded\"}}") "an OpenAI-style context_length_exceeded 400 is a context overflow")
      (assert (ch/contextOverflowError? 413 "prompt is too long: 210000 tokens > 200000 maximum") "a 413 naming a too long prompt is a context overflow")
      (assert (not (ch/contextOverflowError? 400 "unknown field foo")) "a 400 without a context marker is no overflow")
      (assert (not (ch/contextOverflowError? 429 "maximum context length")) "a 429 is never a context overflow")
      (assert (= hop.status 200) (str "an overflow hops on and a larger member answers: " hop.labels " " hop.body))
      (assert (and (stringContains? hop.labels "http:n1") (stringContains? hop.labels "http:n3")) (str "the overflowed member and the larger one are sent: " hop.labels))
      (assert (not (stringContains? hop.labels "http:n2")) (str "a member whose budget is not above the overflowed window is skipped: " hop.labels))
      (assert (stringContains? hop.labels "note:m1:contextOverflow") (str "the overflow is charged to its member as contextOverflow: " hop.labels))
      (assert (stringContains? hop.labels "bk:reset503:cr:m1") (str "CTX-PIN-RELAY: an overflow still sends its member the breaker event of a plain 4xx: " hop.labels))
      (assert (= noneFit.status 413) (str "no member whose budget holds the prompt answers 413: " (stringFromInt64 noneFit.status) " " noneFit.body))
      (assert (stringContains? noneFit.body "(:err :code contextTooLarge :need ") (str "the 413 is the typed contextTooLarge error: " noneFit.body))
      (assert (stringContains? noneFit.body ":maxBudget 30)") (str "the error names the largest budget of the chain: " noneFit.body))
      (assert (not (stringContains? noneFit.body "circuit-breaker")) (str "a context skip is not reported as a breaker cooldown: " noneFit.body))
      (assert (stringContains? noneFit.head "X-ASL-Max-Context=30") (str "the largest budget rides in X-ASL-Max-Context: " noneFit.head))
      (assert (not (stringContains? noneFit.labels "http:")) (str "nothing is sent when no member fits: " noneFit.labels))
      (assert (and (= allOverflow.status 413) (stringContains? allOverflow.body "contextTooLarge")) (str "every member overflowing answers contextTooLarge: " (stringFromInt64 allOverflow.status) " " allOverflow.body))
      (assert (not (stringContains? allOverflow.body ":maxBudget")) (str "no declared budget leaves maxBudget out: " allOverflow.body))
      (assert (= (listLength (stringSplit allOverflow.labels "http:")) 4) (str "each of the three members is tried once: " allOverflow.labels))
      (assert (= pinned.status 400) (str "CTX-PIN-RELAY: a pin profile relays its member's overflow with the upstream status: " (stringFromInt64 pinned.status) " " pinned.body))
      (assert (and (stringContains? pinned.body "context_length_exceeded") (not (stringContains? pinned.body "contextTooLarge"))) (str "CTX-PIN-RELAY: the relayed body is the upstream one, not the gateway's contextTooLarge: " pinned.body))
      (assert (= (listLength (stringSplit pinned.labels "http:")) 2) (str "a pin profile sends once: " pinned.labels))
      (assert (and (= plain400.status 200) (not (stringContains? plain400.labels "contextOverflow"))) (str "a 400 without a context marker keeps the plain profile fallback: " plain400.labels))
      (assert (stringContains? served.body "\"maxContextTokens\": 64000") (str "a reply names the route's largest window: " served.body))
      (assert (stringContains? served.body "\"contextTokens\": 8000") (str "a reply keeps the served member's own window: " served.body))
      (assert (stringStartsWith? bigFirst.labels "http:n2") (str "a large prompt under :budgetFirstAbove goes to the largest window first: " bigFirst.labels))
      (assert (stringStartsWith? smallKeeps.labels "http:n1") (str "a small prompt keeps the chain order: " smallKeeps.labels))
      (assert (stringStartsWith? offKeeps.labels "http:n1") (str "without :budgetFirstAbove the chain order stays: " offKeeps.labels))
      (assert (none? badOption) "a :budgetFirstAbove that is not a positive integer is a config error")
      (assert (stringContains? asn ":maxContextTokens 64000") (str "the ASN reply carries maxContextTokens: " asn))
      (assert (stringContains? asn ":contextTokens 8000") (str "the ASN reply keeps contextTokens: " asn))
      true))
