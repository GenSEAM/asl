(module aslGateway/tests/modelAsProfileTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)
      (config :a c)
      (wire :a w)])

; (:m :ref GW-MODEL-AS-PROFILE :do "a request whose model is a profile id and no registered model or alias routes through that profile chain like model default with X-ASL-Profile, an alias or model of the same name still alias-routes, and an explicit X-ASL-Profile header wins over the model name")
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
  (match (c/gatewayConfigParse! text "modelAsProfile" ".asl/mem/calibration/index.asn")
    ((err _) none)
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) none)
        ((ok st) (some (ch/ChatWorld :env (mapFromPairs (list (pair "CR_KEY" "k-CTXROUTE-1"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (ok table)))))))

fn ! run! text: String hdrs: (List (Pair String String)) body: String replies: (List ch/HttpReply) -> Seen
  (match (worldOf! text)
    ((none) (Seen :labels "" :body "no world" :status 0 :head ""))
    ((some w)
      (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers hdrs :body body) w) "" replies 300)))

fn cfg -> String
  "(:gateway :v 2 :providers ((:provider :id cr :kind openai :base \"http://127.0.0.1:1\" :keyEnv CR_KEY)) :models ((:model :id m1 :provider cr :name \"n1\") (:model :id m2 :provider cr :name \"n2\") (:model :id m3 :provider cr :name \"n3\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1)))) (:profile :id research :routes ((:intent any :chain (m2)))) (:profile :id m3 :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))"

fn bodyFor m: String -> String
  (str "{\"model\":\"" m "\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")

fn ! runTests -> Bool
  (let [(viaModel (run! (cfg) (list) (bodyFor "research") (list)))
        (viaDefault (run! (cfg) (list) (bodyFor "default") (list)))
        (aliasWins (run! (cfg) (list) (bodyFor "m3") (list)))
        (headerWins (run! (cfg) (list (pair "X-ASL-Profile" "default")) (bodyFor "research") (list)))
        (unknown (run! (cfg) (list) (bodyFor "nosuch") (list)))]
    (do
      (assert (and (= viaModel.status 200) (stringContains? viaModel.labels "http:n2") (not (stringContains? viaModel.labels "http:n1"))) (str "model research routes through the research chain: " viaModel.labels " " viaModel.body))
      (assert (stringContains? viaDefault.labels "http:n1") (str "model default keeps the default profile: " viaDefault.labels))
      (assert (and (stringContains? aliasWins.labels "http:n3") (not (stringContains? aliasWins.labels "http:n1"))) (str "a registered alias wins over a profile of the same name: " aliasWins.labels))
      (assert (and (stringContains? headerWins.labels "http:n1") (not (stringContains? headerWins.labels "http:n2"))) (str "an explicit X-ASL-Profile header wins over the model name: " headerWins.labels))
      (assert (not (stringContains? unknown.labels "http:n1")) (str "an unknown model is neither a profile nor default: " unknown.labels))
      true))
