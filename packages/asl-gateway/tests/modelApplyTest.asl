(module aslGateway/tests/modelApplyTest
  :x [runTests]
  :i [(modelSync :a ms)])

; (:m :ref GW-SYNC-APPLY-TOOL :do "fixtures are the modelSyncTest ones: a sync run writes the patch, then models apply splices it into a scratch config; only scratch dirs, never ~/.asl")

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

fn names dir: String -> (List String)
  (resultOr (dirList dir) (list))

fn ! runTests -> Bool
  (let [(dir (str "/tmp/gwModelApply-" (procSelf) "-" (nowNs)))
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
        (synced (ms/modelsSyncCli! (list "--config" cfgPath "--out" out "--fixtures" fx "--cal" calPath "--date" "2026-10-27")))
        (patchPath (str out "/FREE-SYNC-2026-10-27.patch.asn"))
        (before (resultOr (fileReadString cfgPath) "READ-FAILED-BEFORE"))
        (applied (ms/modelsApplyCli! (list patchPath "--config" cfgPath)))
        (after (resultOr (fileReadString cfgPath) "READ-FAILED-AFTER"))
        (afterNames (names dir))
        (backups (filter (fn [(n String)] -> Bool (stringStartsWith? n "gateway.asn.bak-")) afterNames))
        (backupText (resultOr (fileReadString (str dir "/" (optionOr (listHead backups) "none"))) "NO-BACKUP"))
        (again (ms/modelsApplyCli! (list patchPath "--config" cfgPath)))
        (idem (resultOr (fileReadString cfgPath) "READ-FAILED-AGAIN"))
        (badPatch (str dir "/bad.patch.asn"))
        (w6 (fileWrite badPatch "(:patch :id X :for \"c\" :add ((:model :id orBroken :provider noSuchProvider :name \"x\")) :appendTail () :leave ())\n"))
        (refusedCheck (ms/modelsApplyCli! (list badPatch "--config" cfgPath)))
        (afterCheck (resultOr (fileReadString cfgPath) "READ-FAILED-CHECK"))
        (misfitPatch (str dir "/misfit.patch.asn"))
        (w7 (fileWrite misfitPatch "(:patch :id Y :for \"c\" :add () :appendTail ((:profile ghostPool :intent any :aliases (orA))) :leave ())\n"))
        (refusedFit (ms/modelsApplyCli! (list misfitPatch "--config" cfgPath)))
        (afterFit (resultOr (fileReadString cfgPath) "READ-FAILED-FIT"))
        (finalNames (names dir))
        (removed (pathRemove dir))]
    (do
      (assert (and (ok? w1) (and (ok? w2) (and (ok? w3) (and (ok? w4) (and (ok? w5) (and (ok? w6) (ok? w7))))))) "the scratch fixtures are written")
      (assert (= synced (ok 0)) (str "the sync run that writes the patch exits 0, got " synced))
      (assert (= applied (ok 0)) (str "models apply exits 0 on a fitting patch, got " applied))
      (assert (not (= after before)) "the config changed")
      (assert (stringContains? after "(:model :id orNewFreshFree :provider openrouter :name \"new/fresh:free\"") (str "the proposed model row is in the :models list: " after))
      (assert (stringContains? after "(:intent code :chain (orKept orGone orTurned orNewFreshFree orNewFlakyFree)") (str "the new aliases are appended at the tail of the code chain: " after))
      (assert (stringContains? after "(:intent plan :chain (orGone orKept))") "a route the patch does not name is untouched")
      (assert (stringContains? after ":spread ((orKept 3) (orGone 1) (orTurned 1))") "the spread of the code route is untouched")
      (assert (= (listLength backups) 1) (str "exactly one backup of the config was made: " backups))
      (assert (= backupText before) "the backup is the pre-apply config byte for byte")
      (assert (not (listAny? (fn [(n String)] -> Bool (stringContains? n ".tmp")) afterNames)) (str "no tmp file is left after a successful apply: " afterNames))
      (assert (= again (ok 0)) (str "applying the same patch again exits 0, got " again))
      (assert (= idem after) "applying the same patch again changes nothing")
      (assert (= refusedCheck (ok 1)) (str "a patch that breaks the configCheck is refused, got " refusedCheck))
      (assert (= afterCheck after) "a configCheck refusal leaves the config byte-identical")
      (assert (= refusedFit (ok 1)) (str "a patch naming a profile the config lacks is refused, got " refusedFit))
      (assert (= afterFit after) "a misfit refusal leaves the config byte-identical")
      (assert (not (listAny? (fn [(n String)] -> Bool (stringContains? n ".tmp")) finalNames)) (str "no tmp file is left after a refusal: " finalNames))
      (assert (= (listLength (filter (fn [(n String)] -> Bool (stringStartsWith? n "gateway.asn.bak-")) finalNames)) 1) (str "the idempotent rerun and the refusals make no backup, only the first apply did: " finalNames))
      (assert (ok? removed) "the scratch dir is removed")
      true))
