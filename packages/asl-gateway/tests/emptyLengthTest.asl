(module aslGateway/tests/emptyLengthTest
  :x [runTests]
  :i [(chat :a ch)
      (server :a srv)
      (upstream :a u)
      (config :a c)])

; (:m :ref GW-SYN-EMPTY-CONTENT :do "an empty reply with finish_reason length (reasoning spent max_tokens) through the real chat cascade: one member answers 502 ERR_EMPTY_LENGTH naming the cap after one ask, a cascade moves on to the next member; an empty reply with any other finish_reason keeps its same-model retry")

(schema Run
  (:f models (List String))
  (:f status Int64)
  (:f body String)
  (:f end String)
  (:f notes (List String)))

fn configText dir: String -> String
  (str "(:gateway :v 2 :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))"
       " :models ((:model :id m1 :provider test :name \"model-1\") (:model :id m2 :provider test :name \"model-2\"))"
       " :intents ((:intent :id solo) (:intent :id any))"
       " :profiles ((:profile :id default :routes ((:intent solo :chain (m1)) (:intent any :chain (m1 m2)))))"
       " :uses ((:use :for default :profile default)))")

fn testEnv -> (Map String String)
  (mapSet (mapEmpty) "TEST_KEY" "test-key")

fn replyUsing model: String content: String finish: String reasoning: String usage: String -> String
  (str "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"" content "\""
       (if (stringEmpty? reasoning) "" (str ",\"reasoning_content\":\"" reasoning "\""))
       "},\"finish_reason\":\"" finish "\"}],\"usage\":" usage "}")

fn reply model: String content: String finish: String reasoning: String -> String
  (replyUsing model content finish reasoning "{\"prompt_tokens\":5,\"completion_tokens\":32768,\"total_tokens\":32773}")

fn request intent: String -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (list (pair "X-ASL-Intent" intent))
                  :body "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}")

fn statusOf head: (List ch/HeadItem) -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus code) code) (_ acc))) 200 head)

fn ! drive! srv: srv/GatewayLoop step: ch/ChatStep stub: (fn [String] -> String) models: (List String) notes: (List String) fuel: Int64 -> Run
  (if (<= fuel 0)
    (Run :models models :status 0 :body "" :end "fuel" :notes notes)
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effHttp _ model _ _ _ _ _ _)
          (drive! srv (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (stub model)))) stub (listAppend models (list model)) notes (- fuel 1)))
         (_ (let [(r (srv/runEffect! srv eff))
                  (seen (match eff ((ch/effUsageNote _ _ o _) (listAppend notes (list o))) (_ notes)))]
              (drive! (pairFirst r) (k (pairSecond r)) stub models seen (- fuel 1))))))
      ((ch/stepDone resp) (Run :models models :status (statusOf resp.head) :body resp.body :end "done" :notes notes))
      ((ch/stepRaised kind msg) (Run :models models :status 0 :body "" :end (str "raised " kind ": " msg) :notes notes))))

fn ! once! tag: String intent: String stub: (fn [String] -> String) -> Run
  (let [(dir (str "/tmp/gwEmptyLength-" tag "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate dir))
        (_2 (dirCreate (str dir "/.asl")))
        (_3 (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir) "\n")))
        (run (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
               ((err e) (Run :models (list) :status 0 :body "" :end (str "linkOpen: " e) :notes (list)))
               ((ok loop)
                (match (u/upstreamSettings (testEnv))
                  ((err e) (Run :models (list) :status 0 :body "" :end (str "settings: " e) :notes (list)))
                  ((ok settings)
                   (let [(world (ch/ChatWorld :env (testEnv) :rootDir "/" :settings settings :agyPromptMaxBytes 10000
                                              :table (c/gatewayProfilesLoadText! "/test" true (ok (configText dir)) "")))]
                     (drive! loop (ch/chatStart! (request intent) world) stub (list) (list) 200)))))))
        (_4 (removeTree! dir))]
    run)

fn lengthEmpty model: String -> String
  (reply model "" "length" "thinking thinking thinking")

; (:m :do "removes a scratch tree in process (no rm child, so noSelfHost counts no start)")
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
  (let [(solo (once! "solo" "solo" (fn [(m String)] -> String (lengthEmpty m))))
        (cascade (once! "any" "any" (fn [(m String)] -> String (if (= m "model-1") (lengthEmpty m) (reply m "(:step ok)" "stop" "")))))
        (plain (once! "plain" "solo" (fn [(m String)] -> String (reply m "" "stop" ""))))
        (cut (once! "cut" "solo" (fn [(m String)] -> String (replyUsing m "" "stop" "" "{\"prompt_tokens\":0,\"completion_tokens\":0,\"total_tokens\":0}"))))]
    (do (assert (= solo.end "done") (str "the single-member chat ends: " solo.end))
        (assert (= solo.models (list "model-1")) (str "a length-empty reply is not retried on the same model, asked: " (stringJoin solo.models " ")))
        (assert (and (= solo.status 502) (stringContains? solo.body "ERR_EMPTY_LENGTH") (stringContains? solo.body "finish_reason length") (stringContains? solo.body "26 reasoning chars"))
                (str "a single member answers 502 ERR_EMPTY_LENGTH naming the cap and the reasoning spent: " (stringFromInt64 solo.status) " " solo.body))
        (assert (and (= cascade.status 200) (= cascade.models (list "model-1" "model-2"))) (str "a cascade moves past a length-empty member to the next: " (stringFromInt64 cascade.status) " " (stringJoin cascade.models " ")))
        (assert (and (= plain.models (list "model-1" "model-1")) (stringContains? plain.body "ERR_EMPTY_CONTENT")) (str "an empty reply that did not stop at length keeps its same-model retry: " (stringJoin plain.models " ") " " plain.body))
        (assert (and (= cut.models (list "model-1" "model-1")) (listContains? cut.notes "upstreamCut") (not (listContains? cut.notes "empty")))
                (str "an empty 200 with zero usage is noted upstreamCut and keeps its retry: " (stringJoin cut.models " ") " notes " (stringJoin cut.notes " ")))
        (assert (and (listContains? plain.notes "empty") (not (listContains? plain.notes "upstreamCut"))) (str "an empty reply that counted tokens stays noted empty: " (stringJoin plain.notes " ")))
        true))
