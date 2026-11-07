(module aslGateway/tests/sseStreamTest
  :x [runTests]
  :i [(chat :a ch)
      (server :a srv)
      (upstream :a u)
      (config :a c)
      (pyText :a pt)
      (asl-json/json :a j)
      (asl-tools/fleet/run :a fr)])

; (:m :ref GW-SYNTHETIC-INFINITE-STREAM :do "a model row :stream true (Synthetic infinite mode answers only stream=true): the chat cascade sends stream and stream_options include_usage to that row only and folds the SSE reply into one chat completion with content, reasoning and usage; the same holds over the real in-process link and curl against a stand-in SSE upstream (fixtures/sseUpstream.asl) started through fleet/run.asl guardStart! with a deadline, that pauses between chunks and refuses a request without stream")

(schema Run
  (:f datas (List String))
  (:f status Int64)
  (:f body String)
  (:f end String))

fn configText dir: String base: String -> String
  (str "(:gateway :v 2 :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id syn :kind openai :base \"" base "\" :keyEnv \"SYN_TEST_KEY\"))"
       " :models ((:model :id s1 :provider syn :name \"syn-1017\" :stream true :timeoutSec 30) (:model :id p1 :provider syn :name \"plain-1\"))"
       " :intents ((:intent :id solo) (:intent :id plain))"
       " :profiles ((:profile :id default :routes ((:intent solo :chain (s1)) (:intent plain :chain (p1)))))"
       " :uses ((:use :for default :profile default)))")

fn testEnv -> (Map String String)
  (mapSet (mapEmpty) "SYN_TEST_KEY" "test-key")

fn sseText -> String
  (str "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"think \"},\"finish_reason\":null}]}\n\n"
       ": keepalive\n\n"
       "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"more\"},\"finish_reason\":null}]}\n\n"
       "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"(:step \"},\"finish_reason\":null}]}\n\n"
       "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok)\"},\"finish_reason\":\"stop\"}]}\n\n"
       "data: {\"id\":\"s1\",\"model\":\"syn-1017\",\"choices\":[],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":3,\"total_tokens\":10}}\n\n"
       "data: [DONE]\n\n")

fn plainReply -> String
  "{\"id\":\"p\",\"object\":\"chat.completion\",\"model\":\"plain-1\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"(:step plain)\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}"

fn request intent: String -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (list (pair "X-ASL-Intent" intent))
                  :body "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}")

fn statusOf head: (List ch/HeadItem) -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus code) code) (_ acc))) 200 head)

fn ! drive! srv: srv/GatewayLoop step: ch/ChatStep datas: (List String) fuel: Int64 -> Run
  (if (<= fuel 0)
    (Run :datas datas :status 0 :body "" :end "fuel")
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effHttp _ model _ _ req _ _ _)
          (let [(body (if (= model "syn-1017") (sseText) (plainReply)))
                (reply (ch/httpOk 200 (list (pair "Content-Type" (if (= model "syn-1017") "text/event-stream" "application/json"))) body))]
            (drive! srv (k (ch/outHttp reply)) (listAppend datas (list req.data)) (- fuel 1))))
         (_ (let [(r (srv/runEffect! srv eff))] (drive! (pairFirst r) (k (pairSecond r)) datas (- fuel 1))))))
      ((ch/stepDone resp) (Run :datas datas :status (statusOf resp.head) :body resp.body :end "done"))
      ((ch/stepRaised kind msg) (Run :datas datas :status 0 :body "" :end (str "raised " kind ": " msg)))))

fn ! home! tag: String base: String -> String
  (let [(dir (str "/tmp/gwSseStream-" tag "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate dir))
        (_2 (dirCreate (str dir "/.asl")))
        (_3 (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir base) "\n")))]
    dir)

fn ! drop! dir: String -> Bool
  (if (stringStartsWith? dir "/tmp/gwSseStream-")
    (= (processRun (str "/bin/rm -rf '" dir "'")).exitCode 0)
    false)

fn ! once! tag: String intent: String -> Run
  (let [(dir (home! tag "https://example.test/v1"))
        (run (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
               ((err e) (Run :datas (list) :status 0 :body "" :end (str "linkOpen: " e)))
               ((ok loop)
                (match (u/upstreamSettings (testEnv))
                  ((err e) (Run :datas (list) :status 0 :body "" :end (str "settings: " e)))
                  ((ok settings)
                   (let [(world (ch/ChatWorld :env (testEnv) :rootDir "/" :settings settings :agyPromptMaxBytes 10000
                                              :table (c/gatewayProfilesLoadText! "/test" true (ok (configText dir "https://example.test/v1")) "")))]
                     (drive! loop (ch/chatStart! (request intent) world) (list) 200)))))))
        (_ (drop! dir))]
    run)

fn compact s: String -> String
  (stringReplace (stringReplace s " " "") "\n" "")

fn path v: j/Json keys: (List String) -> j/Json
  (match (listHead keys)
    ((none) v)
    ((some k)
      (let [(rest (optionOr (listTail keys) (list)))
            (next (match v
                    ((j/jarr xs) (optionOr (listGet xs (optionOr (stringToInt64 k) 0)) (j/jnull)))
                    (_ (optionOr (pt/jget v k) (j/jnull)))))]
        (path next rest))))

fn textAt body: String keys: (List String) -> String
  (match (pt/jsonLoads body)
    ((ok v) (match (path v keys) ((j/jstr s) s) (_ "")))
    ((err _) ""))

fn intAt body: String keys: (List String) -> Int64
  (match (pt/jsonLoads body)
    ((ok v) (match (path v keys) ((j/jint n) n) (_ -1)))
    ((err _) -1))

fn ! testCascade -> Bool
  (let [(s (once! "solo" "solo"))
        (p (once! "plain" "plain"))
        (sData (compact (optionOr (listHead s.datas) "")))
        (pData (compact (optionOr (listHead p.datas) "")))]
    (do (assert (and (= s.end "done") (= s.status 200)) (str "the stream row answers 200 through the cascade: " s.end " " (stringFromInt64 s.status)))
        (assert (and (stringContains? sData "\"stream\":true") (stringContains? sData "\"include_usage\":true")) (str "the stream row sends stream and stream_options include_usage: " sData))
        (assert (and (not (stringContains? pData "\"stream\"")) (not (stringContains? pData "stream_options"))) (str "a row without :stream sends the body unchanged: " pData))
        (assert (= (textAt s.body (list "choices" "0" "message" "content")) "(:step ok)") (str "content deltas are joined in order: " s.body))
        (assert (= (textAt s.body (list "choices" "0" "message" "reasoning_content")) "think more") (str "reasoning deltas are joined in order: " s.body))
        (assert (and (= (intAt s.body (list "usage" "completion_tokens")) 3) (= (intAt s.body (list "usage" "prompt_tokens")) 7)) (str "usage comes from the final chunk: " s.body))
        (assert (= (textAt s.body (list "choices" "0" "finish_reason")) "stop") (str "the last finish_reason is kept: " s.body))
        (assert (= (textAt p.body (list "choices" "0" "message" "content")) "(:step plain)") (str "a non-stream row still answers as before: " p.body))
        true))

fn ! testFold -> Bool
  (let [(calls (str "data: {\"id\":\"t\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"a\\\"\"}}]},\"finish_reason\":null}]}\n\n"
                    "data: {\"id\":\"t\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":1}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n"
                    "data: [DONE]\n\n"))
        (folded (optionOr (ch/sseToChat calls) ""))
        (broken (ch/sseToChat "data: {\"choices\":[{\"delta\":{\"content\":\"a\"}}]}\n\ndata: {not json\n\n"))
        (empty (ch/sseToChat ": only a comment\n\ndata: [DONE]\n\n"))]
    (do (assert (and (= (textAt folded (list "choices" "0" "message" "tool_calls" "0" "function" "name")) "read")
                     (= (textAt folded (list "choices" "0" "message" "tool_calls" "0" "function" "arguments")) "{\"a\":1}")
                     (= (textAt folded (list "choices" "0" "message" "tool_calls" "0" "id")) "c1"))
                (str "tool call deltas are joined per index: " folded))
        (assert (none? broken) "a data payload that is not JSON makes the whole stream unreadable, never a partial answer")
        (assert (none? empty) "a stream with no data event is unreadable")
        true))

fn ! waitFile! p: String tries: Int64 -> String
  (if (<= tries 0) ""
    (match (fileReadString p)
      ((ok t) (if (stringEmpty? (stringTrim t)) (do (sleepMs 50) (waitFile! p (- tries 1))) (stringTrim t)))
      ((err _) (do (sleepMs 50) (waitFile! p (- tries 1))))))

fn ! testWire -> Bool
  (let [(here (resultOr (realPath ".") "."))
        (dir (home! "wire" "http://127.0.0.1:1/v1"))
        (portFile (str dir "/port"))
        (seenFile (str dir "/seen.txt"))
        (g (fr/guardStart! (list (str here "/bin/asl") "run" (str here "/asl/packages/asl-gateway/tests/fixtures/sseUpstream.asl") portFile seenFile "1500" "20") here (fr/childEnv (list)) (fr/limits 60 20)))
        (port (match g ((ok _) (waitFile! portFile 600)) ((err _) "")))
        (_cfg (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir (str "http://127.0.0.1:" port "/v1")) "\n")))
        (sent (if (stringEmpty? port)
                (err "no port")
                (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
                  ((err e) (err (str "linkOpen: " e)))
                  ((ok l) (pairSecond (srv/linkSend! l "POST" "/v1/chat/completions" (list (pair "Content-Type" "application/json") (pair "Accept" "application/json") (pair "X-ASL-Intent" "solo"))
                                                     "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}" 60000))))))
        (out (match g ((ok gd) (fr/guardLoop gd)) ((err o) o)))
        (raw (match sent ((ok t) t) ((err e) (str "sendError " e))))
        (bodyAt (match (stringIndexOf raw "{") ((some i) (optionOr (stringSlice raw i (stringLength raw)) "")) ((none) "")))
        (seen (compact (resultOr (fileReadString seenFile) "")))
        (stubGone (fr/stubRemove!))
        (stubLeft (fr/stubDirsOwnedBy (procSelf)))
        (dropped (drop! dir))]
    (do (assert (and stubGone (listEmpty? stubLeft)) (str "the stand-in host dir of this run is removed before any assert: " (stringJoin stubLeft " ")))
        (assert (and (ok? g) (not (stringEmpty? port))) (str "the SSE upstream started and wrote its port: " port))
        (assert (= out.exitCode 0) (str "the SSE upstream answered one streamed request and exited 0: " (stringFromInt64 out.exitCode) " " out.stderr))
        (assert (stringContains? seen "\"stream\":true") (str "the in-process gateway sent stream true over curl: " seen))
        (assert (= (textAt bodyAt (list "choices" "0" "message" "content")) "(:step ok)") (str "the streamed content reaches the caller across pauses: " raw))
        (assert (= (intAt bodyAt (list "usage" "completion_tokens")) 3) (str "usage from the final chunk reaches the caller: " raw))
        (assert dropped "the scratch home is removed")
        true))

fn ! runTests -> Bool
  (let [(a (testFold))
        (b (testCascade))
        (w (testWire))]
    (and a (and b w)))
