(module aslGateway/tests/modesTest
  :x [runTests]
  :i [(chat :a ch)
      (server :a srv)
      (upstream :a u)
      (config :a c)])

; (:m :ref GW-MODES :do "profile modes through the real chat cascade and the real server effects (srv/runEffect!) with a stubbed upstream per model: pin relays the first member's 400 and never asks the second, route moves on; judge moves on a reasoning-only empty reply, a truncated one and a step-less one for a step intent, all of which route returns; :judge rows switch checks off; bad mode and judge rows fail config check")

(schema Run
  (:f models (List String))
  (:f status Int64)
  (:f end String))

fn configText dir: String profileExtra: String -> String
  (str "(:gateway :v 2 :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))"
       " :models ((:model :id m1 :provider test :name \"model-1\") (:model :id m2 :provider test :name \"model-2\"))"
       " :intents ((:intent :id code) (:intent :id solo))"
       " :profiles ((:profile :id default " profileExtra " :routes ((:intent solo :chain (m1)) (:intent any :chain (m1 m2)))))"
       " :uses ((:use :for default :profile default)))")

fn testEnv -> (Map String String)
  (mapSet (mapEmpty) "TEST_KEY" "test-key")

fn jesc t: String -> String
  (stringReplace (stringReplace t "\\" "\\\\") "\"" "\\\"")

fn okReply model: String content: String finish: String reasoning: String -> String
  (str "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"" (jesc content) "\""
       (if (stringEmpty? reasoning) "" (str ",\"reasoning_content\":\"" (jesc reasoning) "\""))
       "},\"finish_reason\":\"" finish "\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}")

fn request intent: String excl: String -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (if (stringEmpty? excl) (list (pair "X-ASL-Intent" intent)) (list (pair "X-ASL-Intent" intent) (pair "X-ASL-Exclude-Model" excl)))
                  :body "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}")

fn statusOf head: (List ch/HeadItem) -> Int64
  (fold (fn [(acc Int64) (h ch/HeadItem)] -> Int64 (match h ((ch/headStatus c) c) (_ acc))) 200 head)

fn ! drive! srv: srv/GatewayLoop step: ch/ChatStep stub: (fn [String] -> (Pair Int64 String)) models: (List String) fuel: Int64 -> Run
  (if (<= fuel 0)
    (Run :models models :status 0 :end "fuel")
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effHttp _ model _ _ _ _ _ _)
          (let [(answer (stub model))
                (reply (if (= (pairFirst answer) 200)
                         (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (pairSecond answer))
                         (ch/httpError (pairFirst answer) "Bad Request" (list (pair "Content-Type" "application/json")) (pairSecond answer))))]
            (drive! srv (k (ch/outHttp reply)) stub (listAppend models (list model)) (- fuel 1))))
         (_ (let [(r (srv/runEffect! srv eff))] (drive! (pairFirst r) (k (pairSecond r)) stub models (- fuel 1))))))
      ((ch/stepDone resp) (Run :models models :status (statusOf resp.head) :end "done"))
      ((ch/stepRaised kind msg) (Run :models models :status 0 :end (str "raised " kind ": " msg)))))

fn ! home! tag: String extra: String -> String
  (let [(dir (str "/tmp/gwModes-" tag "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate dir))
        (_2 (dirCreate (str dir "/.asl")))
        (_3 (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir extra) "\n")))]
    dir)

fn ! drop! dir: String -> Bool
  (let [(_ (map (fn [(sub String)] -> Bool (ok? (pathRemove (str dir "/" sub)))) (list ".asl/gateway.asn" ".asl" "calls.asn" "shared.asn")))]
    (ok? (pathRemove dir)))

; (:m :do "one request through a fresh scratch gateway whose default profile carries extra; the HOME is removed before the result returns")
fn ! once! tag: String extra: String intent: String stub: (fn [String] -> (Pair Int64 String)) -> Run
  (onceExcl! tag extra intent "" stub)

fn ! onceExcl! tag: String extra: String intent: String excl: String stub: (fn [String] -> (Pair Int64 String)) -> Run
  (let [(dir (home! tag extra))
        (run (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
               ((err e) (Run :models (list) :status 0 :end (str "linkOpen: " e)))
               ((ok loop)
                (match (u/upstreamSettings (testEnv))
                  ((err e) (Run :models (list) :status 0 :end (str "settings: " e)))
                  ((ok settings)
                   (let [(world (ch/ChatWorld :env (testEnv) :rootDir "/" :settings settings :agyPromptMaxBytes 10000
                                              :table (c/gatewayProfilesLoadText! "/test" true (ok (configText dir extra)) "")))]
                     (drive! loop (ch/chatStart! (request intent excl) world) stub (list) 200)))))))
        (_ (drop! dir))]
    run)

fn firstFails code: Int64 bad: String good: String -> (fn [String] -> (Pair Int64 String))
  (fn [(model String)] -> (Pair Int64 String)
    (if (= model "model-1") (pair code bad) (pair 200 good)))

fn badRequest -> String
  "{\"error\":{\"message\":\"tools are not supported\",\"type\":\"invalid_request_error\"}}"

; (:m :ref GW-MODES :do "pin never asks a second member and relays the first member's status; route under the same stub moves on and answers")
fn ! testPin -> Bool
  (let [(stub (firstFails 400 (badRequest) (okReply "model-2" "(:step ok)" "stop" "")))
        (pin (once! "pin" ":mode pin" "any" stub))
        (route (once! "route" "" "any" stub))
        (pinOk (once! "pinOk" ":mode pin" "any" (fn [(m String)] -> (Pair Int64 String) (pair 200 (okReply m "(:step ok)" "stop" "")))))
        (blank (firstFails 200 (okReply "model-1" "" "stop" "") (okReply "model-2" "(:step ok)" "stop" "")))
        (pinBlank (once! "pinBlank" ":mode pin" "any" blank))
        (routeBlank (once! "routeBlank" "" "any" blank))]
    (do (assert (= pin.end "done") (str "pin ends with a response: " pin.end))
        (assert (= pin.models (list "model-1")) (str "pin asks only the first member, got " (stringJoin pin.models " ")))
        (assert (= pin.status 400) (str "pin relays the member's 400, got " (stringFromInt64 pin.status)))
        (assert (= route.models (list "model-1" "model-2")) (str "route moves on after the 400, got " (stringJoin route.models " ")))
        (assert (= route.status 200) (str "route answers from model-2, got " (stringFromInt64 route.status)))
        (assert (and (= pinOk.status 200) (= pinOk.models (list "model-1"))) "pin answers from its member when it works")
        (assert (= routeBlank.models (list "model-1" "model-2")) (str "route cascades past an empty reply, got " (stringJoin routeBlank.models " ")))
        (assert (not (listContains? pinBlank.models "model-2")) (str "pin never cascades past an empty reply, got " (stringJoin pinBlank.models " ")))
        (assert (= pinBlank.status 502) (str "pin ends an empty reply in 502, got " (stringFromInt64 pinBlank.status)))
        true))

fn reasoningOnly model: String -> String
  (okReply model "" "stop" "thinking without an answer")

; (:m :ref GW-MODES :do "judge moves on replies route returns: reasoning-only empty, truncated, step-less for a step intent; rows turn checks off; when every member fails the profile answers 502")
fn ! testJudge -> Bool
  (let [(good (okReply "model-2" "(:step ok)" "stop" ""))
        (emptyJ (once! "judgeEmpty" ":mode judge" "any" (firstFails 200 (reasoningOnly "model-1") good)))
        (emptyR (once! "routeEmpty" "" "any" (firstFails 200 (reasoningOnly "model-1") good)))
        (cutJ (once! "judgeCut" ":mode judge" "any" (firstFails 200 (okReply "model-1" "(:step half" "length" "") good)))
        (cutR (once! "routeCut" "" "any" (firstFails 200 (okReply "model-1" "(:step half" "length" "") good)))
        (stepJ (once! "judgeStep" ":mode judge :judge (:stepIntents (code))" "code" (firstFails 200 (okReply "model-1" "plain prose" "stop" "") good)))
        (stepOther (once! "judgeStepAny" ":mode judge :judge (:stepIntents (code))" "any" (firstFails 200 (okReply "model-1" "plain prose" "stop" "") good)))
        (off (once! "judgeOff" ":mode judge :judge (:empty false :truncated false)" "any" (firstFails 200 (reasoningOnly "model-1") good)))
        (allBad (once! "judgeAll" ":mode judge" "any" (fn [(m String)] -> (Pair Int64 String) (pair 200 (reasoningOnly m)))))]
    (do (assert (= emptyR.models (list "model-1")) (str "route returns the reasoning-only reply of model-1, got " (stringJoin emptyR.models " ")))
        (assert (= emptyJ.models (list "model-1" "model-2")) (str "judge moves on the empty reply, got " (stringJoin emptyJ.models " ")))
        (assert (= emptyJ.status 200) "judge answers from model-2")
        (assert (= cutR.models (list "model-1")) "route returns the truncated reply")
        (assert (= cutJ.models (list "model-1" "model-2")) (str "judge moves on finish_reason length, got " (stringJoin cutJ.models " ")))
        (assert (= stepJ.models (list "model-1" "model-2")) (str "judge moves on a step-less answer for a step intent, got " (stringJoin stepJ.models " ")))
        (assert (= stepOther.models (list "model-1")) "an intent outside :stepIntents keeps a step-less answer")
        (assert (= off.models (list "model-1")) (str ":judge (:empty false) keeps the reasoning-only reply, got " (stringJoin off.models " ")))
        (assert (and (= allBad.models (list "model-1" "model-2")) (= allBad.status 502)) (str "every member failing a check ends 502, got " (stringFromInt64 allBad.status)))
        true))

; (:m :ref GW-MODES :do "config check: bad :mode and :judge rows are errors naming the profile, sound ones pass")
fn ! testCheck -> Bool
  (let [(check (fn [(extra String)] -> (Pair String Int64) (c/gatewayConfigCheckText! (configText "/tmp/x" extra) "t.asn" "")))
        (good (check ":mode judge :judge (:empty true :truncated false :stepIntents (code) :stepHeads (\"(:step\" \"(:done\"))"))
        (pin (check ":mode pin"))
        (mode (check ":mode decide"))
        (key (check ":mode judge :judge (:wat true)"))
        (flag (check ":mode judge :judge (:empty maybe)"))
        (items (check ":mode judge :judge (:stepIntents code)"))]
    (do (assert (= (pairSecond good) 0) (str "sound judge rows pass: " (pairFirst good)))
        (assert (= (pairSecond pin) 0) (str ":mode pin passes: " (pairFirst pin)))
        (assert (and (= (pairSecond mode) 1) (stringContains? (pairFirst mode) ":mode must be pin, route or judge")) (str "an unknown mode is an error: " (pairFirst mode)))
        (assert (stringContains? (pairFirst key) "unknown :judge key :wat") (str "an unknown judge key is an error: " (pairFirst key)))
        (assert (stringContains? (pairFirst flag) ":judge :empty must be true or false") (str "a non-boolean check is an error: " (pairFirst flag)))
        (assert (stringContains? (pairFirst items) ":judge :stepIntents must be a list") (str "a bare step intent is an error: " (pairFirst items)))
        true))

; (:m :ref D7-FIX :do "X-ASL-Exclude-Model drops matching members; a cascade whose every member matches answers 400 excludedAll and asks no model, so the grader cannot be the writer; a mixed cascade keeps the other member")
fn ! testExclude -> Bool
  (let [(good (fn [(m String)] -> (Pair Int64 String) (pair 200 (okReply m "(:step ok)" "stop" ""))))
        (mixed (onceExcl! "exMixed" "" "any" "m1" good))
        (solo (onceExcl! "exSolo" ":mode pin" "any" "m1" good))
        (all (onceExcl! "exAll" "" "solo" "m1" good))
        (soloOk (onceExcl! "exSoloOk" "" "solo" "" good))
        (none (onceExcl! "exNone" "" "any" "" good))]
    (do (assert (= mixed.models (list "model-2")) (str "a mixed cascade keeps the non-matching member, got " (stringJoin mixed.models " ")))
        (assert (= none.models (list "model-1")) "no exclude asks the first member")
        (assert (= solo.models (list "model-2")) (str "pin skips the excluded first member, got " (stringJoin solo.models " ")))
        (assert (and (= all.status 400) (= all.end "done") (listEmpty? all.models)) (str "every member excluded answers 400 and asks no model, got " (stringFromInt64 all.status) " " (stringJoin all.models " ")))
        (assert (and (= soloOk.status 200) (= soloOk.models (list "model-1"))) "the solo route works when nothing is excluded")
        true))

fn ! runTests -> Bool
  (let [(p (testPin))
        (j (testJudge))
        (k (testCheck))
        (e (testExclude))]
    (and p (and j (and k e))))
