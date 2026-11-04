(module aslGateway/tests/configPathTest
  :x [runTests]
  :i [(aslAgent/providers :a pv)])

; (:m :ref GW-CONFIG-PATH-SUFFIX :do "the in-process gateway keeps its HOME/.asl/gateway.asn rule because the secrets file, ledger and sessions store are all derived from that HOME; a config path outside it is refused with ERR_CONFIG_PATH naming the rule and the path, not the generic ERR_GATEWAY_CONFIG")
fn ! runTests -> Bool
  (let [(e (pv/configPathRefusal "/tmp/sweep/custom.asn"))
        (msg (pv/errorMessage e))
        (root (str "/tmp/gwConfigPath-" (procSelf) "-" (nowNs)))
        (made (dirCreate root))
        (env (pv/ProviderEnv :gatewayUrl "" :inProcess true :profile "" :gatewayConfig (str root "/custom.asn") :tmpDir (str root "/tmp") :childEnv (mapEmpty)))
        (turn (match (pv/makeProvider! "agy" "scout" root "" 60 "sCfgPath" 30 false env "auto")
                ((err pe) (err pe))
                ((ok p) (ok (pv/nextTurn! p "s" "u")))))
        (endToEnd (match turn
                    ((err pe) (str "NOPROVIDER " (pv/errorMessage pe)))
                    ((ok t) (match t.reply ((ok _) "ok") ((err re) (str (pv/errorCode re) " " (pv/errorMessage re)))))))
        (removed (pathRemove root))]
    (do
      (assert (stringStartsWith? endToEnd "ERR_CONFIG_PATH ") (str "a non-suffix config path fails the whole in-process call with ERR_CONFIG_PATH: " endToEnd))
      (assert (stringContains? endToEnd (str root "/custom.asn")) (str "and names the rejected path: " endToEnd))
      (assert (ok? removed) "the scratch dir is removed")
      (assert (= (pv/errorCode e) "ERR_CONFIG_PATH") (str "the refusal carries the typed code, got " (pv/errorCode e)))
      (assert (stringContains? msg "/.asl/gateway.asn") (str "the message names the suffix rule: " msg))
      (assert (stringContains? msg "/tmp/sweep/custom.asn") (str "the message names the rejected path: " msg))
      (assert (stringContains? msg "HOME") (str "the message says why the rule exists: " msg))
      (assert (stringContains? msg "ASL_GATEWAY_URL") (str "the message names the way out: " msg))
      true))
