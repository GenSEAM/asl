(module aslGateway/tests/federationWireTest
  :x [runTests]
  :i [(config :a cfg) (dispatch :a dp) (federation :a f) (secrets :a s) (upstream :a u)])

fn configText -> String
  "(:gateway :v 2 :providers ((:provider :id mac :kind gateway :base \"http://127.0.0.1:18080/v1\" :secret macToken)) :models ((:model :id m :provider mac :name \"agyFlash\")) :profiles ((:profile :id default :routes ((:intent any :chain (m))))) :uses ((:use :for default :profile default)))"

fn ! scratch! -> String
  (let [(d (str "/tmp/gwFedWire-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))]
    d)

fn ! drop! dir: String -> Bool
  (let [(_ (map (fn [(n String)] -> Bool (ok? (pathRemove (str dir "/" n)))) (resultOr (dirList dir) (list))))]
    (ok? (pathRemove dir)))

fn ! runTests -> Bool
  (let [(dir (scratch!))
        (p (str dir "/secrets.asn"))
        (_ (fileWrite p "(:secret :id macToken :value \"tok-WIRE-5b7c19e0\")\n(:secret :id gatewayServeToken :value \"tok-SERVE-77aa\")\n"))
        (_2 (fileChmod p 384))
        (parsed (cfg/gatewayConfigParse! (configText) "wireCfg" ".asl/mem/calibration/index.asn"))
        (bare (mapFromPairs (list (pair "PATH" "/usr/bin"))))
        (overlaid (f/secretsEnvOverlay! p bare))
        (absent (f/secretsEnvOverlay! (str dir "/none.asn") bare))
        (_3 (fileChmod p 420))
        (loose (f/secretsEnvOverlay! p bare))
        (_4 (fileChmod p 384))]
    (match parsed
      ((err e) (do (drop! dir) (assert false (str "config parses: " e)) false))
      ((ok table)
        (let [(st (resultOr (u/upstreamSettings bare) (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0)))
              (rows (dp/rowsFromTable (some table)))
              (row (u/upstreamProviderNamed rows "mac"))
              (env (resultOr overlaid bare))
              (wired (dp/wiringFromConfig (some table) "" st env (dp/builtinFamilies)))
              (unwired (dp/wiringFromConfig (some table) "" st bare (dp/builtinFamilies)))
              (noAuth (f/serveAuthError env (list)))
              (badAuth (f/serveAuthError env (list (pair "Authorization" "Bearer nope"))))
              (goodAuth (f/serveAuthError env (list (pair "authorization" "Bearer tok-SERVE-77aa"))))
              (noServeSecret (f/serveAuthError bare (list)))
              (cleaned (drop! dir))]
          (do
            (assert (match row ((some r) (and (= (r.url st env) "http://127.0.0.1:18080/v1") (= (r.key st env) "tok-WIRE-5b7c19e0"))) ((none) false)) "a :kind gateway row joins dispatch with its base and the bearer read from the secrets file")
            (assert (ok? wired) (str "wiring succeeds once the secrets are overlaid: " (match wired ((err e) e) ((ok _) ""))))
            (assert (match unwired ((err e) (and (stringContains? e "ERR_SECRET_MISSING") (stringContains? e "macToken"))) ((ok _) false)) "a provider whose secret is not in the env fails wiring with ERR_SECRET_MISSING naming the id")
            (assert (match absent ((ok m) (= (mapSize m) 1)) ((err _) false)) "a missing secrets file leaves the env untouched")
            (assert (match loose ((err e) (stringContains? e "ERR_SECRETS_PERMS")) ((ok _) false)) "a 0644 secrets file stops the overlay")
            (assert (match noAuth ((some e) (stringContains? e "401")) ((none) false)) "with a serve token configured a request without a bearer is a 401")
            (assert (match badAuth ((some e) (stringContains? e "401")) ((none) false)) "a wrong bearer is a 401")
            (assert (none? goodAuth) "the right bearer passes")
            (assert (none? noServeSecret) "without a serve token the gateway is open as before")
            cleaned)))))
