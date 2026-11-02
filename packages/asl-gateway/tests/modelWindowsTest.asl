(module aslGateway/tests/modelWindowsTest
  :x [runTests]
  :i [(aslGateway/modelWindows :a mw)
      (aslGateway/modelSync :a ms)
      (aslGateway/config :a cfg)
      (asl-json/json :a j)])

; (:m :ref MODELS-CTX-SYNC :do "fixture /models payloads of every shape the field tables cover, a config with rows around them, then the report and patch rows, the patch applied with models apply's own text step, and the sync CLI run on fixture files in a scratch dir")
fn orBody -> String
  "{\"data\": [{\"id\": \"m/or\", \"context_length\": 1000000, \"top_provider\": {\"max_completion_tokens\": 65536}}, {\"id\": \"m/small\", \"context_length\": 128000}, {\"id\": \"m/nofield\"}, {\"id\": \"m/same\", \"context_length\": 128000, \"max_tokens\": 4096}]}"

fn vercelBody -> String
  "{\"data\": [{\"id\": \"v/m\", \"context_window\": 1048576, \"max_tokens\": 131072}]}"

fn genericBody -> String
  "[{\"id\": \"g/vllm\", \"max_model_len\": 32768, \"max_output_tokens\": 8192}, {\"id\": \"models/g/gem\", \"inputTokenLimit\": 1048576, \"outputTokenLimit\": 65536}, {\"id\": \"g/str\", \"context_length\": \"262144\", \"max_completion_tokens\": 16000.0}]"

fn geminiBody -> String
  "{\"models\": [{\"name\": \"models/gemini-x\", \"inputTokenLimit\": 1048576, \"outputTokenLimit\": 65536}]}"

fn winOf listed: (List (Pair String mw/Window)) id: String -> mw/Window
  (match (listHead (filter (fn [(p (Pair String mw/Window))] -> Bool (= (pairFirst p) id)) listed))
    ((some p) (pairSecond p))
    ((none) (mw/Window :context -1 :maxOut -1)))

fn ! testShapes -> Bool
  (let [(or (resultOr (mw/listedWindows (orBody)) (list)))
        (vc (resultOr (mw/listedWindows (vercelBody)) (list)))
        (ge (resultOr (mw/listedWindows (genericBody)) (list)))
        (bad (mw/listedWindows "not json"))
        (gn (resultOr (mw/listedWindows (geminiBody)) (list)))]
    (do (assert (= (winOf or "m/or") (mw/Window :context 1000000 :maxOut 65536)) "SHAPE: OpenRouter context_length and top_provider.max_completion_tokens")
        (assert (= (winOf or "m/small") (mw/Window :context 128000 :maxOut 0)) "SHAPE: a missing max output is 0")
        (assert (= (winOf or "m/nofield") (mw/Window :context 0 :maxOut 0)) "SHAPE: an item without fields is listed with no window")
        (assert (= (winOf vc "v/m") (mw/Window :context 1048576 :maxOut 131072)) "SHAPE: Vercel context_window and max_tokens")
        (assert (= (winOf ge "g/vllm") (mw/Window :context 32768 :maxOut 8192)) "SHAPE: max_model_len and max_output_tokens")
        (assert (= (winOf ge "g/gem") (mw/Window :context 1048576 :maxOut 65536)) "SHAPE: Gemini limits behind a models/ prefix")
        (assert (= (winOf ge "g/str") (mw/Window :context 262144 :maxOut 16000)) "SHAPE: a numeric string and a float are read as whole numbers")
        (assert (= (winOf gn "gemini-x") (mw/Window :context 1048576 :maxOut 65536)) "SHAPE: Gemini native list, models array with name ids")
        (assert (err? bad) "SHAPE: a body that is not JSON is an error")
        true))

fn cfgText -> String
  (str "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n"
       "  :models ((:model :id aBig :provider test :name \"m/or\" :contextBudget 300000 :maxTokens 100000)\n"
       "           (:model :id bSmall :provider test :name \"m/small\")\n"
       "           (:model :id cNone :provider test :name \"m/nofield\" :contextBudget 50000)\n"
       "           (:model :id dGone :provider test :name \"m/gone\" :contextBudget 70000)\n"
       "           (:model :id eSame :provider test :name \"m/same\" :contextBudget 128000 :maxTokens 4096))\n"
       "  :profiles ((:profile :id p1 :routes ((:intent any :chain (aBig bSmall cNone dGone eSame)))))\n"
       "  :uses ((:use :for default :profile p1)))")

fn rowOf rows: (List mw/WindowRow) alias: String -> mw/WindowRow
  (optionOr (listHead (filter (fn [(r mw/WindowRow)] -> Bool (= r.alias alias)) rows))
    (mw/WindowRow :alias "" :provider "" :name "" :listedContext 0 :listedMaxOut 0 :cfgBudget 0 :cfgMaxTokens 0 :newBudget 0 :newMaxTokens 0 :status "missing"))

fn ! testRows -> Bool
  (match (cfg/gatewayConfigParse! (cfgText) "windows" ".asl/mem/calibration/index.asn")
    ((err e) (do (assert false (str "ROWS: fixture config must parse: " e)) false))
    ((ok table)
      (let [(listed (resultOr (mw/listedWindows (orBody)) (list)))
            (rows (mw/windowRows table "test" listed 200000))
            (a (rowOf rows "aBig"))
            (b (rowOf rows "bSmall"))
            (c (rowOf rows "cNone"))
            (d (rowOf rows "dGone"))
            (e (rowOf rows "eSame"))
            (small (mw/windowRows table "test" listed 100000))]
        (do (assert (= (listLength rows) 5) "ROWS: one row per config alias of the provider")
            (assert (and (= a.newBudget 200000) (= a.status "ok")) (str "ROWS: the budget is min(listed window, cap), got " a.newBudget))
            (assert (= a.newMaxTokens 65536) "ROWS: a max tokens above the listed max output is lowered to it")
            (assert (and (= b.newBudget 128000) (= b.newMaxTokens -1)) "ROWS: a row without budget gets the listed window, no max out change without a configured max tokens")
            (assert (and (= c.status "nofield") (= c.newBudget -1)) "ROWS: an item without a window leaves the row alone")
            (assert (and (= d.status "unlisted") (= d.cfgBudget 70000) (= d.newBudget -1)) "ROWS: a model the list does not name is reported and unchanged")
            (assert (and (= e.status "same") (= e.newBudget -1) (= e.newMaxTokens -1)) "ROWS: a row that already matches proposes nothing")
            (assert (= (rowOf small "bSmall").newBudget 100000) "ROWS: a lower cap wins over the listed window")
            (assert (= (mw/capOfConfigText "(:gateway :contextCap 150000 :v 2)") 150000) "CAP: the config row sets the cap")
            (assert (= (mw/capOfConfigText "(:gateway :v 2)") 200000) "CAP: the default is 200000")
            (assert (ok? (cfg/gatewayConfigParse! (stringReplace (cfgText) "(:gateway :v 2" "(:gateway :v 2 :contextCap 150000") "windowsCap" ".asl/mem/calibration/index.asn")) "CAP: a config with a :contextCap row still parses")
            (let [(patch (mw/windowsPatchText "CTX-T" "mac" rows))
                  (applied (ms/applyPatchText (cfgText) patch))]
              (do (assert (stringContains? patch "(:set :model aBig :contextBudget 200000)") "PATCH: a budget row")
                  (assert (stringContains? patch "(:set :model aBig :maxTokens 65536)") "PATCH: a max tokens row")
                  (assert (not (stringContains? patch "dGone")) "PATCH: unchanged and unlisted rows are not in it")
                  (match applied
                    ((err e) (do (assert false (str "PATCH: models apply text step: " e)) false))
                    ((ok r)
                      (do (assert (stringContains? (pairFirst r) "(:model :id aBig :provider test :name \"m/or\" :contextBudget 200000 :maxTokens 65536)") "APPLY: the row carries the new budget and max tokens")
                          (assert (stringContains? (pairFirst r) ":name \"m/small\" :contextBudget 128000") "APPLY: a row without a budget gets one")
                          (assert (stringContains? (pairFirst r) ":id dGone :provider test :name \"m/gone\" :contextBudget 70000") "APPLY: an unlisted row is byte for byte")
                          (assert (ok? (cfg/gatewayConfigParse! (pairFirst r) "windowsApplied" ".asl/mem/calibration/index.asn")) "APPLY: the config still parses")
                          true)))))))))

fn ! scratch! -> String
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/modelWindowsTest." (stringFromInt64 (procSelf))))
        (_ (pathRemove dir))
        (_ (dirCreate dir))]
    dir)

fn ! testCli -> Bool
  (let [(dir (scratch!))
        (fx (str dir "/fx"))
        (_ (dirCreate fx))
        (_ (fileWrite (str fx "/test.models.json") (orBody)))
        (config (str dir "/cfg.asn"))
        (_ (fileWrite config (cfgText)))
        (out (str dir "/out"))
        (code (ms/modelsSyncCli! (list "--config" config "--out" out "--fixtures" fx "--no-probe" "--date" "2026-11-02" "--cal" (str dir "/nocal.asn"))))
        (report (resultOr (fileReadString (str out "/windows-2026-11-02.asn")) ""))
        (patch (resultOr (fileReadString (str out "/FREE-SYNC-2026-11-02.windows.patch.asn")) ""))
        (untouched (resultOr (fileReadString config) ""))
        (_ (pathRemove dir))]
    (do (assert (= code (ok 0)) "CLI: sync on fixtures succeeds")
        (assert (stringContains? report ":alias aBig") "CLI: the report names the aliases")
        (assert (stringContains? report ":status unlisted") "CLI: the report names rows the list did not cover")
        (assert (stringContains? patch "(:set :model aBig :contextBudget 200000)") "CLI: the windows patch is written beside the sync patch")
        (assert (= untouched (cfgText)) "CLI: sync never writes the config")
        true))

fn ! testNoKey -> Bool
  (let [(dir (scratch!))
        (config (str dir "/cfg.asn"))
        (_ (fileWrite config (stringReplace (cfgText) "TEST_KEY" "CAPORDER_TEST_KEY_NEVER_SET")))
        (out (str dir "/out"))
        (code (ms/modelsSyncCli! (list "--config" config "--out" out "--provider" "test" "--no-probe" "--date" "2026-11-02" "--cal" (str dir "/nocal.asn"))))
        (report (resultOr (fileReadString (str out "/windows-2026-11-02.asn")) ""))
        (patch (resultOr (fileReadString (str out "/FREE-SYNC-2026-11-02.windows.patch.asn")) ""))
        (_ (pathRemove dir))]
    (do (assert (= code (ok 0)) "NOKEY: sync with a keyless provider still succeeds")
        (assert (and (stringContains? report ":alias aBig") (stringContains? report ":alias eSame")) "NOKEY: every alias of the keyless provider is a row")
        (assert (not (stringContains? report ":status ok")) "NOKEY: no row proposes a change")
        (assert (= (listLength (stringSplit report ":status unlisted")) 6) (str "NOKEY: all five rows are unlisted, got " report))
        (assert (not (stringContains? patch ":set")) "NOKEY: the patch has no change rows")
        true))

fn ! runTests -> Bool
  (do (testShapes) (testRows) (testCli) (testNoKey) true)
