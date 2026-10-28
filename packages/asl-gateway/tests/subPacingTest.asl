(module aslGateway/tests/subPacingTest
  :x [runTests]
  :i [(subPacing :a sp)])

; (:m :ref SUB-MULTIPLIERS :do "fixture config, multipliers, FREE-PROBE statuses, a FREE-CAL score and a subscriptions ledger: spread weights are multiplier x quality (a FREE-CAL cell score for the route intent wins over the overall score and the probe ok rate, free models count 8, unknown 1), opencodeGo rpm spends the remaining 57 percent over the 16 days to its renews date, commandCode plan models share the plan pool by weight, and the config file is byte-identical after the run")

fn configText -> String
  (str "(:gateway :v 2\n"
       "  :providers ((:provider :id opencodeGo :kind openai :base \"https://oc.example.test/v1\" :keyEnv GWPACE_UNSET)\n"
       "              (:provider :id commandCode :kind openai :base \"https://cc.example.test/v1\" :keyEnv GWPACE_UNSET))\n"
       "  :models ((:model :id ocDs :provider opencodeGo :name \"deepseek-v4.1-flash\")\n"
       "           (:model :id ocGlm :provider opencodeGo :name \"glm-5.3\")\n"
       "           (:model :id ocOmen :provider opencodeGo :name \"omen-alpha\")\n"
       "           (:model :id ccLing :provider commandCode :name \"inclusionai/ling-3.1-flash\")\n"
       "           (:model :id ccDs :provider commandCode :name \"deepseek/deepseek-v4.1-flash\")\n"
       "           (:model :id ccBeam :provider commandCode :name \"reflection/beam:free\"))\n"
       "  :intents ((:intent :id code))\n"
       "  :profiles ((:profile :id freePool :routes ((:intent code :chain (ocDs ocGlm ocOmen ccLing ccDs ccBeam))))\n"
       "             (:profile :id paidCheap :routes ((:intent any :chain (ocDs)))))\n"
       "  :uses ((:use :for default :profile freePool)))\n")

fn multText -> String
  (str "(:cal :id SUB-MULTIPLIERS-T :multipliers (\n"
       "    (opencodeGo \"deepseek-v4.1-flash\" :x 8 :usd 80 :reqMonth 173330 :rpmEven 4.0)\n"
       "    (opencodeGo \"glm-5.3\" :x 1.5 :usd 15 :reqMonth 1080 :rpmEven 0.025)\n"
       "    (commandCode \"inclusionai/ling-3.1-flash\" :x 10 :usd 100)\n"
       "    (commandCode \"deepseek/deepseek-v4.1-flash\" :x 8 :usd 80)\n"
       "    (commandCode \"reflection/beam:free\" :x free)))\n")

fn calText -> String
  (str "(:cal :id FREE-PROBE-T :models ((opencodeGo \"deepseek-v4.1-flash\" :vps 200 :mac 200 :ms 900) (opencodeGo \"glm-5.3\" :vps 200 :mac 429 :ms 900) (commandCode\n"
       "\"inclusionai/ling-3.1-flash\" :vps 200 :mac 200 :ms 900) (commandCode \"deepseek/deepseek-v4.1-flash\" :vps 200 :mac 200 :ms 900) (commandCode \"reflection/beam:free\" :vps 200 :mac 200 :ms 700)))\n")

fn scoresText -> String
  (str "(:cal :id FREE-CAL-T :cells ((:cell :model ccDs :provider commandCode :name \"deepseek/deepseek-v4.1-flash\" :intent code :score 0.5 :n 3 :spread 0 :temp :default :ms 900 :outTok 40 :fail ())\n"
       "  (:cell :model ocDs :provider opencodeGo :name \"deepseek-v4.1-flash\" :intent any :score 0.5 :n 3 :spread 0 :temp :default :ms 900 :outTok 40 :fail ())\n"
       "  (:cell :model ccLing :provider commandCode :name \"inclusionai/ling-3.1-flash\" :intent code :score null :n 0 :spread 0 :temp :default :ms 0 :outTok 0 :fail (rate)))\n"
       "  :models ((:modelScore :model ccDs :provider commandCode :name \"deepseek/deepseek-v4.1-flash\" :score 0.25 :intents ((code 0.5) (grade 0.0)))\n"
       "           (:modelScore :model ccLing :provider commandCode :name \"inclusionai/ling-3.1-flash\" :score null :intents ())))\n")

fn subsText -> String
  (str "(:subscriptions :v 1\n"
       "  (:sub :id commandCode :renews \"2026-11-16\" :src principal :windows ())\n"
       "  (:sub :id opencodeGo :renews \"2026-11-13\" :windows ((:rolling 5h :usedPercent 1) (:weekly :resets \"2026-11-02\" :usedPercent 0) (:monthly :resets \"2026-11-13\" :usedPercent 43))))\n")

fn ! runTests -> Bool
  (let [(dir (str "/tmp/gwSubPacing-" (procSelf) "-" (nowNs)))
        (_d (dirCreate dir))
        (cfg (str dir "/gateway.asn"))
        (w (list (fileWrite cfg (configText)) (fileWrite (str dir "/mult.asn") (multText)) (fileWrite (str dir "/cal.asn") (calText))
                 (fileWrite (str dir "/scores.asn") (scoresText))
                 (fileWrite (str dir "/subs.asn") (subsText))))
        (before (resultOr (fileReadString cfg) "READ-FAILED-BEFORE"))
        (out (str dir "/subMultipliers.patch"))
        (code (sp/modelsPaceCli! (list "--date" "2026-10-28" "--config" cfg "--mult" (str dir "/mult.asn") "--cal" (str dir "/cal.asn")
                                       "--scores" (str dir "/scores.asn") "--subs" (str dir "/subs.asn") "--out" out "--host" "test")))
        (after (resultOr (fileReadString cfg) "READ-FAILED-AFTER"))
        (patch (resultOr (fileReadString out) ""))
        (removed (pathRemove dir))]
    (do
      (assert (listAll? (fn [(r (Result Unit String))] -> Bool (ok? r)) w) "the fixture files are written")
      (assert (= code (ok 0)) (str "models pace exits 0, got " code))
      (assert (= after before) "the config file is byte-identical after the run")
      (assert (stringContains? patch "(:set :profile freePool :intent code :spread ((ocDs 8) (ocGlm 1) (ocOmen 1) (ccLing 10) (ccDs 4) (ccBeam 8)) :cooldownSec 300)")
              (str "weights: x8 at full ok rate, x1.5 at half rounds to 1, unknown 1, x10, x8 at the code cell score 0.5 is 4 (not the 0.25 overall), a null score falls back to the probe rate, free 8: " patch))
      (assert (stringContains? patch "(:set :profile paidCheap :intent any :spread ((ocDs 4)) :cooldownSec 300)") (str "paidCheap routes get spreads too, from the any cell score 0.5: " patch))
      (assert (stringContains? patch "(ocDs :rpm 4.288 ") (str "opencodeGo rpm spends 57 percent of 173330 monthly requests over 16 days: " patch))
      (assert (stringContains? patch "(ocGlm :rpm 0.027 ") (str "a small allowance paces slowly: " patch))
      (assert (not (stringContains? patch "(ocOmen :rpm")) "a model with no published allowance gets no rpm row")
      (assert (stringContains? patch "(ccLing :rpm 1.447 ") (str "commandCode plan models share the plan pool by overall weight (10 of 12): " patch))
      (assert (stringContains? patch "(ccDs :rpm 0.289 ") (str "2 of 12 of the pool, from the 0.25 overall score: " patch))
      (assert (not (stringContains? patch "(ccBeam :rpm")) "a free commandCode model draws on no credit pool")
      (assert (stringContains? patch "(:budget :provider opencodeGo :renews \"2026-11-13\" :remainingPercent 57.000 :daysLeft 16)") (str "opencodeGo budget row from the ledger: " patch))
      (assert (stringContains? patch "(:budget :provider commandCode :renews \"2026-11-16\" :remainingPercent unknown :daysLeft 19 ") (str "commandCode has no used figure: " patch))
      (assert (= (sp/freeCalScore (scoresText) "ccDs" "grade") (some 0.25)) "an intent with no cell falls back to the overall score")
      (assert (= (sp/freeCalScore (scoresText) "ccLing" "code") (none)) "a null score is no score")
      (assert (= (sp/freeCalScore (scoresText) "ccD" "code") (none)) "an alias that is a prefix of another row id matches nothing")
      (assert (= (sp/fixed3 0.0267) "0.027") "three-decimal formatting")
      (assert (ok? removed) "the scratch dir is removed")
      true))
