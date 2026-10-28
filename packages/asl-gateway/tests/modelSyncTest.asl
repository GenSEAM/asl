(module aslGateway/tests/modelSyncTest
  :x [runTests]
  :i [(modelSync :a ms)
      (config :a c)])

; (:m :ref GW-FREE-MODEL-SYNC :do "fixture /models bodies for an openrouter-kind provider (priced) and a subscription provider (every chat model): a free model gone from /models leaves its chains in the patch, a new free model that answered its probe is proposed at the tails of the pool's bulk routes, paid and non-chat models are never proposed, a model whose probe failed is recorded but joins no chain, and the config file is byte-identical after the run")

fn configText -> String
  (str "(:gateway :v 2\n"
       "  :providers ((:provider :id openrouter :kind openai :base \"https://example.test/v1\" :keyEnv GWSYNC_TEST_UNSET_KEY)\n"
       "              (:provider :id subA :kind openai :base \"https://sub.example.test/v1\" :keyEnv GWSYNC_TEST_UNSET_KEY))\n"
       "  :models ((:model :id orKept :provider openrouter :name \"free/kept:free\")\n"
       "           (:model :id orGone :provider openrouter :name \"free/gone:free\")\n"
       "           (:model :id orTurned :provider openrouter :name \"x/turned:free\")\n"
       "           (:model :id orPaid :provider openrouter :name \"paid/model\"))\n"
       "  :intents ((:intent :id plan) (:intent :id code))\n"
       "  :profiles ((:profile :id freePool :routes ((:intent plan :chain (orGone orKept))\n"
       "                                             (:intent code :chain (orKept orGone orTurned) :spread ((orKept 3) (orGone 1) (orTurned 1)))\n"
       "                                             (:intent any :chain (orKept orTurned))))\n"
       "             (:profile :id paid :routes ((:intent any :chain (orPaid)))))\n"
       "  :uses ((:use :for default :profile freePool)))\n")

fn openrouterModels -> String
  (str "{\"data\": [{\"id\": \"free/kept:free\", \"pricing\": {\"prompt\": \"0\", \"completion\": \"0\"}},"
       " {\"id\": \"x/turned:free\", \"pricing\": {\"prompt\": \"0.000001\", \"completion\": \"0.000002\"}},"
       " {\"id\": \"paid/model\", \"pricing\": {\"prompt\": \"0.00002\", \"completion\": \"0.00004\"}},"
       " {\"id\": \"new/fresh:free\", \"pricing\": {\"prompt\": \"0\", \"completion\": \"0\"}},"
       " {\"id\": \"x/lyria-music:free\", \"pricing\": {\"prompt\": \"0\", \"completion\": \"0\"}}, {\"id\": \"new/flaky:free\", \"pricing\": {\"prompt\": \"0\", \"completion\": \"0\"}}, {\"id\": \"new/broken:free\", \"pricing\": {\"prompt\": \"0\", \"completion\": \"0\"}}, {\"id\": \"new/costly\", \"pricing\": {\"prompt\": \"0.00002\", \"completion\": \"0.00002\"}}]}")

fn subModels -> String
  "{\"object\": \"list\", \"data\": [{\"id\": \"sub-chat\"}, {\"id\": \"sub-embed-v1\"}]}"

fn calFixture -> String
  "(:cal :id FREE-PROBE-20261027 :models ((openrouter \"new/flaky:free\" :vps 429 :mac 429 :ms 250) (openrouter \"new/broken:free\" :vps 404 :mac 404 :ms 90)))\n"

fn ! runTests -> Bool
  (let [(dir (str "/tmp/gwModelSync-" (procSelf) "-" (nowNs)))
        (_d (dirCreate dir))
        (fx (str dir "/fixtures"))
        (_f (dirCreate fx))
        (out (str dir "/out"))
        (cfgPath (str dir "/gateway.asn"))
        (w1 (fileWrite cfgPath (configText)))
        (w2 (fileWrite (str fx "/openrouter.models.json") (openrouterModels)))
        (w3 (fileWrite (str fx "/subA.models.json") (subModels)))
        (w4 (fileWrite (str fx "/probes.tsv") "openrouter\tnew/fresh:free\t200\nopenrouter\tnew/flaky:free\t200\nopenrouter\tnew/broken:free\t200\nsubA\tsub-chat\t429\n"))
        (calPath (str dir "/freeModels.asn"))
        (w5 (fileWrite calPath (calFixture)))
        (before (resultOr (fileReadString cfgPath) "READ-FAILED-BEFORE"))
        (code (ms/modelsSyncCli! (list "--config" cfgPath "--out" out "--fixtures" fx "--cal" calPath "--date" "2026-10-27")))
        (after (resultOr (fileReadString cfgPath) "READ-FAILED-AFTER"))
        (patch (resultOr (fileReadString (str out "/FREE-SYNC-2026-10-27.patch.asn")) ""))
        (cal (resultOr (fileReadString (str out "/FREE-SYNC-2026-10-27.cal.asn")) ""))
        (listed (resultOr (fileReadString (str out "/freeModels-2026-10-27.asn")) ""))
        (removed (pathRemove dir))]
    (do
      (assert (and (ok? w1) (and (ok? w2) (and (ok? w3) (and (ok? w4) (ok? w5))))) "the fixture config, /models bodies and probe table are written")
      (assert (= code (ok 0)) (str "models sync exits 0 on fixtures, got " code))
      (assert (= after before) "the gateway config file is byte-identical after the run")
      (assert (stringContains? patch "(:model :id orNewFreshFree :provider openrouter :name \"new/fresh:free\"") (str "the new free model that answered is proposed as a model row: " patch))
      (assert (stringContains? patch "(:profile freePool :intent code :aliases (orNewFreshFree orNewFlakyFree)) (:profile freePool :intent any :aliases (orNewFreshFree orNewFlakyFree))") (str "it is appended at the tails of the bulk routes code and any only: " patch))
      (assert (not (stringContains? patch "new/costly")) "a paid model is never proposed")
      (assert (not (stringContains? patch "sub-embed")) "a non-chat model of a subscription provider is never proposed")
      (assert (not (stringContains? listed "lyria")) (str "a zero-priced non-chat model on a priced provider is not counted free: " listed))
      (assert (not (stringContains? patch "subASubChat")) "a free model whose probe returned 429 joins no chain")
      (assert (stringContains? cal "(subA \"sub-chat\" :alias subASubChat :probe 429)") (str "the failed probe is recorded in the calibration row: " cal))
      (assert (stringContains? patch "(:alias orGone :name \"free/gone:free\" :why \"gone from /models\" :chains ((freePool plan) (freePool code)))") (str "a model gone from /models leaves every chain naming it: " patch))
      (assert (stringContains? patch "(:alias orTurned :name \"x/turned:free\" :why \"listed but no longer free\" :chains ((freePool code) (freePool any)))") (str "a pool model that turned paid leaves its chains: " patch))
      (assert (not (stringContains? patch "orPaid")) "a paid row outside the free profiles is left alone")
      (assert (stringContains? listed "(:provider openrouter :listed 8 :free (\"free/kept:free\" \"new/fresh:free\" \"new/flaky:free\" \"new/broken:free\"))") (str "the current list keeps only free ids: " listed))
      (assert (= (ms/proposeAlias "openrouter" "a/b-c:free" (list "orABCFree")) "orABCFreeX1") "a proposed alias never collides with a taken one")
      (assert (= (ms/modelFilterFor "vercel") "vercelFree") "vercel is filtered by price, not as a subscription")
      (assert (stringContains? cal "(openrouter \"new/broken:free\" :alias orNewBrokenFree :probe known404)") (str "a model CAL saw refused with 404 is recorded as known404: " cal))
      (assert (not (stringContains? patch "orNewBrokenFree")) "a model CAL saw refused for good joins no chain")
      (assert (= (ms/toProbe (calFixture) (ms/SyncDiff :provider "openrouter" :listed 0 :free (list) :added (list "new/flaky:free" "new/broken:free" "new/unseen:free") :removed (list) :changed (list)))
                 (list "new/flaky:free" "new/unseen:free"))
              "a CAL 429 model and an unseen model are re-probed, a CAL 404 model is not")
      (assert (ok? removed) "the scratch dir is removed")
      true))
