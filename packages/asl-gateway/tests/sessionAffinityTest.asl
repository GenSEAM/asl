(module aslGateway/tests/sessionAffinityTest
  :x [runTests]
  :i [(chat :a ch)
      (server :a srv)
      (upstream :a u)
      (config :a c)])

; (:m :ref GW-SESSION-AFFINITY :do "turns of one X-ASL-Session through the real chat cascade and the real server effects (srv/runEffect!) under a 1:1 spread route: the second turn lands on the member that answered the first, a switch forced by a breaker drops the previous member's reasoning from the forwarded transcript, :affinity false lets the spread alternate, :affinitySwitch keep forwards the reasoning; only effHttp is stubbed")

(schema Sent
  (:f model String)
  (:f data String))

(schema Run
  (:f srv srv/GatewayLoop)
  (:f sent (List Sent))
  (:f end String))

fn configText dir: String extra: String -> String
  (str "(:gateway :v 2 " extra " :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))"
       " :models ((:model :id m1 :provider test :name \"model-1\") (:model :id m2 :provider test :name \"model-2\"))"
       " :profiles ((:profile :id default :routes ((:intent any :chain (m1 m2) :spread ((m1 1) (m2 1))))))"
       " :uses ((:use :for default :profile default)))")

fn testEnv -> (Map String String)
  (mapSet (mapEmpty) "TEST_KEY" "test-key")

fn reply model: String -> String
  (str "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"" model "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"ok\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}")

fn firstTurn -> String
  "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":10}"

fn laterTurn -> String
  "{\"messages\":[{\"role\":\"user\",\"content\":\"hi\"},{\"role\":\"assistant\",\"content\":\"ok\",\"reasoning_content\":\"R1-THOUGHT\"},{\"role\":\"user\",\"content\":\"again\"}],\"max_tokens\":10}"

fn request session: String body: String -> ch/ChatRequest
  (ch/ChatRequest :path "/v1/chat/completions" :headers (list (pair "X-ASL-Intent" "any") (pair "X-ASL-Session" session)) :body body)

fn ! drive! srv: srv/GatewayLoop step: ch/ChatStep sent: (List Sent) fuel: Int64 -> Run
  (if (<= fuel 0)
    (Run :srv srv :sent sent :end "fuel")
    (match step
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effHttp _ model _ _ req _ _ _)
          (drive! srv (k (ch/outHttp (ch/httpOk 200 (list (pair "Content-Type" "application/json")) (reply model))))
                  (listAppend sent (list (Sent :model model :data req.data))) (- fuel 1)))
         (_ (let [(r (srv/runEffect! srv eff))] (drive! (pairFirst r) (k (pairSecond r)) sent (- fuel 1))))))
      ((ch/stepDone _) (Run :srv srv :sent sent :end "done"))
      ((ch/stepRaised kind msg) (Run :srv srv :sent sent :end (str "raised " kind ": " msg)))))

fn ! turn! srv: srv/GatewayLoop world: ch/ChatWorld session: String body: String -> Run
  (drive! srv (ch/chatStart! (request session body) world) (list) 200)

fn lastSent r: Run -> Sent
  (optionOr (listHead (listReverse r.sent)) (Sent :model "" :data ""))

fn aliasOf model: String -> String
  (if (= model "model-1") "m1" "m2")

fn ! home! tag: String extra: String -> String
  (let [(dir (str "/tmp/gwAffinity-" tag "-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (_ (dirCreate dir))
        (_2 (dirCreate (str dir "/.asl")))
        (_3 (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir extra) "\n")))]
    dir)

fn ! drop! dir: String -> Bool
  (let [(_ (map (fn [(sub String)] -> Bool (ok? (pathRemove (str dir "/" sub)))) (list ".asl/gateway.asn" ".asl" "calls.asn" "shared.asn")))]
    (ok? (pathRemove dir)))

fn ! opened! dir: String extra: String -> (Option (Pair srv/GatewayLoop ch/ChatWorld))
  (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
    ((err e) (do (eprintln (str "linkOpen: " e)) none))
    ((ok loop)
     (match (u/upstreamSettings (testEnv))
       ((err _) none)
       ((ok settings)
        (some (pair loop (ch/ChatWorld :env (testEnv) :rootDir "/" :settings settings :agyPromptMaxBytes 10000
                                       :table (c/gatewayProfilesLoadText! "/test" true (ok (configText dir extra)) ""))))))))

; (:m :ref GW-SESSION-AFFINITY :do "default rows: stick, then a breaker-forced switch drops reasoning; a second session is routed on its own")
fn ! testStickAndSwitch -> Bool
  (let [(dir (home! "stick" ""))
        (o (opened! dir ""))]
    (match o
      ((none) (do (drop! dir) (assert false "the in-process gateway opens on the scratch HOME") false))
      ((some p)
       (let [(world (pairSecond p))
             (t1 (turn! (pairFirst p) world "affSess-1" (firstTurn)))
             (m1 (lastSent t1).model)
             (t2 (turn! t1.srv world "affSess-1" (laterTurn)))
             (down (pairFirst (srv/runEffect! t2.srv (ch/effBreakerEvent "markDown" (str "test:" (aliasOf m1)) 0))))
             (t3 (turn! down world "affSess-1" (laterTurn)))
             (cleaned (drop! dir))]
         (do (assert (= t1.end "done") (str "turn 1 ends with a reply: " t1.end))
             (assert (not (stringEmpty? m1)) "turn 1 dispatched a member")
             (assert (= t2.end "done") (str "turn 2 ends with a reply: " t2.end))
             (assert (= (lastSent t2).model m1) (str "turn 2 of the session stays on " m1 " under a 1:1 spread, got " (lastSent t2).model))
             (assert (stringContains? (lastSent t2).data "R1-THOUGHT") "the same member gets its own reasoning back")
             (assert (= t3.end "done") (str "turn 3 ends with a reply: " t3.end))
             (assert (!= (lastSent t3).model m1) (str "with " m1 " down the session moves on, got " (lastSent t3).model))
             (assert (not (stringContains? (lastSent t3).data "R1-THOUGHT")) "the switched-to member gets no reasoning written by the previous one")
             (assert (stringContains? (lastSent t3).data "again") "the switched transcript keeps the user turns")
             (assert cleaned "the scratch HOME is removed")
             true)))))

; (:m :ref GW-SESSION-AFFINITY :do "config rows: :affinity false lets the spread alternate the session; :affinitySwitch keep forwards reasoning across a switch")
fn ! offRows po: (Pair srv/GatewayLoop ch/ChatWorld) -> Bool
  (let [(a1 (turn! (pairFirst po) (pairSecond po) "affOff" (firstTurn)))
        (a2 (turn! a1.srv (pairSecond po) "affOff" (laterTurn)))]
    (do (assert (!= (lastSent a2).model (lastSent a1).model) (str ":affinity false: the 1:1 spread alternates the session, got " (lastSent a1).model " then " (lastSent a2).model))
        true))

fn ! keepRows pk: (Pair srv/GatewayLoop ch/ChatWorld) -> Bool
  (let [(k1 (turn! (pairFirst pk) (pairSecond pk) "affKeep" (firstTurn)))
        (km (lastSent k1).model)
        (kdown (pairFirst (srv/runEffect! k1.srv (ch/effBreakerEvent "markDown" (str "test:" (aliasOf km)) 0))))
        (k2 (turn! kdown (pairSecond pk) "affKeep" (laterTurn)))]
    (do (assert (!= (lastSent k2).model km) "keep: the breaker still moves the session")
        (assert (stringContains? (lastSent k2).data "R1-THOUGHT") ":affinitySwitch keep forwards the previous member's reasoning")
        true))

fn ! rowsAt! tag: String extra: String run: (fn [(Pair srv/GatewayLoop ch/ChatWorld)] -> Bool) -> Bool
  (let [(dir (home! tag extra))
        (ran (match (opened! dir extra)
               ((some p) (run p))
               ((none) (do (assert false (str "the " tag " scratch gateway opens")) false))))
        (cleaned (drop! dir))]
    (do (assert cleaned (str "the " tag " scratch HOME is removed"))
        ran))

; (:m :ref GW-SESSION-AFFINITY :do "config rows: :affinity false lets the spread alternate the session; :affinitySwitch keep forwards reasoning across a switch")
fn ! testRows -> Bool
  (let [(a (rowsAt! "off" ":affinity false" offRows))
        (b (rowsAt! "keep" ":affinitySwitch keep" keepRows))]
    (and a b))

; (:m :ref GW-SESSION-AFFINITY :do "config check: out-of-range or mistyped affinity rows are errors naming the key, sound ones pass")
fn ! testCheck -> Bool
  (let [(check (fn [(extra String)] -> (Pair String Int64) (c/gatewayConfigCheckText! (configText "/tmp/x" extra) "t.asn" "")))
        (good (check ":affinity true :affinityStickSec 600 :affinityForgetSec 3600 :affinitySwitch dropReasoning"))
        (stick (check ":affinityStickSec 0"))
        (order (check ":affinityStickSec 600 :affinityForgetSec 60"))
        (flag (check ":affinity maybe"))
        (switch (check ":affinitySwitch drop"))]
    (do (assert (= (pairSecond good) 0) (str "sound affinity rows pass: " (pairFirst good)))
        (assert (and (= (pairSecond stick) 1) (stringContains? (pairFirst stick) ":affinityStickSec")) (str "stick 0 is an error: " (pairFirst stick)))
        (assert (stringContains? (pairFirst order) ":affinityForgetSec must not be under :affinityStickSec") (str "forget under stick is an error: " (pairFirst order)))
        (assert (stringContains? (pairFirst flag) ":affinity must be true or false") (str "a non-boolean :affinity is an error: " (pairFirst flag)))
        (assert (stringContains? (pairFirst switch) ":affinitySwitch must be dropReasoning or keep") (str "an unknown switch policy is an error: " (pairFirst switch)))
        true))

fn ! runTests -> Bool
  (let [(a (testStickAndSwitch))
        (b (testRows))
        (k (testCheck))]
    (and a (and b k)))
