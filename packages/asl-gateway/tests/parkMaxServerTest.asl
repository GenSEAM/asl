(module aslGateway/tests/parkMaxServerTest
  :x [runTests]
  :i [(aslGateway/server :a srv) (aslGateway/config :a c) (aslGateway/breaker :a b)])

fn cfgText extra: String -> String
  (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))\n")

fn leftAfterMonthPark text: String -> Int64
  (pairSecond (b/breakerDownFor (b/breakerMarkDownFor (srv/breakerStateFromConfig text) "ollama" 1000 1388800) "ollama" 1000))

fn ! checked extra: String -> (Pair String Int64)
  (c/gatewayConfigCheckText! (cfgText extra) "src" ".asl/mem/calibration/index.asn")

; (:m :ref PARKMAX-SERVER-TEST :do "the breaker server.asl builds from a config text honours the :parkMaxSec row: a monthly park of 1388800 s is cut to the row's 86400 and kept whole without a row (default ceiling 32 days); config check refuses 59 and 2764801 and accepts the bounds 60 and 2764800")
fn ! runTests -> Bool
  (let [(capped (leftAfterMonthPark (cfgText " :parkMaxSec 86400")))
        (whole (leftAfterMonthPark (cfgText "")))
        (low (checked " :parkMaxSec 59"))
        (high (checked " :parkMaxSec 2764801"))
        (atFloor (checked " :parkMaxSec 60"))
        (atCeiling (checked " :parkMaxSec 2764800"))]
    (do
      (assert (= capped 86400) (str "a :parkMaxSec 86400 row caps the server's breaker park: " (stringFromInt64 capped)))
      (assert (= whole 1388800) (str "without the row the park is kept whole: " (stringFromInt64 whole)))
      (assert (and (= (pairSecond low) 1) (stringContains? (pairFirst low) "parkMaxSec")) (str "config check refuses :parkMaxSec 59: " (pairFirst low)))
      (assert (and (= (pairSecond high) 1) (stringContains? (pairFirst high) "parkMaxSec")) (str "config check refuses :parkMaxSec 2764801: " (pairFirst high)))
      (assert (= (pairSecond atFloor) 0) (str "config check accepts :parkMaxSec 60: " (pairFirst atFloor)))
      (assert (= (pairSecond atCeiling) 0) (str "config check accepts :parkMaxSec 2764800: " (pairFirst atCeiling)))
      true))
