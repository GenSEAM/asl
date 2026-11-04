(module aslAgent/tests/attribHeadersTest
  :x [runTests]
  :i [(aslAgent/providers :a pv)])

fn hasHeader hs: (List (Pair String String)) k: String v: String -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (and (= (pairFirst p) k) (= (pairSecond p) v))) hs)

fn hasKey hs: (List (Pair String String)) k: String -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) k)) hs)

fn cfgAt turn: Int64 -> pv/VendorConfig
  (pv/VendorConfig :vendor "agy" :mode "scout" :rootDir "/tmp" :model "m" :timeout 10 :queueTimeout 10 :sessionId "s1" :intent "auto"
    :timeoutSet false :env (pv/ProviderEnv :gatewayUrl "" :inProcess false :profile "" :gatewayConfig "" :tmpDir "/tmp" :childEnv (mapEmpty)) :link none :turn turn)

; (:m LEON-ATTRIB: every Leon gateway call names its consumer, and carries a turn header only once a main turn has run)
fn ! runTests -> Bool
  (let [(h0 (pv/attribHeaders (cfgAt 0)))
        (h3 (pv/attribHeaders (cfgAt 3)))]
    (do
      (assert (hasHeader h0 "X-ASL-Consumer" "leon") "consumer leon before the first turn")
      (assert (not (hasKey h0 "X-ASL-Turn")) "no turn header before any main turn")
      (assert (hasHeader h3 "X-ASL-Consumer" "leon") "consumer leon on turn 3")
      (assert (hasHeader h3 "X-ASL-Turn" "3") "turn header is the main-turn number")
      true))
