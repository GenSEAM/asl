(module aslGateway/tests/breakerAliasScopeTest
  :x [runTests]
  :i [(breaker :a b)
      (config :a c)
      (chat :a ch)
      (upstream :a u)])

; (:m :ref GW-BREAKER-ALIAS-SCOPE :do "a 429, a quota or account-wording body and an empty length reply of one alias open only that alias's breaker pool: its sibling on the same provider is still routed; a 401 or an insufficient_quota body, or a billing-worded 429 on a provider that declares an account limit row, closes the whole provider, the real chat loop driven against a real BreakerState, no network")
fn okBody -> String
  "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}]}"

fn lengthBody -> String
  "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"length\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":9}}"

fn cfg extra: String -> String
  (str "(:gateway :v 2 :providers ((:provider :id syn :kind openai :base \"http://127.0.0.1:1\" :keyEnv SYN_KEY)) :models ((:model :id m1 :provider syn :name \"n1\") (:model :id m2 :provider syn :name \"n2\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2))))) :uses ((:use :for default :profile default))" extra ")")

fn applyEv st: b/BreakerState ev: String pool: String park: Int64 -> b/BreakerState
  (cond
    ((= ev "markDown") (b/breakerMarkDownFor st pool 1000 park))
    ((= ev "note503") (pairFirst (b/breakerNote503 st pool 1000)))
    ((= ev "note429") (b/breakerNote429 st pool 1000 park 0))
    ((stringStartsWith? ev "note429window:") (b/breakerNote429 st pool 1000 park 60))
    ((= ev "reset503") (b/breakerReset503 st pool))
    ((= ev "clear") (b/breakerClear st pool))
    (else st))

fn ! drive! step: ch/ChatStep labels: String hits: Int64 first: ch/HttpReply okReply: ch/HttpReply st: b/BreakerState fuel: Int64 -> (Pair String b/BreakerState)
  (if (<= fuel 0)
    (pair (str labels "|outOfFuel") st)
    (match step
      ((ch/stepDone _) (pair labels st))
      ((ch/stepRaised kind _) (pair (str labels "|raised " kind) st))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) labels hits first okReply st (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) labels hits first okReply st (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1000.0)) labels hits first okReply st (- fuel 1)))
         ((ch/effBreakerDown pool)
          (let [(r (b/breakerDownFor st pool 1000))]
            (drive! (k (ch/outFloat (int64ToFloat64 (pairSecond r)))) labels hits first okReply (pairFirst r) (- fuel 1))))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) labels hits first okReply st (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool true)) labels hits first okReply st (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) labels hits first okReply st (- fuel 1)))
         ((ch/effSleepMs _) (drive! (k ch/outDone) labels hits first okReply st (- fuel 1)))
         ((ch/effLimit _ _) (drive! (k (ch/outStrings (list))) labels hits first okReply st (- fuel 1)))
         ((ch/effBreakerEvent ev pool park) (drive! (k ch/outDone) (str labels "|brk:" ev "@" pool) hits first okReply (applyEv st ev pool park) (- fuel 1)))
         ((ch/effUsageNote _ alias outcome _) (drive! (k ch/outDone) (str labels "|note:" alias ":" outcome) hits first okReply st (- fuel 1)))
         ((ch/effHttp _ _ _ _ _ _ _ _)
          (drive! (k (ch/outHttp (if (< hits 1) first okReply))) (str labels "|http") (+ hits 1) first okReply st (- fuel 1)))
         (_ (drive! (k ch/outDone) labels hits first okReply st (- fuel 1)))))))

fn ! chatRun! extra: String first: ch/HttpReply st: b/BreakerState -> (Pair String b/BreakerState)
  (match (c/gatewayConfigParse! (cfg extra) "default" ".asl/mem/calibration/index.asn")
    ((err e) (pair (str "config: " e) st))
    ((ok table)
      (match (u/upstreamSettings (mapEmpty))
        ((err _) (pair "no settings" st))
        ((ok settings)
          (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"model\":\"default\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                    (ch/ChatWorld :env (mapFromPairs (list (pair "SYN_KEY" "k-GBA-1"))) :rootDir "/tmp" :settings settings :agyPromptMaxBytes 10000 :table (ok table)))
                  "" 0 first (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (okBody)) st 300)))))

fn down st: b/BreakerState pool: String -> Bool
  (> (pairSecond (b/breakerDownFor st pool 1000)) 0)

fn count s: String needle: String -> Int64
  (- (listLength (stringSplit s needle)) 1)

fn ! runTests -> Bool
  (let [(st0 (b/defaultBreakerState))
        (acctBody "{\"error\":{\"message\":\"Your account quota is exhausted for this period\"}}")
        (plain429 (ch/httpError 429 "Too Many Requests" (list) acctBody))
        (r1 (chatRun! "" plain429 st0))
        (r1b (chatRun! "" (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (okBody)) (pairSecond r1)))
        (st1 (pairSecond r1))
        (r2 (chatRun! "" (ch/httpError 401 "Unauthorized" (list) "{\"error\":\"bad key\"}") st0))
        (st2 (pairSecond r2))
        (r2b (chatRun! "" (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (okBody)) st2))
        (r3 (chatRun! " :limits ((:limit :provider syn :scope account :window day :calls 500))" plain429 st0))
        (st3 (pairSecond r3))
        (r4 (chatRun! "" (ch/httpError 429 "Too Many Requests" (list) "{\"error\":{\"type\":\"insufficient_quota\"}}") st0))
        (st4 (pairSecond r4))
        (r5 (chatRun! "" (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (lengthBody)) st0))
        (st5 (pairSecond r5))
        (r6 (chatRun! " :limits ((:limit :provider syn :scope model :model m1 :window day :calls 500))" plain429 st0))
        (st6 (pairSecond r6))]
    (do
      (assert (stringContains? (pairFirst r1) "|brk:note429@syn:m1") (str "a 429 on m1 notes the breaker under its own pool syn:m1: " (pairFirst r1)))
      (assert (not (stringContains? (pairFirst r1) "@syn|")) (str "a 429 never touches the provider pool: " (pairFirst r1)))
      (assert (and (down st1 "syn:m1") (not (down st1 "syn")) (not (down st1 "syn:m2"))) "after a 429 on m1 only syn:m1 is down; the provider and its sibling stay up")
      (assert (stringContains? (pairFirst r1) "|note:m2:ok") (str "the sibling m2 of the same provider answers the same call: " (pairFirst r1)))
      (assert (and (= (count (pairFirst r1b) "|http") 1) (stringContains? (pairFirst r1b) "|note:m2:ok") (not (stringContains? (pairFirst r1b) "m1:ok"))) (str "the next call skips the open alias m1 for its breaker time and routes m2 with one http: " (pairFirst r1b)))
      (assert (and (down st2 "syn") (not (down st2 "syn:m1"))) "a 401 closes the whole provider pool")
      (assert (= (count (pairFirst r2b) "|http") 0) (str "with the provider closed no alias of it is tried: " (pairFirst r2b)))
      (assert (and (down st3 "syn") (not (down st3 "syn:m1"))) "an account-wording 429 on a provider with an account limit row closes the provider")
      (assert (down st4 "syn") "an insufficient_quota 429 closes the provider")
      (assert (and (not (down st5 "syn")) (not (down st5 "syn:m1")) (not (stringContains? (pairFirst r5) "|brk:note")) (not (stringContains? (pairFirst r5) "markDown"))) (str "an empty length reply opens no breaker at all, alias or provider: " (pairFirst r5)))
      (assert (stringContains? (pairFirst r5) "|note:m1:emptyLength") (str "...and is recorded as emptyLength: " (pairFirst r5)))
      (assert (and (down st6 "syn:m1") (not (down st6 "syn"))) "a provider with only a model-scope limit row keeps a 429 on the alias")
      true))
