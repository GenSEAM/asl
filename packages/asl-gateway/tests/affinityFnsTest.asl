(module aslGateway/tests/affinityFnsTest
  :x [runTests]
  :i [(affinity :a af)
      (chat :a ch)
      (asl-json/json :a j)])

; (:m :ref COVERAGE-RATCHET-RED :do "direct cases for the session-affinity functions: the default row, config text over :affinity :affinityStickSec :affinityForgetSec :affinitySwitch, the answer for a session as the stick window and the forget window pass, the note that records an answer and drops stale sessions, and the two chat effects as wire ops")
fn recAt alias: String atMs: Int64 -> af/AffinityRecord
  (af/AffinityRecord :alias alias :atMs atMs)

fn table -> (Map String af/AffinityRecord)
  (mapSet (mapEmpty) "s1" (recAt "a1" 1000000))

fn gw extra: String -> String
  (str "(:gateway :v 2 " extra ")")

fn testConfig -> Bool
  (let [(d (af/affinityDefault))
        (none1 (af/affinityConfigFromText (gw "")))
        (all (af/affinityConfigFromText (gw ":affinity false :affinityStickSec 600 :affinityForgetSec 3600 :affinitySwitch keep")))
        (inverted (af/affinityConfigFromText (gw ":affinityStickSec 600 :affinityForgetSec 60")))
        (zero (af/affinityConfigFromText (gw ":affinityStickSec 0")))
        (reasoning (af/affinityConfigFromText (gw ":affinitySwitch dropReasoning")))
        (broken (af/affinityConfigFromText "((("))]
    (do (assert (and d.on (and (= d.stickSec 1800) (and (= d.forgetSec 86400) d.dropOnSwitch))) "the default is on, stick 1800 s, forget one day, drop reasoning on a switch")
        (assert (= none1 d) "a config without affinity rows is the default")
        (assert (= broken d) "unparseable text is the default")
        (assert (and (not all.on) (and (= all.stickSec 600) (and (= all.forgetSec 3600) (not all.dropOnSwitch)))) "every affinity row is read")
        (assert (= inverted.forgetSec 600) "a forget window under the stick window is raised to it")
        (assert (and (= zero.stickSec 1) (= zero.forgetSec 86400)) "a stick window under 1 s is raised to 1 s")
        (assert reasoning.dropOnSwitch ":affinitySwitch dropReasoning drops reasoning")
        true))

fn testAnswer -> Bool
  (let [(cfg (af/affinityDefault))
        (st (table))
        (t0 1000000)]
    (do (assert (= (af/affinityAnswer cfg st "s1" (+ t0 1000)) (list "a1" "1" "1" "0")) "a live session answers its member, sticking, dropping reasoning")
        (assert (= (af/affinityAnswer cfg st "s1" (+ t0 1800000)) (list "a1" "1" "1" "0")) "the stick window includes its last instant")
        (assert (= (af/affinityAnswer cfg st "s1" (+ t0 1801000)) (list "a1" "0" "1" "0")) "past the stick window the member is preferred, not forced")
        (assert (= (af/affinityAnswer cfg st "s1" (+ t0 86400000)) (list "a1" "0" "1" "0")) "the forget window includes its last instant")
        (assert (= (af/affinityAnswer cfg st "s1" (+ t0 86401000)) (list)) "past the forget window the session is forgotten")
        (assert (= (af/affinityAnswer cfg st "other" (+ t0 1000)) (list)) "an unknown session has no answer")
        (assert (= (af/affinityAnswer cfg st "" (+ t0 1000)) (list)) "an empty session key has no answer")
        (assert (= (af/affinityAnswer (af/AffinityConfig :on false :stickSec 1800 :forgetSec 86400 :dropOnSwitch true :waitSec 30) st "s1" (+ t0 1000)) (list)) "affinity off answers nothing")
        (assert (= (af/affinityAnswer (af/AffinityConfig :on true :stickSec 1800 :forgetSec 86400 :dropOnSwitch false :waitSec 30) st "s1" (+ t0 1000)) (list "a1" "1" "0" "30")) "keep policy answers drop 0")
        true))

fn testNote -> Bool
  (let [(cfg (af/affinityDefault))
        (st (table))
        (later (+ 1000000 86401000))
        (swapped (af/affinityNote cfg st "s1" "a2" 2000000))
        (grown (af/affinityNote cfg st "s2" "b1" 2000000))
        (swept (af/affinityNote cfg st "s2" "b1" later))]
    (do (assert (= (mapGet swapped "s1") (some (recAt "a2" 2000000))) "a note replaces the member and time of the session")
        (assert (and (= (mapGet grown "s1") (some (recAt "a1" 1000000))) (= (mapGet grown "s2") (some (recAt "b1" 2000000)))) "a note for another session keeps the live ones")
        (assert (and (= (mapGet swept "s1") (none)) (= (mapGet swept "s2") (some (recAt "b1" later)))) "a note forgets sessions older than the forget window")
        (assert (= (af/affinityNote cfg st "" "a2" 2000000) st) "an empty session is not recorded")
        (assert (= (af/affinityNote cfg st "s2" "" 2000000) st) "an empty alias is not recorded")
        (assert (= (af/affinityNote (af/AffinityConfig :on false :stickSec 1 :forgetSec 1 :dropOnSwitch true :waitSec 30) st "s2" "b1" 2000000) st) "affinity off records nothing")
        true))

fn testEffects -> Bool
  (let [(ask (j/jsonEmit (ch/effectJson (ch/effAffinity "sess-1"))))
        (note (j/jsonEmit (ch/effectJson (ch/effAffinityNote "sess-1" "m2"))))]
    (do (assert (and (stringContains? ask "affinity") (stringContains? ask "sess-1")) (str "the ask names the op and the session: " ask))
        (assert (not (stringContains? ask "affinityNote")) "the ask is not the note")
        (assert (and (stringContains? note "affinityNote") (and (stringContains? note "sess-1") (stringContains? note "m2"))) (str "the note names the op, the session and the alias: " note))
        true))

fn ! runTests -> Bool
  (do (testConfig) (testAnswer) (testNote) (testEffects) true)
