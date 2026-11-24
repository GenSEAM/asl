(module aslGateway/tests/limitSeedTtlTest
  :x [runTests]
  :i [(aslGateway/config :a c)
      (aslGateway/limits :a lim)])

; (:m :ref GW-LIMIT-SEED-TTL-CONFIG :do "seed ttl config range and freshness boundary: 86401 and 0 are one config error, 600 clean; a seed exactly ttl old is refreshed while one ms younger is held; fixed now 1700000000000 ms and ttl 1000 ms")

fn cfgWith extra: String -> String
  (str "(:gateway :v 2" extra " :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id m1 :provider fp :name \"n1\")) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))")

fn ! runTests -> Bool
  (do
    (assert (= (pairSecond (c/gatewayConfigCheckText! (cfgWith " :limitSeedTtlSec 600") "src" ".asl/mem/calibration/index.asn")) 0) "limitSeedTtlSec 600 is a clean config")
    (assert (= (pairSecond (c/gatewayConfigCheckText! (cfgWith " :limitSeedTtlSec 0") "src" ".asl/mem/calibration/index.asn")) 1) "limitSeedTtlSec 0 is one config error")
    (assert (= (pairSecond (c/gatewayConfigCheckText! (cfgWith " :limitSeedTtlSec 86401") "src" ".asl/mem/calibration/index.asn")) 1) "limitSeedTtlSec 86401 is one config error")
    (assert (lim/needsSeedWithin? (- 1700000000000 1000) 1700000000000 1000) "a seed exactly ttl old is refreshed")
    (assert (not (lim/needsSeedWithin? (- 1700000000000 999) 1700000000000 1000)) "a seed 1 ms younger than ttl is held")
    true)
