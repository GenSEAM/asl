(module aslGateway/tests/admissionWireTest
  :x [runTests]
  :i [(chat :a ch)
      (server :a srv)
      (upstream :a u)
      (config :a c)
      (usageLedger :a ul)])

; (:m :ref GW-SYN-ADMISSION :do "end to end through chat.asl and the server's real effect handler on a scratch HOME: an upstream 429 naming concurrency with Retry-After 1 holds the lane for a second (hold file), the parked attempt writes one limit:concurrency429 ledger note, the failed call and the ok call each release their lease, and the parked note is not a sent row so it releases nothing")
(schema Run
  (:f asked Int64)
  (:f at429 Int64)
  (:f status Int64)
  (:f end String)
  (:f notes (List String)))

fn configText dir: String -> String
  (str "(:gateway :v 2 :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))"
       " :models ((:model :id m1 :provider test :name \"model-1\"))"
       " :limits ((:limit :provider test :scope model :model m1 :concurrency 2 :max 2))"
       " :intents ((:intent :id solo))"
       " :profiles ((:profile :id default :routes ((:intent solo :chain (m1)))))"
       " :uses ((:use :for default :profile default)))")

fn testEnv -> (Map String String)
  (mapSet (mapEmpty) "TEST_KEY" "test-key")

fn request -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (list (pair "X-ASL-Intent" "solo") (pair "X-ASL-Queue-Ms" "20000"))
                  :body "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}")

fn statusOf head: (List ch/HeadItem) -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus code) code) (_ acc))) 200 head)

fn ok200 -> String
  "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"model-1\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"fine\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":2,\"total_tokens\":7}}"

fn ! drive! srv: srv/GatewayLoop step: ch/ChatStep ra: String run: Run fuel: Int64 -> Run
  (if (<= fuel 0)
    (with run :end "fuel")
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effHttp _ _ _ _ _ _ _ _)
          (let [(first (= run.asked 0))
                (reply (if first
                         (ch/httpError 429 "Too Many Requests" (if (stringEmpty? ra) (list) (list (pair "Retry-After" ra))) "{\"error\":\"Rate limit: too many concurrent requests\"}")
                         (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (ok200))))]
            (drive! srv (k (ch/outHttp reply)) ra (with run :asked (+ run.asked 1) :at429 (if first (/ (nowNs) 1000000) run.at429)) (- fuel 1))))
         (_ (let [(r (srv/runEffect! srv eff))
                  (seen (match eff ((ch/effUsageNote _ _ o _) (listAppend run.notes (list o))) (_ run.notes)))]
              (drive! (pairFirst r) (k (pairSecond r)) ra (with run :notes seen) (- fuel 1))))))
      ((ch/stepDone resp) (with run :status (statusOf resp.head) :end "done"))
      ((ch/stepRaised kind msg) (with run :end (str "raised " kind ": " msg)))))

fn laneFile dir: String name: String -> String
  (resultOr (fileReadString (str dir "/.asl/run/gwAdmission/" name)) "")

fn leaseLines text: String -> Int64
  (listLength (filter (fn [(s String)] -> Bool (stringStartsWith? s "test\tm1\t")) (stringSplit text "\n")))

fn ! once! ra: String -> (Pair Run (Pair String String))
  (let [(dir (str "/tmp/gwAdmWire-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate dir))
        (_2 (dirCreate (str dir "/.asl")))
        (_3 (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir) "\n")))
        (empty (Run :asked 0 :at429 0 :status 0 :end "" :notes (list)))
        (run (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
               ((err e) (with empty :end (str "linkOpen: " e)))
               ((ok loop)
                (match (u/upstreamSettings (testEnv))
                  ((err e) (with empty :end (str "settings: " e)))
                  ((ok settings)
                   (let [(world (ch/ChatWorld :env (testEnv) :rootDir "/" :settings settings :agyPromptMaxBytes 10000
                                              :table (c/gatewayProfilesLoadText! "/test" true (ok (configText dir)) "")))]
                     (drive! loop (ch/chatStart! (request) world) ra empty 400)))))))
        (hold (laneFile dir "test-m1.asn.hold"))
        (leases (laneFile dir "leases.tsv"))
        (_4 (removeTree! dir))]
    (pair run (pair hold leases)))

; (:m :do "removes a scratch tree in process")
fn ! removeTree! p: String -> Bool
  (match (fileLstat p)
    ((err _) true)
    ((ok st)
      (if (and st.isDir (not st.isSymlink))
        (let [(kids (match (dirList p) ((ok names) (filter (fn [(n String)] -> Bool (and (!= n ".") (!= n ".."))) names)) ((err _) (list))))
              (gone (fold (fn [(a Bool) (n String)] -> Bool (and (removeTree! (str p "/" n)) a)) true kids))]
          (and gone (ok? (pathRemove p))))
        (ok? (pathRemove p)))))

fn ! runTests -> Bool
  (let [(withRa (once! "1"))
        (noRa (once! ""))
        (run (pairFirst withRa))
        (hold (optionOr (stringToInt64 (stringTrim (pairFirst (pairSecond withRa)))) 0))
        (leases (pairSecond (pairSecond withRa)))
        (noHold (pairFirst (pairSecond noRa)))
        (parked (fn [(r Run)] -> Int64 (listLength (filter (fn [(n String)] -> Bool (= n "limit:concurrency429")) r.notes))))]
    (do
      (assert (and (= run.end "done") (= run.status 200) (= run.asked 2)) (str "the chat absorbs the 429 and answers after one resend: " run.end " " (stringFromInt64 run.status) " asked " (stringFromInt64 run.asked)))
      (assert (>= hold (+ run.at429 1000)) (str "Retry-After 1 holds the lane for a second from the 429: hold " (stringFromInt64 hold) " 429 at " (stringFromInt64 run.at429)))
      (assert (= (parked run) 1) (str "one parked attempt writes one limit:concurrency429 ledger note: " (stringJoin run.notes " ")))
      (assert (listContains? run.notes "ok") "the resent call writes its ok row")
      (assert (not (ul/sentOutcome? "limit:concurrency429")) "the parked note is not a sent outcome, so effUsageNote releases no lease for it")
      (assert (= (leaseLines leases) 0) (str "the failed call and the ok call each released their lease: " leases))
      (assert (and (= (pairFirst noRa).status 200) (= (stringTrim noHold) "")) "a 429 without Retry-After sets no hold")
      true))
