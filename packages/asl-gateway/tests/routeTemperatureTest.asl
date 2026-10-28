(module aslGateway/tests/routeTemperatureTest
  :x [runTests]
  :i [(config :a cfg)])

fn cfgText overrideText: String -> String
  (str "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n"
       "  :models ((:model :id m1 :provider test :name \"model-a\" :temperature 0.2) (:model :id m2 :provider test :name \"model-b\"))\n"
       "  :intents ((:intent :id sweep))\n"
       "  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1 m2)) (:intent sweep :chain (m1 m2) " overrideText "))))\n"
       "  :uses ((:use :for default :profile p1)))")

fn entryTemps entries: (List cfg/GatewayResolvedEntry) -> (List (Option Float64))
  (map (fn [(e cfg/GatewayResolvedEntry)] -> (Option Float64)
         (match e ((cfg/entryResolved en) en.params.temperature) ((cfg/entryUnresolved _) none)))
       entries)

fn temps! text: String intent: String exact: Bool -> (Result (List (Option Float64)) String)
  (match (cfg/gateway_config_parse! text "routeTemperature" ".asl/mem/calibration/index.asn")
    ((err e) (err e))
    ((ok tbl)
      (match (if exact (cfg/gatewayRouteEntriesExact! tbl (list) (none) intent) (cfg/gatewayRouteEntries! tbl (list) (none) intent))
        ((err e) (err e))
        ((ok re) (ok (entryTemps re.entries))))))

fn ! runTests -> Bool
  (let [(plain (temps! (cfgText "") "sweep" false))
        (over (temps! (cfgText ":temperatureOverride 0.9") "sweep" false))
        (overExact (temps! (cfgText ":temperatureOverride 0.9") "sweep" true))
        (overAny (temps! (cfgText ":temperatureOverride 0.9") "any" false))
        (overInt (temps! (cfgText ":temperatureOverride 1") "sweep" false))
        (bad (cfg/gateway_config_parse! (cfgText ":temperatureOverride hot") "routeTemperatureBad" ".asl/mem/calibration/index.asn"))]
    (do
      (assert (= plain (ok (list (some 0.2) none))) (str "ROUTETEMP: without an override the model row temperature is the default and a row-less model stays unset, got " plain))
      (assert (= over (ok (list (some 0.9) (some 0.9)))) (str "ROUTETEMP: a route :temperatureOverride wins over the model row and reaches a row-less model, got " over))
      (assert (= overExact (ok (list (some 0.9) (some 0.9)))) (str "ROUTETEMP: the exact lookup applies the override too, got " overExact))
      (assert (= overAny (ok (list (some 0.2) none))) (str "ROUTETEMP: another route of the same profile keeps the model row default, got " overAny))
      (assert (= overInt (ok (list (some 1.0) (some 1.0)))) (str "ROUTETEMP: an integer override is read as a float, got " overInt))
      (assert (match bad ((err e) (stringContains? e "temperatureOverride")) ((ok _) false)) "ROUTETEMP: a non-numeric override is a parse error naming the key")
      true))
