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
       "  :intents ((:intent :id code) (:intent :id research))\n"
       "  :profiles ((:profile :id freePool :routes ((:intent code :chain (ocDs ocGlm ocOmen ccLing ccDs ccBeam) :spread ((ocDs 8))) (:intent research :chain (ccDs ccBeam))))\n"
       "             (:profile :id paidCheap :routes ((:intent any :chain (ocDs) :spread ((ocDs 8))))))\n"
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
       "  (:cell :model ocDs :provider opencodeGo :name \"deepseek-v4.1-flash\" :intent any :score 1.0 :n 3 :infra 1 :spread 0 :temp :default :ms 5000 :outTok 40 :fail ())\n"
       "  (:cell :model macGlm :provider opencodeGo :name \"glm-5.3\" :intent code :score 1.0 :n 3 :spread 0 :temp :default :ms 900 :outTok 40 :fail ())\n"
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
                                       "--scores" (str dir "/scores.asn") "--subs" (str dir "/subs.asn") "--out" out "--host" "test"
                                       "--set" "ccLing" ":temperature" "0.2" "--set" "ccLing" ":retry" "(:max 1)" "--drop" "ocOmen"
                                       "--dropRoute" "ccDs" "freePool/research" "--weight" "ccLing" "freePool/code" "3")))
        (badOut (str dir "/bad.patch"))
        (badCode (sp/modelsPaceCli! (list "--date" "2026-10-28" "--config" cfg "--out" badOut "--drop" "noSuchAlias")))
        (badWrote (fileExists? badOut))
        (zeroCode (sp/modelsPaceCli! (list "--date" "2026-10-28" "--config" cfg "--out" badOut "--weight" "ccLing" "freePool/code" "0")))
        (strayCode (sp/modelsPaceCli! (list "--date" "2026-10-28" "--config" cfg "--out" badOut "--dropRoute" "ocGlm" "freePool/research")))
        (zeroWrote (fileExists? badOut))
        (after (resultOr (fileReadString cfg) "READ-FAILED-AFTER"))
        (patch (resultOr (fileReadString out) ""))
        (removed (pathRemove dir))]
    (do
      (assert (listAll? (fn [(r (Result Unit String))] -> Bool (ok? r)) w) "the fixture files are written")
      (assert (= code (ok 0)) (str "models pace exits 0, got " code))
      (assert (= after before) "the config file is byte-identical after the run")
      (assert (stringContains? patch "(:set :profile freePool :intent code :spread ((ocDs 8) (ocGlm 2) (ccLing 3) (ccDs 4) (ccBeam 8)) :cooldownSec 300)")
              (str "weights: x8 at full ok rate, x1.5 at the score 1.0 of a cell keyed by another host row id (same provider and name) rounds to 2, the dropped ocOmen gone, x10 overridden to 3 by a --weight lead decision, x8 at the code cell score 0.5 is 4 (not the 0.25 overall), a null score falls back to the probe rate, free 8: " patch))
      (assert (stringContains? patch "(:set :profile paidCheap :intent any :spread ((ocDs 4)) :cooldownSec 300)") (str "a saturated intent weighs reliability and speed: score 1.0 x 3 of 4 calls x 1/(1+5000/10000) = 0.5 of x8 is 4: " patch))
      (assert (stringContains? patch "(ocDs :rpm 4.288 ") (str "opencodeGo rpm spends 57 percent of 173330 monthly requests over 16 days: " patch))
      (assert (stringContains? patch "(ocGlm :rpm 0.027 ") (str "a small allowance paces slowly: " patch))
      (assert (stringContains? patch ":drops (ocOmen)") (str "the drop is listed: " patch))
      (assert (stringContains? patch "(ocOmen chain/freePool/code member dropped)") (str "the dropped chain member is a change row: " patch))
      (assert (stringContains? patch "(ocDs spread/paidCheap/any 8 4)") (str "a moved weight is a change row with old and new: " patch))
      (assert (not (stringContains? patch "(ocDs spread/freePool/code")) "an unchanged weight is no change row")
      (assert (stringContains? patch "(ocDs :rpm none 4.288)") (str "a new rpm is a change from none: " patch))
      (assert (stringContains? patch "(:set :model ccLing :retry (:max 1))") (str "--set rows land under :models: " patch))
      (assert (and (stringContains? patch "(ccLing :temperature none 0.2)") (stringContains? patch "(ccLing :retry none (:max 1))")) (str "--set rows are change rows from the configured value: " patch))
      (assert (stringContains? patch "(:set :profile freePool :intent research :spread ((ccBeam 8)) :cooldownSec 300)") (str "--dropRoute takes the alias out of that one chain: " patch))
      (assert (stringContains? patch "(ccDs chain/freePool/research member dropped)") (str "the route drop is a change row: " patch))
      (assert (stringContains? patch "(ccLing spread/freePool/code none 3)") (str "the fixed weight is a change row: " patch))
      (assert (and (stringContains? patch "(:weight :model ccLing :route freePool/code :value 3 :by lead)") (stringContains? patch "(:dropRoute :model ccDs :route freePool/research :by lead)")) (str "route edits are recorded as lead decisions: " patch))
      (assert (and (= zeroCode (ok 2)) (= strayCode (ok 2)) (not zeroWrote)) (str "a --weight below 1 and a --dropRoute alias outside that chain exit 2 and write nothing, got " zeroCode " " strayCode))
      (assert (and (= badCode (ok 2)) (not badWrote)) (str "a --drop alias with no model row exits 2 and writes no patch, got " badCode))
      (assert (stringContains? patch "(ccLing :rpm 1.447 ") (str "commandCode plan models share the plan pool by overall weight (10 of 12): " patch))
      (assert (stringContains? patch "(ccDs :rpm 0.289 ") (str "2 of 12 of the pool, from the 0.25 overall score: " patch))
      (assert (not (stringContains? patch "(ccBeam :rpm")) "a free commandCode model draws on no credit pool")
      (assert (stringContains? patch "(:budget :provider opencodeGo :renews \"2026-11-13\" :remainingPercent 57.000 :daysLeft 16)") (str "opencodeGo budget row from the ledger: " patch))
      (assert (stringContains? patch "(:budget :provider commandCode :renews \"2026-11-16\" :remainingPercent unknown :daysLeft 19 ") (str "commandCode has no used figure: " patch))
      (assert (= (sp/freeCalScore (scoresText) "ccDs" "" "" "grade") (some 0.25)) "an intent with no cell falls back to the overall score")
      (assert (= (sp/freeCalScore (scoresText) "ccLing" "" "" "code") (none)) "a null score is no score")
      (assert (= (sp/freeCalScore (scoresText) "vpsGlm" "opencodeGo" "glm-5.3" "code") (some 1.0)) "a row id the calibrating host lacks finds its cell by provider and name")
      (assert (= (sp/freeCalScore (scoresText) "ccD" "" "" "code") (none)) "an alias that is a prefix of another row id matches nothing")
      (assert (= (sp/fixed3 0.0267) "0.027") "three-decimal formatting")
      (assert (ok? removed) "the scratch dir is removed")
      true))
